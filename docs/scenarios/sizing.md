# Capacity/Sizing Suite — Scenarios

## Versioning

- **V0 (POC):** Chat + Batch only, ladder 1/10/50, single model/config, steady-state only.
- **V1 (full core):** all 6 workload profiles (same as Model Selection), full fixed ladder, steady-state only, GPU/server-side metrics captured at every rung.
- **V2 (customer-calibrated):** customer's real prompts, ladder run once per actual deployment config (e.g. per GPU/MIG profile).
- **V3 (future):** burst/ramp traffic patterns layered on top of steady-state.

## Concurrency ladder

**Fixed: 1 → 5 → 10 → 25 → 50 → 100 → 200**

Chosen over an adaptive or server-max-anchored ladder because deployment configs vary per customer/engagement (1 GPU vs. 2 GPU, small MIG vs. large MIG) — a fixed ladder stays directly comparable across configs for the same customer. Log-ish spacing so it stays meaningful whether the deployment tops out around 25 or keeps climbing past 100.

**Safety circuit breaker:** stop automatically if error rate crosses a threshold (e.g. >5%) at a given rung — protects a customer's live endpoint from being hammered into an outage.

## Workload profiles

Same 6 profiles as the Model Selection suite (see `model-selection-scenarios.md`) — identical ISL/OSL/turns/streaming. Only the concurrency treatment differs: fixed ladder above vs. the shallow 1/5/10/25 sweep used for model comparison.

## Roadmap idea (not built)

Percentage-of-max-concurrency ladder: anchor rungs to the server-reported max concurrency vLLM/NIM logs at startup (25%/50%/75%/100%/125% of N), as a complementary self-contextualizing view alongside the fixed ladder.
