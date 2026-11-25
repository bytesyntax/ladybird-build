#!/usr/bin/env bash
# Deterministic hash of the container recipe.
#
# Usage: hash-recipe.sh [recipe-dir]     (default: .devcontainer)
#
# Prints a single sha256 hex string that changes whenever any recipe file
# (Dockerfile, devcontainer.json, scripts) changes. The Dockerfile bakes this
# value into the image at /opt/ladybird-build/recipe.sha256 and
# check-fresh.sh / rebuild-if-stale.sh compare it against the live recipe.
#
# Generated artifacts (.recipe-hash, recipe.sha256) are excluded so the hash
# is stable and self-consistent on host and in image.
set -euo pipefail

DIR="${1:-.devcontainer}"
cd "$DIR"

find . -type f \
    ! -name '.recipe-hash' \
    ! -name 'recipe.sha256' \
    ! -path './.git/*' \
    | LC_ALL=C sort \
    | while IFS= read -r f; do
        printf '%s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "$f"
      done \
    | sha256sum | awk '{print $1}'
