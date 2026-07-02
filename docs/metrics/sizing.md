# Capacity/Sizing Suite — Metrics

| Metric | What it measures | Why it matters for sizing |
|---|---|---|
| **Output Token Throughput (system-wide)** | Total tokens/sec across all concurrent requests | Core capacity number |
| **Request Throughput (RPS)** | Completed requests/sec | Clarifies whether the endpoint handles many short requests or fewer long ones |
| **TTFT / ITL across concurrency sweep** | Latency degradation as concurrency rises | Finds the practical ceiling via the latency-throughput curve |
| **Goodput vs. concurrency** | Concurrency where SLO compliance breaks down | Directly answers "how many concurrent users can this deployment serve within SLA" |
| **GPU Utilization** (DCGM/PyNVML) | Compute utilization during the run | Confirms the GPU is actually the bottleneck being tested |
| **GPU Memory / KV Cache usage** | Memory pressure from KV cache | Explains *why* throughput plateaus (memory-bound vs. compute-bound) |
| **GPU Power / Temperature** | Power draw and thermal behavior | Relevant for on-prem cost/capacity planning |
| **Server-side metrics** (queue depth, batch size, KV cache % via Prometheus) | Backend-internal state | Pinpoints the actual bottleneck mechanism |
| **Error rate under load** | Failures as concurrency increases | Distinguishes "throughput plateaus" from "server falls over" |
