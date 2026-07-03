#!/usr/bin/env bash
#
# run_content_generation.sh
#
# Model Selection suite — "Content Generation" scenario.
# See docs/scenarios/model-selection.md for the full scenario matrix and
# docs/metrics/model-selection.md for what to read off the resulting export.
#
# Workload shape (V1 baseline, real sample prompts):
#   - Prompts: model-selection/prompts/content_generation.jsonl — real
#     single-turn requests (--custom-dataset-type mooncake_trace, keyed on
#     "text_input" per AIPerf's MooncakeTrace schema), each a short creative/
#     marketing brief. NOT synthetic token noise. Each record is replayed
#     exactly once, in file order (mooncake_trace semantics) — NOT randomly
#     sampled with replacement.
#   - ISL: ~100 tokens (fixed, short brief), driven by the prompt file content
#   - OSL: 800 tokens (long-form output)
#   - Turns: 1 (single-turn; no conversation/think-time flags apply)
#   - Streaming: yes
#   - Concurrency: baseline 1. Set CONCURRENCY to run a sweep point
#     (1/5/10/25) instead.
#
# This mirrors run_rag_long_context.sh's confirmed-working text_input /
# mooncake_trace pattern rather than random_pool (rejected by AIPerf — see
# that script's header for detail) or multi_turn (still unresolved, see
# run_conversational_chat.sh).
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
# TOKENIZER_TRUST_REMOTE_CODE (optional, default off) — set to 1 to pass
# --tokenizer-trust-remote-code. Needed for repos whose tokenizer requires
# executing custom Python from the HF repo (AIPerf will error with "Failed
# to load tokenizer" and suggest this flag if so). This runs arbitrary code
# from that repo — review it on HuggingFace before enabling.
#
# Usage:
#   MODEL=my-model URL=http://localhost:8000 ./run_content_generation.sh
#   CONCURRENCY=10 MODEL=my-model URL=http://localhost:8000 ./run_content_generation.sh
#   HF_TOKEN=hf_xxx TOKENIZER_PATH=meta-llama/Llama-3.1-8B MODEL=my-model URL=http://localhost:8000 ./run_content_generation.sh
#   HF_HOME=/tmp/hf-cache TOKENIZER_PATH=ibm-granite/granite-3.1-8b-instruct MODEL=my-model URL=http://localhost:8000 ./run_content_generation.sh
#   TOKENIZER_TRUST_REMOTE_CODE=1 TOKENIZER_PATH=mradermacher/granite-3.3-8b-instruct-abliterated-i1-GGUF MODEL=my-model URL=http://localhost:8000 ./run_content_generation.sh
#   ./run_content_generation.sh                 # will prompt for both
#
set -euo pipefail

# ---- Config (override via env vars if you like) ----------------------------
INPUT_FILE="${INPUT_FILE:-$(dirname "$0")/prompts/content_generation.jsonl}"
CUSTOM_DATASET_TYPE="${CUSTOM_DATASET_TYPE:-mooncake_trace}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-1}"                          # baseline; sweep: 1/5/10/25
OUTPUT_TOKENS_MEAN="${OUTPUT_TOKENS_MEAN:-800}"
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

# ---- Get TOKENIZER_TRUST_REMOTE_CODE: env var only, default off -------------
# Some repos (e.g. custom fine-tunes/quantizations without a standard
# tokenizer_config.json) require executing tokenizer code from the HF repo
# itself. Off by default since it runs arbitrary Python from that repo —
# review the repo's code before setting this to 1.
if [ "${TOKENIZER_TRUST_REMOTE_CODE:-0}" = "1" ]; then
    TOKENIZER_ARGS+=(--tokenizer-trust-remote-code)
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
    echo "Set INPUT_FILE=/path/to/content_generation.jsonl to override." >&2
    exit 1
fi

echo "----------------------------------------"
echo "Scenario:     Content Generation (Model Selection)"
echo "Model:        $MODEL"
echo "URL:          $URL"
echo "Endpoint:     $ENDPOINT_TYPE $ENDPOINT_PATH"
echo "Input file:   $INPUT_FILE ($CUSTOM_DATASET_TYPE)"
echo "Concurrency:  $CONCURRENCY"
echo "OSL:          ${OUTPUT_TOKENS_MEAN} tokens"
if [ -n "${TOKENIZER_PATH:-}" ]; then
    echo "Tokenizer:    $TOKENIZER_PATH (local, HF Hub disabled)"
else
    echo "Tokenizer:    (none specified, AIPerf will resolve via HuggingFace)"
fi
if [ "${TOKENIZER_TRUST_REMOTE_CODE:-0}" = "1" ]; then
    echo "Trust remote code: yes (--tokenizer-trust-remote-code)"
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
    --output-tokens-mean "$OUTPUT_TOKENS_MEAN" \
    --concurrency "$CONCURRENCY" \
    --warmup-request-count "$WARMUP_REQUESTS" \
    --random-seed "$RANDOM_SEED" \
    --artifact-dir "$OUTPUT_DIR" \
    "${TOKENIZER_ARGS[@]}"
