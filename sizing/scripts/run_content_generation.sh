#!/usr/bin/env bash
#
# run_content_generation.sh
#
# Capacity/Sizing suite — "Content Generation" scenario.
# See docs/scenarios/sizing.md for the full ladder/versioning rationale and
# docs/metrics/sizing.md for what to read off the resulting export.
#
# Workload shape is IDENTICAL to model-selection/scripts/run_content_generation.sh
# (same prompts, same ISL/OSL) — only the concurrency treatment differs:
#   - Prompts: sizing/prompts/content_generation.jsonl — same 20 single-turn
#     creative/marketing briefs as the model-selection scenario
#     (--custom-dataset-type mooncake_trace, keyed on "text_input"), replayed
#     exactly once, in file order.
#   - ISL: ~100 tokens (fixed, short brief), driven by the prompt file content
#   - OSL: 800 tokens (long-form output)
#   - Turns: 1 (single-turn; no conversation/think-time flags apply)
#   - Streaming: yes
#   - Concurrency: ONE rung per invocation. This script does not loop the
#     ladder itself — call it once per rung with CONCURRENCY set to each of
#     1 / 5 / 10 / 25 / 50 / 100 / 200 (see docs/scenarios/sizing.md), same
#     pattern as the model-selection scripts' sweep points. Orchestrating the
#     full ladder (and enforcing the error-rate circuit breaker between
#     rungs) is the caller's responsibility — e.g. a driver script or a
#     per-rung K8s Job (see sizing/k8s/).
#
# Safety circuit breaker (manual, per docs/scenarios/sizing.md):
#   Check the error rate in this rung's export before launching the next
#   rung. If error rate exceeds ~5%, stop the ladder — do not proceed to
#   higher concurrency. This is not automated by this script since rungs are
#   separate invocations; it's the orchestrator's job to read the export and
#   decide whether to continue.
#
# GPU / server-side metrics capture:
#   Alongside the aiperf run, this script backgrounds a polling loop that
#   samples GPU utilization/memory/power/temperature for the duration of the
#   rung, writing CSV into the same OUTPUT_DIR. Uses `dcgmi dmon` if present
#   (preferred — DCGM is the NVIDIA-recommended data-center GPU monitor),
#   falling back to `nvidia-smi --query-gpu` if dcgmi isn't installed. This
#   assumes DCGM or the NVIDIA driver tools are already available on the node
#   the script runs on (e.g. a DCGM DaemonSet/sidecar on the cluster) — this
#   script does not install or stand up DCGM itself.
#   Prometheus-side server-internal metrics (queue depth, batch size, KV
#   cache % from the vLLM/NIM metrics exporter) are NOT captured by this
#   script — they require a Prometheus instance already scraping the backend,
#   which is environment-specific. Pull those separately for the run's time
#   window if your deployment has that exporter enabled.
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
# GPU_POLL_INTERVAL_SECS (optional, default 5) — sampling interval for the
# GPU polling loop.
#
# GPU_METRICS (optional, default on) — set to 0 to skip the GPU polling loop
# entirely (e.g. running against a CPU-only backend, or no DCGM/nvidia-smi
# available).
#
# Usage:
#   MODEL=my-model URL=http://localhost:8000 CONCURRENCY=1 ./run_content_generation.sh
#   CONCURRENCY=50 MODEL=my-model URL=http://localhost:8000 ./run_content_generation.sh
#   HF_TOKEN=hf_xxx TOKENIZER_PATH=meta-llama/Llama-3.1-8B MODEL=my-model URL=http://localhost:8000 CONCURRENCY=100 ./run_content_generation.sh
#   GPU_METRICS=0 MODEL=my-model URL=http://localhost:8000 CONCURRENCY=200 ./run_content_generation.sh
#   ./run_content_generation.sh                 # will prompt for MODEL/URL/CONCURRENCY
#
# Running the full ladder (7 separate invocations, checking error rate
# between each):
#   for c in 1 5 10 25 50 100 200; do
#     CONCURRENCY=$c MODEL=my-model URL=http://localhost:8000 ./run_content_generation.sh
#     # inspect artifacts/rung-$c export's error rate before continuing
#   done
#
set -euo pipefail

