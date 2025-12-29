#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHAMPSIM_DIR="${ROOT_DIR}/third_party/champsim"
TRACER_DIR="${CHAMPSIM_DIR}/tracer/pin"
TOOL_SO="${TRACER_DIR}/obj-intel64/champsim_tracer.so"

ARCH="$(uname -m)"; OS="$(uname -s)"
if [[ "${OS}" != "Linux" || "${ARCH}" != "x86_64" ]]; then
  echo "[tracer] Unsupported platform: ${OS} ${ARCH}." >&2
  exit 1
fi

# Load PIN_ROOT if env.sh exists
if [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/env.sh"
fi

if [[ -z "${PIN_ROOT:-}" ]]; then
  echo "[tracer] PIN_ROOT not set. Run source scripts/env.sh or install_pin.sh first." >&2
  exit 1
fi

if [[ ! -x "${PIN_ROOT}/pin" ]]; then
  echo "[tracer] ${PIN_ROOT}/pin not found or not executable." >&2
  exit 1
fi

if [[ ! -d "${TRACER_DIR}" ]]; then
  echo "[tracer] ChampSim tracer directory not found: ${TRACER_DIR}" >&2
  exit 1
fi

echo "[tracer] Building ChampSim PIN tool using PIN_ROOT=${PIN_ROOT}"
make -C "${TRACER_DIR}" PIN_ROOT="${PIN_ROOT}" >/dev/null

if [[ ! -f "${TOOL_SO}" ]]; then
  echo "[tracer] Build finished but tracer .so missing: ${TOOL_SO}" >&2
  exit 1
fi

echo "[tracer] Built tracer: ${TOOL_SO}"
