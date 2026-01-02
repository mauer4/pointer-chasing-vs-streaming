#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#ifndef DEFAULT_N
#define DEFAULT_N 4000000
#endif

typedef struct Node {
    int32_t value;
    struct Node* next;
} Node;

// ROI Markers
__attribute__((noinline)) void champsim_roi_begin() {
    __asm__ volatile("");
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
    if (n > 50000000) { // linked list is memory-heavy; keep guard tighter
        fprintf(stderr, "N too large\n");
        exit(2);
    }
    return (int)n;
}

int main(int argc, char** argv) {
    int n = parse_n(argc, argv);

    // Allocate nodes contiguously in one block.
    Node* nodes = (Node*)malloc((size_t)n * sizeof(Node));
    if (!nodes) {
        perror("malloc");
        return 1;
    }
    for (int i = 0; i < n; i++) {
        nodes[i].value = (int32_t)(i % 1024);
        nodes[i].next = (i + 1 < n) ? &nodes[i + 1] : NULL;
    }
    Node* head = &nodes[0];

    volatile int64_t sum = 0;

#ifndef TRACING
    // Quick contiguity check (heap list): walk the list once and count adjacent nodes
    // that are exactly one sizeof(Node) apart in virtual address space.
    size_t node_size = sizeof(Node);
    size_t adjacent = 0;
    size_t links = 0;
    for (Node* p = head; p && p->next; p = p->next) {
        links++;
        uintptr_t cur = (uintptr_t)p;
        uintptr_t nxt = (uintptr_t)p->next;
        if (cur + node_size == nxt) adjacent++;
    }
    double adjacent_ratio = links ? (double)adjacent / (double)links : 0.0;

    uint64_t t0 = now_ns();
#endif

    champsim_roi_begin();
    Node* cur = head;
    while (cur) {
        sum += cur->value;
        cur = cur->next;
    }
    champsim_roi_end();

#ifndef TRACING
    uint64_t t1 = now_ns();
    printf("workload=list_add n=%d sum=%lld time_ns=%llu node_size=%zu contiguous_links=%zu/%zu (%.2f%%)\n",
           n, (long long)sum, (unsigned long long)(t1 - t0), node_size, adjacent, links,
           adjacent_ratio * 100.0);
#endif

    // Free contiguous block
    free(nodes);

    return 0;
}
