# Fe API Documentation Site

Versioned API docs for the Fe standard library, served via GitHub Pages at [docs.fe-lang.dev](https://docs.fe-lang.dev).

## How it works

Each release tag gets its own directory containing a gzipped `docs.json` and an `index.html` generated from `_template/index.html`. Shared assets (`fe-web.js`, `styles.css`, `fe-highlight.css`) live at the repo root and are referenced by all versions.

`versions.json` tracks all deployed versions and which is latest. The version picker in the doc viewer reads this file.

## Building docs locally

You need:
- A local `fe` binary with `--stdlib-path` support
- A local clone of the [fe compiler repo](https://github.com/argotorg/fe)
- `gh` CLI, `jq`, `gzip`

```bash
# Build docs for all release tags
make build-all FE_SRC=../fe FE=../fe/target/release/fe

# Build a single version
make build TAG=v26.0.0 FE_SRC=../fe FE=../fe/target/release/fe

# Force rebuild (ignores existing docs)
make build TAG=v26.0.0 FE_SRC=../fe FE=../fe/target/release/fe FORCE=1

# See what needs building
make list
```

The `FE_SRC` path is used to `git archive` the stdlib sources for each tag. The `FE` binary generates docs using `--stdlib-path` to load that tag's stdlib instead of the embedded one. This lets a single binary produce docs for any version.

## CI

New releases trigger the `docs` job in the fe repo's CI. It downloads the release binary, generates docs, and pushes here via `make deploy`.

## Deploy target

`make deploy VERSION=26.0.0 OUTDIR=/tmp/docs-out` copies build artifacts into the site structure. Called by both `make build` and CI.
