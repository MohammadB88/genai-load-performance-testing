#!/usr/bin/env bash
#
# run-test.sh
#
# End-to-end entry point for running the Capacity/Sizing suite's concurrency
# ladder as OpenShift Jobs, one Job per rung (see docs/scenarios/sizing.md for
# the ladder and circuit-breaker rationale). Ties together the other pieces
# in this directory:
#   1. Ensure the target namespace/project exists (creates it if not).
#   2. Create the aiperf-hf-token Secret, prompting for the token — but only
#      if that secret doesn't already exist in the namespace.
#   3. Generate the required ConfigMaps by calling generate-configmaps.sh.
#   4. Apply the shared results PVC (once).
#   5. For each rung in the ladder (in order): render a Job manifest from
#      content-generation-job.yaml with that rung's CONCURRENCY substituted,
#      apply it, wait for completion, then check the rung's error rate in the
#      exported profile_export.json. If error rate exceeds the threshold,
#      STOP — do not submit the next rung (this is the "safety circuit
#      breaker" from docs/scenarios/sizing.md, protecting a customer's live
#      endpoint from being hammered into an outage).
#   6. Print a summary of every resource created/updated and the ladder
#      outcome (rungs completed vs. stopped early).
#
# Uses `oc` (OpenShift CLI) — swap OC_BIN if running against plain
# Kubernetes instead (the subcommands used here are identical in kubectl).
#
# Only the Content Generation scenario is implemented for v1 (see CLAUDE.md /
# version2/) — this script runs that scenario's ladder. Extend SCENARIO/
# JOB_TEMPLATE below if more sizing scenarios are added later.
#
# Usage:
#   ./run-test.sh                                  # interactive: prompts for namespace, HF token
#   ./run-test.sh -n <namespace>
#   ./run-test.sh -n <namespace> -r "1 5 10"       # run only these rungs
#   ./run-test.sh -n <namespace> -e 10             # override error-rate threshold (%, default 5)
#   HF_TOKEN=hf_xxx ./run-test.sh -n <namespace>   # skips the HF token prompt
#
set -euo pipefail

OC="${OC_BIN:-oc}"
DEFAULT_NAMESPACE="aiperf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZING_DIR="$(dirname "$SCRIPT_DIR")"

SCENARIO="content-generation"
JOB_TEMPLATE="$SCRIPT_DIR/content-generation-job.yaml"
ALL_RUNGS=(1 5 10 25 50 100 200)
ERROR_RATE_THRESHOLD_PCT="${ERROR_RATE_THRESHOLD_PCT:-5}"

# Resources created/touched this run, printed as a summary at the end.
CREATED_RESOURCES=()
COMPLETED_RUNGS=()
STOPPED_EARLY=""

NAMESPACE="${NAMESPACE:-}"
SELECTED_RUNGS=(${RUNGS:-})   # from env var RUNGS, space-separated; may be overridden by -r

while getopts "n:r:e:h" opt; do
    case "$opt" in
        n) NAMESPACE="$OPTARG" ;;
        r) SELECTED_RUNGS+=($OPTARG) ;;
        e) ERROR_RATE_THRESHOLD_PCT="$OPTARG" ;;
        h)
            echo "Usage: $0 -n <namespace> [-r \"rung rung ...\"] [-e error-rate-pct]"
            echo "  rungs default to the full ladder: ${ALL_RUNGS[*]}"
            echo "  error-rate-pct: stop the ladder if a rung exceeds this (default 5)"
            exit 0
            ;;
        *)
            echo "Usage: $0 -n <namespace> [-r \"rung rung ...\"] [-e error-rate-pct]" >&2
            exit 1
            ;;
    esac
done

RUNGS=("${SELECTED_RUNGS[@]:-${ALL_RUNGS[@]}}")

# ---- Step 1: namespace ------------------------------------------------------
if [ -z "$NAMESPACE" ]; then
    read -r -p "OpenShift namespace/project [default: $DEFAULT_NAMESPACE]: " NAMESPACE
fi
NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"

if ! "$OC" get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' not found — creating it."
    "$OC" new-project "$NAMESPACE" >/dev/null 2>&1 || "$OC" create namespace "$NAMESPACE"
    CREATED_RESOURCES+=("namespace/$NAMESPACE")
fi

# ---- Step 2: HF token secret -------------------------------------------------
# Only needed when the scenario's TOKENIZER_PATH points at a gated/private HF
# repo. Only prompted for if the secret doesn't already exist in this
# namespace — reruns against a namespace that already has it shouldn't ask
# again. Leaving the prompt blank skips the secret (the Job manifest already
# marks the secret lookup as optional, so that's fine for public tokenizers).
if "$OC" get secret aiperf-hf-token -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Secret aiperf-hf-token already exists in namespace '$NAMESPACE' — skipping prompt."
else
    if [ -z "${HF_TOKEN:-}" ]; then
        read -r -s -p "HuggingFace token (leave empty if tokenizer is public/already cached): " HF_TOKEN
        echo
    fi

    if [ -n "$HF_TOKEN" ]; then
        "$OC" create secret generic aiperf-hf-token \
            --from-literal=HF_TOKEN="$HF_TOKEN" \
            -n "$NAMESPACE" \
            --dry-run=client -o yaml | "$OC" apply -f - -n "$NAMESPACE"
        echo "Secret aiperf-hf-token created in namespace '$NAMESPACE'."
        CREATED_RESOURCES+=("secret/aiperf-hf-token")
    else
        echo "No HF token provided — skipping aiperf-hf-token secret (fine for public tokenizers)."
    fi
