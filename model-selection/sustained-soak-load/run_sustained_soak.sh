#!/usr/bin/env bash
#
# run_sustained_soak.sh
#
# Model Selection suite — "Sustained / Soak Load" scenario.
# See docs/scenarios/sustained-soak-load.md for why this scenario exists and
# how it differs from the 6 workload-profile scenarios.
#
# Unlike the other model-selection scripts (fixed prompt file, mooncake_trace,
# replayed once, stopped by request count), this scenario is duration-driven:
# the goal is to observe whether the deployment degrades over a long
# continuous run (memory leaks, KV-cache fragmentation, GC pauses), not to
# produce a request-count-matched comparison point.
#
# Workload shape:
#   - Prompts: model-selection/sustained-soak-load/prompts/sustained_soak.jsonl
#     — a small pool of short, varied realistic prompts
#     (--custom-dataset-type random_pool, keyed on "text"), sampled WITH
#     REPLACEMENT via --dataset-sampling-strategy random for the duration of
#     the run. NOT replayed once like the other scenarios' mooncake_trace
#     files — repeats are expected and fine here, since the point is
#     sustained traffic, not one-shot coverage of every prompt. See
#     docs/scenarios/README.md for why random_pool (not mooncake_trace) is
#     the right dataset type for this scenario specifically.
#   - Stopping condition: --benchmark-duration (default 1200s / 20 min), not
#     request count. Paired with --benchmark-grace-period so in-flight
#     responses at the deadline are still counted.
#   - Concurrency: fixed (default 20), not swept — steady sustained load is
#     the point, not a comparison ladder.
#   - Streaming: yes
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
#   MODEL=my-model URL=http://localhost:8000 ./run_sustained_soak.sh
#   DURATION_SECONDS=3600 CONCURRENCY=20 MODEL=my-model URL=http://localhost:8000 ./run_sustained_soak.sh
#   HF_TOKEN=hf_xxx TOKENIZER_PATH=meta-llama/Llama-3.1-8B MODEL=my-model URL=http://localhost:8000 ./run_sustained_soak.sh
#   ./run_sustained_soak.sh                 # will prompt for both
#
set -euo pipefail

# ---- Config (override via env vars if you like) ----------------------------
INPUT_FILE="${INPUT_FILE:-$(dirname "$0")/prompts/sustained_soak.jsonl}"
CUSTOM_DATASET_TYPE="${CUSTOM_DATASET_TYPE:-random_pool}"
DATASET_SAMPLING_STRATEGY="${DATASET_SAMPLING_STRATEGY:-random}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-20}"                          # fixed steady load, not swept
DURATION_SECONDS="${DURATION_SECONDS:-1200}"              # 20 minutes
GRACE_PERIOD_SECONDS="${GRACE_PERIOD_SECONDS:-30}"
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
    echo "Set INPUT_FILE=/path/to/sustained_soak.jsonl to override." >&2
    exit 1
fi

echo "----------------------------------------"
echo "Scenario:     Sustained / Soak Load (Model Selection)"
echo "Model:        $MODEL"
echo "URL:          $URL"
echo "Endpoint:     $ENDPOINT_TYPE $ENDPOINT_PATH"
echo "Input file:   $INPUT_FILE ($CUSTOM_DATASET_TYPE, sampling: $DATASET_SAMPLING_STRATEGY)"
echo "Concurrency:  $CONCURRENCY (fixed, not swept)"
echo "Duration:     ${DURATION_SECONDS}s (grace period ${GRACE_PERIOD_SECONDS}s)"
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
    --dataset-sampling-strategy "$DATASET_SAMPLING_STRATEGY" \
    --concurrency "$CONCURRENCY" \
    --benchmark-duration "$DURATION_SECONDS" \
    --benchmark-grace-period "$GRACE_PERIOD_SECONDS" \
    --warmup-request-count "$WARMUP_REQUESTS" \
    --random-seed "$RANDOM_SEED" \
    --artifact-dir "$OUTPUT_DIR" \
    "${TOKENIZER_ARGS[@]}"
