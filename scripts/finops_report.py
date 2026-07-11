#!/usr/bin/env python3
"""FinOps estimation from a stored AIPerf artifact directory.

Standalone equivalent of section 6 of notebooks/aiperf_uc6_gpu_telemetry.ipynb:
reads the raw AIPerf exports and prints price-independent efficiency ratios
first, then $ figures under two ownership lenses — cloud/rented (all-in
$/GPU-hour, electricity included) and on-prem/owned (amortized CapEx +
energy x PUE).

GPU data is taken from whichever form the AIPerf version emitted:
- per-GPU telemetry rows (gpu_telemetry_export.csv, or a telemetry section in
  the summary CSV) — supports --gpus attribution; run energy is max - min of
  the cumulative Energy Consumption counter (never its avg), cross-checked
  against avg power x Benchmark Duration;
- or the aggregated run-totals rows newer AIPerf versions write instead
  ("Total GPU Power (N GPU) (W)", "Total GPU Energy (N GPU) (J)") — already
  windowed to the measurement phase; --gpus does not apply.

If the artifact dir holds several runs, the newest profile_export_aiperf.csv
wins, and companion files are taken from that same run's directory.

Standard library only — runs anywhere the artifacts are (jumphost, CI, laptop).

Usage:
    python scripts/finops_report.py <artifact-dir> [--gpu-hour-price 2.00] ...
"""

import argparse
import csv
import json
import re
import sys
from pathlib import Path


def fnum(value):
    """Float from an export cell; tolerates thousands separators and blanks."""
    if value is None:
        return None
    try:
        return float(str(value).replace(",", "").strip())
    except ValueError:
        return None


def norm(name):
    """Normalize a metric name for matching: lowercase, underscores as spaces."""
    return str(name or "").lower().replace("_", " ")


def read_text(path):
    # AIPerf writes UTF-8 (metric names include °C); utf-8-sig also eats a BOM.
    return path.read_text(encoding="utf-8-sig", errors="replace")


def parse_csv(text):
    rows = list(csv.DictReader(text.splitlines()))
    # Defend against stray whitespace in header names.
    return [{(k or "").strip(): v for k, v in row.items()} for row in rows]


def find_key(obj, key):
    """First value for `key` anywhere in a nested json structure."""
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        obj = list(obj.values())
    if isinstance(obj, (list, tuple)):
        for item in obj:
            if isinstance(item, (dict, list, tuple)):
                found = find_key(item, key)
                if found is not None:
                    return found
    return None


def newest(paths):
    return max(paths, key=lambda p: p.stat().st_mtime, default=None)


def load_exports(artifact_dir):
    """Return (telemetry_rows, totals_rows, concurrency) from the raw exports."""
    summary_path = newest(artifact_dir.rglob("profile_export_aiperf.csv"))
    if summary_path is None:
        sys.exit(f"error: no profile_export_aiperf.csv under {artifact_dir} — not an AIPerf artifact dir?")
    print(f"Summary export         : {summary_path}")
    sections = [s for s in read_text(summary_path).strip().split("\n\n") if s.strip()]
    totals = parse_csv(sections[1]) if len(sections) >= 2 else []

    # Per-GPU telemetry: prefer the file next to the chosen summary (same run),
    # then the newest anywhere, then a telemetry-shaped section of the summary.
    telemetry = []
    telemetry_path = summary_path.parent / "gpu_telemetry_export.csv"
    if not telemetry_path.exists():
        telemetry_path = newest(artifact_dir.rglob("gpu_telemetry_export.csv"))
    if telemetry_path is not None:
        print(f"Telemetry export       : {telemetry_path}")
        telemetry = parse_csv(read_text(telemetry_path))
    else:
        for section in sections[2:]:
            rows = parse_csv(section)
            if rows and any(r.get("Metric") for r in rows):
                print(f"Telemetry export       : extra section of {summary_path.name}")
                telemetry = rows
                break
        else:
            print("Telemetry export       : none — using GPU aggregates from the run totals, if present")

    concurrency = "?"
    json_path = summary_path.parent / "profile_export_aiperf.json"
    if not json_path.exists():
        json_path = newest(artifact_dir.rglob("profile_export_aiperf.json"))
    if json_path is not None:
        try:
            found = find_key(json.loads(read_text(json_path)), "concurrency")
            if found is not None:
                concurrency = found
        except (json.JSONDecodeError, OSError):
            pass
    return telemetry, totals, concurrency


