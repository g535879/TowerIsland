#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

mkdir -p .githooks
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks

echo "Git hooks installed."
echo "Pre-commit now runs: bash Scripts/test-all.sh"
