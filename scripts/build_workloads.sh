#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"
N_LIST="${N_LIST:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--n-list N1,N2,...]

Build workload binaries with different DEFAULT_N values compiled in.

Options:
  --n-list list     Comma-separated list of N values to build binaries for.
  -h, --help        Show this help.

If no --n-list is provided, builds default binaries without -DDEFAULT_N override.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --n-list) N_LIST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[build] Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# shellcheck disable=SC1090
source "$CONFIG_FILE"

DEFAULT_N_LIST="${WORKLOAD_N_LIST:-}"

mkdir -p "$BIN_DIR"

# Determine N values to build for
if [[ -n "$N_LIST" ]]; then
  IFS=',' read -r -a N_VALUES <<< "$N_LIST"
elif [[ -n "$DEFAULT_N_LIST" ]]; then
  IFS=',' read -r -a N_VALUES <<< "$DEFAULT_N_LIST"
else
  # Build default binaries without N suffix
  N_VALUES=("")
fi

for nval in "${N_VALUES[@]}"; do
  if [[ -n "$nval" ]]; then
    echo "[build] Building binaries with N=${nval}"
    make -C "$ROOT_DIR/src" N="$nval" all
  else
    echo "[build] Building default binaries"
    make -C "$ROOT_DIR/src" all
  fi
done

echo "[build] Done."
