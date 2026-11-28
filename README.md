# ladybird-build

Build environment for the [Ladybird browser](https://github.com/LadybirdBrowser/ladybird).

This repository contains a **VS Code-compatible dev container recipe** with all
tools required to build Ladybird (see
[BuildInstructionsLadybird.md](https://github.com/LadybirdBrowser/ladybird/blob/master/Documentation/BuildInstructionsLadybird.md)),
plus the build scripts and CI workflows around it. The Ladybird source itself
lives in the `ladybird/` git submodule (pinned commit).

## Layout

```
.devcontainer/            the container recipe (self-contained)
  Dockerfile              noble base + cmake>=3.30 + clang>=19 + rust + tools
  devcontainer.json       VS Code auto-load config (this folder)
  scripts/
    hash-recipe.sh        deterministic hash over the recipe files
    check-fresh.sh        in-container staleness check (postCreate/postStart)
    bootstrap.sh          postCreate: submodule init + toolchain sanity
    build-ladybird.sh     configure + build Ladybird (Release), prune/clean/status
    rebuild-if-stale.sh   host-side staleness check (git hooks)
    install-cmake.sh      cmake >= 3.30 installer (apt.kitware.com, tarball fallback)
    install-compiler.sh   C++23 compiler installer (apt.llvm.org 22..19, source fallback)
  .recipe-hash            committed recipe hash (auto-maintained by pre-commit hook)
.githooks/                git hooks (core.hooksPath, see scripts/install-hooks.sh)
scripts/                  host-side helpers (build-image.sh, install-hooks.sh)
.github/workflows/        CI: build Ladybird on arm64 + publish dev image to GHCR
ladybird/                 submodule -> LadybirdBrowser/ladybird (pinned)
```

## Quickstart (VS Code)

1. Open this folder in VS Code (Dev Containers extension installed).
2. VS Code detects `.devcontainer/devcontainer.json` and offers
   **"Reopen in Container"**. After the first choice it opens automatically.
   The container is built from `.devcontainer/Dockerfile` (~10-30 min first time).
3. `postCreateCommand` fetches the `ladybird` submodule and verifies the
   toolchain; `postStartCommand` runs the freshness check on every start.
4. Build Ladybird inside the container:

   ```bash
   bash .devcontainer/scripts/build-ladybird.sh        # configure + ninja (Release)
   bash .devcontainer/scripts/build-ladybird.sh prune  # free disk between builds
   bash .devcontainer/scripts/build-ladybird.sh status
   ```

   Run the browser: `bash ladybird/Meta/ladybird.py run --no-build`

   (Headless box? The container can run the browser under Xvfb/VNC - not
   installed by default; see HANDOFF.md.)

No VS Code? Build and enter the image manually:

```bash
scripts/build-image.sh                          # podman/docker build
podman run -it --rm -v "$PWD:/workspace/ladybird-build" -w /workspace/ladybird-build \
    ladybird-build:local bash -c 'bash .devcontainer/scripts/bootstrap.sh'
```

## Rebuilding the container (rebuild triggers)

The recipe is **versioned by a content hash** so "the container is stale" is
detectable, not guessable. The hash (`scripts/hash-recipe.sh .devcontainer`)
is committed in `.devcontainer/.recipe-hash` and baked into the image at
`/opt/ladybird-build/recipe.sha256` by the Dockerfile.

| # | Trigger | What it does |
|---|---------|--------------|
| 1 | `devcontainer.json` `postCreateCommand` / `postStartCommand` | Runs `check-fresh.sh` in the container after creation and on **every** container start; warns (exit 1 with `--strict` / in CI) when the on-disk recipe hash != baked hash |
| 2 | git hooks (`.githooks/`) | `pre-commit` regenerates `.recipe-hash` on every recipe change; `post-merge`/`post-checkout` run `rebuild-if-stale.sh --quiet`, which queries the running container for its baked hash and warns on drift |
| 3 | GitHub workflow `.github/workflows/devcontainer.yml` | On any push touching `.devcontainer/**`: rebuild the image, run `check-fresh.sh --strict` against it, and push it to GHCR tagged `sha-<hash>` + `latest` |

Manual rebuild commands:

```bash
# VS Code: Command Palette -> "Dev Containers: Rebuild Container"
# CLI:     devcontainer rebuild --workspace-folder .
# or:      bash .devcontainer/scripts/rebuild-if-stale.sh --rebuild
# raw:     scripts/build-image.sh
```

## Bumping Ladybird

Or, without touching a local clone: run the **Bump Ladybird** workflow from
the Actions page — pick a branch/tag/full SHA (default `master`), it commits
the new submodule pointer to `main`, and the push auto-triggers a fresh
`build-ladybird` run. The pin only moves on request; an unwanted bump is a
normal `git revert`.

Manually (local):

```bash
git -C ladybird fetch origin master
git -C ladybird checkout master
git add ladybird && git commit -m "bump ladybird to $(git -C ladybird rev-parse --short HEAD)"
```

## CI (GitHub Actions)

Three workflows in `.github/workflows/`:

- **`build-ladybird.yml`** — builds Ladybird **directly on an arm64 runner**
  (no container: the dev image exists to isolate the *local* machine, so on a
  clean runner we just install the same toolchain and run the build). Uploads
  the `Ladybird` binary as an artifact named with the exact commit it was
  built from (`ladybird-Linux-ARM64-<sha>`). Runs on push to `main`, on PRs,
  and on manual dispatch — the dispatch form takes an optional **Ladybird
  branch/tag/commit**, so you can build a newer version *without* moving the
  pinned submodule.
- **`bump-ladybird.yml`** — **moves the pin, on demand only**: picks a
  branch/tag/full SHA from upstream, commits the new submodule pointer and
  pushes it to `main`, which auto-triggers `build-ladybird`. The version never
  moves by itself, and an unwanted bump is a normal `git revert`.
- **`devcontainer.yml`** — builds the **arm64 dev image** and pushes it to GHCR
  (`ghcr.io/<owner>/ladybird-build`, tags `latest` + `sha-<recipe-hash>`). Runs
  on pushes touching `.devcontainer/**`, weekly, and on manual dispatch.

`build-ladybird.yml` and `devcontainer.yml` target a **GitHub-hosted ARM64
(aarch64) runner** — `runs-on: ubuntu-24.04-arm` — since the local machines
are arm64. This is a standard GitHub-hosted ARM64 pool: available on all repos
and free-minute eligible (the label is `ubuntu-24.04-arm`, i.e. `-arm`,
**not** `-arm64`). `bump-ladybird.yml` is pure git plumbing and runs on any
runner. `build-ladybird.yml` caches the vcpkg binary cache + ccache between
runs; the first (cold) build is slow because Qt 6.11 is compiled from source.

Every successful **pinned** build is also published as the rolling
**`latest-arm64`** GitHub release (binary + `VERSION` + sha256, replaced in
place), which gives a stable download URL. Experimental dispatch builds
(with `ladybird_ref` set) are NOT published as releases — only as run
artifacts — so the release always means "latest build of the pinned
version".

### Updating from a laptop

```bash
scripts/update-ladybird.sh                   # installs to ~/.local/bin/Ladybird
scripts/update-ladybird.sh /opt/lb/Ladybird  # or anywhere else
```

The script downloads the latest release asset, verifies its published sha256,
installs it, and prints the Ladybird commit the binary was built from. By
hand, the stable URL is
`https://github.com/bytesyntax/ladybird-build/releases/latest/download/Ladybird-Linux-ARM64`.

## Licensing & distribution

Ladybird is **BSD-2-Clause** — permissive enough to build, keep, and even
share the binaries; the only hard rule is that the copyright notice and full
licence text ship with any binary distribution. Full texts for **both**
licences (this repo's tooling, and Ladybird for the builds we publish) live
in [LICENCE.md](LICENCE.md), which the `latest-arm64` release uploads as an
asset alongside every binary — a pointer alone is not a substitute under
BSD-2 clause 2. Third-party deps (Qt6 is LGPL/commercial dual-licensed,
etc.) ship their notices in Ladybird's `LICENSES.txt`.

Rules this project follows, so sharing builds stays clean:

- **Provenance**: every CI artifact is named with the exact Ladybird commit
  it came from (`ladybird-Linux-ARM64-<sha>`), and `main` pins a submodule
  commit — any binary is always reproducible from public source, which is
  also what the license expects of a distribution.
- **Unofficial**: the artifacts are personal/unofficial builds, not an
  official Ladybird release — the name and logo stay with the Ladybird
  project.
- **Publishing further** (release, package repo, ...): allowed by the
  license, but keep the source pointer (`LadybirdBrowser/ladybird` @ `<sha>`)
  wherever the binary goes — the rolling `latest-arm64` release does exactly
  this in its notes and `VERSION` asset.

## Resources

The build is heavy. This repository was set up on a box with 8 cores, 7G RAM
(+8G swap) and ~16G free disk; the devcontainer.json therefore exports memory
guards by default: `LB_JOBS=3`, `LAGOM_LINK_POOL_SIZE=2`,
`VCPKG_MAX_CONCURRENCY=2`. The vcpkg binary cache + ccache live in a persistent
named volume (`ladybird-build-cache` -> `/var/lib/ladybird-cache`) so container
rebuilds stay cheap. If the machine cannot keep up, the CI build workflow is
the reliable fallback. See HANDOFF.md for the full resource analysis.
