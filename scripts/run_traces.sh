#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAMPSIM_DIR="$ROOT_DIR/third_party/champsim"
BIN_DIR="$ROOT_DIR/bin"
TRACE_DIR="$ROOT_DIR/traces"
RESULTS_DIR="$ROOT_DIR/results"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/workloads.conf}"

WORKLOAD_N="${WORKLOAD_N:-100000}" # backward compat; per-workload n_* overrides
INCLUDE_STACK="${INCLUDE_STACK:-0}"
STACK_ONLY="${STACK_ONLY:-0}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--include-stack] [--stack-only]

Options:
  --include-stack   Also trace and run the stack-based workloads (array_add_stack, list_add_stack).
                    You can also set INCLUDE_STACK=1 in the environment.
  --stack-only      Run only the stack-based workloads (implies --include-stack). You can also set STACK_ONLY=1.
  -h, --help        Show this help.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --include-stack)
      INCLUDE_STACK=1
      ;;
    --stack-only)
      STACK_ONLY=1
      INCLUDE_STACK=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[run] Unknown argument: $arg"
      usage
      exit 2
      ;;
  esac
done

mkdir -p "$TRACE_DIR" "$RESULTS_DIR"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

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

trace_for_workload() {
  local w="$1" n="$2"
  echo "$TRACE_DIR/${w}/${w}_n=${n}.champsimtrace"
}

# 4) Run ChampSim
run_sim() {
  local workload_name="$1"
  local trace_in="$2"
  local warmup="$3"
  local sim="$4"

  local out_dir="$RESULTS_DIR/${workload_name}"
  mkdir -p "$out_dir"

  echo "[sim] Running $workload_name on trace $trace_in (warmup=$warmup sim=$sim)"
  "$CHAMPSIM_BIN" --warmup-instructions "$warmup" --simulation-instructions "$sim" "$trace_in" >"$out_dir/sim.txt" 2>"$out_dir/sim.err" || true
  echo "[sim] Output: $out_dir/sim.txt"
}

# Iterate workloads from config
set +e
TRACE_ERRORS=0
for w in "${WORKLOADS[@]}"; do
  eval "STACK_FLAG=\${stack_${w}:-0}"
  if [[ "$STACK_ONLY" -eq 1 && "$STACK_FLAG" -ne 1 ]]; then
    continue
  fi
  if [[ "$STACK_ONLY" -ne 1 && "$INCLUDE_STACK" -eq 0 && "$STACK_FLAG" -eq 1 ]]; then
    continue
  fi

  eval "N_W=\${n_${w}:-${WORKLOAD_N}}"
  eval "WARMUP_W=\${warmup_${w}:-${CHAMPSIM_WARMUP_INSTRUCTIONS:-500000}}"
  eval "SIM_W=\${sim_${w}:-${CHAMPSIM_SIM_INSTRUCTIONS:-40000000}}"

  trace_base="$(trace_for_workload "$w" "$N_W")"
  trace_path="${trace_base}.xz"
  if [[ ! -f "$trace_path" && -f "$trace_base" ]]; then
    trace_path="$trace_base"
  fi

  if [[ ! -f "$trace_path" ]]; then
    echo "[run] missing trace $trace_path (run scripts/gen_traces.sh)" >&2
    TRACE_ERRORS=1
    continue
  fi

  # Attempt trace generation (best-effort)
  gen_trace "$w" "$BIN_DIR/$w" "$trace_base"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    if [[ -f "${trace_base}.xz" ]]; then
      trace_path="${trace_base}.xz"
    elif [[ -f "$trace_base" ]]; then
      trace_path="$trace_base"
    fi
  else
    TRACE_ERRORS=1
    continue
  fi

  run_sim "${w}_${N_W}" "$trace_path" "$WARMUP_W" "$SIM_W"
done
set -e

if [[ $TRACE_ERRORS -ne 0 ]]; then
  echo "[run] Some traces missing or failed; see logs above."
fi

echo "[run] Done. Results are under results/ (ignored by git)."
