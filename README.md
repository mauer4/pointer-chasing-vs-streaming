# Pointer chasing vs streaming (ChampSim)

This repo sets up four tiny C workloads (heap + stack variants) and runs them through ChampSim using instruction traces.

- Workload A (heap): streaming sum over an array (`array_add`)
- Workload B (heap): pointer-chasing sum over a linked list (`list_add`)
- Workload C (stack): streaming sum over an array allocated on the stack (`array_add_stack`)
- Workload D (stack): pointer-chasing sum over a stack-allocated list (`list_add_stack`)

## What’s intentionally **not** tracked in git

- ChampSim source/build: `third_party/champsim/`
- Generated traces: `traces/`
- Simulation outputs + plots: `results/`

Those paths are ignored via `.gitignore`.

## Quick start

### 1) Setup + build ChampSim

This repo builds ChampSim from source under `third_party/champsim/`.

The important ChampSim-specific detail is that its Makefile expects vcpkg dependencies under:

- `third_party/champsim/vcpkg_installed/<triplet>/{include,lib,...}`

So we install vcpkg packages using `--x-install-root=./vcpkg_installed`.

Run:

```bash
./scripts/setup.sh
```

After a successful setup, you should have:

- ChampSim binary: `third_party/champsim/bin/champsim`
- Binary options file (sanity check): `third_party/champsim/absolute.options` (must include a non-empty `-isystem .../vcpkg_installed/.../include`)

### 2) Build workloads (trace + non-trace)

```bash
./scripts/build_workloads.sh
```

This produces both regular and trace-enabled binaries:

- `bin/array_add`, `bin/list_add`, `bin/array_add_stack`, `bin/list_add_stack`
- `bin/array_add_trace`, `bin/list_add_trace`, `bin/array_add_stack_trace`, `bin/list_add_stack_trace`

### 3) Generate traces (PIN → ChampSim trace)

```bash
# Heap only (default)
./scripts/gen_traces.sh

# Include stack variants
./scripts/gen_traces.sh --include-stack
./scripts/gen_traces.sh --stack-only        # only stack variants

# Force regenerate traces
./scripts/gen_traces.sh --regen-traces

# Sweep multiple problem sizes
./scripts/gen_traces.sh --n-list 100000,200000,400000
./scripts/gen_traces.sh --n 200000           # single override for all workloads
```

Traces are compressed by default (`.xz`) and reused on subsequent runs unless `--regen-traces` is set.

### 4) Run ChampSim on existing traces (no retracing)

```bash
./scripts/run_traces.sh                     # heap only
./scripts/run_traces.sh --include-stack     # include stack workloads
./scripts/run_traces.sh --stack-only        # only stack workloads

# Optional: generate metrics after sims
./scripts/run_traces.sh --run-metrics

# Sweep multiple problem sizes using existing traces (requires traces for those N)
./scripts/run_traces.sh --n-list 100000,200000 --run-metrics
```

To rerun only the simulations with new instruction budgets: update `config/workloads.conf` and rerun `scripts/run_traces.sh` (no PIN involved).

### 5) Run native (non-trace) binaries

```bash
./scripts/run_native.sh           # heap only
./scripts/run_native.sh --include-stack
./scripts/run_native.sh --stack-only

# Sweep multiple N values
./scripts/run_native.sh --n-list 100000,200000
```

### 6) One-shot orchestration

```bash
./scripts/run_all.sh --include-stack --run-metrics   # builds, traces, sims, native, metrics
./scripts/run_all.sh --regen-traces                  # force retracing first
./scripts/run_all.sh --n-list 100000,200000 --run-metrics --include-stack
```

### Workload config

Workloads and their settings live in `config/workloads.conf`:

- `WORKLOADS`: ordered list (e.g., `array_add list_add array_add_stack list_add_stack`)
- Problem sizes: `WORKLOAD_N` (single value or comma-separated list). Optional `WORKLOAD_N_LIST` can also supply the list.
- ChampSim budgets (global defaults): `CHAMPSIM_WARMUP_INSTRUCTIONS` and `CHAMPSIM_SIM_INSTRUCTIONS` (single values) with optional lists `CHAMPSIM_WARMUP_INSTRUCTIONS_LIST` / `CHAMPSIM_SIM_INSTRUCTIONS_LIST` aligned by index with the N list when sweeping.
- Per-workload budgets (preferred overrides): `warmup_cycles_<name>` / `sim_cycles_<name>` with optional lists `warmup_cycles_<name>_list` / `sim_cycles_<name>_list` aligned to the N sweep; fall back to the global defaults above.
- Stack flags: `stack_<name>` (1 for stack variant) control inclusion with `--include-stack`/`--stack-only`.

