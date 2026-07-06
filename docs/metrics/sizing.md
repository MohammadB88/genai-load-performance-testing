# Capacity/Sizing Suite — Metrics

| Metric | What it measures | Why it matters for sizing | Captured by |
|---|---|---|---|
| **Output Token Throughput (system-wide)** | Total tokens/sec across all concurrent requests | Core capacity number | aiperf export (implemented) |
| **Request Throughput (RPS)** | Completed requests/sec | Clarifies whether the endpoint handles many short requests or fewer long ones | aiperf export (implemented) |
| **TTFT / ITL across concurrency sweep** | Latency degradation as concurrency rises | Finds the practical ceiling via the latency-throughput curve | aiperf export (implemented) |
| **Goodput vs. concurrency** | Concurrency where SLO compliance breaks down | Directly answers "how many concurrent users can this deployment serve within SLA" | aiperf export (implemented) |
| **Error rate under load** | Failures as concurrency increases | Distinguishes "throughput plateaus" from "server falls over"; also drives the ladder's safety circuit breaker | aiperf export (implemented) |
| **GPU Utilization** | Compute utilization during the run | Confirms the GPU is actually the bottleneck being tested | `sizing/scripts/run_content_generation.sh`'s `dcgmi dmon` / `nvidia-smi` polling loop → `gpu-metrics.csv` (implemented; requires DCGM or NVIDIA driver tooling on the node) |
| **GPU Memory / KV Cache usage** | Memory pressure from KV cache | Explains *why* throughput plateaus (memory-bound vs. compute-bound) | Same polling loop (GPU memory only; KV cache % is server-side, see below) |
| **GPU Power / Temperature** | Power draw and thermal behavior | Relevant for on-prem cost/capacity planning | Same polling loop (implemented) |
| **Server-side metrics** (queue depth, batch size, KV cache % via Prometheus) | Backend-internal state | Pinpoints the actual bottleneck mechanism | **Not captured** — requires a Prometheus instance already scraping the backend's metrics exporter; pull manually for the run's time window if available |
