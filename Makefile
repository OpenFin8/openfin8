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

# Build identity stamps (sentin8-build-info README §3): the
# stamps ride the SAME shell line as the cargo command — make runs each
# recipe line in its own shell, so a standalone `export …` line would
# evaporate before cargo starts. The hash resolves via PLAIN `git
# rev-parse` (no -C path): the stamp expands AFTER the `cd` into the
# repo, so a repo-relative `git -C` would resolve from INSIDE and miss
# (stamping every binary EMPTY). Inside the build-services loop the
# `cd openfin8-$$s` has already happened when the prefix expands.
stamp_env = SENTIN8_BUILD_PROFILE=$(if $(RELEASE),release,debug) SENTIN8_GIT_SHA=$$(git rev-parse --short HEAD 2>/dev/null)

SERVICES := ca us uk br eu au

.PHONY: help build build-core build-services clean test status enroll start

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

# The prefix export rides the SAME shell line as the CLI command (see
# stamp_env — make runs each recipe line in its own shell). It must be
# explicit here: composable enroll (RS §6) merges this group's repo
# fragments into a temp aggregate in /tmp, so the CLI's own vertical-root
# fallback (target/release under the registry's parent dir) can never see
# this group's dev builds — binary resolution depends entirely on
# SENTIN8_CAPTAIN_BINARY_PREFIX. Enrollment covers the country service
# repos (each ships a service-registration.json) plus the Flutter app
# (openfin8-eopenca, vertical: bank8 — its fragment lists it under
# "apps"); the openfin8-core KERNEL is NOT enrolled — the registry needs
# no entry for a library crate (services link it by git tag).
enroll: ## Enroll every openfin8 repo (composable registration, RS §6)
	@export SENTIN8_CAPTAIN_BINARY_PREFIX="$(PREFIX)"; \
	cd ../sentin8/sentin8-cli && $(call stamp_env,sentin8-cli) $(CARGO) run --bin sentin8-cli -- vertical enroll \
		$(patsubst %,../../openfin8/openfin8-%,$(SERVICES)) \
		../../openfin8/openfin8-eopenca

# ── Fleet run (RS §4.5.2 — the three-level rule) ──────────
# This group's fleet scope: `make start` boots ONLY the platform base +
# THIS vertical — the SENTIN8_SERVICES boot pin when captain is down,
# the idempotent `captain start <types>` API form when it is up. The
# platform base is the minimal plane a vertical's services call at boot
# (acme cert mints, auth identity, proxy ingress, bus events, sys
# registration, bff tokens, web apps); everything else fails open
# (RS §5.1). The catalog stays the FULL union — other groups join the
# running fleet via their own group start; `make stop` here stops only
# this group's instances (the captain and the platform stay up).
SERVICE_TYPES := $(patsubst %,openfin8:%,$(SERVICES))
PLATFORM_BASE := sentin8:acme,sentin8:auth,sentin8:proxy,sentin8:bus,sentin8:sys,sentin8:bff,sentin8:web
GROUP_SCOPE := $(PLATFORM_BASE),$(SERVICE_TYPES)

# The SERVING set rides the boot pin; the designed-only skeletons (br/au)
# stay OUT of the RUNNING fleet — their shells carry no data plane yet
# (shell::serve panics before the listener). Build + enroll sweep them;
# the fleet does not.
FLEET_TYPES := openfin8:ca,openfin8:us,openfin8:uk,openfin8:eu
FLEET_SCOPE := $(PLATFORM_BASE),$(FLEET_TYPES)

# Tree anchors (RS §4.5.1 discipline): the sibling sentin8-cli, the root
# .env, ONE absolute tree run dir, and the binary-prefix chain covering
# this group's + the platform's built target dirs. Entries are ABSOLUTE —
# `vertical enroll` runs the CLI from ../sentin8/sentin8-cli, where a
# relative `openfin8-*/target/debug` entry would resolve against the CLI's
# own cwd and miss.
TREE_ROOT := $(abspath ..)
PLATFORM := $(TREE_ROOT)/sentin8
CLI_DIR := $(PLATFORM)/sentin8-cli
ROOT_ENV := $(TREE_ROOT)/.env
BINARY_DIR = $(if $(RELEASE),release,debug)
CLI_BIN := $(firstword $(wildcard $(CLI_DIR)/target/$(BINARY_DIR)/sentin8-cli))
CLI_RUN = $(if $(CLI_BIN),$(CLI_BIN),cargo run --quiet --manifest-path $(CLI_DIR)/Cargo.toml --bin sentin8-cli --)
SPACE := $(empty) $(empty)
PREFIX_DIRS := $(wildcard $(PLATFORM)/sentin8-*/target/$(BINARY_DIR)) $(abspath $(wildcard */target/$(BINARY_DIR)))
PREFIX := $(subst $(SPACE),:,$(strip $(PREFIX_DIRS:%=%)))

define group_rundir
export SENTIN8_RUN_DIR="$(TREE_ROOT)/.run"; \
export SENTIN8_LOG_DIR="$(TREE_ROOT)/.run/logs"; \
export SENTIN8_CAPTAIN_SOCK="$(TREE_ROOT)/.run/captain.sock"
endef

start: ## Start THIS group: platform base + openfin8 (STARTSCOPE-1; captain boots scoped or joins live)
	@test -f $(ROOT_ENV) || { echo "ERROR: no $(ROOT_ENV) — copy .env.example" >&2; exit 1; }
	@export SENTIN8_CAPTAIN_BINARY_PREFIX="$(PREFIX)"; \
	export SENTIN8_PG_POOL_MAX=$${SENTIN8_PG_POOL_MAX:-8}; \
	set -a; . $(ROOT_ENV); set +a; \
	$(group_rundir); \
	if [ -z "$$(docker compose -f $(PLATFORM)/docker-compose.yml ps --status=running -q 2>/dev/null)" ]; then \
		echo "→ dev infra down — starting PG 18 + Valkey (RS §2.2.1)"; \
		docker compose -f $(PLATFORM)/docker-compose.yml up -d >/dev/null || exit 1; \
		for i in $$(seq 1 30); do \
			n=$$(docker compose -f $(PLATFORM)/docker-compose.yml ps --status=running -q 2>/dev/null | wc -l); \
			[ "$$n" -ge 2 ] && break; sleep 1; \
		done; \
	fi; \
	if $(CLI_RUN) captain services --no-infra >/dev/null 2>&1; then \
		echo "→ captain up — starting openfin8 via API (idempotent): $(FLEET_TYPES)"; \
		$(CLI_RUN) captain start "$(FLEET_TYPES)"; \
	else \
		echo "→ captain down — scoped boot (platform base + openfin8:ca/us/uk/eu, STARTSCOPE-1)"; \
		export SENTIN8_SERVICES="$(FLEET_SCOPE)"; \
		$(CLI_RUN) captain start; \
	fi