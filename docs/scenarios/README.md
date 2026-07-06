# Scenarios — Notes

Supplementary notes that apply across `model-selection.md` and `sizing.md`. See those files for the actual scenario matrices, and `sustained-soak-load.md` for the soak-testing scenario (orthogonal to both).

## Stopping conditions: request-count vs. `--benchmark-duration`

Source: [AIPerf `docs/cli-options.md`](https://github.com/ai-dynamo/aiperf/blob/main/docs/cli-options.md) and [`docs/tutorials/time-based-benchmarking.md`](https://github.com/ai-dynamo/aiperf/blob/main/docs/tutorials/time-based-benchmarking.md).

AIPerf supports two independent stopping conditions, which can be combined:

- **`--request-count` / `--num-requests`** — stop after N requests. If unset, AIPerf derives a count from timing mode and dataset size (`max(10, concurrency * 2)` for synthetic datasets). Supports comma-separated sweeps.
- **`--benchmark-duration`** — stop dispatching new requests after N seconds, paired with **`--benchmark-grace-period`** (default 30s; can be `0` or `'inf'`) to wait for in-flight responses. Responses landing within the grace period are counted; anything still pending when it expires is dropped from metrics.
- If both are set, **first condition reached wins** — they are not mutually exclusive.

AIPerf's own docs frame `--benchmark-duration` as the right tool for **SLA validation, stability/soak testing, and capacity planning** — i.e. sustained-load questions ("does this deployment degrade over a 20+ minute window?"). It is not what they recommend for point-in-time comparison across models or concurrency rungs, since two runs of equal duration against backends of different speed will execute different request counts, which weakens percentile metrics (p95/p99 TTFT, ITL) precisely when comparability across runs is the goal.

**Why this repo doesn't use `--benchmark-duration` in Model Selection or Sizing:** both suites replay a fixed prompt file once per run (`mooncake_trace`, `text_input` key, file-order replay — see `model-selection.md`), which is a request-count-equivalent stopping condition by construction. This keeps sample size identical across models/rungs, which both suites depend on for comparability. `sample-script.sh` (`--benchmark-duration` + `random_pool` sampling) was the reference for the dedicated **Sustained / Soak Load scenario** — see `sustained-soak-load.md` — which is an orthogonal addition, not a replacement for the existing 6 workload profiles.

## `--dataset-sampling-strategy` options

Per AIPerf's CLI reference, three strategies exist (default depends on dataset type):

- **`sequential`** — iterate the dataset in order.
- **`random`** — sample with replacement.
- **`shuffle`** — iterate without replacement, re-shuffling once exhausted.

This only applies to dataset types that draw from a pool (e.g. `random_pool`, keyed on `text`/`texts`). It does not apply to `mooncake_trace` (keyed on `text_input`), which always replays deterministically in file order — there is no pool to sample from.

## `random_pool` vs. `mooncake_trace`: which for which scenario

These are not interchangeable — they serve different testing goals, and the choice isn't just about the JSONL key.

| | `random_pool` | `mooncake_trace` |
|---|---|---|
| JSONL key | `text` / `texts` | `text_input` |
| Selection | `--dataset-sampling-strategy` (`sequential`/`random`/`shuffle`) | none — deterministic file-order replay, once each |
| Best for | sustained/soak load, sampling a small pool repeatedly over a long run | point-in-time comparison across models or concurrency rungs |

**Model Selection & Sizing suites use `mooncake_trace`.** Both suites exist to compare models or concurrency rungs against each other (see `model-selection.md`, `sizing.md`), which requires every run to see the *same* requests, in the *same* order, exactly once — otherwise sampling variance (e.g. `random_pool` drawing prompt A three times and prompt B zero times in one run) becomes indistinguishable from real model/config differences, especially with the small prompt pools used here (18-20 records). The RAG/Content Generation prompt files are also designed as one-shot test cases (`docs/scenarios/model-selection.md:45`) — each a self-contained "document + question" or "brief" — not variety-inducing filler meant to be redrawn.

**`random_pool` is the right tool for sustained/soak testing** — see `sustained-soak-load.md` — where the goal is continuous, somewhat-varied traffic over a long duration rather than exact-once coverage of a fixed set. It is not a drop-in replacement for `mooncake_trace` in the comparison-oriented scenarios — switching would both break AIPerf's schema validation (wrong key) and weaken comparability (uneven prompt coverage per run).
