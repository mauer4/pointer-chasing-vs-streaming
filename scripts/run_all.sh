#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"
INCLUDE_STACK=${INCLUDE_STACK:-0}
STACK_ONLY=${STACK_ONLY:-0}
RUN_METRICS=${RUN_METRICS:-0}
REGEN_TRACES=${REGEN_TRACES:-0}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--include-stack] [--stack-only] [--run-metrics]

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
    --regen-traces) REGEN_TRACES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run_all] Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

STACK_ARGS=()
if [[ "$INCLUDE_STACK" -eq 1 ]]; then
  STACK_ARGS+=("--include-stack")
fi
if [[ "$STACK_ONLY" -eq 1 ]]; then
  STACK_ARGS+=("--stack-only")
fi

# 1) Build + generate traces (tracing binaries)
echo "[run_all] Generating traces via scripts/gen_traces.sh"
echo "[run_all] Note: run_traces.sh will reuse existing traces unless --regen-traces is set."
echo "[run_all] (Optional) To pre-generate traces explicitly, run: scripts/gen_traces.sh"

# 2) Run ChampSim on traces (metrics postponed to end)
echo "[run_all] Running ChampSim simulations via scripts/run_traces.sh"
if (( ${#STACK_ARGS[@]} )); then
  CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" RUN_METRICS=0 REGEN_TRACES="$REGEN_TRACES" \
    "$ROOT_DIR/scripts/run_traces.sh" "${STACK_ARGS[@]}" || true
else
  CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" RUN_METRICS=0 REGEN_TRACES="$REGEN_TRACES" \
    "$ROOT_DIR/scripts/run_traces.sh" || true
fi

# 3) Run native (non-trace) binaries
echo "[run_all] Running native binaries via scripts/run_native.sh"
if (( ${#STACK_ARGS[@]} )); then
  CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" \
    "$ROOT_DIR/scripts/run_native.sh" "${STACK_ARGS[@]}" || true
else
  CONFIG_FILE="$CONFIG_FILE" INCLUDE_STACK="$INCLUDE_STACK" STACK_ONLY="$STACK_ONLY" \
    "$ROOT_DIR/scripts/run_native.sh" || true
fi

# 4) Optional metrics generation (after all runs)
if [[ "$RUN_METRICS" -eq 1 ]]; then
  METRICS_SCRIPT="$ROOT_DIR/analysis/generate_metrics.py"
  if [[ -f "$METRICS_SCRIPT" ]]; then
    echo "[run_all] Running metrics script"
    python "$METRICS_SCRIPT" || echo "[run_all] Metrics script failed"
  else
    echo "[run_all] Metrics script not found at $METRICS_SCRIPT"
  fi
else
  echo "[run_all] Skipping metrics (enable with --run-metrics or RUN_METRICS=1)"
fi

echo "[run_all] Done. Traces under $ROOT_DIR/traces, simulations under $ROOT_DIR/results/, native runs under $ROOT_DIR/results/non-trace/."
