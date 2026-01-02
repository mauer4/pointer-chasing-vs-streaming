# Workload Metrics

### Heap

| workload | IPC | L1D load hit rate | L1D load miss rate | L1D load accesses |
|---|---:|---:|---:|---:|
| array_add | 3.192 | 49.59% | 50.41% | 73144 |
| list_add | 1.111 | 98.53% | 1.47% | 485256 |

**Speedup (array / list):** 2.873


### Stack

| workload | IPC | L1D load hit rate | L1D load miss rate | L1D load accesses |
|---|---:|---:|---:|---:|
| array_add_stack | 2.806 | 58.34% | 41.66% | 160816 |
| list_add_stack | 1.413 | 86.60% | 13.40% | 132502 |

**Speedup (array / list):** 1.986

