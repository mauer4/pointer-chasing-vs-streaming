#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"
INCLUDE_STACK=${INCLUDE_STACK:-0}
STACK_ONLY=${STACK_ONLY:-0}
RUN_METRICS=${RUN_METRICS:-0}
REGEN_TRACES=${REGEN_TRACES:-0}
N_OVERRIDE="${N_OVERRIDE:-}"
N_LIST="${N_LIST:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--include-stack] [--stack-only] [--run-metrics] [--n N] [--n-list N1,N2,...]

Orchestrates the full flow:
  1) Build tracing and non-tracing workloads
  2) Generate traces (tracing binaries)
  3) Run ChampSim simulations on traces
  4) Run native (non-trace) binaries
  5) Optionally run analysis/generate_metrics.py

Flags:
  --include-stack   Also include stack workloads (array_add_stack, list_add_stack).
  --stack-only      Only run stack workloads (implies --include-stack).
  --run-metrics     Run the metrics report after all runs.
  --regen-traces    Force regeneration of traces even if compressed traces exist.
  --n N             Override problem size for all workloads.
  --n-list list     Comma-separated list of N values to sweep (performs full flow per N).
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
    --regen-traces) REGEN_TRACES=1; shift ;;
    --n) N_OVERRIDE="$2"; shift 2 ;;
    --n-list) N_LIST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run_all] Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# Load config to get default N list if not provided via flags/env
# shellcheck disable=SC1090
source "$CONFIG_FILE"
DEFAULT_N_LIST="${WORKLOAD_N_LIST:-}"
DEFAULT_N_VALUE="${WORKLOAD_N:-}"

# Capture config-provided N list as an array for budget indexing
CONFIG_N_VALUES=()
if [[ -n "$DEFAULT_N_LIST" ]]; then
  IFS=',' read -r -a CONFIG_N_VALUES <<< "$DEFAULT_N_LIST"
elif [[ "$DEFAULT_N_VALUE" == *,* ]]; then
  IFS=',' read -r -a CONFIG_N_VALUES <<< "$DEFAULT_N_VALUE"
elif [[ -n "$DEFAULT_N_VALUE" ]]; then
  CONFIG_N_VALUES=("$DEFAULT_N_VALUE")
fi

STACK_ARGS=()
if [[ "$INCLUDE_STACK" -eq 1 ]]; then
  STACK_ARGS+=("--include-stack")
fi
if [[ "$STACK_ONLY" -eq 1 ]]; then
  STACK_ARGS+=("--stack-only")
fi

# Will append --n <value> later inside loop per N

# Determine N sweep first (before building)
if [[ -n "$N_LIST" ]]; then
  IFS=',' read -r -a N_VALUES <<< "$N_LIST"
elif [[ -n "$DEFAULT_N_LIST" ]]; then
  IFS=',' read -r -a N_VALUES <<< "$DEFAULT_N_LIST"
elif [[ "$DEFAULT_N_VALUE" == *,* ]]; then
  IFS=',' read -r -a N_VALUES <<< "$DEFAULT_N_VALUE"
else
  N_VALUES=( "${N_OVERRIDE:-$DEFAULT_N_VALUE}" )
fi

# Build N-specific binaries
echo "[run_all] Step 1/5: Building workloads (trace + non-trace) for N values: ${N_VALUES[*]}"
if [[ -n "$N_LIST" ]]; then
  CONFIG_FILE="$CONFIG_FILE" "$ROOT_DIR/scripts/build_workloads.sh" --n-list "$N_LIST"
elif [[ -n "$DEFAULT_N_LIST" ]]; then
  CONFIG_FILE="$CONFIG_FILE" "$ROOT_DIR/scripts/build_workloads.sh" --n-list "$DEFAULT_N_LIST"
elif [[ "$DEFAULT_N_VALUE" == *,* ]]; then
  CONFIG_FILE="$CONFIG_FILE" "$ROOT_DIR/scripts/build_workloads.sh" --n-list "$DEFAULT_N_VALUE"
