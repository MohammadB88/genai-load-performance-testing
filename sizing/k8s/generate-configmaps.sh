#!/usr/bin/env bash
#
# generate-configmaps.sh
#
# Creates (or updates) the ConfigMaps required by the Capacity/Sizing suite's
# Job manifest in this directory (content-generation-job.yaml). Only one
# scenario is implemented so far (Content Generation) — Conversational Chat
# and RAG/Long-Context are out of v1 scope (see version2/, CLAUDE.md). This
# script's structure mirrors model-selection/k8s/generate-configmaps.sh so
# adding scenarios later is a small diff.
#
# Each scenario needs two ConfigMaps: its run script and its sample prompts
# file, mounted read-only into the Job pod since the pod has no TTY for
# interactive prompts. These are shared across all ladder rungs — the rung's
# CONCURRENCY value is set via the Job manifest's env, not the ConfigMap.
#
# Uses `oc` (OpenShift CLI) rather than `kubectl` — swap the binary below if
# running against plain Kubernetes instead; the `create configmap` subcommand
# is identical in both.
#
# This script does NOT create the results PVC (results-pvc.yaml) or the
# optional aiperf-hf-token Secret — apply/create those separately:
#   oc apply -f sizing/k8s/results-pvc.yaml -n <namespace>
#   oc create secret generic aiperf-hf-token --from-literal=HF_TOKEN=hf_xxx -n <namespace>
#
# Usage:
#   ./generate-configmaps.sh -n <namespace>
#   ./generate-configmaps.sh -n <namespace> -s content-generation
#   ./generate-configmaps.sh -n <namespace> -s all
#   NAMESPACE=my-namespace SCENARIOS="content-generation" ./generate-configmaps.sh
#   ./generate-configmaps.sh                                      # prompts for namespace; blank -> "aiperf"
#
set -euo pipefail

OC="${OC_BIN:-oc}"
DEFAULT_NAMESPACE="aiperf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZING_DIR="$(dirname "$SCRIPT_DIR")"
SCENARIOS_SCRIPTS_DIR="$SIZING_DIR/scripts"

# All known scenarios: name | script file | prompts file
# Only content-generation is implemented for v1 — extend this list when
# conversational-chat / rag-long-context are brought into the sizing suite.
ALL_SCENARIOS=(
    "content-generation|run_content_generation.sh|content_generation.jsonl"
)

NAMESPACE="${NAMESPACE:-}"
SELECTED_NAMES=(${SCENARIOS:-})   # from env var SCENARIOS, space-separated; may be overridden by -s

while getopts "n:s:h" opt; do
    case "$opt" in
        n) NAMESPACE="$OPTARG" ;;
        s) SELECTED_NAMES+=("$OPTARG") ;;
        h)
            echo "Usage: $0 -n <namespace> [-s <scenario>]..."
            echo "  scenario: content-generation | all"
            echo "  (repeat -s to select multiple; omit -s for an interactive picker)"
            exit 0
            ;;
        *)
            echo "Usage: $0 -n <namespace> [-s <scenario>]..." >&2
            exit 1
            ;;
    esac
done

if [ -z "$NAMESPACE" ]; then
    read -r -p "OpenShift namespace/project [default: $DEFAULT_NAMESPACE]: " NAMESPACE
fi
NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"

NS_ARGS=(-n "$NAMESPACE")

# ---- Ensure the namespace/project exists ------------------------------------
if ! "$OC" get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' not found — creating it."
    "$OC" new-project "$NAMESPACE" >/dev/null 2>&1 || "$OC" create namespace "$NAMESPACE"
fi

# ---- Pick which scenarios to generate configmaps for ------------------------
SCENARIOS=()
if [ "${#SELECTED_NAMES[@]}" -gt 0 ]; then
    # Non-interactive: -s flags or SCENARIOS env var were given.
    for entry in "${ALL_SCENARIOS[@]}"; do
        name="${entry%%|*}"
        for wanted in "${SELECTED_NAMES[@]}"; do
            if [ "$wanted" = "all" ] || [ "$wanted" = "$name" ]; then
                SCENARIOS+=("$entry")
                break
            fi
        done
    done
    if [ "${#SCENARIOS[@]}" -eq 0 ]; then
        echo "Error: no matching scenarios for: ${SELECTED_NAMES[*]}" >&2
        echo "Valid names: all $(for e in "${ALL_SCENARIOS[@]}"; do printf '%s ' "${e%%|*}"; done)" >&2
        exit 1
    fi
else
    # Interactive: prompt with a numbered multi-select.
    echo "Which scenario(s) do you want to generate ConfigMaps for?"
    i=1
    for entry in "${ALL_SCENARIOS[@]}"; do
        echo "  $i) ${entry%%|*}"
        i=$((i + 1))
    done
    echo "  a) all"
    read -r -p "Enter numbers separated by spaces (e.g. \"1\"), or 'a' for all: " selection

    if [ "$selection" = "a" ] || [ "$selection" = "all" ]; then
        SCENARIOS=("${ALL_SCENARIOS[@]}")
    else
        for num in $selection; do
            if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#ALL_SCENARIOS[@]}" ]; then
                echo "Error: invalid selection '$num'." >&2
                exit 1
            fi
            SCENARIOS+=("${ALL_SCENARIOS[$((num - 1))]}")
        done
    fi

    if [ "${#SCENARIOS[@]}" -eq 0 ]; then
        echo "Error: no scenarios selected." >&2
        exit 1
    fi
fi

echo "----------------------------------------"
echo "Namespace:  $NAMESPACE"
echo "oc binary:  $OC"
echo "Scenarios:  $(for e in "${SCENARIOS[@]}"; do printf '%s ' "${e%%|*}"; done)"
echo "----------------------------------------"

for entry in "${SCENARIOS[@]}"; do
    IFS='|' read -r scenario script_file prompts_file <<< "$entry"

    script_path="$SCENARIOS_SCRIPTS_DIR/$script_file"
    prompts_path="$SIZING_DIR/prompts/$prompts_file"

    if [ ! -f "$script_path" ]; then
        echo "Error: script file '$script_path' not found." >&2
        exit 1
    fi
    if [ ! -f "$prompts_path" ]; then
        echo "Error: prompts file '$prompts_path' not found." >&2
        exit 1
    fi

    script_cm="aiperf-sizing-${scenario}-script"
    prompts_cm="aiperf-sizing-${scenario}-prompts"

    echo "==> $scenario"
    echo "    ConfigMap: $script_cm  (from $script_file)"
    "$OC" create configmap "$script_cm" \
        --from-file="${script_file}=${script_path}" \
        "${NS_ARGS[@]}" \
        --dry-run=client -o yaml | "$OC" apply -f - "${NS_ARGS[@]}"

    echo "    ConfigMap: $prompts_cm  (from $prompts_file)"
    "$OC" create configmap "$prompts_cm" \
        --from-file="${prompts_file}=${prompts_path}" \
        "${NS_ARGS[@]}" \
        --dry-run=client -o yaml | "$OC" apply -f - "${NS_ARGS[@]}"
done

echo "----------------------------------------"
echo "Done. ConfigMaps created/updated in namespace '$NAMESPACE'."
echo "Next: apply the results PVC (once) and run the ladder, e.g."
echo "  oc apply -f sizing/k8s/results-pvc.yaml -n $NAMESPACE"
echo "  ./run-test.sh -n $NAMESPACE"
echo "----------------------------------------"
