#!/usr/bin/env bash
# Update the local Ladybird install from the latest arm64 build this repo
# publishes on GitHub (the rolling `latest-arm64` release).
#
# Usage: scripts/update-ladybird.sh [destination]
#   destination defaults to ~/.local/bin/Ladybird
#
# Downloads the binary + its published sha256 + VERSION, verifies the hash,
# installs, and prints the Ladybird commit the binary was built from.
set -euo pipefail
REPO="bytesyntax/ladybird-build"
DEST="${1:-$HOME/.local/bin/Ladybird}"
BASE="https://github.com/${REPO}/releases/latest/download"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

curl -fL --progress-bar -O "$BASE/Ladybird-Linux-ARM64"
curl -fsL -O "$BASE/Ladybird-Linux-ARM64.sha256"
sha256sum -c Ladybird-Linux-ARM64.sha256

install -m 755 Ladybird-Linux-ARM64 "$DEST"
echo "installed: $DEST"
echo "built from:"
curl -fsL -o VERSION "$BASE/VERSION" && sed 's/^/  /' VERSION