elif [[ -n "${N_VALUES[0]}" ]]; then
  # Single N value
  CONFIG_FILE="$CONFIG_FILE" "$ROOT_DIR/scripts/build_workloads.sh" --n-list "${N_VALUES[0]}"
else
  # Build defaults
  CONFIG_FILE="$CONFIG_FILE" "$ROOT_DIR/scripts/build_workloads.sh"
fi

STEP_TOTAL=5
for nval in "${N_VALUES[@]}"; do
  N_LABEL=${nval:-"(config n_*)"}
  echo "[run_all] === N=${N_LABEL} ==="

  N_ARGS=()
  if [[ -n "$nval" ]]; then
    N_ARGS+=("--n" "$nval")
  fi

  # When the user supplies --n-list, force child scripts to honor only this N (ignore config lists)
  CHILD_N_LIST=""
  if [[ -n "$N_LIST" ]]; then
    CHILD_N_LIST="$nval"
  fi

   # Determine budget index based on position within config N list (if present)
   BUDGET_IDX=""
   if (( ${#CONFIG_N_VALUES[@]} > 0 )); then
     for i in "${!CONFIG_N_VALUES[@]}"; do
       if [[ "${CONFIG_N_VALUES[$i]}" == "$nval" ]]; then
         BUDGET_IDX="$i"
         break
       fi
     done
   fi

  echo "[run_all] Step 2/$STEP_TOTAL: Generating traces via scripts/gen_traces.sh"
  if (( ${#STACK_ARGS[@]} )); then
    CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" REGEN_TRACES="$REGEN_TRACES" N_LIST="$CHILD_N_LIST" \
      "$ROOT_DIR/scripts/gen_traces.sh" "${STACK_ARGS[@]}" "${N_ARGS[@]}"
  else
    CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" REGEN_TRACES="$REGEN_TRACES" N_LIST="$CHILD_N_LIST" \
      "$ROOT_DIR/scripts/gen_traces.sh" "${N_ARGS[@]}"
  fi

  echo "[run_all] Step 3/$STEP_TOTAL: Running ChampSim simulations via scripts/run_traces.sh"
  if (( ${#STACK_ARGS[@]} )); then
    CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" RUN_METRICS=0 N_LIST="$CHILD_N_LIST" BUDGET_IDX="$BUDGET_IDX" \
      "$ROOT_DIR/scripts/run_traces.sh" "${STACK_ARGS[@]}" "${N_ARGS[@]}"
  else
    CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" RUN_METRICS=0 N_LIST="$CHILD_N_LIST" BUDGET_IDX="$BUDGET_IDX" \
      "$ROOT_DIR/scripts/run_traces.sh" "${N_ARGS[@]}"
  fi

  echo "[run_all] Step 4/$STEP_TOTAL: Running native binaries via scripts/run_native.sh"
  if (( ${#STACK_ARGS[@]} )); then
    CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" N_LIST="$CHILD_N_LIST" \
      "$ROOT_DIR/scripts/run_native.sh" "${STACK_ARGS[@]}" "${N_ARGS[@]}"
  else
    CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" N_LIST="$CHILD_N_LIST" \
      "$ROOT_DIR/scripts/run_native.sh" "${N_ARGS[@]}"
  fi

  echo "[run_all] Step 5/$STEP_TOTAL: Metrics generation"
  if [[ "$RUN_METRICS" -eq 1 ]]; then
    METRICS_SCRIPT="$ROOT_DIR/analysis/generate_metrics.py"
    if [[ -f "$METRICS_SCRIPT" ]]; then
      echo "[run_all] Running metrics script (N=${N_LABEL})"
      if [[ -n "$nval" ]]; then
        python3 "$METRICS_SCRIPT" --n "$nval" || echo "[run_all] Metrics script failed for N=$nval"
      else
        python3 "$METRICS_SCRIPT" || echo "[run_all] Metrics script failed"
      fi
    else
      echo "[run_all] Metrics script not found at $METRICS_SCRIPT"
    fi
  else
    echo "[run_all] Skipping metrics (enable with --run-metrics or RUN_METRICS=1)"
  fi
done

echo "[run_all] Done."
