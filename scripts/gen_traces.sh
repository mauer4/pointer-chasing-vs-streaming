#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHAMPSIM_DIR="${ROOT_DIR}/third_party/champsim"
TRACER_DIR="${CHAMPSIM_DIR}/tracer/pin"
TRACER_SO="${TRACER_DIR}/obj-intel64/champsim_tracer.so"
WORKLOAD_BIN_DIR="${ROOT_DIR}/bin"
TRACE_ROOT="${ROOT_DIR}/traces"
LOG_ROOT="${ROOT_DIR}/results/traces"

ARCH="$(uname -m)"; OS="$(uname -s)"
if [[ "${OS}" != "Linux" || "${ARCH}" != "x86_64" ]]; then
  echo "[trace] Unsupported platform: ${OS} ${ARCH}." >&2
  exit 1
fi

# Load PIN_ROOT if available
if [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/env.sh"
fi

PIN_BIN="${PIN_ROOT:-}/pin"

usage() {
  cat <<EOF
Usage: $0 [--n N] [--compress] [--trace-bin SUFFIX] [--dry-run]
  --n N              Number of elements (default 4000000)
  --compress         Compress traces with xz
  --trace-bin SUFFIX Suffix for binary (e.g., _trace for array_add_trace)
  --dry-run          Print commands only
EOF
}

N=4000000
COMPRESS=0
DRYRUN=0
BIN_SUFFIX=""
PIN_TRACE_TAKE=20000000 # 20M instructions

while [[ $# -gt 0 ]]; do
  case "$1" in
    --n) N="$2"; shift 2;;
    --compress) COMPRESS=1; shift;;
    --trace-bin) BIN_SUFFIX="$2"; shift 2;;
    --dry-run) DRYRUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "${PIN_ROOT:-}" || ! -x "${PIN_BIN}" ]]; then
  echo "[trace] PIN_ROOT not set or pin not executable. Run 'source scripts/env.sh' and install_pin.sh." >&2
  exit 1
fi

if [[ ! -f "${TRACER_SO}" ]]; then
  echo "[trace] Tracer .so missing: ${TRACER_SO}. Run scripts/build_champsim_tracer.sh." >&2
  exit 1
fi

ARRAY_BIN="${WORKLOAD_BIN_DIR}/array_add${BIN_SUFFIX}"
LIST_BIN="${WORKLOAD_BIN_DIR}/list_add${BIN_SUFFIX}"

if [[ ! -x "${ARRAY_BIN}" || ! -x "${LIST_BIN}" ]]; then
  echo "[trace] Workload binaries missing: ${ARRAY_BIN} or ${LIST_BIN}." >&2
  echo "[trace] Run scripts/build_variants.sh." >&2
  exit 1
fi

mkdir -p "${TRACE_ROOT}" "${LOG_ROOT}"

run_one() {
  local name="$1"
  local bin="$2"
  local out_dir="${TRACE_ROOT}/${name}"
  local log_dir="${LOG_ROOT}/${name}"
  mkdir -p "${out_dir}" "${log_dir}"

  local fname="${name}_n=${N}.champsimtrace"
  local trace_path="${out_dir}/${fname}"
  local trace_path_xz="${trace_path}.xz"
  local latest_link="${out_dir}/latest.champsimtrace"

  # -s 0: skip 0 instructions
  # -t N: take N instructions
  local cmd=("${PIN_BIN}" -t "${TRACER_SO}" -o "${trace_path}" -s "0" -t "${PIN_TRACE_TAKE}" -- "${bin}" "${N}")

  echo "[trace] ${name}: ${trace_path}"
  if [[ ${DRYRUN} -eq 1 ]]; then
    printf '[trace] DRYRUN: '; printf '%q ' "${cmd[@]}"; echo
    return 0
  fi

  # Logs
  local out_log="${log_dir}/${fname}.out"
  local err_log="${log_dir}/${fname}.err"

  "${cmd[@]}" >"${out_log}" 2>"${err_log}" || { echo "[trace] ${name} failed" >&2; return 1; }

  if [[ ${COMPRESS} -eq 1 ]]; then
    xz -T0 -f "${trace_path}"
    trace_path="${trace_path_xz}"
  fi

  ln -sfn "$(basename "${trace_path}")" "${latest_link}"
  echo "[trace] ${name}: wrote $(basename "${trace_path}")"
}

run_one "array_add" "${ARRAY_BIN}"
run_one "list_add" "${LIST_BIN}"
