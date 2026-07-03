#!/usr/bin/env bash
#
# run-test.sh
#
# End-to-end entry point for running one or more Model Selection scenario
# tests as OpenShift Jobs. Ties together the other pieces in this directory:
#   1. Ensure the target namespace/project exists (creates it if not).
#   2. Create the aiperf-hf-token Secret, prompting for the token — but only
#      if that secret doesn't already exist in the namespace.
#   3. Generate the required ConfigMaps by calling generate-configmaps.sh.
#   4. Apply the shared results PVC (once) and the chosen scenario Job(s).
#   5. Print a summary of every resource created/updated this run.
#
# Uses `oc` (OpenShift CLI) — swap OC_BIN if running against plain
# Kubernetes instead (the subcommands used here are identical in kubectl).
#
# Usage:
#   ./run-test.sh                                  # interactive: prompts for namespace, HF token, test(s)
#   ./run-test.sh -n <namespace>
#   ./run-test.sh -n <namespace> -t rag-long-context -t content-generation
#   ./run-test.sh -n <namespace> -t all
#   HF_TOKEN=hf_xxx ./run-test.sh -n <namespace> -t all    # skips the HF token prompt
#
set -euo pipefail

OC="${OC_BIN:-oc}"
DEFAULT_NAMESPACE="aiperf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_SELECTION_DIR="$(dirname "$SCRIPT_DIR")"

# Resources created/touched this run, printed as a summary at the end.
CREATED_RESOURCES=()

# name | job manifest
ALL_TESTS=(
    "rag-long-context|rag-long-context-job.yaml"
    "conversational-chat|conversational-chat-job.yaml"
    "content-generation|content-generation-job.yaml"
)

NAMESPACE="${NAMESPACE:-}"
SELECTED_NAMES=(${TESTS:-})   # from env var TESTS, space-separated; may be overridden by -t

while getopts "n:t:h" opt; do
    case "$opt" in
        n) NAMESPACE="$OPTARG" ;;
        t) SELECTED_NAMES+=("$OPTARG") ;;
        h)
            echo "Usage: $0 -n <namespace> [-t <test>]..."
            echo "  test: rag-long-context | conversational-chat | content-generation | all"
            echo "  (repeat -t to select multiple; omit -t for an interactive picker)"
            exit 0
            ;;
        *)
            echo "Usage: $0 -n <namespace> [-t <test>]..." >&2
            exit 1
            ;;
    esac
done

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
# Only needed when a scenario's TOKENIZER_PATH points at a gated/private HF
# repo. Only prompted for if the secret doesn't already exist in this
# namespace — reruns against a namespace that already has it shouldn't ask
# again. Leaving the prompt blank skips the secret (the Job manifests already
# mark the secret lookup as optional, so that's fine for public tokenizers).
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

# ---- Step 3: pick which test(s) to run --------------------------------------
TESTS=()
if [ "${#SELECTED_NAMES[@]}" -gt 0 ]; then
    for entry in "${ALL_TESTS[@]}"; do
        name="${entry%%|*}"
        for wanted in "${SELECTED_NAMES[@]}"; do
            if [ "$wanted" = "all" ] || [ "$wanted" = "$name" ]; then
                TESTS+=("$entry")
                break
            fi
        done
    done
    if [ "${#TESTS[@]}" -eq 0 ]; then
        echo "Error: no matching tests for: ${SELECTED_NAMES[*]}" >&2
        echo "Valid names: all $(for e in "${ALL_TESTS[@]}"; do printf '%s ' "${e%%|*}"; done)" >&2
        exit 1
    fi
else
    echo "Which test(s) do you want to run?"
    i=1
    for entry in "${ALL_TESTS[@]}"; do
        echo "  $i) ${entry%%|*}"
        i=$((i + 1))
    done
    echo "  a) all"
    read -r -p "Enter numbers separated by spaces (e.g. \"1 3\"), or 'a' for all: " selection

    if [ "$selection" = "a" ] || [ "$selection" = "all" ]; then
        TESTS=("${ALL_TESTS[@]}")
    else
        for num in $selection; do
            if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#ALL_TESTS[@]}" ]; then
                echo "Error: invalid selection '$num'." >&2
                exit 1
            fi
            TESTS+=("${ALL_TESTS[$((num - 1))]}")
        done
    fi

    if [ "${#TESTS[@]}" -eq 0 ]; then
        echo "Error: no tests selected." >&2
        exit 1
    fi
fi

echo "----------------------------------------"
echo "Namespace:  $NAMESPACE"
echo "Tests:      $(for e in "${TESTS[@]}"; do printf '%s ' "${e%%|*}"; done)"
echo "----------------------------------------"

# ---- Step 4a: generate ConfigMaps for the selected tests --------------------
TEST_NAMES=()
for entry in "${TESTS[@]}"; do
    TEST_NAMES+=("${entry%%|*}")
done

chmod +x "$SCRIPT_DIR/generate-configmaps.sh"
"$SCRIPT_DIR/generate-configmaps.sh" -n "$NAMESPACE" $(printf -- '-s %s ' "${TEST_NAMES[@]}")
for name in "${TEST_NAMES[@]}"; do
    CREATED_RESOURCES+=("configmap/aiperf-${name}-script" "configmap/aiperf-${name}-prompts")
done

# ---- Step 4b: shared results PVC (idempotent, once per namespace) ----------
"$OC" apply -f "$SCRIPT_DIR/results-pvc.yaml" -n "$NAMESPACE"
CREATED_RESOURCES+=("pvc/aiperf-model-selection-results")

# ---- Step 4c: apply the Job manifest for each selected test -----------------
for entry in "${TESTS[@]}"; do
    IFS='|' read -r test_name job_file <<< "$entry"
    echo "==> Starting test: $test_name"
    "$OC" apply -f "$SCRIPT_DIR/$job_file" -n "$NAMESPACE"
    CREATED_RESOURCES+=("job/aiperf-${test_name}")
done

echo "----------------------------------------"
echo "Done. Job(s) submitted in namespace '$NAMESPACE'."
echo
echo "Resources created/updated this run:"
for resource in "${CREATED_RESOURCES[@]}"; do
    echo "  - $resource"
done
echo
echo "Watch progress with, e.g.:"
echo "  oc get pods -n $NAMESPACE -w"
echo "  oc logs -f job/aiperf-<test-name> -n $NAMESPACE"
echo "----------------------------------------"
