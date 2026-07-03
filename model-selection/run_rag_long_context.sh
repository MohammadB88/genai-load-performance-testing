#!/usr/bin/env bash
#
# run_rag_long_context.sh
#
# Model Selection suite — "RAG / Long-Context Q&A" scenario.
# See docs/scenarios/model-selection.md for the full scenario matrix and
# docs/metrics/model-selection.md for what to read off the resulting export.
#
# Workload shape (V1 baseline, real sample prompts):
#   - Prompts: model-selection/prompts/rag_long_context.jsonl — real
#     single-turn requests (--custom-dataset-type random_pool), each a long
#     retrieved-document-style context followed by a question. NOT synthetic
#     token noise.
#   - ISL: ~4,000 tokens (fixed), driven by the prompt file content itself
#   - OSL: 250 tokens
#   - Turns: 1 (single-turn; no conversation/think-time flags apply)
#   - Streaming: yes
#   - Concurrency: baseline 1. Set CONCURRENCY to run a sweep point
#     (1/5/10/25) instead.
#
# This mirrors sample-script.sh's random_pool + text_input pattern rather
# than the multi_turn dataset type, which is still unresolved
# (AIPerf rejects fields like turn_delay we haven't tracked down the exact
# schema for yet — see run_conversational_chat.sh).
#
# MODEL and URL are read from environment variables if set, otherwise
# the script will prompt for them interactively.
#
# HF_TOKEN (optional) is read from the environment if set, otherwise the
# script will prompt for it — only needed when TOKENIZER_PATH points at a
# gated/private HuggingFace repo (e.g. meta-llama/*) rather than a local
# directory. It is exported so transformers/huggingface_hub picks it up.
#
# HF_HOME (optional) overrides where huggingface_hub caches downloaded
# tokenizer files. Set this if you hit a PermissionError against the image's
# default cache dir (e.g. /app/.cache/huggingface in a non-root/read-only
# container) — point it at a writable path instead, e.g. /tmp/hf-cache.
#
# Usage:
#   MODEL=my-model URL=http://localhost:8000 ./run_rag_long_context.sh
#   CONCURRENCY=10 MODEL=my-model URL=http://localhost:8000 ./run_rag_long_context.sh
#   HF_TOKEN=hf_xxx TOKENIZER_PATH=meta-llama/Llama-3.1-8B MODEL=my-model URL=http://localhost:8000 ./run_rag_long_context.sh
#   HF_HOME=/tmp/hf-cache TOKENIZER_PATH=ibm-granite/granite-3.1-8b-instruct MODEL=my-model URL=http://localhost:8000 ./run_rag_long_context.sh
#   ./run_rag_long_context.sh                 # will prompt for both
#
set -euo pipefail

# ---- Config (override via env vars if you like) ----------------------------
INPUT_FILE="${INPUT_FILE:-$(dirname "$0")/prompts/rag_long_context.jsonl}"
CUSTOM_DATASET_TYPE="${CUSTOM_DATASET_TYPE:-random_pool}"
DATASET_SAMPLING_STRATEGY="${DATASET_SAMPLING_STRATEGY:-random}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-1}"                          # baseline; sweep: 1/5/10/25
OUTPUT_TOKENS_MEAN="${OUTPUT_TOKENS_MEAN:-250}"
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

# ---- Get HF_TOKEN: env var, else prompt (optional) --------------------------
# Only needed when the tokenizer must be pulled from a gated/private HF repo
# (e.g. meta-llama/*). Skipped entirely for local tokenizer dirs, since those
# run fully offline (HF_HUB_OFFLINE=1 above).
if [ -z "${TOKENIZER_PATH:-}" ] || [ ! -d "${TOKENIZER_PATH:-}" ]; then
    if [ -z "${HF_TOKEN:-}" ]; then
        read -r -s -p "HuggingFace token (--token, leave empty if tokenizer is public/already cached): " HF_TOKEN
        echo
    fi
fi
if [ -n "${HF_TOKEN:-}" ]; then
    export HF_TOKEN
fi

# ---- HF cache dir override (avoids PermissionError in read-only/non-root
# containers, where the image's default HF_HOME e.g. /app/.cache/huggingface
# isn't writable by the runtime user) ----------------------------------------
if [ -n "${HF_HOME:-}" ]; then
    export HF_HOME
    mkdir -p "$HF_HOME"
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
    echo "Set INPUT_FILE=/path/to/rag_long_context.jsonl to override." >&2
    exit 1
fi

echo "----------------------------------------"
echo "Scenario:     RAG / Long-Context Q&A (Model Selection)"
echo "Model:        $MODEL"
echo "URL:          $URL"
echo "Endpoint:     $ENDPOINT_TYPE $ENDPOINT_PATH"
echo "Input file:   $INPUT_FILE ($CUSTOM_DATASET_TYPE, $DATASET_SAMPLING_STRATEGY)"
echo "Concurrency:  $CONCURRENCY"
echo "OSL:          ${OUTPUT_TOKENS_MEAN} tokens"
if [ -n "${TOKENIZER_PATH:-}" ]; then
    echo "Tokenizer:    $TOKENIZER_PATH (local, HF Hub disabled)"
else
    echo "Tokenizer:    (none specified, AIPerf will resolve via HuggingFace)"
fi
if [ -n "${HF_TOKEN:-}" ]; then
    echo "HF_TOKEN:     set"
else
    echo "HF_TOKEN:     (none, only needed for gated/private tokenizer repos)"
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
    --dataset-sampling-strategy "$DATASET_SAMPLING_STRATEGY" \
    --output-tokens-mean "$OUTPUT_TOKENS_MEAN" \
    --concurrency "$CONCURRENCY" \
    --warmup-request-count "$WARMUP_REQUESTS" \
    --random-seed "$RANDOM_SEED" \
    --artifact-dir "$OUTPUT_DIR" \
    "${TOKENIZER_ARGS[@]}"
