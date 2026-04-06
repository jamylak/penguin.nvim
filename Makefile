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

.PHONY: native run check clean

native: $(NATIVE_LIB)

$(NATIVE_LIB): $(CURDIR)/src/penguin_filter.c
	mkdir -p $(CURDIR)/build
	$(CC) $(CFLAGS) $(SHARED_FLAGS) -o $(NATIVE_LIB) $(CURDIR)/src/penguin_filter.c

run:
	$(NVIM) -u $(CURDIR)/scripts/minimal_init.lua

check:
	$(NVIM) --headless -u NONE -i NONE -l $(CURDIR)/scripts/headless_check.lua

clean:
	rm -rf $(CURDIR)/build
