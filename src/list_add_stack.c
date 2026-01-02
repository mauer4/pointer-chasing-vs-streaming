#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#ifndef DEFAULT_N
#define DEFAULT_N 100000
#endif

// Limit stack usage: 1e6 nodes ~ (16B) = ~16 MB; adjust as needed
#define MAX_N 1000000

typedef struct {
    int32_t value;
    int32_t next; // index of next node, -1 for end
} node_t;

// ROI Markers
__attribute__((noinline)) void champsim_roi_begin() { __asm__ volatile(""); }
__attribute__((noinline)) void champsim_roi_end()   { __asm__ volatile(""); }

#ifndef TRACING
static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}
#endif

static int parse_n(int argc, char** argv) {
    if (argc < 2) return DEFAULT_N;
    long n = strtol(argv[1], NULL, 10);
    if (n <= 0) return DEFAULT_N;
    if (n > MAX_N) {
        fprintf(stderr, "N too large for stack allocation (max %d)\n", MAX_N);
        exit(2);
    }
    return (int)n;
}

int main(int argc, char** argv) {
    int n = parse_n(argc, argv);

    node_t nodes[MAX_N];

    for (int i = 0; i < n; i++) {
        nodes[i].value = (int32_t)(i % 1024);
        nodes[i].next = (i + 1 < n) ? (i + 1) : -1;
    }

    volatile int64_t sum = 0;

#ifndef TRACING
    uint64_t t0 = now_ns();
#endif

    champsim_roi_begin();
    int cur = 0;
    while (cur != -1) {
        sum += nodes[cur].value;
        cur = nodes[cur].next;
    }
    champsim_roi_end();

#ifndef TRACING
    uint64_t t1 = now_ns();
    printf("workload=list_add_stack n=%d sum=%lld time_ns=%llu\n", n, (long long)sum, (unsigned long long)(t1 - t0));
#endif

    return 0;
}