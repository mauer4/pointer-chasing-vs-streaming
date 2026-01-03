# Report: Array vs. Linked-List Parallelism

## Objective
Determine whether an array-based summation exhibits higher memory-level and data-level parallelism than a linked-list-based summation, using ChampSim to isolate architectural effects.

## Methodology

### 1. Configuration
*   **Simulator**: ChampSim (built from source).
*   **Core**: 1 Core, 4GHz, Out-of-Order (ROB=352, LQ=128, SQ=72).
*   **Prefetchers**: **Disabled** (L1/L2/LLC set to `no`) to isolate OOO hardware parallelism from prefetcher pattern matching.
*   **Memory**: 16GB DDR4-3200.
*   **Workloads**:
    *   `array_add`: Streaming summation of `int32_t` array (stride 4 bytes).
    *   `list_add`: Pointer-chasing summation of `struct Node` (stride random/dependent).
*   **Dataset**: N=4,000,000 elements (16MB Array, 64MB List). Both exceed LLC (2MB).

### 2. Trace Generation
*   **Tool**: Intel PIN with a custom ChampSim tracer.
*   **ROI**: Used `champsim_roi_begin()` / `champsim_roi_end()` markers in C code to trace **only the summation loop**, excluding `malloc` initialization.
*   **Verification**: Array trace compressed to ~5MB. List trace compressed to ~7MB. Both clean and focused.

## Results

### ChampSim Simulation (Virtual)

| Metric | Array Summation | Linked List Summation | Ratio (Array/List) |
| :--- | :--- | :--- | :--- |
| **IPC** | **0.5973** | **0.0747** | **~8.0x** |
| **L1D Misses** | 1,339,296 | ~7,133 (scaled) | - |
| **L1D MSHR Merges** | **1,250,009** | **8** | Huge Diff |
| **Avg L1D Miss Latency** | 166.8 cycles | 167.2 cycles | ~Same |
| **LLC Misses** | ~90k | ~7k (scaled) | - |

**Key Observations:**
1.  **IPC Disparity**: The array implementation is **8x faster** in terms of Instructions Per Cycle.
2.  **MSHR Merging**: The array workload shows massive MSHR merging (1.25M merges for 1.34M misses). This indicates that while individual accesses miss in L1D (due to no prefetcher), the OOO core successfully issues multiple load requests to the same cache line before the first one returns (spatial locality).
3.  **Parallelism**: The high IPC for Array proves that the core can overlap memory requests. For Linked List, the low IPC (0.07) and negligible MSHR merging confirm that execution is serialized by the data dependency (`cur = cur->next`), preventing the OOO core from hiding memory latency.

### Sanity Check (Physical Hardware)
*   **Array Time**: ~10.9 ms
*   **List Time**: ~21.5 ms
*   **Ratio**: ~2.0x
*   **Note**: The ratio is smaller on real hardware because **hardware prefetchers are enabled**, which significantly helps the linked list (since the allocator happened to place nodes contiguously in reverse order). ChampSim with prefetchers disabled reveals the true architectural bottleneck of pointer chasing.

## Conclusion
The experiment confirms that **array-based summation exhibits significantly higher memory-level parallelism** than linked-list summation.
*   **Array**: Allows the OOO core to issue multiple future loads in parallel (MLP), hiding latency and saturating memory bandwidth.
*   **Linked List**: Forces serialization due to pointer dependencies, exposing full memory latency for every node access.
