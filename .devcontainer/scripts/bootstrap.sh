#!/usr/bin/env bash
# Container bootstrap - runs after container creation (devcontainer.json
# postCreateCommand). Verifies the toolchain, ensures the ladybird checkout
# is present, and runs the recipe freshness check.
set -uo pipefail
cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

echo "== ladybird-build bootstrap =="
echo "workspace: $REPO_ROOT"

# 1. Freshness check (rebuild trigger #1, non-fatal here)
bash .devcontainer/scripts/check-fresh.sh || true

# 2. Ensure the ladybird source is present
if [[ ! -f ladybird/CMakeLists.txt ]]; then
    echo "fetching ladybird submodule..."
    git submodule update --init --recursive
fi
echo "ladybird @ $(git -C ladybird rev-parse --short HEAD)"

# 3. Toolchain sanity
# shellcheck disable=SC1091
source /opt/ladybird-build/toolchain.env 2>/dev/null || true
: "${CC:=$(command -v clang-22 || command -v clang-21 || command -v clang-20 || command -v clang-19 || command -v clang || echo MISSING)}"
CC_NAME="$(basename "${CC}")"
case "$CC_NAME" in
    clang-*) CXX_NAME="clang++-${CC_NAME#clang-}" ;;
    clang)   CXX_NAME="clang++" ;;
    *)       CXX_NAME="${CC_NAME}++" ;;
esac

echo "compiler:  $CC  ($(command -v "$CC" >/dev/null 2>&1 && "$CC" --version | head -n1 || echo not found))"
echo "cxx:       $CXX_NAME"
echo "cmake:     $(cmake --version 2>/dev/null | head -n1 || echo MISSING)"
echo "ninja:     $(ninja --version 2>/dev/null || echo MISSING)"
echo "nasm:      $(nasm --version 2>/dev/null | head -n1 || echo MISSING)"
echo "rust:      $(rustup show active-toolchain 2>/dev/null || echo 'rustup: no default toolchain (ladybird pins its own via rust-toolchain.toml)')"

# 4. Resource budget warning (full build wants ~15-20G free + several GB RAM)
DF_KB="$(df -k --output=avail "$REPO_ROOT" | tail -n1 | tr -d ' ')"
if (( DF_KB < 12 * 1024 * 1024 )); then
    echo "WARNING: only $(( DF_KB / 1024 / 1024 ))G free on the workspace volume; a full build needs ~15-20G (see HANDOFF.md)" >&2
fi

echo
echo "Next step:  bash .devcontainer/scripts/build-ladybird.sh"
