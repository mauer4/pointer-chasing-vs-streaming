#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
RESULTS_DIR="$ROOT_DIR/results/non-trace"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"
INCLUDE_STACK="${INCLUDE_STACK:-0}"
STACK_ONLY="${STACK_ONLY:-0}"
N_OVERRIDE="${N_OVERRIDE:-}"
N_LIST="${N_LIST:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--include-stack] [--stack-only] [--n N] [--n-list N1,N2,...]

Runs the non-tracing binaries and captures stdout to results/non-trace/.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-stack) INCLUDE_STACK=1; shift ;;
    --stack-only) STACK_ONLY=1; INCLUDE_STACK=1; shift ;;
    --n) N_OVERRIDE="$2"; shift 2 ;;
    --n-list) N_LIST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run_native] Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Build non-tracing binaries once
"$ROOT_DIR/scripts/build_workloads.sh"

DEFAULT_N="${WORKLOAD_N:-100000}"
DEFAULT_N_LIST="${WORKLOAD_N_LIST:-}"

run_for_n() {
  local n_override="$1"
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
      N_W="$DEFAULT_N"
    fi

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

for nval in "${N_VALUES[@]}"; do
  echo "[run_native] === N=${nval} ==="
  run_for_n "$nval"
done

