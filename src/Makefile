# Auto-generated build rules for workload binaries
# Usage:
#   make            # build default binaries (no DEFAULT_N override)
#   make N=100000   # build binaries with DEFAULT_N=100000, outputs *_100000 and *_100000_trace

ROOT_DIR := $(abspath ..)
BIN_DIR  := $(ROOT_DIR)/bin

PROGS := array_add list_add array_add_stack list_add_stack

CC      ?= cc
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -pedantic
DEFAULT_N_FLAG := $(if $(N),-DDEFAULT_N=$(N),)
N_SUFFIX := $(if $(N),_$(N),)

BINS       := $(addprefix $(BIN_DIR)/,$(addsuffix $(N_SUFFIX),$(PROGS)))
TRACE_BINS := $(addprefix $(BIN_DIR)/,$(addsuffix $(N_SUFFIX)_trace,$(PROGS)))

.PHONY: all clean
all: $(BINS) $(TRACE_BINS)

$(BIN_DIR):
	@mkdir -p $@

# Template to generate build rules for each workload
define BUILD_WORKLOAD
$(BIN_DIR)/$(1)$(N_SUFFIX): $(1).c | $(BIN_DIR)
	$(CC) $(CFLAGS) $(DEFAULT_N_FLAG) -o $$@ $$<

$(BIN_DIR)/$(1)$(N_SUFFIX)_trace: $(1).c | $(BIN_DIR)
	$(CC) $(CFLAGS) $(DEFAULT_N_FLAG) -DTRACING -o $$@ $$<
endef

$(foreach p,$(PROGS),$(eval $(call BUILD_WORKLOAD,$(p))))

clean:
	rm -f \
	  $(BIN_DIR)/array_add $(BIN_DIR)/list_add $(BIN_DIR)/array_add_stack $(BIN_DIR)/list_add_stack \
	  $(BIN_DIR)/array_add_* $(BIN_DIR)/list_add_* $(BIN_DIR)/array_add_stack_* $(BIN_DIR)/list_add_stack_*
