SHELL := /bin/bash

.PHONY: all fmt lint test ci

all: fmt lint test

fmt:
	@command -v shfmt >/dev/null 2>&1 && shfmt -w -i 2 -ci -sr scripts || echo "shfmt not installed"

lint:
	@command -v shellcheck >/dev/null 2>&1 && shellcheck -x scripts/**/*.sh scripts/*/*.sh scripts/*.sh || echo "shellcheck not installed"

test:
	@command -v bats >/dev/null 2>&1 && bats -r tests || echo "bats not installed"

ci: lint test