# ---- Config (override via env vars if you like) ----------------------------
INPUT_FILE="${INPUT_FILE:-$(dirname "$0")/prompts/content_generation.jsonl}"
CUSTOM_DATASET_TYPE="${CUSTOM_DATASET_TYPE:-mooncake_trace}"
ENDPOINT_TYPE="${ENDPOINT_TYPE:-chat}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/v1/chat/completions}"
CONCURRENCY="${CONCURRENCY:-1}"                          # one rung: 1/5/10/25/50/100/200
OUTPUT_TOKENS_MEAN="${OUTPUT_TOKENS_MEAN:-800}"
WARMUP_REQUESTS="${WARMUP_REQUESTS:-10}"
RANDOM_SEED="${RANDOM_SEED:-42}"
GPU_METRICS="${GPU_METRICS:-1}"
GPU_POLL_INTERVAL_SECS="${GPU_POLL_INTERVAL_SECS:-5}"

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
    read -r -p "Directory to store benchmark results [default: ./artifacts/rung-${CONCURRENCY}]: " OUTPUT_DIR
fi
OUTPUT_DIR="${OUTPUT_DIR:-./artifacts/rung-${CONCURRENCY}}"
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
echo "Scenario:     Content Generation (Sizing)"
echo "Model:        $MODEL"
echo "URL:          $URL"
echo "Endpoint:     $ENDPOINT_TYPE $ENDPOINT_PATH"
echo "Input file:   $INPUT_FILE ($CUSTOM_DATASET_TYPE)"
echo "Concurrency:  $CONCURRENCY (rung)"
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
echo "GPU metrics:  $([ "$GPU_METRICS" = "1" ] && echo "on (every ${GPU_POLL_INTERVAL_SECS}s)" || echo "off")"
echo "----------------------------------------"

# ---- GPU polling loop (backgrounded for the duration of the aiperf run) -----
GPU_POLL_PID=""
GPU_POLL_LOG="$OUTPUT_DIR/gpu-metrics.csv"

start_gpu_polling() {
    if [ "$GPU_METRICS" != "1" ]; then
        return
    fi

    if command -v dcgmi >/dev/null 2>&1; then
        echo "GPU polling: using dcgmi dmon -> $GPU_POLL_LOG"
        # -e: field IDs for util (203), mem used/total (252,253), power (155), temp (150)
        # -d: interval in ms
        dcgmi dmon -e 203,252,253,155,150 -d $((GPU_POLL_INTERVAL_SECS * 1000)) \
            > "$GPU_POLL_LOG" 2>&1 &
        GPU_POLL_PID=$!
    elif command -v nvidia-smi >/dev/null 2>&1; then
        echo "GPU polling: dcgmi not found, falling back to nvidia-smi -> $GPU_POLL_LOG"
        {
            while true; do
                nvidia-smi --query-gpu=timestamp,index,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu \
                    --format=csv,noheader
                sleep "$GPU_POLL_INTERVAL_SECS"
            done
        } > "$GPU_POLL_LOG" 2>&1 &
        GPU_POLL_PID=$!
    else
        echo "GPU polling: neither dcgmi nor nvidia-smi found on this node — skipping GPU metrics capture." >&2
        echo "(Set GPU_METRICS=0 to silence this if the backend is CPU-only.)" >&2
    fi
}

stop_gpu_polling() {
    if [ -n "$GPU_POLL_PID" ]; then
        kill "$GPU_POLL_PID" 2>/dev/null || true
        wait "$GPU_POLL_PID" 2>/dev/null || true
    fi
}
trap stop_gpu_polling EXIT

start_gpu_polling

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

echo "----------------------------------------"
echo "Rung complete. Check the export's error rate before running the next"
echo "rung in the ladder — stop if it exceeds ~5% (see docs/scenarios/sizing.md)."
echo "----------------------------------------"
