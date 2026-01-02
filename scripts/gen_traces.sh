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
CONFIG_FILE="${CONFIG_FILE:-${ROOT_DIR}/config/workloads.conf}"
REGEN_TRACES="${REGEN_TRACES:-0}"

STACK_ONLY="${STACK_ONLY:-0}"
INCLUDE_STACK="${INCLUDE_STACK:-0}"

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
  --n N              Number of elements (default 100000)
  --compress         Compress traces with xz (default: on)
  --no-compress      Do not compress traces
  --trace-bin SUFFIX Suffix for binary (default: _trace)
  --dry-run          Print commands only
  --stack-only       Trace only workloads marked stack_<w>=1
  --include-stack    Trace both heap and stack workloads
  --regen-traces     Force regeneration even if traces already exist
EOF
}

N=100000
COMPRESS=1
DRYRUN=0
BIN_SUFFIX="_trace"
PIN_TRACE_TAKE=20000000 # 20M instructions

while [[ $# -gt 0 ]]; do
  case "$1" in
    --n) N="$2"; shift 2;;
    --compress) COMPRESS=1; shift;;
  --no-compress) COMPRESS=0; shift;;
    --trace-bin) BIN_SUFFIX="$2"; shift 2;;
    --dry-run) DRYRUN=1; shift;;
    --stack-only) STACK_ONLY=1; shift;;
    --include-stack) INCLUDE_STACK=1; shift;;
    --regen-traces) REGEN_TRACES=1; shift;;
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

build_trace_bin() {
  local w="$1"
  local src="${ROOT_DIR}/src/${w}.c"
  local out="${WORKLOAD_BIN_DIR}/${w}${BIN_SUFFIX}"
  if [[ ! -x "${out}" ]]; then
    cc -O2 -std=c11 -Wall -Wextra -pedantic -DTRACING -o "${out}" "${src}"
  fi
  echo "${out}"
}

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

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

  # Reuse existing traces unless regeneration is forced
  if [[ "${REGEN_TRACES}" -ne 1 ]]; then
    if [[ -f "${trace_path_xz}" ]]; then
      ln -sfn "$(basename "${trace_path_xz}")" "${latest_link}"
      echo "[trace] ${name}: reusing existing compressed trace $(basename "${trace_path_xz}")"
      return 0
    elif [[ -f "${trace_path}" ]]; then
      ln -sfn "$(basename "${trace_path}")" "${latest_link}"
      echo "[trace] ${name}: reusing existing trace $(basename "${trace_path}")"
      return 0
    fi
  else
    rm -f "${trace_path}" "${trace_path_xz}"
  fi

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

for w in "${WORKLOADS[@]}"; do
  eval "STACK_FLAG=\${stack_${w}:-0}"
  # filtering
  if [[ "${STACK_ONLY}" == "1" && "${STACK_FLAG}" != "1" ]]; then
    continue
  fi
  if [[ "${STACK_ONLY}" != "1" && "${INCLUDE_STACK}" == "0" && "${STACK_FLAG}" == "1" ]]; then
    continue
  fi

  eval "N_W=\${n_${w}:-${N}}"

  N="${N_W}"  # override global N for this workload
  bin_path="$(build_trace_bin "${w}")"
  run_one "${w}" "${bin_path}"
done
