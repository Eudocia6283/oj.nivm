NVIM ?= nvim

.PHONY: test test-p0 test-integration

test: test-p0 test-integration

test-p0:
	$(NVIM) --headless -u NONE -i NONE '+set rtp^=.' -l tests/p0.lua

test-integration:
	$(NVIM) --headless -u NONE -i NONE '+set rtp^=.' -l tests/integration.lua
