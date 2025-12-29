#!/usr/bin/env bash
# Source this to export PIN_ROOT and other tracing env defaults.
# Idempotent and safe to source multiple times.
#set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TP_DIR="${ROOT_DIR}/third_party"

# Try to resolve PIN_ROOT deterministically:
# 1) If PIN_ROOT already set and contains bin, keep it.
# 2) Else, use third_party/pin if present.
# 3) Else, pick the newest third_party/pin-* directory.
if [[ -n "${PIN_ROOT:-}" && -x "${PIN_ROOT}/pin" ]]; then
  export PIN_ROOT="$(cd "${PIN_ROOT}" && pwd)"
elif [[ -x "${TP_DIR}/pin/pin" ]]; then
  export PIN_ROOT="$(cd "${TP_DIR}/pin" && pwd)"
else
  latest_pin_dir="$(ls -1dt ${TP_DIR}/pin-* 2>/dev/null | head -n1 || true)"
  if [[ -n "${latest_pin_dir}" && -x "${latest_pin_dir}/pin" ]]; then
    export PIN_ROOT="$(cd "${latest_pin_dir}" && pwd)"
  fi
fi

if [[ -z "${PIN_ROOT:-}" ]]; then
  echo "[env] PIN_ROOT not found. Run scripts/install_pin.sh first." >&2
else
  echo "[env] PIN_ROOT=${PIN_ROOT}"
fi

# Default knobs for trace generation (can be overridden by caller)
export PIN_TRACE_SKIP="${PIN_TRACE_SKIP:-0}"
export PIN_TRACE_TAKE="${PIN_TRACE_TAKE:-1000000}"

