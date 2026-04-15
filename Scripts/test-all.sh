#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOCK="$HOME/.tower-island/di.sock"

cd "$PROJECT_DIR"

echo "==> [1/2] Running Swift unit tests..."
swift test

echo "==> [2/2] Running integration tests..."
if [[ ! -S "$SOCK" ]]; then
    echo "ERROR: Tower Island socket not found at $SOCK"
    echo "Please launch Tower Island first, then rerun: bash Scripts/test-all.sh"
    exit 1
fi

bash Scripts/test.sh

echo ""
echo "All automated tests passed."
