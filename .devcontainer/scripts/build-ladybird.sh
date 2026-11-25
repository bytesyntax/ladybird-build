#!/usr/bin/env bash
# Configure + build Ladybird inside the dev container.
#
# Usage: build-ladybird.sh [build|prune|clean|status]
#   build   (default) configure the Release preset and run ninja
#   prune   free disk: drop vcpkg build trees/downloads (binary cache kept)
#   clean   wipe the ladybird Build/ directory
#   status  show toolchain, disk usage and last build artifacts
#
# Memory guards for small machines are taken from the environment (the
# devcontainer.json sets sane defaults): LB_JOBS, LAGOM_LINK_POOL_SIZE,
# VCPKG_MAX_CONCURRENCY.
set -uo pipefail
cd "$(dirname "$0")/../.."
SRC="ladybird"
BUILD_DIR="$SRC/Build/release"

case "${1:-build}" in
    clean)
        rm -rf "$SRC"/Build
        echo "removed $SRC/Build"
        exit 0
        ;;
    prune)
        rm -rf "$SRC"/Build/*/vcpkg/buildtrees \
               "$SRC"/Build/*/vcpkg/packages \
               "$SRC"/Build/*/vcpkg/downloads \
               "$SRC"/Build/*/vcpkg/trees
        df -h "$SRC" | tail -n1
        exit 0
        ;;
    status)
        df -h "$SRC" | tail -n1
        if [[ -d "$BUILD_DIR" ]]; then
            echo "build dir: $BUILD_DIR"
            du -sh "$BUILD_DIR" 2>/dev/null
            ls -lh "$BUILD_DIR/bin/" 2>/dev/null | head -n10 || true
        else
            echo "not configured yet (no $BUILD_DIR)"
        fi
        exit 0
        ;;
    build)
        ;;
    *)
        echo "unknown command: $1 (use build|prune|clean|status)" >&2
        exit 2
        ;;
esac

[[ -f "$SRC/CMakeLists.txt" ]] || git submodule update --init --recursive

# Toolchain selection (written by the image's install-compiler.sh)
# shellcheck disable=SC1091
source /opt/ladybird-build/toolchain.env 2>/dev/null || true
: "${CC:=$(command -v clang-22 || command -v clang-21 || command -v clang-20 || command -v clang-19 || command -v clang || true)}"
if [[ -z "${CC:-}" ]]; then
    echo "no usable compiler found (need clang >= 19)" >&2
    exit 1
fi
CC_BIN="$(command -v "$CC")"
CC_NAME="$(basename "$CC_BIN")"
case "$CC_NAME" in
    clang-*) CXX_BIN="$(command -v "clang++-${CC_NAME#clang-}" || command -v clang++)" ;;
    clang)   CXX_BIN="$(command -v clang++)" ;;
    *)       CXX_BIN="${CC_BIN}++" ;;
esac
export CXX="$CXX_BIN"

JOBS="${LB_JOBS:-3}"
export LAGOM_LINK_POOL_SIZE="${LAGOM_LINK_POOL_SIZE:-2}"
export VCPKG_MAX_CONCURRENCY="${VCPKG_MAX_CONCURRENCY:-2}"

echo "== compiler:  $CC_BIN"
echo "== cxx:       $CXX_BIN"
echo "== jobs:      $JOBS (link pool: $LAGOM_LINK_POOL_SIZE, vcpkg concurrency: $VCPKG_MAX_CONCURRENCY)"
echo "== disk:"
df -h "$SRC" | tail -n1

echo
echo "== configure (Release preset) =="
cmake --preset Release \
    -S "$SRC" \
    -DCMAKE_C_COMPILER="$CC_BIN" \
    -DCMAKE_CXX_COMPILER="$CXX_BIN" \
    || { echo "configure FAILED" >&2; exit 1; }

echo
echo "== build (ninja -j$JOBS) =="
if ! ninja -C "$BUILD_DIR" -j"$JOBS"; then
    echo "build FAILED (see errors above)" >&2
    exit 1
fi

echo
echo "== build OK =="
ls -lh "$BUILD_DIR/bin/" 2>/dev/null | head -n10
echo
echo "Run the browser:  bash $SRC/Meta/ladybird.py run --no-build"
echo "Free disk:        bash $0 prune"
