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

```bash
git -C ladybird fetch origin master
git -C ladybird checkout master
git add ladybird && git commit -m "bump ladybird to $(git -C ladybird rev-parse --short HEAD)"
```

## Resources

The build is heavy. This repository was set up on a box with 8 cores, 7G RAM
(+8G swap) and ~16G free disk; the devcontainer.json therefore exports memory
guards by default: `LB_JOBS=3`, `LAGOM_LINK_POOL_SIZE=2`,
`VCPKG_MAX_CONCURRENCY=2`. The vcpkg binary cache + ccache live in a persistent
named volume (`ladybird-build-cache` -> `/var/lib/ladybird-cache`) so container
rebuilds stay cheap. If the machine cannot keep up, the CI build workflow is
the reliable fallback. See HANDOFF.md for the full resource analysis.
