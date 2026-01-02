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
```

Traces are compressed by default (`.xz`) and reused on subsequent runs unless `--regen-traces` is set.

### 4) Run ChampSim on existing traces (no retracing)

```bash
./scripts/run_traces.sh                     # heap only
./scripts/run_traces.sh --include-stack     # include stack workloads
./scripts/run_traces.sh --stack-only        # only stack workloads

# Optional: generate metrics after sims
./scripts/run_traces.sh --run-metrics
```

To rerun only the simulations with new instruction budgets: update `config/workloads.conf` and rerun `scripts/run_traces.sh` (no PIN involved).

### 5) Run native (non-trace) binaries

```bash
./scripts/run_native.sh           # heap only
./scripts/run_native.sh --include-stack
./scripts/run_native.sh --stack-only
```

### 6) One-shot orchestration

```bash
./scripts/run_all.sh --include-stack --run-metrics   # builds, traces, sims, native, metrics
./scripts/run_all.sh --regen-traces                  # force retracing first
```

### Workload config

Workloads and their per-benchmark settings live in `config/workloads.conf`:

- `WORKLOADS`: ordered list (e.g., `array_add list_add array_add_stack list_add_stack`)
- Global defaults: `WORKLOAD_N`, `CHAMPSIM_WARMUP_INSTRUCTIONS`, `CHAMPSIM_SIM_INSTRUCTIONS`
- Per-workload keys: `n_<name>`, `warmup_<name>`, `sim_<name>`, `stack_<name>` (1 for stack variant)

Both `scripts/gen_traces.sh` and `scripts/run_traces.sh` read this file and honor `--stack-only` / `--include-stack` filtering. You can override `CONFIG_FILE` to point at a different config.

Tracing prerequisites (Intel PIN)

ChampSim simulates **from traces**. This repo uses ChampSim's bundled **Intel PIN** tracer (`third_party/champsim/tracer/pin`) to create them. Only `scripts/gen_traces.sh` needs PIN; `scripts/run_traces.sh` consumes existing traces and does **not** require PIN.

To generate traces automatically, provide a built Intel PIN distribution and set:

- `PIN_ROOT=/path/to/pin-*/` (must contain an executable `pin` at `$PIN_ROOT/pin`)

If `PIN_ROOT` is not set, `scripts/gen_traces.sh` will stop and tell you which trace files are missing under `traces/`.

By default, `scripts/gen_traces.sh` reuses an existing compressed trace (`.xz`). Use `--regen-traces` to force regeneration.

You can control run sizes with:

- `WORKLOAD_N` (default `100000`)
- `CHAMPSIM_WARMUP_INSTRUCTIONS` (default `500000`)
- `CHAMPSIM_SIM_INSTRUCTIONS` (default `40000000`)
- `INCLUDE_STACK=1` / `--include-stack` to include the stack-based workloads
- `STACK_ONLY=1` / `--stack-only` to run only the stack-based workloads

Expected artifacts after a successful run:

- Traces: `traces/<workload>/<workload>_n=<N>.champsimtrace.xz` (plus `latest.champsimtrace` symlink)
- Results: `results/<workload>_<N>/sim.txt` and `sim.err`

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
- Trace logs: `results/traces/<bench>/*.out|*.err`
- Simulation outputs: `results/<bench>_<N>/sim.txt|sim.err`
- Native outputs: `results/non-trace/<bench>_<N>/run.txt|run.err`

### Rerun ChampSim only (new budgets, no retrace)

1. Edit `config/workloads.conf` to change `CHAMPSIM_WARMUP_INSTRUCTIONS`, `CHAMPSIM_SIM_INSTRUCTIONS`, or per-workload overrides (`warmup_<w>`, `sim_<w>`).
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
