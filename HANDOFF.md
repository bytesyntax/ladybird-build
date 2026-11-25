# HANDOFF

Working state of the `ladybird-build` project, written for the **next session**
(or a human) to continue. Read this top to bottom, then start at the first
unchecked item.

## Mission

Create a repository that can build the Ladybird browser
(https://github.com/LadybirdBrowser/ladybird, per
`Documentation/BuildInstructionsLadybird.md`):
1. a build/dev container recipe with its own rebuild triggers (DONE - see S0)
2. the container compatible with VS Code `.devcontainers`, loading automatically (DONE - see S0)
3. build Ladybird inside the container (S1)
4. GitHub workflow(s): container rebuild on recipe change + CI build (S2)

## Session plan

| Session | Scope | Status |
|---------|-------|--------|
| S0 | research, repo scaffold, container recipe + triggers, docs | **DONE** |
| S1a | container image builds + verified (`ladybird-build:local`) | **DONE** |
| S1b | build Ladybird inside the container | **TODO** |
| S2 | `.github/workflows/` (devcontainer rebuild-on-change + CI build), README CI section | **TODO** |

## S0 - what was done (committed)

- Repo `git init`-ed (branch `main`), hooks installed (`core.hooksPath=.githooks`).
- `ladybird/` submodule pinned to master `79075e698d5e5e3b92a74e36793355162ec9b3c0`.
- `.devcontainer/` recipe (self-contained, Ubuntu noble base):
  - `Dockerfile` - tools per build instructions: autoconf/automake, ccache, nasm,
    ninja, meson-free vcpkg flow, Qt dev packages NOT needed (Qt 6.11 comes from
    vcpkg on Linux - verified in `Meta/CMake/environment.cmake`: `find_package(Qt6 6.10 ...)`
    against the vcpkg tree), cmake >= 3.30 (install-cmake.sh), clang (install-compiler.sh),
    rustup. Bakes recipe hash to `/opt/ladybird-build/recipe.sha256`.
  - `devcontainer.json` - VS Code auto-load, workspace at `/workspace/ladybird-build`,
    persistent volume `ladybird-build-cache` -> `/var/lib/ladybird-cache`
    (vcpkg binary cache + ccache), memory-guard env (`LB_JOBS=3`,
    `LAGOM_LINK_POOL_SIZE=2`, `VCPKG_MAX_CONCURRENCY=2`), postCreate=bootstrap.sh,
    postStart=check-fresh.sh.
  - Rebuild-trigger system (3 layers, documented in README):
    1. `check-fresh.sh` (in-container, postCreate+postStart, `--strict` for CI)
    2. git hooks: pre-commit regenerates `.devcontainer/.recipe-hash`;
       post-merge/post-checkout run `rebuild-if-stale.sh --quiet`
    3. (S2) CI workflow on `.devcontainer/**` path changes
- `scripts/` host helpers, `README.md`, this file.

## Environment facts (this machine - re-verify before assuming)

- **aarch64** (ARM64), 8 cores, 7.3G RAM (mostly used by other processes!),
  8G swap (~4G free), **one 41G btrfs volume with ~16G free** (/ == /home).
- No docker. **podman 6.2.0** (rootless, storage in `~/.local/share/containers`
  on the same volume). VS Code Dev Containers works with podman.
- Network egress: github.com (raw/api/releases), apt.kitware.com,
  static.rust-lang.org, sh.rustup.rs all reachable.
  apt.llvm.org **works from inside the podman build network** (S0's build
  pulled llvm-toolchain-noble-22 arm64 fine) even though plain `curl` from
  the host egress got 301->404s on content paths - trust the container
  build, not host curl, when judging that mirror.
- Ladybird facts: no submodules of its own; vcpkg manifest mode clones vcpkg
  into `ladybird/Build/vcpkg-release` at configure time; **Linux builds Qt 6.11.3
  from source via vcpkg** (feature `qt`), plus skia/ffmpeg/openssl etc.
  Compiler min: clang 19 / gcc 14 (`Meta/Utils/find_compiler.py`).
  Release preset: RelWithDebInfo, binary dir `ladybird/Build/release`.

## S1 - verify the container image, then build Ladybird

### 1. Container image - DONE (verified)

`scripts/build-image.sh` succeeded end-to-end on this host (log:
`logs/devcontainer-build.log`), tag `ladybird-build:local`. Verified inside:
baked hash `d567f1e0...` == host `.recipe-hash`, **clang-22.1.8** /
**clang++-22** (recorded in `/opt/ladybird-build/toolchain.env`), cmake 4.5.0,
ninja 1.11.1, nasm 2.16.01, rustc 1.100.0 (stable; ladybird's own pinned
toolchain downloads on first cargo run), git 2.56.1. apt.llvm.org worked
inside the build network (fast path taken, no source-LLVM fallback needed).

If the recipe changes later and `scripts/build-image.sh` fails, iterate:
fix script -> rebuild. Likely failure points:
1. `mcr.microsoft.com` unreachable -> change `FROM` to `ubuntu:24.04` and add
   `git`, `lsb-release`, `ca-certificates`, `gnupg`, user `vscode` (uid 1000,
   in `adm,dialout` groups: `useradd -m -u 1000 -g vscode -s /bin/bash vscode`).
