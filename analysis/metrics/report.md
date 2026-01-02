# Workload Metrics

### Heap

| workload | IPC | L1D load hit rate | L1D load miss rate | L1D load accesses | LLC load hit rate | LLC load miss rate | L1D load MSHR merges |
|---|---:|---:|---:|---:|---:|---:|---:|
| array_add | 3.227 | 54.58% | 45.42% | 73151 | 99.84% | 0.16% | 28650 |
| list_add | 1.130 | 98.50% | 1.50% | 470560 | 0.00% | 0.00% | 7030 |

**IPC speedup (array / list):** 2.856


### Heap wall-clock

| workload | runtime (ms) |
|---|---:|
| array_add | 0.053 |
| list_add | 0.117 |

**Wall-clock speedup (array / list):** 2.201


### Stack

| workload | IPC | L1D load hit rate | L1D load miss rate | L1D load accesses | LLC load hit rate | LLC load miss rate | L1D load MSHR merges |
|---|---:|---:|---:|---:|---:|---:|---:|
| array_add_stack | 2.805 | 58.56% | 41.44% | 160862 | 80.39% | 19.61% | 56273 |
| list_add_stack | 1.401 | 86.55% | 13.45% | 132363 | 87.22% | 12.78% | 1895 |

**IPC speedup (array / list):** 2.002

