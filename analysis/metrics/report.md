# Workload Metrics

### Heap

| workload | IPC | L1D load hit rate | L1D load miss rate | L1D load accesses | LLC load hit rate | LLC load miss rate | L1D load MSHR merges | L1D load MSHR rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| array_add | 3.152 | 54.98% | 45.02% | 45551 | 99.74% | 0.26% | 17656 | 38.7609% |
| list_add | 1.430 | 91.47% | 8.53% | 5722 | 0.00% | 100.00% | 204 | 3.5652% |

**IPC speedup (array / list):** 2.204


### Heap wall-clock

| workload | runtime (ms) |
|---|---:|
| array_add | 0.047 |
| list_add | 0.129 |

**Wall-clock speedup (array / list):** 2.757


### Stack

_No data found._

