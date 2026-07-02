#!/usr/bin/env bash
#
# run_conversational_chat.sh
#
# Model Selection suite — "Conversational Chat" scenario.
# See docs/scenarios/model-selection.md for the full scenario matrix and
# docs/metrics/model-selection.md for what to read off the resulting export.
#
# Workload shape (V1 baseline, synthetic prompts):
#   - ISL: 150 new tokens/turn
#   - OSL: 200 tokens (stddev 50)
#   - Turns: 4 ± 1 per conversation
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
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-1}"                          # baseline; sweep: 1/5/10/25
CONVERSATION_NUM="${CONVERSATION_NUM:-20}"
CONVERSATION_TURN_MEAN="${CONVERSATION_TURN_MEAN:-4}"
CONVERSATION_TURN_STDDEV="${CONVERSATION_TURN_STDDEV:-1}"
CONVERSATION_TURN_DELAY_MEAN_MS="${CONVERSATION_TURN_DELAY_MEAN_MS:-3500}"     # 2-5s human think time
CONVERSATION_TURN_DELAY_STDDEV_MS="${CONVERSATION_TURN_DELAY_STDDEV_MS:-750}"
SYNTHETIC_INPUT_TOKENS_MEAN="${SYNTHETIC_INPUT_TOKENS_MEAN:-150}"             # per-turn new tokens
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
# If set, AIPerf loads the tokenizer directly from local files and makes
# no calls to HuggingFace Hub.
if [ -z "${TOKENIZER_PATH:-}" ]; then
    read -r -p "Path to local tokenizer (leave empty to use HF, model name as tokenizer): " TOKENIZER_PATH
fi

TOKENIZER_ARGS=()
if [ -n "${TOKENIZER_PATH:-}" ]; then
    if [ ! -d "$TOKENIZER_PATH" ]; then
        echo "Error: tokenizer path '$TOKENIZER_PATH' does not exist or is not a directory." >&2
        exit 1
    fi
    # Force offline mode so transformers never attempts to reach huggingface.co,
    # even if the local files are somehow incomplete.
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1
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

echo "----------------------------------------"
echo "Scenario:     Conversational Chat (Model Selection)"
echo "Model:        $MODEL"
echo "URL:          $URL"
echo "Endpoint:     $ENDPOINT_TYPE $ENDPOINT_PATH"
echo "Concurrency:  $CONCURRENCY"
echo "Conversations:$CONVERSATION_NUM"
echo "Turns/conv:   ${CONVERSATION_TURN_MEAN} ± ${CONVERSATION_TURN_STDDEV}"
echo "Think-time:   ${CONVERSATION_TURN_DELAY_MEAN_MS}ms ± ${CONVERSATION_TURN_DELAY_STDDEV_MS}ms"
echo "ISL:          ${SYNTHETIC_INPUT_TOKENS_MEAN} tokens/turn"
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
    --conversation-num "$CONVERSATION_NUM" \
    --conversation-turn-mean "$CONVERSATION_TURN_MEAN" \
    --conversation-turn-stddev "$CONVERSATION_TURN_STDDEV" \
    --conversation-turn-delay-mean "$CONVERSATION_TURN_DELAY_MEAN_MS" \
    --conversation-turn-delay-stddev "$CONVERSATION_TURN_DELAY_STDDEV_MS" \
    --synthetic-input-tokens-mean "$SYNTHETIC_INPUT_TOKENS_MEAN" \
    --output-tokens-mean "$OUTPUT_TOKENS_MEAN" \
    --output-tokens-stddev "$OUTPUT_TOKENS_STDDEV" \
    --concurrency "$CONCURRENCY" \
    --warmup-request-count "$WARMUP_REQUESTS" \
    --random-seed "$RANDOM_SEED" \
    --artifact-dir "$OUTPUT_DIR" \
    "${TOKENIZER_ARGS[@]}"
