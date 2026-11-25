#!/usr/bin/env bash
# Host-side rebuild trigger (rebuild trigger #3) - run from the HOST, outside
# the container. Compares the recipe hash baked into the running container
# with the hash of the current on-disk recipe and tells you to rebuild when
# they drift.
#
# Usage: rebuild-if-stale.sh [--rebuild] [--quiet]
#   --rebuild  actually rebuild via the devcontainer CLI (if installed)
#   --quiet    only print when stale (for git hooks)
set -uo pipefail
cd "$(dirname "$0")/../.."

QUIET=0
REBUILD=0
for a in "$@"; do
    case "$a" in
        --quiet) QUIET=1 ;;
        --rebuild) REBUILD=1 ;;
    esac
done

CURRENT="$(bash .devcontainer/scripts/hash-recipe.sh .devcontainer)"

RUNNER=""
if command -v podman >/dev/null 2>&1; then RUNNER=podman
elif command -v docker >/dev/null 2>&1; then RUNNER=docker
fi

CONTAINER=""
if [[ -n "$RUNNER" ]]; then
    CONTAINER="$("$RUNNER" ps --format '{{.Names}}' 2>/dev/null | grep -i ladybird | head -n1 || true)"
fi
if [[ -z "$CONTAINER" ]]; then
    [[ $QUIET == 1 ]] || echo "rebuild-if-stale: no running ladybird container found (start VS Code first)"
    exit 0
fi

BAKED="$("$RUNNER" exec "$CONTAINER" head -n1 /opt/ladybird-build/recipe.sha256 2>/dev/null | awk '{print $1}' || true)"
if [[ -z "$BAKED" ]]; then
    [[ $QUIET == 1 ]] || echo "rebuild-if-stale: container '$CONTAINER' predates the recipe-hash system; rebuild once to adopt it"
    exit 1
fi

if [[ "$CURRENT" == "$BAKED" ]]; then
    [[ $QUIET == 1 ]] || echo "rebuild-if-stale: container '$CONTAINER' is up to date ($CURRENT)"
    exit 0
fi

echo "rebuild-if-stale: container '$CONTAINER' is STALE (image: $BAKED, recipe: $CURRENT)"
if [[ $REBUILD == 1 ]]; then
    if command -v devcontainer >/dev/null 2>&1; then
        exec devcontainer rebuild --workspace-folder "$PWD"
    fi
    echo "no 'devcontainer' CLI on PATH - rebuild in VS Code instead (below)" >&2
    exit 1
fi
cat <<EOF
To rebuild:
  VS Code:  Command Palette -> "Dev Containers: Rebuild Container"
  CLI:      devcontainer rebuild --workspace-folder "$PWD"
            (or: bash $0 --rebuild)
EOF
exit 1
