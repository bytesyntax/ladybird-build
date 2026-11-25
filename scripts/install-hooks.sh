#!/usr/bin/env bash
# Point git at the repo-local hooks that keep the container recipe fresh.
# Run once per clone:  bash scripts/install-hooks.sh
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "core.hooksPath -> .githooks (pre-commit keeps .recipe-hash in sync; post-merge/post-checkout check container freshness)"
