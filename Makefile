NVIM ?= nvim
DEPS_DIR := .deps
PLENARY_DIR := $(DEPS_DIR)/plenary.nvim
# Pinned plenary.nvim commit used by the test runner.
PLENARY_REV := 74b06c6c75e4eeb3108ec01852001636d85a932b

.PHONY: test deps clean-deps

## Run the test suite (spec/*_spec.lua) in headless Neovim.
test: deps
	$(NVIM) --headless --noplugin -u spec/minimal_init.lua \
		-c "PlenaryBustedDirectory spec { minimal_init = 'spec/minimal_init.lua', sequential = true, timeout = 60000 }"

## Fetch test dependencies (plenary.nvim, and vscode-diff via npm).
deps: $(PLENARY_DIR) node_modules/vscode-diff/package.json

$(PLENARY_DIR):
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)
	git -C $(PLENARY_DIR) checkout --quiet $(PLENARY_REV)

node_modules/vscode-diff/package.json: package.json package-lock.json
	npm ci

clean-deps:
	rm -rf $(DEPS_DIR)