fi

echo "----------------------------------------"
echo "Namespace:        $NAMESPACE"
echo "Scenario:         $SCENARIO"
echo "Ladder (rungs):   ${RUNGS[*]}"
echo "Error threshold:  ${ERROR_RATE_THRESHOLD_PCT}%"
echo "----------------------------------------"

# ---- Step 3: generate ConfigMaps for the scenario ---------------------------
chmod +x "$SCRIPT_DIR/generate-configmaps.sh"
"$SCRIPT_DIR/generate-configmaps.sh" -n "$NAMESPACE" -s "$SCENARIO"
CREATED_RESOURCES+=("configmap/aiperf-sizing-${SCENARIO}-script" "configmap/aiperf-sizing-${SCENARIO}-prompts")

# ---- Step 4: shared results PVC (idempotent, once per namespace) -----------
"$OC" apply -f "$SCRIPT_DIR/results-pvc.yaml" -n "$NAMESPACE"
CREATED_RESOURCES+=("pvc/aiperf-sizing-results")

# ---- Step 5: run the ladder, one Job per rung, checking the circuit
# breaker between rungs ------------------------------------------------------
for rung in "${RUNGS[@]}"; do
    job_name="aiperf-sizing-${SCENARIO}-rung-${rung}"
    echo "==> Starting rung: concurrency=$rung (job/$job_name)"

    # Render the Job manifest for this rung: substitute the templated rung-1
    # values (metadata.name, labels.rung, env.CONCURRENCY, env.OUTPUT_DIR)
    # with this rung's values.
    sed \
        -e "s/aiperf-sizing-content-generation-rung-1/${job_name}/g" \
        -e "s/rung: \"1\"/rung: \"${rung}\"/g" \
        -e "s/value: \"1\"                                   # TODO: one of 1\/5\/10\/25\/50\/100\/200/value: \"${rung}\"/" \
        -e "s#/artifacts/content-generation/rung-1#/artifacts/content-generation/rung-${rung}#g" \
        "$JOB_TEMPLATE" | "$OC" apply -f - -n "$NAMESPACE"
    CREATED_RESOURCES+=("job/$job_name")

    echo "    Waiting for job/$job_name to complete (or fail)..."
    if ! "$OC" wait --for=condition=complete "job/$job_name" -n "$NAMESPACE" --timeout=7200s; then
        if "$OC" get job "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.failed}' | grep -q '[1-9]'; then
            echo "Error: rung $rung's job failed — stopping the ladder. Inspect with:" >&2
            echo "  oc logs -f job/$job_name -n $NAMESPACE" >&2
            STOPPED_EARLY="rung $rung (job failed)"
            break
        fi
    fi

    # ---- Circuit breaker: check this rung's error rate before continuing ---
    # Pull profile_export.json off the shared PVC via a throwaway pod, since
    # the Job's own pod may already be gone/Completed with no exec access.
    export_path="/artifacts/content-generation/rung-${rung}/profile_export.json"
    error_rate=$(
        "$OC" run "aiperf-sizing-check-${rung}" --rm -i --restart=Never \
            --image=busybox -n "$NAMESPACE" --quiet \
            --overrides="{\"spec\":{\"containers\":[{\"name\":\"check\",\"image\":\"busybox\",\"command\":[\"cat\",\"${export_path}\"],\"volumeMounts\":[{\"name\":\"artifacts\",\"mountPath\":\"/artifacts\"}]}],\"volumes\":[{\"name\":\"artifacts\",\"persistentVolumeClaim\":{\"claimName\":\"aiperf-sizing-results\"}}]}}" \
            2>/dev/null | grep -o '"error_rate"[^,}]*' | grep -o '[0-9.]*' || echo ""
    )

    if [ -n "$error_rate" ]; then
        echo "    Rung $rung error rate: ${error_rate}%"
        if awk -v er="$error_rate" -v th="$ERROR_RATE_THRESHOLD_PCT" 'BEGIN { exit !(er > th) }'; then
            echo "Error rate ${error_rate}% exceeds threshold ${ERROR_RATE_THRESHOLD_PCT}% at rung $rung." >&2
            echo "Stopping the ladder here — not submitting higher rungs." >&2
            STOPPED_EARLY="rung $rung (error rate ${error_rate}% > ${ERROR_RATE_THRESHOLD_PCT}%)"
            COMPLETED_RUNGS+=("$rung")
            break
        fi
    else
        echo "    Warning: could not read error_rate from $export_path — check manually before trusting later rungs." >&2
    fi

    COMPLETED_RUNGS+=("$rung")
done

echo "----------------------------------------"
echo "Done."
echo
echo "Resources created/updated this run:"
for resource in "${CREATED_RESOURCES[@]}"; do
    echo "  - $resource"
done
echo
echo "Ladder rungs completed: ${COMPLETED_RUNGS[*]:-none}"
if [ -n "$STOPPED_EARLY" ]; then
    echo "Ladder stopped early at: $STOPPED_EARLY"
fi
echo
echo "Watch progress with, e.g.:"
echo "  oc get jobs -n $NAMESPACE -w"
echo "  oc logs -f job/aiperf-sizing-${SCENARIO}-rung-<N> -n $NAMESPACE"
echo "----------------------------------------"
