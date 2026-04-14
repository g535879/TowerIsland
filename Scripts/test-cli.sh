#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/tower-island-cli.sh"

if [[ ! -f "$LIB" ]]; then
    echo "missing CLI library: $LIB" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$LIB"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

test_selects_dmg_asset_from_release_json() {
    local json
    json='{"tagName":"v1.2.3","assets":[{"name":"notes.txt","url":"https://example.com/notes.txt"},{"name":"TowerIsland-v1.2.3.dmg","url":"https://example.com/TowerIsland-v1.2.3.dmg"}]}'

    local asset_url
    asset_url="$(tower_island_release_asset_url "$json")"

    [[ "$asset_url" == "https://example.com/TowerIsland-v1.2.3.dmg" ]] \
        || fail "expected dmg asset url, got: $asset_url"
}

test_rejects_release_without_dmg_asset() {
    local json
    json='{"tagName":"v1.2.3","assets":[{"name":"notes.txt","url":"https://example.com/notes.txt"}]}'

    if tower_island_release_asset_url "$json" >/dev/null 2>&1; then
        fail "expected missing dmg asset to fail"
    fi
}

test_help_for_empty_command() {
    local output
    output="$(tower_island_dispatch "" 2>&1 || true)"

    [[ "$output" == *"Usage: tower-island <command>"* ]] \
        || fail "expected usage output, got: $output"
}

test_upgrade_command_dispatches() {
    local output
    output="$(TOWER_ISLAND_TEST_MODE=1 tower_island_dispatch "upgrade")"

    [[ "$output" == "upgrade:test-mode" ]] \
        || fail "expected test-mode dispatch, got: $output"
}

test_selects_dmg_asset_from_release_json
test_rejects_release_without_dmg_asset
test_help_for_empty_command
test_upgrade_command_dispatches

echo "CLI tests passed"
