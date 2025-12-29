#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAMPSIM_DIR="$ROOT_DIR/third_party/champsim"
BIN_DIR="$ROOT_DIR/bin"
TRACE_DIR="$ROOT_DIR/traces"
RESULTS_DIR="$ROOT_DIR/results"

WORKLOAD_N="${WORKLOAD_N:-100000}"

mkdir -p "$TRACE_DIR" "$RESULTS_DIR"

if [[ ! -d "$CHAMPSIM_DIR" ]]; then
  echo "[run] ChampSim not found at $CHAMPSIM_DIR"
  echo "[run] Run: scripts/setup.sh"
  exit 1
fi

# 1) Build workloads
"$ROOT_DIR/scripts/build_workloads.sh"

# 2) Locate ChampSim binary
# Build scripts typically create something like: bin/champsim
# We'll search for an executable named champsim.
CHAMPSIM_BIN=""
if [[ -x "$CHAMPSIM_DIR/bin/champsim" ]]; then
  CHAMPSIM_BIN="$CHAMPSIM_DIR/bin/champsim"
else
  CHAMPSIM_BIN="$(find "$CHAMPSIM_DIR" -maxdepth 4 -type f -name champsim -perm -u+x 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$CHAMPSIM_BIN" ]]; then
  echo "[run] Could not find ChampSim executable. Did build succeed?"
  echo "[run] Look under $CHAMPSIM_DIR"
  exit 1
fi

echo "[run] Using ChampSim: $CHAMPSIM_BIN"

# 3) Trace generation
# ChampSim ships an Intel PIN tracer under tracer/pin.
# We support three modes:
# - If a trace already exists in traces/, we reuse it.
# - If PIN_ROOT is set and points to a built PIN distribution, we build+use the tracer.
# - Otherwise, we fail with clear instructions.

gen_trace() {
  local workload_name="$1"
  local exe="$2"
  local trace_out="$3"

  local trace_out_xz="${trace_out}.xz"

  if [[ -f "$trace_out" ]]; then
    echo "[trace] Reusing existing trace: $trace_out"
    return 0
  fi

  if [[ -f "$trace_out_xz" ]]; then
    echo "[trace] Reusing existing compressed trace: $trace_out_xz"
    return 0
  fi


  if [[ -z "${PIN_ROOT:-}" ]]; then
    echo "[trace] Missing PIN_ROOT; cannot generate traces automatically."
    echo "[trace] ChampSim provides a PIN tracer at: $CHAMPSIM_DIR/tracer/pin"
    echo "[trace] Options:"
    echo "        1) Provide PIN_ROOT (path to an Intel PIN distribution) and re-run."
    echo "        2) OR place a compatible trace at: $trace_out (or $trace_out_xz)"
    return 2
  fi

  if [[ ! -x "$PIN_ROOT/pin" ]]; then
    echo "[trace] PIN_ROOT is set but '$PIN_ROOT/pin' is not executable."
    echo "[trace] PIN_ROOT should point at the root of the PIN distribution."
    return 2
  fi

  local pin_tracer_dir="$CHAMPSIM_DIR/tracer/pin"
  local tracer_so="$pin_tracer_dir/obj-intel64/champsim_tracer.so"

  echo "[trace] Building PIN tracer (if needed): $pin_tracer_dir"
  make -C "$pin_tracer_dir" >/dev/null

  if [[ ! -f "$tracer_so" ]]; then
    echo "[trace] Expected tracer .so was not produced: $tracer_so"
    return 3
  fi

  echo "[trace] Generating trace for $workload_name (n=$WORKLOAD_N): $trace_out"
  "$PIN_ROOT/pin" -t "$tracer_so" -o "$trace_out" -- "$exe" "$WORKLOAD_N"

  if [[ ! -f "$trace_out" ]]; then
    echo "[trace] Trace generation failed; output not found: $trace_out"
    return 3
  fi

  # Compress to save space; ChampSim can read .xz directly.
  xz -T0 -f "$trace_out"
  if [[ ! -f "$trace_out_xz" ]]; then
    echo "[trace] Compression failed; expected: $trace_out_xz"
    return 3
  fi
  echo "[trace] Wrote: $trace_out_xz"
}

ARRAY_TRACE="$TRACE_DIR/array_add_${WORKLOAD_N}.champsimtrace"
LIST_TRACE="$TRACE_DIR/list_add_${WORKLOAD_N}.champsimtrace"

# Attempt trace generation (best-effort)
set +e
gen_trace "array_add" "$BIN_DIR/array_add" "$ARRAY_TRACE"
ARRAY_RC=$?
gen_trace "list_add" "$BIN_DIR/list_add" "$LIST_TRACE"
LIST_RC=$?
set -e

if [[ $ARRAY_RC -ne 0 || $LIST_RC -ne 0 ]]; then
  echo "[run] Trace generation not completed for all workloads."
  echo "[run] Once you have traces in $TRACE_DIR, this script will run ChampSim and write results to $RESULTS_DIR."
  exit 4
fi

# 4) Run ChampSim
run_sim() {
  local workload_name="$1"
  local trace_in="$2"
  local out_dir="$RESULTS_DIR/$workload_name"
  mkdir -p "$out_dir"

  echo "[sim] Running $workload_name on trace $trace_in"
  # Follow ChampSim README: pass the trace file as a positional argument.
  # Use smaller instruction counts by default to keep runs snappy.
  local warmup="${CHAMPSIM_WARMUP_INSTRUCTIONS:-500000}"
  local sim="${CHAMPSIM_SIM_INSTRUCTIONS:-2000000}"
  "$CHAMPSIM_BIN" --warmup-instructions "$warmup" --simulation-instructions "$sim" "$trace_in" >"$out_dir/sim.txt" 2>"$out_dir/sim.err" || true
  echo "[sim] Output: $out_dir/sim.txt"
}

run_sim "array_add_${WORKLOAD_N}" "${ARRAY_TRACE}.xz"
run_sim "list_add_${WORKLOAD_N}" "${LIST_TRACE}.xz"

echo "[run] Done. Results are under results/ (ignored by git)."
