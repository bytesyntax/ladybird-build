#!/usr/bin/env bash
# Build the dev container image directly with podman/docker (the CI-like
# path). VS Code's "Dev Containers: Rebuild Container" does the same build
# plus the VS Code server layer.
#
# Usage: scripts/build-image.sh [tag]     (default tag: ladybird-build:local)
set -euo pipefail
cd "$(dirname "$0")/.."

RUNNER=""
if command -v podman >/dev/null 2>&1; then RUNNER=podman
elif command -v docker >/dev/null 2>&1; then RUNNER=docker
else
    echo "no podman/docker found" >&2
    exit 1
fi

TAG="${1:-ladybird-build:local}"
echo "building $TAG with $RUNNER (log: logs/devcontainer-build.log)"
mkdir -p logs
"$RUNNER" build -f .devcontainer/Dockerfile -t "$TAG" \
    --label ladybird-build=1 \
    .devcontainer 2>&1 | tee logs/devcontainer-build.log

echo "done: $TAG"
echo "recipe hash: $(bash .devcontainer/scripts/hash-recipe.sh .devcontainer)"
