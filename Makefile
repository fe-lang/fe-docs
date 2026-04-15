# Fe Docs — Build & deploy versioned stdlib documentation
#
# Prerequisites: fe binary with --stdlib-path, gh CLI, gzip, python3
#
# Usage:
#   make build-all FE_SRC=../fe FE=path/to/fe   # Build all tags
#   make build-all FE_SRC=../fe FE=... FORCE=1   # Rebuild everything
#   make build TAG=v26.0.0 FE_SRC=../fe FE=...   # Build one tag
#   make deploy VERSION=26.0.0 OUTDIR=/tmp/out   # Deploy pre-built docs
#   make list                                     # Show tag status

FE       ?= fe
FE_REPO  ?= argotorg/fe
FE_SRC   ?= $(error FE_SRC required — path to local clone of $(FE_REPO))
BUILD    := _build

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

.PHONY: build build-all deploy list clean

build:
ifndef TAG
	$(error TAG required. Usage: make build TAG=v26.0.0 FE_SRC=../fe FE=path/to/fe)
endif
	@$(MAKE) --no-print-directory _build-tag T=$(TAG)

_build-tag:
	@tag="$(T)"; \
	version="$${tag#v}"; \
	if [ -f "$${version}/docs.json.gz" ] && [ -z "$(FORCE)" ]; then \
		echo "SKIP $$tag"; \
		exit 0; \
	fi; \
	echo "BUILD $$tag ..."; \
	rm -rf "$(BUILD)"; mkdir -p "$(BUILD)/out"; \
	git -C "$(FE_SRC)" archive "$$tag" -- ingots/ 2>/dev/null \
		| tar -xC "$(BUILD)" \
	|| { echo "  ERROR: failed to get ingots/ for $$tag" >&2; exit 1; }; \
	[ -d "$(BUILD)/ingots/core" ] || { echo "  ERROR: $$tag has no ingots/core" >&2; exit 1; }; \
	echo "" > "$(BUILD)/empty.fe"; \
	$(FE) doc --builtins --stdlib-path "$(BUILD)/ingots" "$(BUILD)/empty.fe" -o "$(BUILD)/out" json; \
	jq '.index.items |= [.[] | select(.path != "empty")] | .index.modules |= [.[] | select(.path != "empty")]' \
		"$(BUILD)/out/docs.json" > "$(BUILD)/out/docs.json.tmp" && mv "$(BUILD)/out/docs.json.tmp" "$(BUILD)/out/docs.json"; \
	$(FE) doc -o "$(BUILD)/out" bundle --with-css; \
	$(MAKE) --no-print-directory deploy VERSION="$$version" OUTDIR="$(BUILD)/out"; \
	rm -rf "$(BUILD)"; \
	echo "  DONE $$tag"

deploy:
ifndef VERSION
	$(error VERSION required)
endif
ifndef OUTDIR
	$(error OUTDIR required — directory containing docs.json, fe-web.js, etc.)
endif
	@echo "Deploying Fe $(VERSION) docs..."
	@for f in fe-web.js fe-highlight.css styles.css; do \
		[ -f "$(OUTDIR)/$$f" ] && cp "$(OUTDIR)/$$f" "./$$f" && echo "  Updated $$f" || true; \
	done
	@mkdir -p "$(VERSION)"
	@gzip -c "$(OUTDIR)/docs.json" > "$(VERSION)/docs.json.gz"
	@sed 's|{{VERSION}}|$(VERSION)|g' _template/index.html > "$(VERSION)/index.html"
	@echo "  Created $(VERSION)/ ($$(du -h "$(VERSION)/docs.json.gz" | cut -f1))"
	@[ -f versions.json ] || echo '{"latest":"","versions":[]}' > versions.json
	@jq --arg v "$(VERSION)" \
		'if (.versions | index($$v)) then . else .versions += [$$v] end | .latest = ([.versions[] | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$$"))] | first // .versions[0])' \
		versions.json > versions.json.tmp && mv versions.json.tmp versions.json
	@echo "  versions.json: latest=$$(jq -r '.latest' versions.json), $$(jq '.versions | length' versions.json) versions"

build-all:
	@echo "Fetching release tags..."; \
	tags=$$(gh release list --repo $(FE_REPO) --limit 100 --json tagName --jq '.[].tagName | select(startswith("v"))'); \
	failed=0; \
	for tag in $$tags; do \
		$(MAKE) --no-print-directory _build-tag T=$$tag FORCE="$(FORCE)" || failed=$$((failed + 1)); \
	done; \
	echo ""; \
	if [ $$failed -gt 0 ]; then \
		echo "WARNING: $$failed version(s) failed."; \
	else \
		echo "All versions built."; \
	fi

list:
	@tags=$$(gh release list --repo $(FE_REPO) --limit 100 --json tagName --jq '.[].tagName | select(startswith("v"))'); \
	for tag in $$tags; do \
		version="$${tag#v}"; \
		if [ -f "$${version}/docs.json.gz" ]; then \
			echo "  $$tag  (built)"; \
		else \
			echo "  $$tag  (needs build)"; \
		fi; \
	done

clean:
	rm -rf $(BUILD)
