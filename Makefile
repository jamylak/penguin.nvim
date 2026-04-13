NVIM ?= nvim
CC ?= cc
CFLAGS ?= -O2
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
LIB_EXT := dylib
SHARED_FLAGS := -dynamiclib -undefined dynamic_lookup
else
LIB_EXT := so
SHARED_FLAGS := -shared -fPIC
endif

NATIVE_LIB := $(CURDIR)/build/penguin_filter.$(LIB_EXT)

.PHONY: native run run-lua bench check check-lua clean

native: $(NATIVE_LIB)

$(NATIVE_LIB): $(CURDIR)/src/penguin_filter.c
	mkdir -p $(CURDIR)/build
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -o $(NATIVE_LIB) $(CURDIR)/src/penguin_filter.c

run: native
	$(NVIM) -u $(CURDIR)/scripts/minimal_native_init.lua

run-lua:
	$(NVIM) -u $(CURDIR)/scripts/minimal_init.lua

bench: native
	$(NVIM) --headless -u NONE -i NONE -l $(CURDIR)/scripts/headless_bench.lua

check: native
	$(NVIM) --headless -u NONE -i NONE -l $(CURDIR)/scripts/headless_native_check.lua

check-lua:
	$(NVIM) --headless -u NONE -i NONE -l $(CURDIR)/scripts/headless_check.lua

clean:
	rm -rf $(CURDIR)/build
