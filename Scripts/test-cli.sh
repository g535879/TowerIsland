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

test_extracts_mount_dir_from_hdiutil_attach_output() {
    local output mount_dir
    output=$'/dev/disk16\tGUID_partition_scheme\t\n/dev/disk16s1\tApple_HFS\t/Volumes/Tower Island 7'

    mount_dir="$(tower_island_mount_dir_from_attach_output "$output")"

    [[ "$mount_dir" == "/Volumes/Tower Island 7" ]] \
        || fail "expected mount dir, got: $mount_dir"
}

test_cleanup_upgrade_artifacts_allows_empty_mount_dir() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    tower_island_cleanup_upgrade_artifacts "" "$tmpdir"

    [[ ! -e "$tmpdir" ]] \
        || fail "expected temp dir to be removed"
}

test_cli_bin_path_detected_in_path() {
    PATH="/usr/bin:$HOME/.tower-island/bin:/bin"

    tower_island_cli_bin_in_path
}

test_cli_bin_path_detected_as_missing() {
    PATH="/usr/bin:/bin"

    if tower_island_cli_bin_in_path; then
        fail "expected tower-island bin path to be reported as missing"
    fi
}

test_shell_profile_path_hint_for_zsh() {
    local hint
    hint="$(SHELL=/bin/zsh tower_island_shell_profile_path_hint)"

    [[ "$hint" == *".zshrc"* ]] \
        || fail "expected zsh profile hint, got: $hint"
}

test_shell_profile_path_hint_for_bash() {
    local hint
    hint="$(SHELL=/bin/bash tower_island_shell_profile_path_hint)"

    [[ "$hint" == *".bash_profile"* ]] \
        || fail "expected bash profile hint, got: $hint"
}

test_selects_dmg_asset_from_release_json
test_rejects_release_without_dmg_asset
test_help_for_empty_command
test_upgrade_command_dispatches
test_extracts_mount_dir_from_hdiutil_attach_output
test_cleanup_upgrade_artifacts_allows_empty_mount_dir
test_cli_bin_path_detected_in_path
test_cli_bin_path_detected_as_missing
test_shell_profile_path_hint_for_zsh
test_shell_profile_path_hint_for_bash

echo "CLI tests passed"
