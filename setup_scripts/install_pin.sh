#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TP_DIR="${ROOT_DIR}/third_party"
PIN_VERSION="pin-3.22-98547-g7a303a835-gcc-linux"
PIN_TARBALL="${PIN_VERSION}.tar.gz"
PIN_URL="https://software.intel.com/sites/landingpage/pintool/downloads/${PIN_TARBALL}"
PIN_DEST_BASE="${TP_DIR}/${PIN_VERSION}"
PIN_SYMLINK="${TP_DIR}/pin"
META_FILE="${PIN_SYMLINK}/README.version"

ARCH="$(uname -m)"; OS="$(uname -s)"
if [[ "${OS}" != "Linux" || "${ARCH}" != "x86_64" ]]; then
  echo "[pin] Unsupported platform: ${OS} ${ARCH}. Intel PIN binaries are Linux x86_64." >&2
  exit 1
fi

mkdir -p "${TP_DIR}"

if [[ -x "${PIN_SYMLINK}/pin" ]]; then
  echo "[pin] Existing PIN detected at ${PIN_SYMLINK}"
  exit 0
fi

if [[ ! -d "${PIN_DEST_BASE}" ]]; then
  echo "[pin] Downloading ${PIN_TARBALL} from ${PIN_URL}"
  curl -L "${PIN_URL}" -o "${TP_DIR}/${PIN_TARBALL}"
  echo "[pin] Unpacking to ${PIN_DEST_BASE}"
  tar -C "${TP_DIR}" -xzf "${TP_DIR}/${PIN_TARBALL}"
else
  echo "[pin] Using existing directory ${PIN_DEST_BASE}"
fi

# Create/refresh symlink
rm -f "${PIN_SYMLINK}"
ln -s "${PIN_DEST_BASE}" "${PIN_SYMLINK}"

# Metadata
mkdir -p "${PIN_SYMLINK}"
cat >"${META_FILE}" <<EOF
Intel PIN
Version: ${PIN_VERSION}
Source: ${PIN_URL}
Installed: $(date -u)
Location: ${PIN_DEST_BASE}
EOF

# Export instructions
cat <<'EOF'
[pin] Installed.
[pin] To use, run: source setup_scripts/env.sh
[pin] PIN_ROOT will be set to third_party/pin
EOF
