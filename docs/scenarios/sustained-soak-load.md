# Sustained / Soak Load Scenario

Orthogonal to the 6 workload-profile scenarios in `model-selection.md` / `sizing.md`. Those vary ISL/OSL/turns/streaming to mirror business use cases and stop after a fixed, small request count. This scenario varies a different axis entirely — **wall-clock duration** — and answers a different question: *does this deployment degrade over a long continuous run?* (memory leaks, KV-cache fragmentation, GC pauses). None of the 6 profiles are designed to catch that, since they all stop quickly.

See `docs/scenarios/README.md` for the general AIPerf background this scenario relies on (stopping conditions, dataset sampling strategies, `random_pool` vs. `mooncake_trace`).

## Workload shape

- **Dataset**: `random_pool` (`text` key) + `--dataset-sampling-strategy random`, sampling **with replacement** from a small prompt pool. Unlike the other scenarios' `mooncake_trace` files (replayed once, in order), repeats are expected and fine here — the goal is sustained traffic, not one-shot coverage.
- **Stopping condition**: `--benchmark-duration` (default 1200s / 20 min), not request count. Paired with `--benchmark-grace-period` (default 30s) so in-flight responses at the deadline are still counted. This is the one scenario in this repo where duration-based stopping is the right call (see `docs/scenarios/README.md`).
- **Concurrency**: fixed (default 20), not swept — steady sustained load is the point, not a comparison ladder.
- **Streaming**: yes.

## Files

Self-contained under `model-selection/sustained-soak-load/` (separate from the shared `model-selection/scripts/` and `model-selection/prompts/` used by the 6 workload-profile scenarios, since this scenario is orthogonal to that matrix):

- `model-selection/sustained-soak-load/run_sustained_soak.sh` — the scenario script (source of truth for the `aiperf profile` invocation), adapted from the original `sample-script.sh` template at the repo root.
- `model-selection/sustained-soak-load/prompts/sustained_soak.jsonl` — 10 short, varied realistic prompts, keyed on `text` (matching `random_pool`'s schema).

## Status

Script + prompts are checked in and runnable standalone. **Not yet wired into K8s** — consistent with this repo's current scope decision to fully wire only Content Generation for V1 (see commit "focus on only one scenario for version1"). Add a Job manifest (mirroring `model-selection/k8s/content-generation-job.yaml`) when this scenario is prioritized for K8s delivery.

## Usage

```bash
MODEL=my-model URL=http://localhost:8000 ./model-selection/sustained-soak-load/run_sustained_soak.sh
DURATION_SECONDS=3600 CONCURRENCY=20 MODEL=my-model URL=http://localhost:8000 ./model-selection/sustained-soak-load/run_sustained_soak.sh
```

See the script header for the full set of env vars (tokenizer, HF token/cache, output dir, etc.) — same conventions as the other model-selection scripts.
