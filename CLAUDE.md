# CLAUDE.md

Context for Claude Code (or any Claude instance) working in this repo.

## Project

Reproducible LLM performance testing suite built on NVIDIA AIPerf, backend-agnostic (any OpenAI-compatible endpoint: NIM, vLLM, TGI, etc.). Used in a consulting context — handed to different customers to help them (1) choose a model and (2) size infrastructure.

Two independent suites:
- **Model Selection** — `model-selection/` — compares models on UX-relevant performance (TTFT, ITL, goodput). Baseline concurrency + a shallow 1/5/10/25 sweep.
- **Capacity/Sizing** — `sizing/` — same 6 workload profiles, but run against a fixed concurrency ladder (1/5/10/25/50/100/200) to find where a given deployment's latency/goodput breaks down.

Full scenario definitions and metrics tables: see `docs/scenarios/` and `docs/metrics/`.

## Conventions

- **One bash script per scenario** is the source of truth (contains the `aiperf profile` invocation and its flags/values). No separate YAML config schema — the script *is* the config.
- Kubernetes (Job/Helm — primary delivery) and the jumphost fallback (native pip/binary install, no Docker — roadmap, not built yet) both call the **same** per-scenario scripts. Never fork scenario logic between the two.
- **Output = raw AIPerf export.** No processed/reformatted report layer currently — decided deliberately, keep it that way unless revisited.
- **Reproducibility = Git.** Scripts and their run outputs are both committed. Pin the AIPerf version used per run.
- If you change a scenario's parameters (ISL/OSL, turns, think-time, concurrency), update the corresponding table in `docs/scenarios/` in the same change — the docs and the scripts must stay in sync, since the docs are what gets shown to customers.
- Think-time ≠ tool-round-trip delay. Chat/human-facing scenarios use `--conversation-turn-delay-mean/stddev` tuned to 2–5s; Agentic uses the same flags tuned to 300–800ms. Don't conflate the two when writing or editing scripts.

## Status

Planning complete for both suites (scenarios, metrics). **No bash scripts**
