#!/usr/bin/env bash
#
# run_conversational_chat.sh
#
# Model Selection suite — "Conversational Chat" scenario.
# See docs/scenarios/model-selection.md for the full scenario matrix and
# docs/metrics/model-selection.md for what to read off the resulting export.
#
# Workload shape (V1 baseline, real sample prompts):
#   - Prompts: model-selection/prompts/conversational_chat.jsonl — real
#     multi-turn conversations (--custom-dataset-type multi_turn), NOT
#     synthetic token noise. ISL is therefore whatever these prompts
#     tokenize to (targeting ~150 tokens/turn) rather than a fixed value.
#   - OSL: 200 tokens (stddev 50)
#   - Turns: 3-5 per conversation (mean ~4), fixed by the prompt file itself
#   - Think-time between turns: 2-5s human read/type time
#     (--conversation-turn-delay-mean/stddev, NOT the short tool-round-trip
#     delay used by the Agentic scenario)
#   - Streaming: yes
#   - Concurrency: baseline 1. Set CONCURRENCY to run a sweep point
#     (1/5/10/25) instead.
#
# MODEL and URL are read from environment variables if set, otherwise
# the script will prompt for them interactively.
#
# Usage:
#   MODEL=my-model URL=http://localhost:8000 ./run_conversational_chat.sh
#   CONCURRENCY=10 MODEL=my-model URL=http://localhost:8000 ./run_conversational_chat.sh
#   ./run_conversational_chat.sh                 # will prompt for both
#
set -euo pipefail

# ---- Config (override via env vars if you like) ----------------------------
INPUT_FILE="${INPUT_FILE:-$(dirname "$0")/prompts/conversational_chat.jsonl}"
CUSTOM_DATASET_TYPE="${CUSTOM_DATASET_TYPE:-multi_turn}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-1}"                          # baseline; sweep: 1/5/10/25
CONVERSATION_TURN_DELAY_MEAN_MS="${CONVERSATION_TURN_DELAY_MEAN_MS:-3500}"     # 2-5s human think time
CONVERSATION_TURN_DELAY_STDDEV_MS="${CONVERSATION_TURN_DELAY_STDDEV_MS:-750}"
OUTPUT_TOKENS_MEAN="${OUTPUT_TOKENS_MEAN:-200}"
OUTPUT_TOKENS_STDDEV="${OUTPUT_TOKENS_STDDEV:-50}"
WARMUP_REQUESTS="${WARMUP_REQUESTS:-10}"
RANDOM_SEED="${RANDOM_SEED:-42}"

# ---- Get MODEL: env var, else prompt ----------------------------------------
if [ -z "${MODEL:-}" ]; then
    read -r -p "Enter model name (--model): " MODEL
fi

# ---- Get URL: env var, else prompt ------------------------------------------
if [ -z "${URL:-}" ]; then
    read -r -p "Enter endpoint URL (--url), e.g. http://localhost:8000: " URL
fi

# ---- Get TOKENIZER_PATH: env var, else prompt (optional) -------------------
# Accepts either a local directory (offline tokenizer files) or a HuggingFace
# repo id (e.g. ibm-granite/granite-3.1-8b-instruct) — useful when --model
# doesn't uniquely resolve to one tokenizer on the Hub.
if [ -z "${TOKENIZER_PATH:-}" ]; then
    read -r -p "Tokenizer: local dir or HF repo id (leave empty to use --model as tokenizer name): " TOKENIZER_PATH
fi

TOKENIZER_ARGS=()
if [ -n "${TOKENIZER_PATH:-}" ]; then
    if [ -d "$TOKENIZER_PATH" ]; then
        # Local directory: force offline mode so transformers never attempts
        # to reach huggingface.co, even if the local files are incomplete.
        export HF_HUB_OFFLINE=1
        export TRANSFORMERS_OFFLINE=1
    fi
    TOKENIZER_ARGS=(--tokenizer "$TOKENIZER_PATH")
fi

# ---- Get OUTPUT_DIR: env var, else prompt -----------------------------------
if [ -z "${OUTPUT_DIR:-}" ]; then
    read -r -p "Directory to store benchmark results [default: ./artifacts]: " OUTPUT_DIR
fi
OUTPUT_DIR="${OUTPUT_DIR:-./artifacts}"
mkdir -p "$OUTPUT_DIR"

if [ -z "$MODEL" ] || [ -z "$URL" ]; then
    echo "Error: MODEL and URL must both be set." >&2
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: input file '$INPUT_FILE' not found." >&2
    echo "Set INPUT_FILE=/path/to/conversational_chat.jsonl to override." >&2
    exit 1
fi

echo "----------------------------------------"
echo "Scenario:     Conversational Chat (Model Selection)"
echo "Model:        $MODEL"
echo "URL:          $URL"
echo "Endpoint:     $ENDPOINT_TYPE $ENDPOINT_PATH"
echo "Input file:   $INPUT_FILE ($CUSTOM_DATASET_TYPE)"
echo "Concurrency:  $CONCURRENCY"
echo "Think-time:   ${CONVERSATION_TURN_DELAY_MEAN_MS}ms ± ${CONVERSATION_TURN_DELAY_STDDEV_MS}ms"
echo "OSL:          ${OUTPUT_TOKENS_MEAN} tokens (stddev ${OUTPUT_TOKENS_STDDEV})"
if [ -n "${TOKENIZER_PATH:-}" ]; then
    echo "Tokenizer:    $TOKENIZER_PATH (local, HF Hub disabled)"
else
    echo "Tokenizer:    (none specified, AIPerf will resolve via HuggingFace)"
fi
echo "Output dir:   $OUTPUT_DIR"
echo "----------------------------------------"

aiperf profile \
    --model "$MODEL" \
    --url "$URL" \
    --endpoint-type "$ENDPOINT_TYPE" \
    --endpoint "$ENDPOINT_PATH" \
    --streaming \
    --input-file "$INPUT_FILE" \
    --custom-dataset-type "$CUSTOM_DATASET_TYPE" \
    --conversation-turn-delay-mean "$CONVERSATION_TURN_DELAY_MEAN_MS" \
    --conversation-turn-delay-stddev "$CONVERSATION_TURN_DELAY_STDDEV_MS" \
    --output-tokens-mean "$OUTPUT_TOKENS_MEAN" \
    --output-tokens-stddev "$OUTPUT_TOKENS_STDDEV" \
    --concurrency "$CONCURRENCY" \
    --warmup-request-count "$WARMUP_REQUESTS" \
    --random-seed "$RANDOM_SEED" \
    --artifact-dir "$OUTPUT_DIR" \
    "${TOKENIZER_ARGS[@]}"
