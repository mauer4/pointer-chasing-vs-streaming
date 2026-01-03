#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#ifndef DEFAULT_N
#define DEFAULT_N 4000000
#endif

// ROI Markers
__attribute__((noinline)) void champsim_roi_begin() {
    __asm__ volatile(""); // Prevent optimization
}

__attribute__((noinline)) void champsim_roi_end() {
    __asm__ volatile("");
}

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
    if (n > 200000000) { // basic sanity guard
        fprintf(stderr, "N too large\n");
        exit(2);
    }
    return (int)n;
}

int main(int argc, char** argv) {
    int n = parse_n(argc, argv);

    int32_t* a = (int32_t*)malloc((size_t)n * sizeof(int32_t));
    if (!a) {
        perror("malloc");
        return 1;
    }

    // Deterministic initialization
    for (int i = 0; i < n; i++) {
        a[i] = (int32_t)(i % 1024);
    }

    volatile int64_t sum = 0;

#ifndef TRACING
    uint64_t t0 = now_ns();
#endif

    champsim_roi_begin();
    // Streaming access
    for (int i = 0; i < n; i++) {
        sum += a[i];
    }
    champsim_roi_end();

#ifndef TRACING
    uint64_t t1 = now_ns();
    printf("workload=array_add n=%d sum=%lld time_ns=%llu\n", n, (long long)sum, (unsigned long long)(t1 - t0));
#endif

    free(a);
    return 0;
}
