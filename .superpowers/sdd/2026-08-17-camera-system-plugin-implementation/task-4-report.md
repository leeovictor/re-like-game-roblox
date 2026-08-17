# Task 4 Report

## Automated Verification

- `selene --config selene.roblox.toml plugin`: passed, 0 errors and 0 warnings.
- `rojo sourcemap plugin.project.json --include-non-scripts --output /tmp/camera-system-plugin-sourcemap.json`: passed.
- `luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/camera-system-plugin-sourcemap.json --formatter gnu plugin`: passed. The temporary sourcemap is required because the plugin is intentionally outside `default.project.json`; the tool emitted only its client file-watching informational warning.
- `rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx`: passed.
- `git diff --check`: passed with no output.

## Studio Manual Limitations

Roblox Studio is not available in this environment, so the local plugin installation, dock-widget interaction, viewport selection synchronization, ChangeHistory undo/redo, marker rendering, and playtest validation could not be performed here. Those workflows require installing `/tmp/camera-system-plugin.rbxmx` as a local Studio plugin and exercising the checklist in the Task 4 brief.

## Scope

Implemented only `plugin/camera/CameraSystemPreview.luau`, `plugin/camera/CameraSystemWidget.luau`, and `plugin/init.plugin.luau`. The widget emits callbacks; the entrypoint owns model, preview, selection/event refresh, and cleanup lifecycle.

## Round 1 Fix Verification

- `selene --config selene.roblox.toml plugin`: passed, 0 errors, 0 warnings, and 0 parse errors.
- `rojo sourcemap plugin.project.json --include-non-scripts --output /tmp/camera-system-plugin-sourcemap.json`: passed.
- `luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/camera-system-plugin-sourcemap.json --formatter gnu plugin`: passed; only the tool's informational client file-watching warning was emitted.
- `rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx`: passed.
- `git diff --check`: passed with no output.

The round fixes preserve independent shot/zone selections, use the actual hierarchy folders for ownership, retain row-to-instance associations, watch relevant attributes on existing and newly added parts, and set every generated preview marker to `Archivable = false`.

## Round 1 Follow-Up Verification

- `selene --config selene.roblox.toml plugin`: passed, 0 errors, 0 warnings, and 0 parse errors.
- `rojo sourcemap plugin.project.json --include-non-scripts --output /tmp/camera-system-plugin-sourcemap.json`: passed.
- `luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/camera-system-plugin-sourcemap.json --formatter gnu plugin`: passed; only the tool's informational client file-watching warning was emitted.
- `rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx`: passed.
- `git diff --check`: passed with no output.

The follow-up also routes authoring actions through the widget's independent logical selections and stores row associations in a typed row-to-instance table rather than an Instance attribute.
