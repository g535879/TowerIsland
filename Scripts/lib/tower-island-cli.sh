#!/bin/bash
set -euo pipefail

TOWER_ISLAND_REPO="${TOWER_ISLAND_REPO:-g535879/TowerIsland}"
TOWER_ISLAND_APP_PATH="${TOWER_ISLAND_APP_PATH:-/Applications/Tower Island.app}"
TOWER_ISLAND_BIN_DIR="${TOWER_ISLAND_BIN_DIR:-$HOME/.tower-island/bin}"

tower_island_usage() {
    cat <<'EOF'
Usage: tower-island <command>

Commands:
  upgrade    Download and install the latest GitHub release
  help       Show this help message
EOF
}

tower_island_require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: required command not found: $cmd" >&2
        exit 1
    fi
}

tower_island_release_asset_url() {
    local release_json="$1"

    RELEASE_JSON="$release_json" python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["RELEASE_JSON"])
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(".dmg"):
        print(asset["url"])
        break
else:
    sys.exit(1)
PY
}

tower_island_release_tag() {
    gh release list \
        --repo "$TOWER_ISLAND_REPO" \
        --exclude-drafts \
        --exclude-pre-releases \
        --limit 1 \
        --json tagName \
        --jq '.[0].tagName'
}

tower_island_release_json() {
    local tag="$1"
    gh release view "$tag" \
        --repo "$TOWER_ISLAND_REPO" \
        --json tagName,assets,name,publishedAt
}

tower_island_download_release_asset() {
    local tag="$1"
    local output="$2"
    gh release download "$tag" \
        --repo "$TOWER_ISLAND_REPO" \
        --pattern '*.dmg' \
        --output "$output" \
        --clobber
}

tower_island_mount_dir_from_attach_output() {
    local attach_output="$1"

    printf '%s\n' "$attach_output" \
        | awk -F '\t' '/\/Volumes\// {print $NF}' \
        | tail -n 1
}

tower_island_cleanup_upgrade_artifacts() {
    local mount_dir="${1:-}"
    local tmpdir="${2:-}"

    if [[ -n "$mount_dir" ]]; then
        hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
    fi

    if [[ -n "$tmpdir" ]]; then
        rm -rf "$tmpdir"
    fi
}

tower_island_cli_bin_in_path() {
    case ":$PATH:" in
        *":$TOWER_ISLAND_BIN_DIR:"*) return 0 ;;
        *) return 1 ;;
    esac
}

tower_island_shell_profile_path_hint() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"

    case "$shell_name" in
        zsh)
            printf '%s\n' '~/.zshrc'
            ;;
        bash)
            printf '%s\n' '~/.bash_profile'
            ;;
        fish)
            printf '%s\n' '~/.config/fish/config.fish'
            ;;
        *)
            printf '%s\n' 'your shell profile'
            ;;
    esac
}

tower_island_print_path_guidance() {
    if tower_island_cli_bin_in_path; then
        return 0
    fi

    local profile_hint
    profile_hint="$(tower_island_shell_profile_path_hint)"

    echo ""
    echo "To run 'tower-island upgrade' from any directory, add this to $profile_hint:"
    echo "  export PATH=\"$TOWER_ISLAND_BIN_DIR:\$PATH\""
}

tower_island_upgrade() {
    if [[ "${TOWER_ISLAND_TEST_MODE:-0}" == "1" ]]; then
        echo "upgrade:test-mode"
        return 0
    fi

    tower_island_require_command gh
    tower_island_require_command hdiutil
    tower_island_require_command xattr
    tower_island_require_command open

    local tag
    tag="$(tower_island_release_tag)"
    if [[ -z "$tag" || "$tag" == "null" ]]; then
        echo "error: unable to determine latest release tag" >&2
        exit 1
    fi

    local release_json
    release_json="$(tower_island_release_json "$tag")"

    local asset_api_url
    asset_api_url="$(tower_island_release_asset_url "$release_json")" || {
        echo "error: latest release does not contain a DMG asset" >&2
        exit 1
    }

    local tmpdir dmg_path mount_dir volume_app
    tmpdir="$(mktemp -d)"
    trap 'tower_island_cleanup_upgrade_artifacts "" "$tmpdir"' EXIT

    dmg_path="$tmpdir/TowerIsland.dmg"
    echo "==> Downloading $tag from GitHub Releases..."
    tower_island_download_release_asset "$tag" "$dmg_path"

    echo "==> Mounting DMG..."
    local attach_output
    attach_output="$(hdiutil attach "$dmg_path" -nobrowse)"
    mount_dir="$(tower_island_mount_dir_from_attach_output "$attach_output")"
    if [[ -z "$mount_dir" ]]; then
        echo "error: failed to mount DMG" >&2
        exit 1
    fi

    trap 'tower_island_cleanup_upgrade_artifacts "${mount_dir:-}" "${tmpdir:-}"' EXIT

    volume_app="$mount_dir/Tower Island.app"
    if [[ ! -d "$volume_app" ]]; then
        echo "error: mounted DMG does not contain Tower Island.app" >&2
        exit 1
    fi

    echo "==> Stopping running app..."
    pkill -x "TowerIsland" >/dev/null 2>&1 || true

    echo "==> Installing to $TOWER_ISLAND_APP_PATH..."
    rm -rf "$TOWER_ISLAND_APP_PATH"
    cp -R "$volume_app" "$TOWER_ISLAND_APP_PATH"

    echo "==> Clearing Gatekeeper quarantine..."
    xattr -cr "$TOWER_ISLAND_APP_PATH" || true

    echo "==> Unmounting DMG..."
    hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
    mount_dir=""

    echo "==> Launching app..."
    open "$TOWER_ISLAND_APP_PATH"

    echo "Upgraded Tower Island to $tag"
    echo "Release asset: $asset_api_url"
    tower_island_print_path_guidance
}

tower_island_dispatch() {
    local command="${1:-}"
    shift || true

    case "$command" in
        "" | help | --help | -h)
            tower_island_usage
            ;;
        upgrade)
            tower_island_upgrade "$@"
            ;;
        *)
            echo "error: unknown command: $command" >&2
            tower_island_usage >&2
            return 1
            ;;
    esac
}
