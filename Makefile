# Fe Docs — Build & deploy versioned stdlib documentation
#
# Prerequisites:
#   - fe binary with --stdlib-path support
#   - gh CLI (lists release tags)
#   - python3 (reads docs.json metadata)
#   - local clone of fe repo (FE_SRC, for checking out ingots per tag)
#
# Usage:
#   make build-all                  # Build docs for all eligible tags
#   make build-all FORCE=1          # Rebuild everything, ignore cache
#   make build TAG=v26.0.0          # Build docs for a specific tag
#   make build TAG=v26.0.0 FORCE=1  # Force rebuild a specific tag
#   make list                       # Show which tags would be built
#   make clean                      # Remove build cache

FE       ?= fe
FE_REPO  ?= argotorg/fe
FE_SRC   ?= $(error FE_SRC is required — path to a local clone of $(FE_REPO))
CACHE    := .build-cache

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# ── Single tag build ──────────────────────────────────────────────

.PHONY: build
build:
ifndef TAG
	$(error TAG is required. Usage: make build TAG=v26.0.0)
endif
	@$(MAKE) --no-print-directory _build-tag T=$(TAG)

# Internal target that builds one tag. Called by build and build-all.
.PHONY: _build-tag
_build-tag:
	@tag="$(T)"; \
	version="$${tag#v}"; \
	cache_key="$(CACHE)/$${version}.schema"; \
	\
	if [ -f "$$cache_key" ] && [ -z "$(FORCE)" ]; then \
		cached=$$(cat "$$cache_key"); \
		if [ -f "$${version}/docs.json" ]; then \
			current=$$(python3 -c "import json; print(json.load(open('$${version}/docs.json')).get('schema_version',''))" 2>/dev/null || echo ""); \
			if [ "$$cached" = "$$current" ] && [ -n "$$current" ]; then \
				echo "SKIP $$tag (schema v$$cached already built)"; \
				exit 0; \
			fi; \
		fi; \
	fi; \
	\
	echo "BUILD $$tag ..."; \
	tmpdir=$$(mktemp -d); \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	\
	git -C "$(FE_SRC)" archive "$$tag" -- ingots/ 2>/dev/null \
		| tar -xC "$$tmpdir" \
	|| { echo "  ERROR: git archive failed for $$tag — does the tag exist in $(FE_SRC)?" >&2; exit 1; }; \
	\
	if [ ! -d "$$tmpdir/ingots/core" ]; then \
		echo "  ERROR: $$tag has no ingots/core" >&2; \
		exit 1; \
	fi; \
	\
	outdir="$$tmpdir/out"; \
	mkdir -p "$$outdir"; \
	echo "" > "$$tmpdir/empty.fe"; \
	$(FE) doc --builtins --stdlib-path "$$tmpdir/ingots" "$$tmpdir/empty.fe" -o "$$outdir" json; \
	$(FE) doc -o "$$outdir" bundle --with-css; \
	\
	./deploy.sh "$$outdir/docs.json" "$$outdir"; \
	\
	new_schema=$$(python3 -c "import json; print(json.load(open('$${version}/docs.json')).get('schema_version',''))" 2>/dev/null || echo "?"); \
	mkdir -p "$(CACHE)"; \
	echo "$$new_schema" > "$$cache_key"; \
	echo "  DONE $$tag (schema v$$new_schema)"

# ── Build all eligible tags ───────────────────────────────────────

.PHONY: build-all
build-all:
	@echo "Discovering release tags from $(FE_REPO)..."
	@tags=$$(gh release list --repo $(FE_REPO) --limit 100 --json tagName \
		--jq '[.[].tagName | select(startswith("v26"))] | sort_by(split(".") | map(split("-") | map(tonumber? // .))) | .[]'); \
	count=$$(echo "$$tags" | wc -l | tr -d ' '); \
	echo "Found $$count eligible tags"; \
	echo ""; \
	for tag in $$tags; do \
		$(MAKE) --no-print-directory _build-tag T=$$tag FORCE="$(FORCE)" || true; \
	done; \
	echo ""; \
	echo "Done. Review changes, then commit and push."

# ── List what would be built ──────────────────────────────────────

.PHONY: list
list:
	@tags=$$(gh release list --repo $(FE_REPO) --limit 100 --json tagName \
		--jq '[.[].tagName | select(startswith("v26"))] | sort_by(split(".") | map(split("-") | map(tonumber? // .))) | .[]'); \
	for tag in $$tags; do \
		version="$${tag#v}"; \
		cache_key="$(CACHE)/$${version}.schema"; \
		if [ -f "$$cache_key" ] && [ -f "$${version}/docs.json" ]; then \
			schema=$$(cat "$$cache_key"); \
			echo "  $$tag  (cached, schema v$$schema)"; \
		else \
			echo "  $$tag  (needs build)"; \
		fi; \
	done

# ── Clean build cache ────────────────────────────────────────────

.PHONY: clean
clean:
	rm -rf $(CACHE)
	@echo "Build cache cleared. Next build-all will rebuild everything."
