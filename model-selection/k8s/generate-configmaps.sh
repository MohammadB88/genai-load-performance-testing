#!/usr/bin/env bash
#
# generate-configmaps.sh
#
# Creates (or updates) the ConfigMaps required by the Model Selection suite's
# Job manifests in this directory (rag-long-context-job.yaml,
# conversational-chat-job.yaml, content-generation-job.yaml). Each scenario
# needs two ConfigMaps: its run script and its sample prompts file, mounted
# read-only into the Job pod since the pod has no TTY for interactive prompts.
#
# Uses `oc` (OpenShift CLI) rather than `kubectl` — swap the binary below if
# running against plain Kubernetes instead; the `create configmap` subcommand
# is identical in both.
#
# This script does NOT create the results PVC (results-pvc.yaml) or the
# optional aiperf-hf-token Secret — apply/create those separately:
#   oc apply -f model-selection/k8s/results-pvc.yaml -n <namespace>
#   oc create secret generic aiperf-hf-token --from-literal=HF_TOKEN=hf_xxx -n <namespace>
#
# Usage:
#   ./generate-configmaps.sh -n <namespace>                       # interactive scenario picker
#   ./generate-configmaps.sh -n <namespace> -s rag-long-context -s content-generation
#   ./generate-configmaps.sh -n <namespace> -s all
#   NAMESPACE=my-namespace SCENARIOS="rag-long-context content-generation" ./generate-configmaps.sh
#
set -euo pipefail

OC="${OC_BIN:-oc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_SELECTION_DIR="$(dirname "$SCRIPT_DIR")"

# All known scenarios: name | script file | prompts file
ALL_SCENARIOS=(
    "rag-long-context|run_rag_long_context.sh|rag_long_context.jsonl"
    "conversational-chat|run_conversational_chat.sh|conversational_chat.jsonl"
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
            echo "  scenario: rag-long-context | conversational-chat | content-generation | all"
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
    read -r -p "OpenShift namespace/project: " NAMESPACE
fi
if [ -z "$NAMESPACE" ]; then
    echo "Error: namespace must be set (-n <namespace> or NAMESPACE env var)." >&2
    exit 1
fi

NS_ARGS=(-n "$NAMESPACE")

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
    read -r -p "Enter numbers separated by spaces (e.g. \"1 3\"), or 'a' for all: " selection

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

    script_path="$MODEL_SELECTION_DIR/$script_file"
    prompts_path="$MODEL_SELECTION_DIR/prompts/$prompts_file"

    if [ ! -f "$script_path" ]; then
        echo "Error: script file '$script_path' not found." >&2
        exit 1
    fi
    if [ ! -f "$prompts_path" ]; then
        echo "Error: prompts file '$prompts_path' not found." >&2
        exit 1
    fi

    script_cm="aiperf-${scenario}-script"
    prompts_cm="aiperf-${scenario}-prompts"

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
echo "Next: apply the results PVC (once) and the scenario Job(s), e.g."
echo "  oc apply -f model-selection/k8s/results-pvc.yaml -n $NAMESPACE"
echo "  oc apply -f model-selection/k8s/rag-long-context-job.yaml -n $NAMESPACE"
echo "----------------------------------------"
