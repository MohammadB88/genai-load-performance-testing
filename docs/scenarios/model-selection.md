# Model Selection Suite — Scenarios

## Versioning

- **V0 (POC):** Chat + RAG only, synthetic prompts, baseline concurrency (1) only, no sweep. Run against 2+ candidate models.
- **V1 (full core):** all 6 scenarios below, synthetic prompts, baseline + sweep (1/5/10/25).
- **V2 (customer-calibrated):** customer-provided real prompts replace synthetic (synthetic acts as the template), full customization overlay enabled.

## Scenario matrix (V1 baseline)

| Scenario | ISL (tokens) | OSL (tokens) | Turns (mean ± stddev) | Think-time between turns | Streaming (default) | Concurrency |
|---|---|---|---|---|---|---|
| **Conversational Chat** | 150/turn (new tokens) | 200 (σ 50) | 4 ± 1 | 2–5s human think time | Yes | Baseline 1; sweep 1/5/10/25 |
| **RAG / Long-Context Q&A** | 4,000 (fixed) | 250 | 1 (single-turn) | N/A | Yes | Baseline 1; sweep 1/5/10/25 |
| **Summarization** | 8,000 (fixed) | 300 | 1 (single-turn) | N/A | **No** ⚠️ assumption — confirm with customer | Baseline 1; sweep 1/5/10/25 |
| **Agentic / Tool-Calling** | 300/turn (growing w/ tool output) | 150 (structured call output) | 4 ± 1 | 300–800ms (tool round-trip, not human) | Non-streaming on tool-call turns, streaming on final answer ⚠️ assumption — confirm with customer | Baseline 1; sweep 1/5/10/25 |
| **Batch / Non-Interactive** | 6,000 (fixed) | 800 | 1 (single-turn) | N/A | No | Baseline 1; sweep 1/5/10/25 |
| **Content Generation** | 100 (fixed, short brief) | 800 (long-form output) | 1 (single-turn) | N/A | Yes | Baseline 1; sweep 1/5/10/25 |

*(Code Generation: lower-priority 7th scenario, roadmap.)*

## Think-time implementation

Uses AIPerf's native `--conversation-turn-delay-mean` / `--conversation-turn-delay-stddev` (ms), alongside `--conversation-num`, `--conversation-turn-mean`/`--conversation-turn-stddev`.

```
aiperf profile \
  --model <model> \
  --endpoint-type chat \
  --streaming \
  --conversation-num <N> \
  --conversation-turn-mean 4 \
  --conversation-turn-stddev 1 \
  --conversation-turn-delay-mean 3500 \
  --conversation-turn-delay-stddev 750 \
  --synthetic-input-tokens-mean 150 \
  --output-tokens-mean 200 \
  --concurrency 1
```

Mean 3500ms / stddev 750ms centers on 3.5s with most draws landing in the 2–5s target range. Agentic scenarios use their own shorter delay (300–800ms) since that delay represents a tool round-trip, not human read/type time.

## Prompt source

- V0/V1: synthetic prompts only.
- V2: customer-provided real prompts, slotted into the same ISL/OSL/turn structure defined above (synthetic = template).
