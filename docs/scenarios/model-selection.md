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

*(Code Generation: lower-priority additional scenario, roadmap.)*

Not part of this matrix: **Sustained / Soak Load**, an orthogonal scenario that varies duration rather than ISL/OSL/turns/streaming. See `docs/scenarios/sustained-soak-load.md`.

## Think-time implementation

Uses AIPerf's native `--conversation-turn-delay-mean` / `--conversation-turn-delay-stddev` (ms). Turn count and per-turn text come from the input file (see Prompt source below) rather than `--conversation-num`/`--conversation-turn-mean`/`--conversation-turn-stddev`, which only apply when AIPerf is generating conversations synthetically.

```
aiperf profile \
  --model <model> \
  --endpoint-type chat \
  --streaming \
  --input-file model-selection/prompts/conversational_chat.jsonl \
  --custom-dataset-type multi_turn \
  --conversation-turn-delay-mean 3500 \
  --conversation-turn-delay-stddev 750 \
  --output-tokens-mean 200 \
  --concurrency 1
```

Mean 3500ms / stddev 750ms centers on 3.5s with most draws landing in the 2–5s target range. Agentic scenarios use their own shorter delay (300–800ms) since that delay represents a tool round-trip, not human read/type time.

## Prompt source

- **Conversational Chat**: real sample prompts (`model-selection/prompts/conversational_chat.jsonl`), not synthetic token noise. 20 multi-turn sessions (`--custom-dataset-type multi_turn`), 3–5 turns each, everyday-assistant topics. ISL is therefore whatever these prompts tokenize to (targeting ~150 tokens/turn) rather than a fixed synthetic value.
  ⚠️ **Known issue:** the `multi_turn` dataset schema used by this file has not been confirmed against the installed AIPerf version — a run against the NGC image rejected a field (`turn_delay`) with a Pydantic `extra_forbidden` error, meaning the actual schema differs from what AIPerf's public docs describe. `run_conversational_chat.sh` and its prompt file are checked in but **not yet a confirmed-working scenario**. Do not treat as validated until this is resolved.
- **RAG / Long-Context Q&A**: real sample prompts (`model-selection/prompts/rag_long_context.jsonl`), not synthetic token noise. 18 single-turn requests (`--custom-dataset-type mooncake_trace`, keyed on `text_input` per AIPerf's `MooncakeTrace` schema — each record replayed exactly once, in file order), each a ~4,000-token synthetic "document" (rotated across 3 topical domains: cloud infra, customer support, retail ops) followed by a question. This is the **confirmed-working** reference for the single-turn/`text_input` path.
  ⚠️ `--custom-dataset-type random_pool` was tried first and rejected by AIPerf (`RandomPool` requires a `text`/`texts` key, not `text_input` — see `run_rag_long_context.sh` header for detail). `mooncake_trace` is also the better semantic fit: deterministic single-turn replay rather than pool sampling with replacement.
- **Content Generation**: real sample prompts (`model-selection/prompts/content_generation.jsonl`), not synthetic token noise. 20 single-turn requests (`--custom-dataset-type mooncake_trace`, keyed on `text_input`, same confirmed-working pattern as RAG), each a short (~100-token) creative/marketing brief (blog intros, product descriptions, ad copy, press releases, etc.) — OSL is driven by `--output-tokens-mean 800` rather than the prompt content, since the point of this scenario is long-form generation from a short prompt.
- Other V0/V1 scenarios (Summarization, Agentic, Batch): synthetic prompts only, generated via AIPerf's `--synthetic-input-tokens-mean`; sample prompt files not yet built.
- V2: customer-provided real prompts replace synthetic/sample prompts across all scenarios, slotted into the same ISL/OSL/turn structure defined above (current prompts act as the template).