def total_row(totals, name_contains):
    for row in totals:
        if name_contains in norm(row.get("Metric")):
            return fnum(row.get("Value"))
    return None


def total_metric_name(totals, name_contains):
    for row in totals:
        if name_contains in norm(row.get("Metric")):
            return row.get("Metric")
    return None


def metric_rows(telemetry, name_contains):
    return [r for r in telemetry if name_contains in norm(r.get("Metric"))]


def attributed(rows, gpu_indices):
    if gpu_indices is None or not any("GPU_Index" in r for r in rows):
        return rows
    wanted = {str(i) for i in gpu_indices}
    return [r for r in rows if str(r.get("GPU_Index")) in wanted]


def main():
    parser = argparse.ArgumentParser(
        description="FinOps estimation from a stored AIPerf artifact directory.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("artifact_dir", type=Path,
                        help="AIPerf artifact directory (searched recursively for the exports)")
    parser.add_argument("--gpu-hour-price", type=float, default=2.00,
                        help="cloud/rented all-in $/GPU-hour")
    parser.add_argument("--gpu-purchase-price", type=float, default=30_000,
                        help="on-prem CapEx, $ per GPU")
    parser.add_argument("--amortization-years", type=float, default=4,
                        help="depreciation horizon for the CapEx")
    parser.add_argument("--electricity-price-kwh", type=float, default=0.15,
                        help="on-prem electricity price, $/kWh")
    parser.add_argument("--pue", type=float, default=1.3,
                        help="datacenter power usage effectiveness (cooling/overhead multiplier)")
    parser.add_argument("--utilization", type=float, default=1.0,
                        help="fraction of billed hours actually serving — divides capacity cost only")
    parser.add_argument("--gpus", type=int, nargs="+", default=None, metavar="IDX",
                        help="attributed GPU indices (per-GPU telemetry only), if the exporter "
                             "also saw GPUs not serving this model")
    parser.add_argument("--api-price-per-mtok", type=float, default=None,
                        help="optional managed-API $/M output tokens, as a sanity anchor")
    args = parser.parse_args()

    if not args.artifact_dir.is_dir():
        sys.exit(f"error: {args.artifact_dir} is not a directory")
    telemetry, totals, concurrency = load_exports(args.artifact_dir)

    tps = total_row(totals, "output token throughput")        # tokens/sec, system-wide
    duration_s = total_row(totals, "benchmark duration")      # seconds, warmup excluded
    req_ps = total_row(totals, "request throughput")          # requests/sec
    total_out_tok = total_row(totals, "total output tokens") or (tps * duration_s if tps and duration_s else None)

    # GPU power/energy: per-GPU telemetry rows if available, else the
    # aggregated "Total GPU ..." rows newer AIPerf versions put in run totals.
    power = attributed(metric_rows(telemetry, "power usage"), args.gpus)
    energy = attributed(metric_rows(telemetry, "energy consumption"), args.gpus)
    counter_kwh = None
    if power:
        n_gpus = len(power)
        gpu_label = (", ".join(str(r["GPU_Index"]) for r in power)
                     if all("GPU_Index" in r for r in power)
                     else f"{n_gpus} (indices not reported)")
        avg_power_w = sum(fnum(r.get("avg")) or 0.0 for r in power)
        energy_source = "counter max-min"
        # Cumulative counter (MJ): the run's energy is max - min, never avg.
        deltas = [(fnum(r.get("max")), fnum(r.get("min"))) for r in energy]
        if deltas and all(mx is not None and mn is not None for mx, mn in deltas):
            delta_mj = sum(mx - mn for mx, mn in deltas)
            counter_kwh = delta_mj / 3.6 if delta_mj > 0 else None  # 1 kWh = 3.6 MJ
    else:
        avg_power_w = total_row(totals, "total gpu power")
        energy_j = total_row(totals, "total gpu energy")
        counter_kwh = energy_j / 3.6e6 if energy_j else None
        energy_source = "AIPerf-reported"
        power_name = total_metric_name(totals, "total gpu power") or ""
        gpu_match = re.search(r"\((\d+)\s*GPU", power_name)
        n_gpus = int(gpu_match.group(1)) if gpu_match else 1
        gpu_label = f"{n_gpus} (aggregated in run totals)"
        if args.gpus is not None:
            print("note: --gpus ignored — no per-GPU telemetry in these exports, "
                  "only aggregated run totals")

    if tps is None or avg_power_w is None:
        print("error: throughput or power rows missing — cannot build a FinOps estimate for this run.",
              file=sys.stderr)
        print(f"  output token throughput found : {'yes' if tps is not None else 'NO'}", file=sys.stderr)
        print(f"  GPU power found               : {'yes' if avg_power_w is not None else 'NO'}",
              file=sys.stderr)
        print(f"  run-totals metrics available  : {sorted(str(r.get('Metric')) for r in totals) or '(none)'}",
              file=sys.stderr)
        print(f"  telemetry metrics available   : {sorted({str(r.get('Metric')) for r in telemetry}) or '(none)'}",
              file=sys.stderr)
        sys.exit(1)

    tokens_per_gpu_hour = tps * 3600 / n_gpus
    derived_kwh = (avg_power_w * duration_s / 3.6e6) if duration_s else None
    run_energy_kwh = counter_kwh if counter_kwh is not None else derived_kwh

    print(f"Attributed GPUs        : {gpu_label}")
    print("\n-- Efficiency ratios (price-independent) --")
    print(f"Tokens per GPU-hour    : {tokens_per_gpu_hour:,.0f}")
    if counter_kwh is not None and derived_kwh is not None:
        print(f"Run energy             : {counter_kwh:.4f} kWh ({energy_source})  "
              f"vs {derived_kwh:.4f} kWh (avg power x duration) — large gaps mean coarse sampling")
    elif run_energy_kwh is not None:
        print(f"Run energy             : {run_energy_kwh:.4f} kWh")
    kwh_per_mtok = None
    if run_energy_kwh and total_out_tok:
        kwh_per_mtok = run_energy_kwh / total_out_tok * 1e6
        print(f"Energy per 1M tokens   : {kwh_per_mtok:.2f} kWh  "
              f"({total_out_tok / (run_energy_kwh * 3.6e6):.2f} tokens/joule)")

    # Cloud lens: the all-in rate already includes electricity — capacity only.
    cloud_mtok = args.gpu_hour_price / tokens_per_gpu_hour * 1e6 / args.utilization
    print(f"\n-- Cloud / rented ($ {args.gpu_hour_price:.2f}/GPU-hr all-in, U={args.utilization:.0%}) --")
    print(f"$ per 1M output tokens : ${cloud_mtok:,.4f}")

    # On-prem lens: amortized CapEx (capacity, /U) + energy (scales with load).
    capex_hr = args.gpu_purchase_price / (args.amortization_years * 8760)
    onprem_capex_mtok = capex_hr / tokens_per_gpu_hour * 1e6 / args.utilization
    onprem_energy_mtok = kwh_per_mtok * args.electricity_price_kwh * args.pue if kwh_per_mtok else 0.0
    onprem_mtok = onprem_capex_mtok + onprem_energy_mtok
    print(f"\n-- On-prem / owned (${args.gpu_purchase_price:,.0f}/GPU over {args.amortization_years:g}y = "
          f"${capex_hr:.2f}/GPU-hr, + energy @ ${args.electricity_price_kwh}/kWh x PUE {args.pue}) --")
    print(f"$ per 1M output tokens : ${onprem_mtok:,.4f}  "
          f"(CapEx ${onprem_capex_mtok:,.4f} + energy ${onprem_energy_mtok:,.4f})")

    if req_ps:
        tok_per_req = tps / req_ps
        print(f"\n$ per 1K requests      : cloud ${cloud_mtok * tok_per_req / 1000:,.4f}, "
              f"on-prem ${onprem_mtok * tok_per_req / 1000:,.4f}  "
              f"(~{tok_per_req:,.0f} output tokens/request)")
    if args.api_price_per_mtok:
        print(f"\nvs API @ ${args.api_price_per_mtok}/M output tokens: "
              f"cloud lens is {cloud_mtok / args.api_price_per_mtok:,.1f}x the API price at this load")

    print(f"\nNOTE: measured at concurrency {concurrency}. Per-token cost falls steeply with batching")
    print("until saturation — for a capacity price, use the artifacts from the sizing/ ladder's")
    print("highest healthy rung, not a low-concurrency demo run.")


if __name__ == "__main__":
    main()
