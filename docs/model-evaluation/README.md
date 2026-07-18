# Model Evaluation (Output Quality)

Findings on where model evaluation fits in this repo, and documentation for the
DeepEval-based output-quality workflow added under `notebooks/`.

## 1. Performance evaluation vs. quality evaluation

This repo evaluates models on two distinct axes — only one of which existed
before the DeepEval notebook was added:

| Axis | Question it answers | Tooling | Where |
|---|---|---|---|
| **Performance / UX quality** | Is the model fast and responsive under load? (TTFT, ITL, goodput) | NVIDIA AIPerf | `model-selection/`, `sizing/`, most of `notebooks/` |
| **Output quality** | Does the model's output actually answer the prompt correctly? | DeepEval (LLM-as-judge) | `notebooks/model_eval_deepeval.ipynb` |

The distinction is deliberate and already documented elsewhere in the repo:

- `docs/metrics/model-selection.md` states it directly: AIPerf measures
  performance/UX quality (speed, responsiveness, consistency) — **not** output
  correctness or hallucination rate.
- `docs/customer/performance-guide.md` (§6.7 and Conclusion) limits its quality
  guidance to spot-checking responses for basic coherence — explicitly a sanity
  check, not an assessment — and notes that output-quality validation requires a
  separate evaluation.

Model selection needs both axes: a fast model that answers wrong is not a
candidate. Until the DeepEval notebook, the quality axis had no tooling in this
repo — the Model Selection suite compares models on performance only.

## 2. The DeepEval quality-evaluation workflow

`notebooks/model_eval_deepeval.ipynb` implements a minimal but complete eval
loop using [DeepEval](https://github.com/confident-ai/deepeval). It does **not**
use AIPerf. Five steps:

1. **Golden dataset** — curated `(input, expected_output)` pairs. The starter
   set mirrors the repo's v1 Content Generation scope (factual QA, technical
   listing, customer email drafting, summarization). `expected_output` is a
   *reference answer*, not a string matched verbatim — the judge compares
   substance (facts, coverage, intent), not wording.
2. **Generate** — one chat completion per case against the model under test,
   via any OpenAI-compatible endpoint (NIM, vLLM, TGI, ...) — the same
   backend-agnostic assumption as every scenario in this repo.
   `temperature=0` for repeatability.
3. **Test cases** — each case becomes a DeepEval `LLMTestCase` bundling
   input / actual output / expected output.
4. **Metrics** — two LLM-as-judge metrics, each returning a 0–1 score plus a
   written reason:

   | Metric | What it checks | Needs `expected_output` | Threshold |
   |---|---|---|---|
   | Correctness (custom `GEval`) | actual output is substantively consistent with the reference answer | yes | 0.5 |
   | Answer Relevancy (built-in) | output addresses the input, no off-topic filler | no | 0.7 |

5. **Results** — per-(case, metric) table with score, pass/fail, and the
   judge's reason, plus a per-metric summary (mean score, pass rate). Saved as
   JSON under `notebooks/artifacts/deepeval-model-eval/` so runs can be
   committed (repo convention: reproducibility = Git). The saved artifact
   records model, endpoint, judge, temperature, and the full dataset.

### Judge model configuration

The judge is independent of the model under test:

- **OpenAI judge (default)** — set `OPENAI_API_KEY`; `JUDGE_MODEL` in the
  notebook picks the model (default `gpt-4o-mini`).
- **Local / on-prem judge** — point DeepEval at any OpenAI-compatible endpoint
  once via `deepeval set-local-model --model-name ... --base-url ...`, then set
  `JUDGE_MODEL = None` in the notebook. Keeps the whole workflow on-prem.

Use a judge that is **stronger than and different from** the model under test —
a model grading its own output inflates scores.

### Comparing models

Same pattern as the performance suites: the workload (golden dataset) stays
fixed, only the endpoint changes. Rerun the generate + evaluate sections with a
different `MODEL`/`BASE_URL` and diff the saved JSON artifacts. Combined with
the Model Selection suite's TTFT/ITL/goodput numbers, this covers both axes of
the model-selection decision.

## 3. Caveats and boundaries

- **LLM-as-judge scores are judge-dependent.** Pin the judge per run (recorded
  in the saved artifact), and spot-check the judges' written reasons rather
  than trusting scores blindly. Small score deltas (< ~0.1) between models are
  noise.
- **Not wired into either suite.** Like the rest of `notebooks/`, this is
  reference/demo material, not source of truth, and not part of the K8s
  delivery. Promoting it to a committed suite (script + manifests) is a
  separate decision.
- **No cloud dependency.** The workflow deliberately skips Confident AI's
  hosted platform (`deepeval login`) — everything runs and is stored locally,
  matching the repo's raw-artifact convention.
- **Growth path.** Add rows to the golden dataset (e.g. write reference answers
  for `model-selection/prompts/content_generation.jsonl` prompts), or add
  metrics: `FaithfulnessMetric` / `HallucinationMetric` become relevant when
  the RAG scenario lands in v2 (they require `retrieval_context`); `BiasMetric`,
  `ToxicityMetric`, and custom `GEval` criteria are also available.

## 4. Related files

- `notebooks/model_eval_deepeval.ipynb` — the workflow itself
- `notebooks/requirements.txt` — includes `deepeval` and `openai`
- `docs/metrics/model-selection.md` — the performance-vs-correctness boundary statement
- `docs/customer/performance-guide.md` — customer-facing note that quality validation is out of AIPerf's scope
