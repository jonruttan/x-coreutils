# Install copies this bundle to <share>/langs/coreutils, where `x -l` looks: a
# lang is installed when its files are there. No registry, no database.

X ?= x

# The version is derived from git describe, never committed: lang.xon declares
# what this lang requires; the installed artifact carries what it is.
LANG_VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
SHARE := $(if $(PREFIX),$(PREFIX)/share/x,$(shell $(X) --share-dir))
DEST  := $(SHARE)/langs/coreutils

# What a consumer needs to RUN the lang: the declaration, the entry, the
# modules.  Not the suite, not the tooling, not CI.
PAYLOAD := lang.xon run.x cu

.PHONY: install
install: ## Install into <share>/langs/coreutils
	@test -n "$(SHARE)" || { echo "x-coreutils: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-coreutils: no x tree at $(SHARE)" >&2; exit 1; }
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -R $(PAYLOAD) "$(DEST)/"
	printf '%s\n' '$(LANG_VERSION)' > "$(DEST)/version"
	@echo "x-coreutils: installed to $(DEST)"
	@echo "x-coreutils: try  x -l coreutils"

.PHONY: uninstall
uninstall: ## Remove it again
	rm -rf "$(DEST)"
	@echo "x-coreutils: removed $(DEST)"

.PHONY: test
test: ## Run the spec suite (every failure is loud)
	X="$(X)" sh tests/spec-runner.sh

.PHONY: lint
lint: ## Lint the bundle's own sources -- advisory rules included, and gated
	X="$(X)" sh tests/lint.sh

.PHONY: check
check: lint ## Lint, then run the suite against tests/contract/known-failures.txt -- what CI gates on
	X="$(X)" sh tests/spec-gate.sh

.PHONY: bundle
bundle: ## Roll a release tarball and print its pin
	sh tools/bundle.sh

.PHONY: help
help: ## Show targets
	@make 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[32m%-12s\033[0m %s\n", $$1, $$2}' $(COREUTILSFILE_LIST)

.PHONY: options
options: install ## Regenerate docs/options.md, the option-parity matrix against busybox
	$(X) -l coreutils -f tools/options-matrix.x > docs/options.md
	@tail -1 docs/options.md
