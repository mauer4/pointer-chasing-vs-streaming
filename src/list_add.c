#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#ifndef DEFAULT_N
#define DEFAULT_N 100000
#endif

typedef struct Node {
    int32_t value;
    struct Node* next;
} Node;

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

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

    // Allocate nodes. We intentionally keep pointer-chasing behavior.
    // For determinism, values follow a simple pattern.
    Node* head = NULL;
    for (int i = n - 1; i >= 0; i--) {
        Node* node = (Node*)malloc(sizeof(Node));
        if (!node) {
            perror("malloc");
            return 1;
        }
        node->value = (int32_t)(i % 1024);
        node->next = head;
        head = node;
    }

    volatile int64_t sum = 0;
    uint64_t t0 = now_ns();

    Node* cur = head;
    while (cur) {
        sum += cur->value;
        cur = cur->next;
    }

    uint64_t t1 = now_ns();

    printf("workload=list_add n=%d sum=%lld time_ns=%llu\n", n, (long long)sum, (unsigned long long)(t1 - t0));

    // Free
    cur = head;
    while (cur) {
        Node* next = cur->next;
        free(cur);
        cur = next;
    }

    return 0;
}
