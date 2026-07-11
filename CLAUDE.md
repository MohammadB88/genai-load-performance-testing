# CLAUDE.md

Context for Claude Code (or any Claude instance) working in this repo.

## Project

Reproducible LLM performance testing suite built on NVIDIA AIPerf, backend-agnostic (any OpenAI-compatible endpoint: NIM, vLLM, TGI, etc.). Used in a consulting context — handed to different customers to help them (1) choose a model and (2) size infrastructure.

Two independent suites:
- **Model Selection** — `model-selection/` — compares models on UX-relevant performance (TTFT, ITL, goodput). Baseline concurrency + a shallow 1/5/10/25 sweep.
- **Capacity/Sizing** — `sizing/` — same workload profiles, but run against a fixed concurrency ladder (1/5/10/25/50/100/200) to find where a given deployment's latency/goodput breaks down.

**v1 scope is Content Generation only.** Conversational Chat and RAG/Long-Context were pulled out of v1 and live under `version2/` (not wired into either suite, not documented as current status). Ignore `version2/` unless explicitly asked to work on it — it's future scope, not dead code.

A third, orthogonal scenario — **Sustained/Soak Load** (`model-selection/sustained-soak-load/`) — varies wall-clock duration instead of ISL/OSL/turns, to catch degradation over long continuous runs (memory leaks, KV-cache fragmentation, GC pauses). Uses `--benchmark-duration` + `random_pool` sampling rather than the fixed-request-count `mooncake_trace` replay the other scenarios use. See `docs/scenarios/sustained-soak-load.md` and `docs/scenarios/README.md` (general AIPerf stopping-condition/sampling background).

Full scenario definitions and metrics tables: see `docs/scenarios/` and `docs/metrics/`. Customer-facing guide: `docs/customer/performance-guide.md`.

## Conventions

- **One bash script per scenario** is the source of truth (contains the `aiperf profile` invocation and its flags/values). No separate YAML config schema — the script *is* the config.
- Kubernetes (Job — primary delivery) and the jumphost fallback (native pip/binary install, no Docker — roadmap, not built yet) both call the **same** per-scenario scripts. Never fork scenario logic between the two.
- **Output = raw AIPerf export.** No processed/reformatted report layer currently — decided deliberately, keep it that way unless revisited.
- **Reproducibility = Git.** Scripts and their run outputs are both committed. Pin the AIPerf version used per run.
- If you change a scenario's parameters (ISL/OSL, turns, think-time, concurrency), update the corresponding table in `docs/scenarios/` in the same change — the docs and the scripts must stay in sync, since the docs are what gets shown to customers.
- Think-time ≠ tool-round-trip delay. Chat/human-facing scenarios use `--conversation-turn-delay-mean/stddev` tuned to 2–5s; Agentic uses the same flags tuned to 300–800ms. Don't conflate the two when writing or editing scripts.

## Notebooks & FinOps

- **`notebooks/`** — exploratory/reference Jupyter notebooks, separate from the two committed suites. `model_selection_content_generation.ipynb` runs the Model Selection Content Generation scenario end-to-end interactively. `aiperf_uc1`…`aiperf_uc8` are hands-on companions to `docs/reference/aiperf-office-hours.md` (notes from NVIDIA's Dynamo office-hours AIPerf walkthrough), each demonstrating one AIPerf capability (synthetic profiling, raw exports, mooncake trace replay, goodput, time slices, GPU telemetry, embeddings, rankings). `model_eval_deepeval.ipynb` is the one *output-quality* notebook — a minimal DeepEval (LLM-as-judge) eval workflow complementing the performance suites; it does not use AIPerf. Deps in `notebooks/requirements.txt`. Not wired into either suite's automation — reference/demo material, not source of truth.
- **`scripts/finops_report.py`** — standalone cost-estimation report from a stored AIPerf artifact directory: price-independent efficiency ratios plus $ figures under cloud/rented and on-prem/owned ownership lenses. Standard-library only. Parses either GPU-telemetry export layout AIPerf may emit (see `docs/reference/aiperf-office-hours.md` uc6 and the module docstring). Standalone equivalent of the notebook's FinOps section (`aiperf_uc6_gpu_telemetry.ipynb` §6) — keep both in sync if the estimation logic changes.

## Status

- **Model Selection** (`model-selection/`) — implemented for v1 scope (Content Generation only): `run_content_generation.sh`, its prompt dataset, and K8s Job manifests + ConfigMap/PVC generation under `model-selection/k8s/`.
- Conversational Chat and RAG/Long-Context scripts, prompts, and K8s manifests moved to `version2/` — out of scope for v1, not integrated, not maintained as part of the current suites.
- **Sizing** (`sizing/`) — implemented for v1 scope (Content Generation only): `run_content_generation.sh` (one aiperf invocation per ladder rung, plus a backgrounded `dcgmi`/`nvidia-smi` GPU-metrics polling loop), its prompt dataset, and K8s manifests under `sizing/k8s/` (one Job per rung, shared PVC, and `run-test.sh` which runs the full ladder and enforces the error-rate circuit breaker between rungs). Prometheus-based server-side metrics (queue depth, batch size, KV cache %) are documented but not yet captured — no exporter/scrape setup assumed.
- **Sustained/Soak Load** (`model-selection/sustained-soak-load/`) — script + prompts checked in and runnable standalone; **not yet wired into K8s** (add a Job manifest mirroring `model-selection/k8s/content-generation-job.yaml` when prioritized).
- Customer-facing guide (`docs/customer/performance-guide.md`) is being revised to document only the v1 Content Generation scenario; unimplemented/deferred scenarios are intentionally excluded until built.
