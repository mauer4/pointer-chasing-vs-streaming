# Pointer chasing vs streaming (ChampSim)

This repo sets up two tiny C workloads and runs them through ChampSim using instruction traces.

- Workload A: streaming sum over an array
- Workload B: pointer-chasing sum over a linked list

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

### 2) Build workloads

```bash
./scripts/build_workloads.sh
```

This produces:

- `bin/array_add`
- `bin/list_add`

### 3) Generate traces + run ChampSim

```bash
./scripts/run_traces.sh
```

### Tracing prerequisites (Intel PIN)

ChampSim can simulate **only from traces**. This repo uses ChampSim's bundled **Intel PIN** tracer (`third_party/champsim/tracer/pin`).

Do you need to install the pintool?

- **Yes, if you want this repo to generate traces from the C workloads automatically.**
- **No, if you already have compatible ChampSim traces** (you can drop them into `traces/` and skip PIN entirely).

To generate traces automatically, you must provide a built Intel PIN distribution and set:

- `PIN_ROOT=/path/to/pin-*/` (must contain an executable `pin` at `$PIN_ROOT/pin`)

If `PIN_ROOT` is not set, `scripts/run_traces.sh` will stop and tell you exactly which trace files it expects you to provide under `traces/`.

You can control run sizes with:

- `WORKLOAD_N` (default `100000`)
- `CHAMPSIM_WARMUP_INSTRUCTIONS` (default `500000`)
- `CHAMPSIM_SIM_INSTRUCTIONS` (default `2000000`)

Expected artifacts after a successful run:

- Traces: `traces/*.champsimtrace.xz`
- Results: `results/<workload>/sim.txt` and `results/<workload>/sim.err`

3) Analyze

Open `notebooks/analysis.ipynb`.

## Tracing workflow (end-to-end)

1) Set env
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

4) Build workloads (array + linked list)
```bash
bash scripts/build_workloads.sh
# (if needed) copy to build/bin for the tracing script
mkdir -p build/bin && cp -v bin/* build/bin/
```

5) Generate traces with PIN + ChampSim tracer
```bash
bash scripts/gen_traces.sh --n 100000 --compress
```

Artifacts
- Traces: `traces/<bench>/<bench>_n=<N>.champsimtrace[.xz]` (+ `latest.champsimtrace` symlink)
- Trace logs: `results/traces/<bench>/*.out|*.err`

## Troubleshooting (common issues)

- **PIN_ROOT not set**: run `source scripts/env.sh`; if still empty, run `scripts/install_pin.sh`.
- **pintool .so not found**: run `scripts/build_champsim_tracer.sh` (requires PIN_ROOT and a Linux x86_64 host).
- **Permission/download errors**: install scripts avoid sudo; ensure network access to the Intel PIN URL and write perms under `third_party/`.
- **Missing dependencies**: ChampSim deps are handled via `scripts/setup.sh` (vcpkg). Bench builds need `gcc`/`clang`.
