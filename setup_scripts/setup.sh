#!/usr/bin/env bash
# Non-fatal setup: keep going to surface *all* issues in one run.
# This repo is often used on environments where sudo is unavailable (e.g. vast.ai).
# ChampSim provides dependencies via its bundled vcpkg; prefer that over apt.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/results"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"

# Tee all output to a log file so failures are visible even when a command errors.
exec > >(tee -a "$LOG_FILE") 2>&1

FAILURES=0
failed_steps=()

TP_DIR="$ROOT_DIR/third_party"
CHAMPSIM_DIR="$TP_DIR/champsim"

info() { echo "[setup] $*"; }

run_step() {
  local name="$1"; shift
  info "==> $name"
  "$@"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    info "[WARN] step failed (rc=$rc): $name"
    FAILURES=$((FAILURES + 1))
    failed_steps+=("$name")
  fi
  return 0
}

run_step_cd() {
  local name="$1"; shift
  local dir="$1"; shift
  info "==> $name (in $dir)"
  (cd "$dir" && "$@")
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    info "[WARN] step failed (rc=$rc): $name"
    FAILURES=$((FAILURES + 1))
    failed_steps+=("$name")
  fi
  return 0
}

run_step_bash() {
  local name="$1"; shift
  info "==> $name"
  bash -lc "$*"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    info "[WARN] step failed (rc=$rc): $name"
    FAILURES=$((FAILURES + 1))
    failed_steps+=("$name")
  fi
  return 0
}

info "Workspace: $ROOT_DIR"
info "Logging to: $LOG_FILE"

# 1) System dependencies (opt-in install; no surprise sudo)
# ChampSim build generally needs: git, gcc/g++, make, python3. Some configs may use cmake.
# If SETUP_INSTALL_SYSTEM_DEPS=1 and passwordless sudo is available, we'll install.
# Otherwise we only emit guidance and fail fast on missing tools.
if command -v apt-get >/dev/null 2>&1; then
  if [[ "${SETUP_INSTALL_SYSTEM_DEPS:-0}" == "1" ]]; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      info "Installing minimal apt dependencies (opt-in, passwordless sudo detected)..."
      run_step "apt-get update" sudo apt-get update -y
      run_step "apt-get install deps" sudo apt-get install -y \
        git \
        build-essential \
        gcc g++ \
        make \
        cmake \
        ninja-build \
        pkg-config \
        python3 python3-pip \
        ca-certificates \
        zip unzip curl tar
    else
      info "SETUP_INSTALL_SYSTEM_DEPS=1 but passwordless sudo is unavailable; skipping install."
    fi
  else
    info "Skipping apt installs (SETUP_INSTALL_SYSTEM_DEPS!=1)."
  fi
else
  info "No apt-get found; skipping system package install."
fi

# Preflight: ensure tools needed for vcpkg/bootstrap are present even if apt was skipped.
run_step "preflight: zip/unzip/curl/tar/pkg-config" bash -lc 'for tool in zip unzip curl tar pkg-config; do if ! command -v "$tool" >/dev/null 2>&1; then echo "$tool missing. Install (Debian/Ubuntu): sudo apt-get install -y zip unzip curl tar pkg-config"; exit 1; fi; done'

# 2) Python deps for notebook (always in local venv to avoid PEP668)
VENVDIR="$ROOT_DIR/.venv"
PYTHON_VENV="$VENVDIR/bin/python"
PIP_VENV="$VENVDIR/bin/pip"

info "Ensuring local venv at $VENVDIR (avoids system pip/PEP668)"
run_step "python venv create" python3 -m venv "$VENVDIR"

info "Installing python deps in venv..."
run_step "pip upgrade (venv)" "$PIP_VENV" install --upgrade pip
run_step "pip install notebook deps (venv)" "$PIP_VENV" install -U pandas numpy matplotlib seaborn
info "To use the venv: source $VENVDIR/bin/activate"

# 3) Clone ChampSim (not tracked in git)
mkdir -p "$TP_DIR"
if [[ -d "$CHAMPSIM_DIR/.git" ]]; then
  info "ChampSim already cloned at $CHAMPSIM_DIR"
else
  info "Cloning ChampSim into $CHAMPSIM_DIR"
  run_step "git clone ChampSim" git clone --depth 1 https://github.com/ChampSim/ChampSim.git "$CHAMPSIM_DIR"
fi

