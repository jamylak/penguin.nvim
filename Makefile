NVIM ?= nvim

.PHONY: run check

run:
	$(NVIM) -u $(CURDIR)/scripts/minimal_init.lua

check:
	$(NVIM) --headless -u NONE -i NONE -l $(CURDIR)/scripts/headless_check.lua
