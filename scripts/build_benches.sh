#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${ROOT_DIR}/src"
BUILD_DIR="${ROOT_DIR}/build/bin"
CC_BIN="${CC:-gcc}"
CFLAGS_EXTRA="${CFLAGS_EXTRA:-}"
BASE_CFLAGS="-O3 -march=native -std=c11 -Wall -Wextra"

usage() {
  echo "Usage: $0 [--clean]" >&2
}

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "${ROOT_DIR}/build"
  echo "[benches] cleaned build/"
  exit 0
fi

mkdir -p "${BUILD_DIR}"

build_one() {
  local src="$1" out="$2"
  echo "[benches] Building ${out}"
  "${CC_BIN}" ${BASE_CFLAGS} ${CFLAGS_EXTRA} -o "${out}" "${src}"
}

build_one "${SRC_DIR}/array_add.c" "${BUILD_DIR}/array_add"
build_one "${SRC_DIR}/list_add.c" "${BUILD_DIR}/list_add"

if [[ ! -x "${BUILD_DIR}/array_add" || ! -x "${BUILD_DIR}/list_add" ]]; then
  echo "[benches] Build failed: binaries missing" >&2
  exit 1
fi

echo "[benches] Built binaries in ${BUILD_DIR}"
