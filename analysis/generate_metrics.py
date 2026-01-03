#!/usr/bin/env python3
"""Generate IPC, cache, and MSHR metrics tables for array vs list (heap and stack).

Reads per-workload settings from config/workloads.conf, pulls IPC and L1D/LLC LOAD
hit/miss counts (plus L1D MSHR merges when present) from results/champsim_results/<workload>_<N>/sim.txt,
computes hit/miss rates and array-vs-list speedup, and writes a Markdown report to
analysis/metrics/report.md (or report_<N>.md when --n is provided).

Usage:
    python analysis/generate_metrics.py [--heap-only] [--stack-only] [--n N]

Outputs:
    analysis/metrics/report.md
    analysis/metrics/report_<N>.md (when --n is used)
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path
from typing import Dict, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config" / "workloads.conf"
RESULTS_DIR = ROOT / "results" / "champsim_results"
LEGACY_RESULTS_DIR = ROOT / "results"  # fallback for older runs
NONTRACE_RESULTS_DIR = ROOT / "results" / "non-trace"
OUTPUT_DIR = ROOT / "analysis" / "metrics"


def parse_config(path: Path) -> Tuple[list[str], Dict[str, str]]:
    """Parse a simple bash-style config file for WORKLOADS and key/value pairs."""
    workloads: list[str] = []
    kv: Dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("WORKLOADS="):
            # Expect: WORKLOADS=(a b c)
            m = re.search(r"WORKLOADS=\(([^)]*)\)", line)
            if m:
                workloads = m.group(1).split()
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip()
    return workloads, kv


def get_config_value(kv: Dict[str, str], key: str, default: str) -> str:
    return kv.get(key, default)


def parse_sim_metrics(sim_path: Path) -> Optional[Dict[str, float]]:
    if not sim_path.is_file():
        return None
    text = sim_path.read_text()

    ipc_match = re.search(r"CPU 0 cumulative IPC:\s*([0-9.]+)", text)
    l1d_match = re.search(
        r"cpu0->cpu0_L1D\s+LOAD\s+ACCESS:\s*([0-9]+)\s+HIT:\s*([0-9]+)\s+MISS:\s*([0-9]+)",
        text,
    )
    llc_match = re.search(
        r"cpu0->LLC(?:\s+CACHE)?\s+LOAD\s+ACCESS:\s*([0-9]+)\s+HIT:\s*([0-9]+)\s+MISS:\s*([0-9]+)",
        text,
    )
    mshr_match = re.search(
        r"cpu0->cpu0_L1D\s+LOAD\s+ACCESS:\s*[0-9]+\s+HIT:\s*[0-9]+\s+MISS:\s*[0-9]+\s+MSHR_MERGE:\s*([0-9]+)",
        text,
    )

    if not ipc_match or not l1d_match:
        return None

    access = int(l1d_match.group(1))
    hit = int(l1d_match.group(2))
    miss = int(l1d_match.group(3))
    hit_rate = hit / access if access else 0.0
    miss_rate = miss / access if access else 0.0

    metrics: Dict[str, float] = {
        "ipc": float(ipc_match.group(1)),
        "l1d_access": float(access),
        "l1d_hit": float(hit),
        "l1d_miss": float(miss),
        "l1d_hit_rate": hit_rate,
        "l1d_miss_rate": miss_rate,
    }

    if llc_match:
        llc_access = int(llc_match.group(1))
        llc_hit = int(llc_match.group(2))
        llc_miss = int(llc_match.group(3))
        metrics.update(
            {
                "llc_access": float(llc_access),
                "llc_hit": float(llc_hit),
                "llc_miss": float(llc_miss),
                "llc_hit_rate": llc_hit / llc_access if llc_access else 0.0,
                "llc_miss_rate": llc_miss / llc_access if llc_access else 0.0,
            }
        )

    if mshr_match:
        metrics["l1d_load_mshr_merge"] = float(mshr_match.group(1))
        metrics["l1d_load_mshr_rate"] = (
            metrics["l1d_load_mshr_merge"] / metrics["l1d_access"] if metrics["l1d_access"] else 0.0
        )

    return metrics


def parse_runtime(runtime_path: Path) -> Optional[float]:
    """Return runtime in milliseconds from a run.txt file."""
    if not runtime_path.is_file():
        return None
    text = runtime_path.read_text()
    m = re.search(r"time_ns=([0-9]+)", text)
    if not m:
        return None
    ns = int(m.group(1))
    return ns / 1e6  # ms


def workload_n(kv: Dict[str, str], name: str, fallback: str, override_n: Optional[str]) -> str:
    if override_n is not None:
        return override_n
    return get_config_value(kv, f"n_{name}", fallback)


def workload_stack_flag(kv: Dict[str, str], name: str) -> bool:
    return get_config_value(kv, f"stack_{name}", "0") == "1"


def sim_file_for(workload: str, n: str) -> Path:
    """Prefer new champsim_results path; fall back to legacy location if needed."""
    new_path = RESULTS_DIR / f"{workload}_{n}" / "sim.txt"
    if new_path.is_file():
        return new_path
    legacy_path = LEGACY_RESULTS_DIR / f"{workload}_{n}" / "sim.txt"
    return legacy_path


def runtime_file_for(workload: str, n: str) -> Path:
    return NONTRACE_RESULTS_DIR / f"{workload}_{n}" / "run.txt"


def render_table(title: str, rows: list[dict], speedup: Optional[float]) -> str:
    if not rows:
        return f"### {title}\n\n_No data found._\n\n"
    header = "| workload | IPC | L1D load hit rate | L1D load miss rate | L1D load accesses | LLC load hit rate | LLC load miss rate | L1D load MSHR merges | L1D load MSHR rate |\n"
    sep = "|---|---:|---:|---:|---:|---:|---:|---:|---:|\n"
    body_lines = []
    for r in rows:
        llc_hit_rate = r.get("llc_hit_rate")
        llc_miss_rate = r.get("llc_miss_rate")
        l1d_mshr = r.get("l1d_load_mshr_merge")
        body_lines.append(
            "| {name} | {ipc:.3f} | {l1h:.2f}% | {l1m:.2f}% | {l1a} | {llch} | {llcm} | {mshr} | {mshrr} |".format(
                name=r["name"],
                ipc=r["ipc"],
                l1h=r["l1d_hit_rate"] * 100,
                l1m=r["l1d_miss_rate"] * 100,
                l1a=int(r["l1d_access"]),
                llch=(f"{llc_hit_rate*100:.2f}%" if llc_hit_rate is not None else "-"),
                llcm=(f"{llc_miss_rate*100:.2f}%" if llc_miss_rate is not None else "-"),
                mshr=(f"{int(l1d_mshr)}" if l1d_mshr is not None else "-"),
                mshrr=(
                    f"{r['l1d_load_mshr_rate']*100:.4f}%" if r.get("l1d_load_mshr_rate") is not None else "-"
                ),
            )
        )
    table = "### " + title + "\n\n" + header + sep + "\n".join(body_lines) + "\n\n"
    if speedup is not None:
        table += f"**IPC speedup (array / list):** {speedup:.3f}\n\n"
    return table


def render_runtime_table(title: str, rows: list[dict], speedup: Optional[float]) -> str:
    if not rows:
        return ""
    header = "| workload | runtime (ms) |\n"
    sep = "|---|---:|\n"
    body_lines = []
    for r in rows:
        body_lines.append(f"| {r['name']} | {r['runtime_ms']:.3f} |")
    table = "### " + title + " wall-clock\n\n" + header + sep + "\n".join(body_lines) + "\n\n"
    if speedup is not None:
        table += f"**Wall-clock speedup (array / list):** {speedup:.3f}\n\n"
    return table


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate IPC/L1D metrics tables")
    parser.add_argument("--heap-only", action="store_true", help="Include only heap workloads")
    parser.add_argument("--stack-only", action="store_true", help="Include only stack workloads")
    parser.add_argument("--n", dest="override_n", help="Override N for all workloads (also sets report name)")
    args = parser.parse_args()

    workloads, kv = parse_config(CONFIG_PATH)
    if not workloads:
        raise SystemExit(f"No WORKLOADS found in {CONFIG_PATH}")

    # Identify array/list pairs
    def collect_pair(is_stack: bool):
        arr_name = "array_add_stack" if is_stack else "array_add"
        list_name = "list_add_stack" if is_stack else "list_add"
        if arr_name not in workloads or list_name not in workloads:
            return None
        return arr_name, list_name

    pairs = []
    if not args.stack_only:
        pair = collect_pair(False)
        if pair:
            pairs.append(("Heap", pair))
    if not args.heap_only:
        pair = collect_pair(True)
        if pair:
            pairs.append(("Stack", pair))

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_file = OUTPUT_DIR / (f"report_{args.override_n}.md" if args.override_n else "report.md")

    sections: list[str] = []
    for title, (arr_w, list_w) in pairs:
        # Check stack flags vs requested mode
        is_stack = workload_stack_flag(kv, arr_w)
        if title == "Heap" and is_stack:
            continue
        if title == "Stack" and not is_stack:
            continue

        arr_n = workload_n(kv, arr_w, "100000", args.override_n)
        list_n = workload_n(kv, list_w, "100000", args.override_n)

        arr_metrics = parse_sim_metrics(sim_file_for(arr_w, arr_n))
        list_metrics = parse_sim_metrics(sim_file_for(list_w, list_n))

        metric_rows: list[dict] = []
        ipc_speedup = None
        if arr_metrics:
            metric_rows.append({"name": arr_w, **arr_metrics})
        if list_metrics:
            metric_rows.append({"name": list_w, **list_metrics})
        if arr_metrics and list_metrics:
            ipc_speedup = arr_metrics["ipc"] / list_metrics["ipc"] if list_metrics["ipc"] else None

        arr_runtime = parse_runtime(runtime_file_for(arr_w, arr_n))
        list_runtime = parse_runtime(runtime_file_for(list_w, list_n))
        runtime_rows: list[dict] = []
        wall_speedup = None
        if arr_runtime is not None:
            runtime_rows.append({"name": arr_w, "runtime_ms": arr_runtime})
        if list_runtime is not None:
            runtime_rows.append({"name": list_w, "runtime_ms": list_runtime})
        if arr_runtime is not None and list_runtime is not None:
            wall_speedup = list_runtime / arr_runtime if arr_runtime else None

        section_parts = [render_table(title, metric_rows, ipc_speedup)]
        runtime_table = render_runtime_table(title, runtime_rows, wall_speedup)
        if runtime_table:
            section_parts.append(runtime_table)
        sections.append("\n".join(section_parts))

    if not sections:
        output_file.write_text("No data found. Ensure traces/runs are present in results/.\n")
    else:
        output_file.write_text("# Workload Metrics\n\n" + "\n".join(sections))

    print(f"Wrote {output_file}")


if __name__ == "__main__":
    main()
