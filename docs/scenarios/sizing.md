# Capacity/Sizing Suite — Scenarios

## Versioning

- **V0 (POC):** Chat + Batch only, ladder 1/10/50, single model/config, steady-state only.
- **V1 (full core):** all workload profiles in v1 scope (same as Model Selection), full fixed ladder, steady-state only, GPU/server-side metrics captured at every rung.
- **V2 (customer-calibrated):** customer's real prompts, ladder run once per actual deployment config (e.g. per GPU/MIG profile).
- **V3 (future):** burst/ramp traffic patterns layered on top of steady-state.

## v1 scope (implemented)

**Content Generation only** — Conversational Chat and RAG/Long-Context were pulled out of v1 and moved to `version2/` (see CLAUDE.md); they are not part of this suite yet.

- Script: `sizing/scripts/run_content_generation.sh` — same prompts/ISL/OSL as `model-selection/scripts/run_content_generation.sh`; only the concurrency treatment differs (fixed ladder vs. shallow sweep).
- One aiperf invocation per ladder rung (`CONCURRENCY` env var), matching the Model Selection scripts' pattern — the script does not loop the ladder itself.
- K8s: `sizing/k8s/` — one Job manifest per rung (rendered from `content-generation-job.yaml`), a shared results PVC across all rungs/scenarios, and `run-test.sh`, which runs the full ladder end-to-end and stops if a rung's error rate crosses the circuit-breaker threshold.
- GPU/server-side metrics: the script backgrounds a `dcgmi dmon` (falls back to `nvidia-smi --query-gpu`) polling loop for the duration of each rung, writing `gpu-metrics.csv` alongside the aiperf export. Assumes DCGM or NVIDIA driver tooling is already available on the node — this does not stand up DCGM itself. Prometheus-side server-internal metrics (queue depth, batch size, KV cache %) are **not** captured automatically; pull those separately from an existing Prometheus/exporter setup if available.

## Concurrency ladder

**Fixed: 1 → 5 → 10 → 25 → 50 → 100 → 200**

Chosen over an adaptive or server-max-anchored ladder because deployment configs vary per customer/engagement (1 GPU vs. 2 GPU, small MIG vs. large MIG) — a fixed ladder stays directly comparable across configs for the same customer. Log-ish spacing so it stays meaningful whether the deployment tops out around 25 or keeps climbing past 100.

**Safety circuit breaker:** stop automatically if error rate crosses a threshold (e.g. >5%) at a given rung — protects a customer's live endpoint from being hammered into an outage.

## Workload profiles

Same profiles as the Model Selection suite for whatever's in scope there (see `docs/scenarios/model-selection.md`) — identical ISL/OSL/turns/streaming. Only the concurrency treatment differs: fixed ladder above vs. the shallow 1/5/10/25 sweep used for model comparison. v1 scope is Content Generation only (see above); the other profiles remain planning-only until built.

## Roadmap idea (not built)

Percentage-of-max-concurrency ladder: anchor rungs to the server-reported max concurrency vLLM/NIM logs at startup (25%/50%/75%/100%/125% of N), as a complementary self-contextualizing view alongside the fixed ladder.
