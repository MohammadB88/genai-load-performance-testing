# AIPerf — Notes from the Dynamo Office Hours Walkthrough

Notes distilled from NVIDIA's Dynamo office-hours session on AIPerf (Ben Hamm, PM for Dynamo performance) and its companion gist. Kept as reference for which AIPerf capabilities this repo already uses, and which are candidates for future scenarios.

Sources:
- Gist: [AIPerf Comprehensive Benchmarking Guide](https://gist.github.com/BenHamm/31c648f7d7331c94c1f3a45859db6677) (AIPerf v0.3.0)
- Video transcript: Dynamo office hours, AIPerf benchmarking walkthrough (same content plus Q&A)

Demo endpoint used throughout the gist: Qwen3-0.6B on vLLM v0.11.0, 8 independent replicas across 8× H200 on Kubernetes — deliberately overprovisioned, and taken down after the session.

## What AIPerf is

- NVIDIA's open-source LLM benchmarking tool ([ai-dynamo/aiperf](https://github.com/ai-dynamo/aiperf)), built by the Dynamo team as a "common language" for performance testing between NVIDIA and customers.
- Pip-installable, pure Python, backend-agnostic — targets any OpenAI-compatible endpoint (the demo uses chat completions). Same premise this repo is built on.
- Motivation over a DIY request loop: handles scaling the client side (no client-side bottleneck), live dashboard, percentile reporting, raw per-request exports, trace replay, goodput, time slices.

## Use case 1 — simple synthetic profiling

```bash
aiperf profile \
  --model qwen3-0.6b \
  --url $ENDPOINT_URL \
  --endpoint-type chat \
  --streaming \
  --concurrency 100 \
  --request-count 1000 \
  --isl 1000 \
  --osl 500 \
  --tokenizer Qwen/Qwen3-0.6B
```

- `--streaming` is what makes TTFT/ITL measurable; the tokenizer must match the model or token counts (and therefore TPS) are wrong.
- ISL/OSL can be fixed or sampled from a distribution (mean/stddev flags).
- Summary table reports avg/min/max/P99/P90/P50/std for TTFT, request latency, inter-token latency, plus system-level output-token throughput and request throughput.
- Reasoning models (Q&A): AIPerf by default separates reasoning tokens from visible output tokens; thinking tokens do count toward OSL.

## Pareto / concurrency sweep

Same benchmark rerun at concurrency 10/50/100/200/500, plotting **TPS-per-GPU (cost efficiency) vs TPS-per-user (UX)**:

| Concurrency | Total TPS | TPS/GPU | TPS/user | TTFT (avg) |
|---|---|---|---|---|
| 10 | 3,045 | 1,522 | 365 | ~250 ms |
| 50 | 12,890 | 6,445 | 326 | ~270 ms |
| 100 | 22,521 | 11,261 | 285 | ~347 ms |
| 200 | 35,999 | **18,000 (peak)** | 239 | ~420 ms |
| 500 | 29,836 | 14,918 | 129 | ~1,129 ms |

- Per-GPU efficiency peaked at concurrency 200 and *regressed* at 500 (suspected network/port-exhaustion effects on a client-to-server run); per-user TPS and TTFT degrade monotonically with concurrency.
- The curve is how you pick a cost/UX trade-off and set a per-replica load-balancer cap. Same idea as this repo's sizing ladder (`sizing/`), which additionally enforces an error-rate circuit breaker between rungs.

## Use case 2 — raw per-request exports

- Every run writes `profile_export.jsonl`: one record per request with TTFT, request latency, ITL, ISL/OSL, nanosecond timestamps, worker id — plus CSV/JSON summary exports and a log.
- Anything not in the summary table (the gist demos a custom P75) can be computed from the raw JSONL. This is the basis for this repo's "output = raw AIPerf export, no processed report layer" convention.

## Use case 3 — trace-based benchmarking (Mooncake)

- Replays **real production traffic** instead of synthetic prompts. Demo dataset: the Mooncake arXiv Q&A trace — ~23,600 requests over 60 min, median ISL ~6.4K tokens, mean ~8.8K, long tail past 100K.
- Mooncake anonymizes with **block hashes**: each record is a timestamp + ISL/OSL + hash IDs. Repeated hash IDs across requests represent shared prefixes (follow-up questions on the same document), so KV-cache/prefix-reuse patterns are preserved without leaking user data. AIPerf expands hashes into natural language while respecting the repetition.
- Flags: `--input-file mooncake_trace.jsonl --custom-dataset-type mooncake_trace`, plus `--fixed-schedule` to honor original timestamps. Dropping `--fixed-schedule` replays as fast as possible (capacity testing) while keeping the naturalistic prefix-reuse structure.
- Primary use: **A/B testing KV-cache optimizations** (e.g., Dynamo's KV-aware routing) — realistic prefix reuse makes TTFT gains from caching measurable, which independent synthetic prompts cannot show. Dynamo's repo has a smart-router A/B doc using exactly this method.
- Also supports ShareGPT and your own saved traces, which can be edited/scaled (e.g., 4× volume on the same schedule) for stress testing.
- Note the naming collision: this repo uses `--custom-dataset-type mooncake_trace` as a *file format* for fixed-order replay of our own prompt files (see `docs/scenarios/README.md`), not the actual Mooncake dataset. The gist uses the real trace with real timestamps.

## Use case 4 — goodput

```bash
--goodput "time_to_first_token:370 request_latency:648"
```

- Reports **requests/sec that meet all specified SLOs**, alongside raw throughput. Demo: 26.7 req/s throughput but 7.43 req/s goodput — only **28% of requests met both SLAs**, a gap that averages and single percentiles hide.
- Closest single metric to "what fraction of users had a good experience"; both suites' metrics docs (`docs/metrics/`) name goodput as the most decision-relevant number for the same reason.

## Use case 5 — time-slice analysis

```bash
--slice-duration 10
```

- Buckets results into fixed time windows; emits `profile_export_aiperf_timeslices.csv/.json`.
- Demo caught a cold-start effect: slice 0 TTFT 545 ms vs ~344 ms once warm, despite lower request count in slice 0.
- Directly relevant to the Sustained/Soak scenario (`docs/scenarios/sustained-soak-load.md`) — this is the built-in way to see degradation *within* a long run rather than only in the end-of-run aggregate.

## Other capabilities and Q&A points

- **In-cluster benchmarking**: run AIPerf inside the same K8s cluster (or on the GPU node) to eliminate network round-trip latency and ephemeral-port exhaustion as confounders. Recommended for high-scale or controlled comparisons; this repo's K8s Job delivery already does this.
- **GPU telemetry**: AIPerf can collect GPU utilization/memory-bandwidth metrics (multi-GPU supported) via a **DCGM exporter endpoint** — documented in the AIPerf repo. Candidate alternative to the sizing suite's backgrounded `dcgmi`/`nvidia-smi` polling loop.
- **Request cancellation testing**: `--request-cancellation-rate 20 --request-cancellation-delay 0.5` cancels a percentage of requests after a delay, to test resource cleanup and graceful degradation under user abandonment.
- **Roadmap (per the session)**: server-side metrics (queue depth, engine telemetry — exactly what `docs/scenarios/sizing.md` lists as documented-but-not-captured), Kubernetes-native distributed load generation (multiple load-tester pods), automatic plot generation, synthetic loadgen for KV-cache-efficiency testing. Nsight kernel-tracing integration in progress, no date.

## Relevance to this repo — quick map

| Gist capability | Status here |
|---|---|
| Raw export as the deliverable | Adopted (repo convention) |
| Concurrency sweep / Pareto | Adopted (`sizing/` ladder; model-selection shallow sweep) |
| Goodput SLOs | Documented as the key decision metric (`docs/metrics/`); `--goodput` flag not yet passed in scenario scripts — currently a post-hoc computation from the raw export |
| In-cluster load generation | Adopted (K8s Jobs) |
| Time-slice analysis (`--slice-duration`) | Not used yet — natural fit for sustained/soak |
| Real-trace replay with timestamps (`--fixed-schedule`) | Not used — our `mooncake_trace` usage is format-only, fixed-order replay |
| DCGM-exporter GPU telemetry via AIPerf | Not used — sizing polls `dcgmi`/`nvidia-smi` instead |
| Request cancellation testing | Not used |