2. apt.llvm.org broken -> the script falls through to the LLVM-from-source
   build (slower; edit install-compiler.sh strategy 3 for memory if needed).
3. Anything else: read the log, fix, rebuild. **Every Dockerfile/script edit
   changes the recipe hash - that is intended; the triggers exist for this.**

### 2. Build Ladybird inside the container

```bash
podman run -it --rm \
  -v "$PWD/ladybird:/workspace/ladybird" \
  -v ladybird-build-cache:/var/lib/ladybird-cache \
  -w /workspace/ladybird-build .devcontainer/..  # NOT right - see below
```
(Prefer VS Code "Reopen in Container" so postCreate runs; or run the
equivalent of devcontainer.json's postCreate manually:
`bash .devcontainer/scripts/bootstrap.sh` then `bash .devcontainer/scripts/build-ladybird.sh`.)

Build phases and what to expect (first run, cold cache):
1. **vcpkg bootstrap + install** (~1-3 h on this box): Qt6 6.11 from source is
   the long pole. Watch RAM; if the host starts swapping hard (>2h with low
   progress), lower `VCPKG_MAX_CONCURRENCY=1` and restart - the binary cache
   keeps completed ports.
2. **Ladybird compile** (~1-2 h with LB_JOBS=3): `ninja -C ladybird/Build/release`.
   If OOM-killed mid-build, re-run the same command - ninja is incremental.
3. After success: `ladybird/Build/release/bin/Ladybird` exists. A GUI browser
   on a headless box cannot be "run" for real - verify the binary links
   (`ldd`), and optionally `./ladybird/Meta/ladybird.py run --no-build` under
   xvfb if one is available. Binary existence + clean link = done.

Disk discipline (only ~16G free!):
- after vcpkg finishes: `bash .devcontainer/scripts/build-ladybird.sh prune`
- keep: `ladybird/Build/release` (final), vcpkg `installed/` trees,
  `/var/lib/ladybird-cache` (binary cache + ccache)
- drop: `~/.cache`, old podman layers (`podman system prune -f`), ccache
  (`ccache -c`) if desperate
- if the volume fills up mid-build: `build-ladybird.sh prune` + `podman system prune -f`

If the local build cannot finish for resource reasons, that is an acceptable
outcome for S1 - record WHERE it got stuck in this file and let S2's CI build
be the verified build path. Do NOT claim success without a binary.

## S2 - GitHub workflows

Create (repo currently has none):

1. `.github/workflows/devcontainer.yml` - model on upstream
   `LadybirdBrowser/ladybird: .github/workflows/dev-container.yml`:
   - `on: push paths: [.devcontainer/**, .github/workflows/devcontainer.yml]`
     + `workflow_dispatch` + weekly `schedule`
   - job: checkout -> `podman/docker build -f .devcontainer/Dockerfile`
     (or `devcontainers/ci`) -> run `check-fresh.sh --strict` inside the new
     image -> push to GHCR tagged `sha-$(hash)` and `latest`
     (needs `GITHUB_TOKEN` + `packages: write`; GHCR login step)
2. `.github/workflows/build-ladybird.yml`:
   - `on: push` (master) + `pull_request` + `workflow_dispatch`
   - runner: `ubuntu-24.04` (x86_64; note this host is aarch64 - CI covers
     x86_64, local covers arm64)
   - steps: checkout with submodules -> build container image from
     `.devcontainer/Dockerfile` -> `cmake --preset Release` with
     `-DCMAKE_C_COMPILER/-DCMAKE_CXX_COMPILER` per toolchain.env ->
     `ninja -j$(nproc)` (GitHub runners have 4 cores / 16G RAM - the
     LAGOM_LINK_POOL_SIZE guard still applies) ->
     `upload-artifact` of `ladybird/Build/release/bin/Ladybird`
   - cache the vcpkg binary cache between runs (`/var/lib/ladybird-cache`
     equivalent) to keep the build under ~1h
3. Update README.md "CI" section once they exist.

## Resuming (copy-paste prompt for a new session)

> Continue the ladybird-build project in /home/olto/repos/ladybird-build.
> First read HANDOFF.md and continue from its "S1b" (or "S2") section.
> Current goal: [build Ladybird inside the container:
> run `bash .devcontainer/scripts/bootstrap.sh` then
> `bash .devcontainer/scripts/build-ladybird.sh` (image `ladybird-build:local`
> is ready; prefer VS Code "Reopen in Container" so postCreate runs) |
> create the GitHub workflows per HANDOFF.md S2]. Keep the recipe-hash
> rebuild triggers working after any .devcontainer change.

## Definition of done (whole project)

- [x] Recipe + triggers + VS Code auto-load config (S0)
- [x] `scripts/build-image.sh` succeeds on this host (S1a) - verified toolchain
- [ ] `ladybird/Build/release/bin/Ladybird` built in-container (S1b)
- [ ] `.github/workflows/devcontainer.yml` + `build-ladybird.yml` green (S2)
- [ ] README/HANDOFF updated to final state

## Log

- S0 (2026-11-25): repo scaffolded, recipe + 3-layer rebuild triggers written,
  submodule pinned @79075e6, `podman build` completed + verified:
  clang-22.1.8 / cmake 4.5.0 / ninja / nasm / rustc, baked recipe hash
  d567f1e0 == host .recipe-hash. Next: S1b (build Ladybird in-container),
  then S2 (workflows).
