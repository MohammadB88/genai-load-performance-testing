# Model Selection Suite — Metrics

Note: AIPerf measures performance/UX quality (speed, responsiveness, consistency) — not output correctness or hallucination rate. Keep that distinction visible to customers.

| Metric | What it measures | Why it matters for model choice |
|---|---|---|
| **TTFT** | Time to first token — queueing + prefill + network | Drives perceived responsiveness; critical for interactive use cases |
| **TTST** | Time to second token | Reveals scheduling overhead separate from prefill cost |
| **ITL** | Time between consecutive output tokens | Determines streaming smoothness; choppy streaming is noticeable even at good average speed |
| **Output Token Throughput per User** | Generation speed from one user's perspective | Maps to "does it feel like it's typing at a natural pace" |
| **End-to-End Request Latency** | Total time to final token | The metric for non-streaming/batch use cases |
| **Output Sequence Length** | Tokens actually generated | Sanity check — unexpectedly short outputs flag truncation issues |
| **Goodput** | % of requests meeting TTFT/ITL/latency SLOs simultaneously | Most decision-relevant number — two models can share raw throughput but differ hugely in goodput |
| **Error rate** | Malformed/failed responses | Basic reliability signal at the tested concurrency/config |
