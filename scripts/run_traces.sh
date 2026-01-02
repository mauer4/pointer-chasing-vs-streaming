#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAMPSIM_DIR="$ROOT_DIR/third_party/champsim"
TRACE_DIR="$ROOT_DIR/traces"
RESULTS_DIR="$ROOT_DIR/results"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"

RUN_METRICS="${RUN_METRICS:-0}"
INCLUDE_STACK="${INCLUDE_STACK:-0}"
STACK_ONLY="${STACK_ONLY:-0}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--include-stack] [--stack-only] [--run-metrics]

Run ChampSim simulations using existing traces (no trace generation).

Options:
  --include-stack   Include stack workloads in addition to heap (array/list).
  --stack-only      Only run stack workloads (implies --include-stack).
  --run-metrics     Run analysis/generate_metrics.py after simulations.
  -h, --help        Show this help.

Environment overrides:
  CONFIG_FILE=/path/to/workloads.conf
  INCLUDE_STACK=1 STACK_ONLY=1 RUN_METRICS=1
EOF
}

for arg in "$@"; do
  case "$arg" in
    --include-stack) INCLUDE_STACK=1 ;;
    --stack-only) STACK_ONLY=1; INCLUDE_STACK=1 ;;
    --run-metrics) RUN_METRICS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run_traces] Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

# shellcheck disable=SC1090
source "$CONFIG_FILE"

DEFAULT_WARMUP="${CHAMPSIM_WARMUP_INSTRUCTIONS:-500000}"
DEFAULT_SIM="${CHAMPSIM_SIM_INSTRUCTIONS:-40000000}"
DEFAULT_N="${WORKLOAD_N:-100000}"

if [[ ! -d "$CHAMPSIM_DIR" ]]; then
  echo "[run_traces] ChampSim not found at $CHAMPSIM_DIR"
  echo "[run_traces] Run: scripts/setup.sh"
  exit 1
fi

CHAMPSIM_BIN=""
if [[ -x "$CHAMPSIM_DIR/bin/champsim" ]]; then
  CHAMPSIM_BIN="$CHAMPSIM_DIR/bin/champsim"
else
  CHAMPSIM_BIN="$(find "$CHAMPSIM_DIR" -maxdepth 4 -type f -name champsim -perm -u+x 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$CHAMPSIM_BIN" ]]; then
  echo "[run_traces] Could not find ChampSim executable. Did build succeed?"
  exit 1
fi

mkdir -p "$TRACE_DIR" "$RESULTS_DIR"

trace_for_workload() {
  local w="$1" n="$2"
  echo "$TRACE_DIR/${w}/${w}_n=${n}.champsimtrace"
}

run_sim() {
  local workload_name="$1" n_val="$2" trace_in="$3" warmup="$4" sim="$5"
  local out_dir="$RESULTS_DIR/${workload_name}_${n_val}"
  mkdir -p "$out_dir"

  echo "[sim] ${workload_name}_${n_val}: trace=$trace_in warmup=$warmup sim=$sim"
  if ! "$CHAMPSIM_BIN" --warmup-instructions "$warmup" --simulation-instructions "$sim" "$trace_in" >"$out_dir/sim.txt" 2>"$out_dir/sim.err"; then
    echo "[sim] ${workload_name}_${n_val}: ChampSim exited with error (see $out_dir/sim.err)" >&2
    return 1
  fi
  return 0
}

set +e
EXIT_CODE=0
for w in "${WORKLOADS[@]}"; do
  eval "STACK_FLAG=\${stack_${w}:-0}"
  if [[ "$STACK_ONLY" -eq 1 && "$STACK_FLAG" -ne 1 ]]; then
    continue
  fi
  if [[ "$STACK_ONLY" -ne 1 && "$INCLUDE_STACK" -eq 0 && "$STACK_FLAG" -eq 1 ]]; then
    continue
  fi

  eval "N_W=\${n_${w}:-${DEFAULT_N}}"
  eval "WARMUP_W=\${warmup_${w}:-${DEFAULT_WARMUP}}"
  eval "SIM_W=\${sim_${w}:-${DEFAULT_SIM}}"

  trace_base="$(trace_for_workload "$w" "$N_W")"
  if [[ -f "${trace_base}.xz" ]]; then
    trace_path="${trace_base}.xz"
  elif [[ -f "$trace_base" ]]; then
    trace_path="$trace_base"
  else
    echo "[run_traces] Missing trace for $w n=$N_W at ${trace_base}[.xz]. Run scripts/gen_traces.sh first." >&2
    EXIT_CODE=1
    continue
  fi

  if ! run_sim "$w" "$N_W" "$trace_path" "$WARMUP_W" "$SIM_W"; then
    EXIT_CODE=1
  fi
done
set -e

if [[ "$RUN_METRICS" -eq 1 ]]; then
  METRICS_SCRIPT="$ROOT_DIR/analysis/generate_metrics.py"
  if [[ -x "$METRICS_SCRIPT" || -f "$METRICS_SCRIPT" ]]; then
    echo "[metrics] Running $METRICS_SCRIPT"
    python "$METRICS_SCRIPT" || echo "[metrics] Metrics script exited with an error"
  else
    echo "[metrics] Metrics script not found at $METRICS_SCRIPT"
  fi
fi

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "[run_traces] Completed with errors."
else
  echo "[run_traces] Done. Results under $RESULTS_DIR/"
fi

exit $EXIT_CODE
