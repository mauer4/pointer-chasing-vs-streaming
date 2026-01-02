#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
RESULTS_DIR="$ROOT_DIR/results/non-trace"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"
INCLUDE_STACK="${INCLUDE_STACK:-0}"
STACK_ONLY="${STACK_ONLY:-0}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--include-stack] [--stack-only]

Runs the non-tracing binaries and captures stdout to results/non-trace/.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --include-stack) INCLUDE_STACK=1 ;;
    --stack-only) STACK_ONLY=1 ; INCLUDE_STACK=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run_native] Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Build non-tracing binaries
"$ROOT_DIR/scripts/build_workloads.sh"

for w in "${WORKLOADS[@]}"; do
  eval "STACK_FLAG=\${stack_${w}:-0}"
  if [[ "$STACK_ONLY" -eq 1 && "$STACK_FLAG" -ne 1 ]]; then
    continue
  fi
  if [[ "$STACK_ONLY" -ne 1 && "$INCLUDE_STACK" -eq 0 && "$STACK_FLAG" -eq 1 ]]; then
    continue
  fi

  eval "N_W=\${n_${w}:-100000}"
  exe="$BIN_DIR/$w"
  if [[ ! -x "$exe" ]]; then
    echo "[run_native] Missing binary: $exe" >&2
    continue
  fi
  out_dir="$RESULTS_DIR/${w}_${N_W}"
  mkdir -p "$out_dir"
  echo "[run_native] Running $w n=$N_W"
  "$exe" "$N_W" >"$out_dir/run.txt" 2>"$out_dir/run.err" || true
  echo "[run_native] Output: $out_dir/run.txt"

done

