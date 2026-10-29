# SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
# SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
# SPDX-FileCopyrightText: Copyright Contributors to the OpenFin8
# SPDX-License-Identifier: Apache-2.0

# Makefile — openfin8/ vertical group (RS §4.4)
#
# Group build in DAG order: the openfin8-core kernel first, then the
# country service repos. NO docker-compose here — the platform group
# (../sentin8/) owns the dev infra (PostgreSQL 18 + Valkey, §2.2.1);
# this vertical's services consume it over localhost. Each child repo
# is independent; its own `cargo build` is self-sufficient — this file
# is convenience.

SHELL := /bin/bash
CARGO ?= cargo

# Build identity stamps (BUILDID-1, sentin8-build-info README §3): the
# stamps ride the SAME shell line as the cargo command — make runs each
# recipe line in its own shell, so a standalone `export …` line would
# evaporate before cargo starts. The hash resolves via PLAIN `git
# rev-parse` (no -C path): the stamp expands AFTER the `cd` into the
# repo, so a repo-relative `git -C` would resolve from INSIDE and miss
# (stamping every binary EMPTY). Inside the build-services loop the
# `cd openfin8-$$s` has already happened when the prefix expands.
stamp_env = SENTIN8_BUILD_PROFILE=$(if $(RELEASE),release,debug) SENTIN8_GIT_SHA=$$(git rev-parse --short HEAD 2>/dev/null)

SERVICES := core ca us uk br eu au

.PHONY: help build build-core build-services clean test status

help: ## Show this help
	@echo "openfin8/ vertical group"
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

build: build-core build-services ## Build the group in DAG order

build-core: ## Build the openfin8-core kernel crate (services depend on this)
	@cd openfin8-core && $(call stamp_env,openfin8-core) $(CARGO) build

build-services: build-core ## Build every openfin8 country service repo
	@for s in ca us uk br eu au; do \
		echo "=== openfin8-$$s ==="; \
		(cd openfin8-$$s && $(call stamp_env,openfin8-$$s) $(CARGO) build) || exit 1; \
	done

test: ## Run the core kernel tests + per-service suites
	@cd openfin8-core && $(call stamp_env,openfin8-core) $(CARGO) test
	@for s in ca us uk br eu au; do (cd openfin8-$$s && $(call stamp_env,openfin8-$$s) $(CARGO) test) || true; done

# clean — every child repo's own clean (cargo target/ + their local
# .run .run/logs .tmp; the e2e suite removes node_modules/reports).
# Tree-level .run/.tmp are tree-root-owned; this group's clean leaves
# them alone (the ROOT `make clean` owns them).
clean: ## Clean every child repo (target/, build artifacts, local .run/.tmp)
	@for d in $$(ls -d openfin8-*/ 2>/dev/null); do \
		[ -f "$$d/Makefile" ] || continue; \
		echo "==> clean: $$d"; \
		$(MAKE) --no-print-directory -C "$$d" clean || exit 1; \
	done

status: ## Per-repo HEADs
	@for d in */; do \
		[ -d "$$d/.git" ] || continue; \
		printf "%-22s %s\n" "$$d" "$$(git -C $$d log --oneline -1 2>/dev/null | head -c 60)"; \
	done