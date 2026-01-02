#!/usr/bin/env python3
"""Generate IPC and L1D metrics tables for array vs list (heap and stack).

Reads per-workload settings from config/workloads.conf, pulls IPC and L1D LOAD
hit/miss counts from results/<workload>_<N>/sim.txt, computes hit/miss rates and
array-vs-list speedup, and writes a Markdown report to analysis/metrics/report.md.

Usage:
  python analysis/generate_metrics.py [--heap-only] [--stack-only]

Outputs:
  analysis/metrics/report.md
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path
from typing import Dict, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config" / "workloads.conf"
RESULTS_DIR = ROOT / "results"
OUTPUT_DIR = ROOT / "analysis" / "metrics"
OUTPUT_FILE = OUTPUT_DIR / "report.md"


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
    if not ipc_match or not l1d_match:
        return None

    access = int(l1d_match.group(1))
    hit = int(l1d_match.group(2))
    miss = int(l1d_match.group(3))
    hit_rate = hit / access if access else 0.0
    miss_rate = miss / access if access else 0.0

    return {
        "ipc": float(ipc_match.group(1)),
        "l1d_access": float(access),
        "l1d_hit": float(hit),
        "l1d_miss": float(miss),
        "l1d_hit_rate": hit_rate,
        "l1d_miss_rate": miss_rate,
    }


def workload_n(kv: Dict[str, str], name: str, fallback: str) -> str:
    return get_config_value(kv, f"n_{name}", fallback)


def workload_stack_flag(kv: Dict[str, str], name: str) -> bool:
    return get_config_value(kv, f"stack_{name}", "0") == "1"


def sim_file_for(workload: str, n: str) -> Path:
    return RESULTS_DIR / f"{workload}_{n}" / "sim.txt"


def render_table(title: str, rows: list[dict], speedup: Optional[float]) -> str:
    if not rows:
        return f"### {title}\n\n_No data found._\n\n"
    header = "| workload | IPC | L1D load hit rate | L1D load miss rate | L1D load accesses |\n"
    sep = "|---|---:|---:|---:|---:|\n"
    body_lines = []
    for r in rows:
        body_lines.append(
            f"| {r['name']} | {r['ipc']:.3f} | {r['l1d_hit_rate']*100:.2f}% | {r['l1d_miss_rate']*100:.2f}% | {int(r['l1d_access'])} |"
        )
    table = "### " + title + "\n\n" + header + sep + "\n".join(body_lines) + "\n\n"
    if speedup is not None:
        table += f"**Speedup (array / list):** {speedup:.3f}\n\n"
    return table


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate IPC/L1D metrics tables")
    parser.add_argument("--heap-only", action="store_true", help="Include only heap workloads")
    parser.add_argument("--stack-only", action="store_true", help="Include only stack workloads")
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

    sections: list[str] = []
    for title, (arr_w, list_w) in pairs:
        # Check stack flags vs requested mode
        is_stack = workload_stack_flag(kv, arr_w)
        if title == "Heap" and is_stack:
            continue
        if title == "Stack" and not is_stack:
            continue

        arr_n = workload_n(kv, arr_w, "100000")
        list_n = workload_n(kv, list_w, "100000")

        arr_metrics = parse_sim_metrics(sim_file_for(arr_w, arr_n))
        list_metrics = parse_sim_metrics(sim_file_for(list_w, list_n))

        rows = []
        speedup = None
        if arr_metrics:
            rows.append({"name": arr_w, **arr_metrics})
        if list_metrics:
            rows.append({"name": list_w, **list_metrics})
        if arr_metrics and list_metrics:
            speedup = arr_metrics["ipc"] / list_metrics["ipc"] if list_metrics["ipc"] else None

        sections.append(render_table(title, rows, speedup))

    if not sections:
        OUTPUT_FILE.write_text("No data found. Ensure traces/runs are present in results/.\n")
    else:
        OUTPUT_FILE.write_text("# Workload Metrics\n\n" + "\n".join(sections))

    print(f"Wrote {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
