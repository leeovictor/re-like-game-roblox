#!/usr/bin/env bash
set -euo pipefail

INSTALL=1
if [[ "${1:-}" == "--no-install" ]]; then
	INSTALL=0
elif [[ $# -gt 0 ]]; then
	echo "usage: scripts/plugin-build.sh [--no-install]" >&2
	exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

ROBLOX_PLUGINS_DIR="${ROBLOX_PLUGINS_DIR:-/mnt/c/Users/leona/AppData/Local/Roblox/Plugins}"
PLUGIN_BACKUP_DIR="${PLUGIN_BACKUP_DIR:-$(dirname "$ROBLOX_PLUGINS_DIR")/PluginBackups}"
INSTALLED_PLUGIN="$ROBLOX_PLUGINS_DIR/camera-system-plugin.rbxmx"

SHA="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
	SHA="${SHA}-dirty"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="$PLUGIN_BACKUP_DIR/camera-system-plugin-${TIMESTAMP}-${SHA}.rbxmx"

mkdir -p "$PLUGIN_BACKUP_DIR"

# On the first run, preserve the currently installed plugin so it can be rolled back.
if [[ -f "$INSTALLED_PLUGIN" ]]; then
	shopt -s nullglob
	existing_archives=("$PLUGIN_BACKUP_DIR"/*.rbxmx)
	shopt -u nullglob
	if [[ ${#existing_archives[@]} -eq 0 ]]; then
		cp -p "$INSTALLED_PLUGIN" "$PLUGIN_BACKUP_DIR/camera-system-plugin-installed-${TIMESTAMP}.rbxmx"
		echo "Archived the currently installed plugin before the first build."
	fi
fi

TEMP_BUILD="$(mktemp /tmp/camera-system-plugin.XXXXXX.rbxmx)"
trap 'rm -f "$TEMP_BUILD"' EXIT

echo "Building plugin from plugin.project.json..."
rojo build -o "$TEMP_BUILD" plugin.project.json

cp "$TEMP_BUILD" "$ARCHIVE_PATH"
echo "Archived: $ARCHIVE_PATH"

# Keep the five most recent archives.
mapfile -t archives < <(ls -1t "$PLUGIN_BACKUP_DIR"/*.rbxmx 2>/dev/null || true)
if [[ ${#archives[@]} -gt 5 ]]; then
	printf '%s\n' "${archives[@]:5}" | xargs -r rm -f
fi

if [[ "$INSTALL" -eq 1 ]]; then
	if [[ ! -d "$ROBLOX_PLUGINS_DIR" ]]; then
		echo "error: Roblox plugins directory not found: $ROBLOX_PLUGINS_DIR" >&2
		echo "Set ROBLOX_PLUGINS_DIR or build with --no-install." >&2
		exit 1
	fi
	mv "$TEMP_BUILD" "$INSTALLED_PLUGIN"
	echo "Installed: $INSTALLED_PLUGIN"
	echo "Restart Roblox Studio to load the updated plugin."
else
	echo "Skipped install (--no-install)."
fi
