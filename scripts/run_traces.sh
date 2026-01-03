#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAMPSIM_DIR="$ROOT_DIR/third_party/champsim"
TRACE_DIR="$ROOT_DIR/traces"
RESULTS_DIR="$ROOT_DIR/results/champsim_results"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"

RUN_METRICS="${RUN_METRICS:-0}"
INCLUDE_STACK="${INCLUDE_STACK:-0}"
STACK_ONLY="${STACK_ONLY:-0}"
N_OVERRIDE="${N_OVERRIDE:-}"
N_LIST="${N_LIST:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--include-stack] [--stack-only] [--run-metrics] [--n N] [--n-list N1,N2,...]

Run ChampSim simulations using existing traces (no trace generation).

Options:
  --include-stack   Include stack workloads in addition to heap (array/list).
  --stack-only      Only run stack workloads (implies --include-stack).
  --run-metrics     Run analysis/generate_metrics.py after simulations.
  --n N             Override problem size for all workloads (and report filename).
  --n-list list     Comma-separated list of N values to sweep (overrides per-workload n_*).
  -h, --help        Show this help.

Environment overrides:
  CONFIG_FILE=/path/to/workloads.conf
  INCLUDE_STACK=1 STACK_ONLY=1 RUN_METRICS=1 N_OVERRIDE=100000 N_LIST=100000,200000
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-stack) INCLUDE_STACK=1; shift ;;
    --stack-only) STACK_ONLY=1; INCLUDE_STACK=1; shift ;;
    --run-metrics) RUN_METRICS=1; shift ;;
    --n) N_OVERRIDE="$2"; shift 2 ;;
    --n-list) N_LIST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run_traces] Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# shellcheck disable=SC1090
source "$CONFIG_FILE"

DEFAULT_WARMUP="${CHAMPSIM_WARMUP_INSTRUCTIONS:-500000}"
DEFAULT_WARMUP_LIST="${CHAMPSIM_WARMUP_INSTRUCTIONS_LIST:-}"
DEFAULT_SIM="${CHAMPSIM_SIM_INSTRUCTIONS:-40000000}"
DEFAULT_SIM_LIST="${CHAMPSIM_SIM_INSTRUCTIONS_LIST:-}"
DEFAULT_N_LIST="${WORKLOAD_N_LIST:-}"
# WORKLOAD_N may be a single value or comma-separated list
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