# 4) Build ChampSim (baseline)
# ChampSim build interface changes occasionally; we try the common build path.
info "Building ChampSim (this may take a bit)..."
if [[ -d "$CHAMPSIM_DIR" ]]; then
  if [[ -f "$CHAMPSIM_DIR/build_champsim.sh" ]]; then
    run_step "chmod build_champsim.sh" chmod +x "$CHAMPSIM_DIR/build_champsim.sh"
    run_step "build_champsim.sh x86 1" bash -lc "cd '$CHAMPSIM_DIR' && ./build_champsim.sh x86 1"
  elif [[ -f "$CHAMPSIM_DIR/build.sh" ]]; then
    run_step "chmod build.sh" chmod +x "$CHAMPSIM_DIR/build.sh"
    run_step "build.sh" bash -lc "cd '$CHAMPSIM_DIR' && ./build.sh"
  elif [[ -f "$CHAMPSIM_DIR/Makefile" ]]; then
    # Follow ChampSim README for dependency management via vcpkg.
    # This avoids relying on sudo/apt for libraries like fmt/CLI11.
  run_step "git submodule update --init" bash -lc "cd '$CHAMPSIM_DIR' && git submodule update --init"
  run_step "vcpkg bootstrap" bash -lc "cd '$CHAMPSIM_DIR' && ./vcpkg/bootstrap-vcpkg.sh"

  # IMPORTANT: ChampSim's Makefile expects dependencies under ./vcpkg_installed/<triplet>/...
  # (TRIPLET_DIR is derived from vcpkg_installed/*). If we run vcpkg without --x-install-root,
  # headers/libraries won't be found and the generated absolute.options may contain a dangling '-isystem'.
    run_step "vcpkg install (into vcpkg_installed/)" bash -lc "cd '$CHAMPSIM_DIR' && ./vcpkg/vcpkg install --x-install-root=./vcpkg_installed"

    # Root-cause guard: ChampSim's Makefile derives include/lib dirs from ./vcpkg_installed/*/.
    # If this directory is missing or empty, stop here to avoid cascading errors.
    if [[ ! -d "$CHAMPSIM_DIR/vcpkg_installed/x64-linux/include" ]]; then
      info "[WARN] vcpkg_installed/x64-linux/include missing; skipping ChampSim build. Install system deps (e.g., pkg-config) and rerun setup."
      FAILURES=$((FAILURES + 1))
      failed_steps+=("vcpkg install (deps missing)")
    else
      # If previous runs created malformed option files, force regeneration.
      run_step "clean stale options" bash -lc "cd '$CHAMPSIM_DIR' && rm -f absolute.options"

      # Generate _configuration.mk and generated headers under .csconfig/
      run_step "config.sh champsim_config.json" bash -lc "cd '$CHAMPSIM_DIR' && ./config.sh champsim_config.json"

      # Preflight checks that catch the exact class of failure we saw (broken include flags / missing generated files)
      run_step "preflight: generated core_inst.inc" bash -lc "cd '$CHAMPSIM_DIR' && test -f .csconfig/core_inst.inc"
      run_step "preflight: vcpkg json header" bash -lc "cd '$CHAMPSIM_DIR' && test -f vcpkg_installed/x64-linux/include/nlohmann/json.hpp"
      run_step "preflight: vcpkg bzip2 header" bash -lc "cd '$CHAMPSIM_DIR' && test -f vcpkg_installed/x64-linux/include/bzlib.h"

      # Ensure absolute.options is well-formed and points at vcpkg_installed/<triplet>/include
      run_step "preflight: regenerate absolute.options" bash -lc "cd '$CHAMPSIM_DIR' && make -B absolute.options"
      run_step "preflight: absolute.options sanity" bash -lc "cd '$CHAMPSIM_DIR' && ! grep -qE '(^|[[:space:]])-isystem[[:space:]]*$' absolute.options"
      run_step "preflight: absolute.options has vcpkg_installed" bash -lc "cd '$CHAMPSIM_DIR' && grep -q 'vcpkg_installed/.*/include' absolute.options"

      # Deterministic build first, *then* parallelize once verified.
      run_step "make (single-threaded)" bash -lc "cd '$CHAMPSIM_DIR' && make"
      run_step "make (parallel)" bash -lc "cd '$CHAMPSIM_DIR' && make -j'$(nproc)'"
    fi
  else
    info "[WARN] Could not find build script/Makefile in ChampSim clone. Check upstream layout."
    FAILURES=$((FAILURES + 1))
    failed_steps+=("find ChampSim build entrypoint")
  fi

  # Verify binary exists if we didn't record failures during build steps.
  if [[ $FAILURES -eq 0 && ! -x "$CHAMPSIM_DIR/bin/champsim" ]]; then
    info "[WARN] ChampSim build finished but $CHAMPSIM_DIR/bin/champsim was not found/executable."
    FAILURES=$((FAILURES + 1))
    failed_steps+=("verify ChampSim binary")
  fi
else
  info "[WARN] ChampSim directory missing, skipping build."
  FAILURES=$((FAILURES + 1))
  failed_steps+=("ChampSim clone")
fi

info "Done. ChampSim is in third_party/champsim (ignored by git)."

if [[ $FAILURES -ne 0 ]]; then
  info "Completed with $FAILURES failing step(s):"
  for s in "${failed_steps[@]}"; do
    info "  - $s"
  done
  info "See log: $LOG_FILE"
  exit 1
fi

info "All setup steps completed successfully. Log: $LOG_FILE"
exit 0
