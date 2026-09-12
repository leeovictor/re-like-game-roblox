#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

ROBLOX_PLUGINS_DIR="${ROBLOX_PLUGINS_DIR:-/mnt/c/Users/leona/AppData/Local/Roblox/Plugins}"
PLUGIN_BACKUP_DIR="${PLUGIN_BACKUP_DIR:-$(dirname "$ROBLOX_PLUGINS_DIR")/PluginBackups}"
INSTALLED_PLUGIN="$ROBLOX_PLUGINS_DIR/camera-system-plugin.rbxmx"

shopt -s nullglob
archives=("$PLUGIN_BACKUP_DIR"/*.rbxmx)
shopt -u nullglob

install_archive() {
	local source="$1"
	mkdir -p "$ROBLOX_PLUGINS_DIR"
	cp "$source" "$INSTALLED_PLUGIN"
	echo "Installed: $(basename "$source") -> $INSTALLED_PLUGIN"
	echo "Restart Roblox Studio to load the restored plugin."
}

list_archives() {
	if [[ ${#archives[@]} -eq 0 ]]; then
		echo "No archives found in $PLUGIN_BACKUP_DIR"
		return
	fi
	local sorted
	mapfile -t sorted < <(ls -1t "$PLUGIN_BACKUP_DIR"/*.rbxmx)
	local archive marker
	for archive in "${sorted[@]}"; do
		if [[ -f "$INSTALLED_PLUGIN" ]] && cmp -s "$archive" "$INSTALLED_PLUGIN"; then
			marker=" [installed]"
		else
			marker=" [differs from installed]"
		fi
		printf '%s  %s%s\n' "$(date -r "$archive" '+%Y-%m-%d %H:%M:%S')" "$(basename "$archive")" "$marker"
	done
}

resolve_archive_path() {
	local candidate="$1"
	if [[ "$candidate" != /* ]]; then
		candidate="$PLUGIN_BACKUP_DIR/$candidate"
	fi
	local resolved_backup resolved_candidate
	resolved_backup="$(realpath -m "$PLUGIN_BACKUP_DIR")"
	resolved_candidate="$(realpath -m "$candidate")"
	case "$resolved_candidate" in
	"$resolved_backup"/*) ;;
	*)
		echo "error: '$1' is outside $PLUGIN_BACKUP_DIR" >&2
		exit 1
		;;
	esac
	if [[ ! -f "$resolved_candidate" ]]; then
		echo "error: archive not found: $resolved_candidate" >&2
		exit 1
	fi
	printf '%s\n' "$resolved_candidate"
}

command="${1:-previous}"

case "$command" in
list)
	list_archives
	;;
previous)
	if [[ ${#archives[@]} -eq 0 ]]; then
		echo "No archives found in $PLUGIN_BACKUP_DIR" >&2
		exit 1
	fi
	mapfile -t sorted < <(ls -1t "$PLUGIN_BACKUP_DIR"/*.rbxmx)
	restored=""
	for archive in "${sorted[@]}"; do
		if [[ -f "$INSTALLED_PLUGIN" ]] && cmp -s "$archive" "$INSTALLED_PLUGIN"; then
			continue
		fi
		restored="$archive"
		break
	done
	if [[ -z "$restored" ]]; then
		echo "All archives match the installed plugin; nothing to restore." >&2
		exit 1
	fi
	install_archive "$restored"
	;;
*)
	archive_path="$(resolve_archive_path "$command")"
	install_archive "$archive_path"
	;;
esac