run_for_n() {
  local n_override="$1" idx="$2"
  set +e
  local local_rc=0
  for w in "${WORKLOADS[@]}"; do
    eval "STACK_FLAG=\${stack_${w}:-0}"
    if [[ "$STACK_ONLY" -eq 1 && "$STACK_FLAG" -ne 1 ]]; then
      continue
    fi
    if [[ "$STACK_ONLY" -ne 1 && "$INCLUDE_STACK" -eq 0 && "$STACK_FLAG" -eq 1 ]]; then
      continue
    fi

    local N_W
    if [[ -n "$n_override" ]]; then
      N_W="$n_override"
    else
      N_W="${DEFAULT_N}"
    fi

    local WARMUP_W SIM_W

    # Per-workload warmup list (aligned with N sweep index)
    eval "WARMUP_LIST_W=\${warmup_cycles_${w}_list:-}"
    if [[ -n "$WARMUP_LIST_W" ]]; then
      IFS=',' read -r -a W_ARR_W <<< "$WARMUP_LIST_W"
      if (( idx < ${#W_ARR_W[@]} )); then WARMUP_W="${W_ARR_W[$idx]}"; fi
    fi
    # Fallback to global warmup list (aligned by index)
    if [[ -z "$WARMUP_W" && -n "$DEFAULT_WARMUP_LIST" ]]; then
      IFS=',' read -r -a W_ARR <<< "$DEFAULT_WARMUP_LIST"
      if (( idx < ${#W_ARR[@]} )); then WARMUP_W="${W_ARR[$idx]}"; fi
    fi
    # Fallback to per-workload single value, then global single value
    if [[ -z "$WARMUP_W" ]]; then
      eval "WARMUP_W=\${warmup_cycles_${w}:-}"
    fi
    if [[ -z "$WARMUP_W" ]]; then
      eval "WARMUP_W=\${warmup_${w}:-}"
    fi
    if [[ -z "$WARMUP_W" ]]; then
      WARMUP_W="$DEFAULT_WARMUP"
    fi

    # Per-workload sim list (aligned with N sweep index)
    eval "SIM_LIST_W=\${sim_cycles_${w}_list:-}"
    if [[ -n "$SIM_LIST_W" ]]; then
      IFS=',' read -r -a S_ARR_W <<< "$SIM_LIST_W"
      if (( idx < ${#S_ARR_W[@]} )); then SIM_W="${S_ARR_W[$idx]}"; fi
    fi
    # Fallback to global sim list
    if [[ -z "$SIM_W" && -n "$DEFAULT_SIM_LIST" ]]; then
      IFS=',' read -r -a S_ARR <<< "$DEFAULT_SIM_LIST"
      if (( idx < ${#S_ARR[@]} )); then SIM_W="${S_ARR[$idx]}"; fi
    fi
    # Fallback to per-workload single value, then global single value
    if [[ -z "$SIM_W" ]]; then
      eval "SIM_W=\${sim_cycles_${w}:-}"
    fi
    if [[ -z "$SIM_W" ]]; then
      eval "SIM_W=\${sim_${w}:-}"
    fi
    if [[ -z "$SIM_W" ]]; then
      SIM_W="$DEFAULT_SIM"
    fi

    trace_base="$(trace_for_workload "$w" "$N_W")"
    if [[ -f "${trace_base}.xz" ]]; then
      trace_path="${trace_base}.xz"
    elif [[ -f "$trace_base" ]]; then
      trace_path="$trace_base"
    else
      echo "[run_traces] Missing trace for $w n=$N_W at ${trace_base}[.xz]. Run scripts/gen_traces.sh first." >&2
      local_rc=1
      continue
    fi

    if ! run_sim "$w" "$N_W" "$trace_path" "$WARMUP_W" "$SIM_W"; then
      local_rc=1
    fi
  done
  set -e
  return $local_rc
}

if [[ -n "$N_LIST" ]]; then
  IFS=',' read -r -a N_VALUES <<< "$N_LIST"
elif [[ -n "$DEFAULT_N_LIST" ]]; then
  IFS=',' read -r -a N_VALUES <<< "$DEFAULT_N_LIST"
elif [[ "$DEFAULT_N" == *,* ]]; then
  IFS=',' read -r -a N_VALUES <<< "$DEFAULT_N"
else
  N_VALUES=( "${N_OVERRIDE:-$DEFAULT_N}" )
fi

EXIT_CODE=0
idx=0
for nval in "${N_VALUES[@]}"; do
  echo "[run_traces] === N=${nval} ==="
  if ! run_for_n "$nval" "$idx"; then
    EXIT_CODE=1
  fi

  idx=$((idx+1))

  if [[ "$RUN_METRICS" -eq 1 ]]; then
    METRICS_SCRIPT="$ROOT_DIR/analysis/generate_metrics.py"
    if [[ -x "$METRICS_SCRIPT" || -f "$METRICS_SCRIPT" ]]; then
      echo "[metrics] Running $METRICS_SCRIPT (N=$nval)"
      if ! python "$METRICS_SCRIPT" --n "$nval"; then
        echo "[metrics] Metrics script exited with an error for N=$nval" >&2
      fi
    else
      echo "[metrics] Metrics script not found at $METRICS_SCRIPT"
    fi
  fi
done

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "[run_traces] Completed with errors."
else
  echo "[run_traces] Done. Results under $RESULTS_DIR/"
fi

exit $EXIT_CODE
