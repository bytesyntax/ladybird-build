#!/usr/bin/env bash
# In-container freshness check (rebuild trigger #1).
#
# Compares the hash of the live recipe in the workspace against the hash that
# was baked into this container image when it was built (see Dockerfile).
# Warns on stderr when the two drift; with --strict (or LADYBIRD_BUILD_STRICT=1)
# it exits non-zero so CI can fail on a stale container.
#
# Usage: check-fresh.sh [--strict]
set -uo pipefail

STRICT="${LADYBIRD_BUILD_STRICT:-0}"
[[ "${1:-}" == "--strict" ]] && STRICT=1

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
BAKED_FILE="/opt/ladybird-build/recipe.sha256"

if [[ ! -f "$BAKED_FILE" ]]; then
    echo "check-fresh: no baked recipe hash at $BAKED_FILE (image predates the rebuild-trigger system); skipping" >&2
    exit 0
fi

CURRENT="$(bash "$SELF_DIR/hash-recipe.sh" "$REPO_ROOT/.devcontainer")"
BAKED="$(head -n1 "$BAKED_FILE" | awk '{print $1}')"

if [[ "$CURRENT" == "$BAKED" ]]; then
    echo "check-fresh: recipe is up to date ($CURRENT)"
    exit 0
fi

cat >&2 <<EOF
check-fresh: WARNING - container recipe is STALE
  image built with: $BAKED
  recipe on disk:   $CURRENT

Rebuild the container before building Ladybird:
  VS Code: Command Palette -> "Dev Containers: Rebuild Container"
  CLI:     devcontainer rebuild --workspace-folder "$REPO_ROOT"
EOF

if [[ "$STRICT" == 1 ]]; then
    exit 1
fi
exit 0