Budgets are taken as-is (no automatic scaling by N). Both `scripts/gen_traces.sh` and `scripts/run_traces.sh` read this file and honor `--stack-only` / `--include-stack` filtering. You can override `CONFIG_FILE` to point at a different config.

Tracing prerequisites (Intel PIN)

ChampSim simulates **from traces**. This repo uses ChampSim's bundled **Intel PIN** tracer (`third_party/champsim/tracer/pin`) to create them. Only `scripts/gen_traces.sh` needs PIN; `scripts/run_traces.sh` consumes existing traces and does **not** require PIN.

To generate traces automatically, provide a built Intel PIN distribution and set:

- `PIN_ROOT=/path/to/pin-*/` (must contain an executable `pin` at `$PIN_ROOT/pin`)

If `PIN_ROOT` is not set, `scripts/gen_traces.sh` will stop and tell you which trace files are missing under `traces/`.

By default, `scripts/gen_traces.sh` reuses an existing compressed trace (`.xz`). Use `--regen-traces` to force regeneration.

You can control run sizes with:

- `WORKLOAD_N` (default `100000`) or `WORKLOAD_N_LIST` for multiple values
- Global budgets: `CHAMPSIM_WARMUP_INSTRUCTIONS` / `_LIST`, `CHAMPSIM_SIM_INSTRUCTIONS` / `_LIST`
- Per-workload budgets: `warmup_cycles_<name>` / `sim_cycles_<name>` (and optional `_list` variants) override the globals
- `INCLUDE_STACK=1` / `--include-stack` to include the stack-based workloads
- `STACK_ONLY=1` / `--stack-only` to run only the stack-based workloads

Expected artifacts after a successful run:

- Traces: `traces/<workload>/<workload>_n=<N>.champsimtrace.xz` (plus `latest.champsimtrace` symlink)
- Trace logs: `results/pin_tool_logs/<workload>/*.out|*.err` (empty logs removed)
- ChampSim results: `results/champsim_results/<workload>_<N>/sim.txt|sim.err`
- Native outputs: `results/non-trace/<workload>_<N>/run.txt|run.err`
- Metrics reports: `analysis/metrics/report.md` (default) or `analysis/metrics/report_<N>.md` when `--n`/`--n-list` is used

3) Analyze

Open `notebooks/analysis.ipynb`.

## Tracing workflow (end-to-end)

1) Set env (loads `PIN_ROOT` if present)
```bash
source scripts/env.sh
```

2) Install Intel PIN locally (no sudo)
```bash
bash scripts/install_pin.sh
```

3) Build ChampSim tracer (PIN tool)
```bash
bash scripts/build_champsim_tracer.sh
```

4) Build workloads (trace + non-trace)
```bash
bash scripts/build_workloads.sh
```

5) Generate traces with PIN + ChampSim tracer
```bash
bash scripts/gen_traces.sh --include-stack   # add --stack-only or --regen-traces as needed
```

6) Run ChampSim on existing traces (no PIN)
```bash
bash scripts/run_traces.sh --include-stack --run-metrics
```

7) Run native binaries (wall-clock)
```bash
bash scripts/run_native.sh --include-stack
```

Artifacts
- Traces: `traces/<bench>/<bench>_n=<N>.champsimtrace[.xz]` (+ `latest.champsimtrace` symlink)
- Trace logs: `results/pin_tool_logs/<bench>/*.out|*.err` (empty logs are removed)
- Simulation outputs: `results/champsim_results/<bench>_<N>/sim.txt|sim.err`
- Native outputs: `results/non-trace/<bench>_<N>/run.txt|run.err`

### Rerun ChampSim only (new budgets, no retrace)

1. Edit `config/workloads.conf` to change global budgets (`CHAMPSIM_WARMUP_INSTRUCTIONS` / `_LIST`, `CHAMPSIM_SIM_INSTRUCTIONS` / `_LIST`), per-workload budgets (`warmup_cycles_<name>` / `_list`, `sim_cycles_<name>` / `_list`), or the N list (`WORKLOAD_N` / `WORKLOAD_N_LIST`).
2. Reuse existing traces by running:
	```bash
	./scripts/run_traces.sh --include-stack --run-metrics
	```
	(add `--stack-only` if desired). This does not rebuild workloads, rebuild ChampSim, or regenerate traces.

## Troubleshooting (common issues)

- **PIN_ROOT not set**: run `source scripts/env.sh`; if still empty, run `scripts/install_pin.sh`.
- **pintool .so not found**: run `scripts/build_champsim_tracer.sh` (requires PIN_ROOT and a Linux x86_64 host).
- **Permission/download errors**: install scripts avoid sudo; ensure network access to the Intel PIN URL and write perms under `third_party/`.
- **Missing dependencies**: ChampSim deps are handled via `scripts/setup.sh` (vcpkg). Bench builds need `gcc`/`clang`.
