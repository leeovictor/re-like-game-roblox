# Task 4 Report

## Automated Verification

- `selene --config selene.roblox.toml plugin`: passed, 0 errors and 0 warnings.
- `rojo sourcemap plugin.project.json --include-non-scripts --output /tmp/camera-system-plugin-sourcemap.json`: passed.
- `luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/camera-system-plugin-sourcemap.json --formatter gnu plugin`: passed; only the tool's informational client file-watching warning was emitted.
- `rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx`: passed.
- `selene --config selene.lune.toml tests lune`: passed, 0 errors and 0 warnings.
- `lune run test`: passed, 10 suites, 53 passed, 0 failed.
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

## Root Cause and Fix

`plugin` is provided as a global to the plugin entry script, but it is not available in required ModuleScripts. `CameraSystemWidget.new` indexed that module-global value while creating the dock widget, causing `CreateDockWidgetPluginGui` to be called on nil.

- `plugin/init.plugin.luau`: creates the `DockWidgetPluginGui` through the valid `pluginApi` and passes the resulting GUI to the widget.
- `plugin/camera/CameraSystemWidget.luau`: accepts the already-created GUI instead of accessing the global `plugin`; callback-driven controls and the non-mutating model boundary are unchanged.

## TDD / Regression Limitation

The repository has no practical Lune or Roblox runtime harness for loading plugin entry scripts and constructing `DockWidgetPluginGui`. The smallest feasible regression seam is the injected `DockWidgetPluginGui` constructor argument, which removes the module's dependency on the unavailable global. The pre-fix Studio failure was confirmed from the supplied stack trace; it cannot be reproduced by the Lune test runner because the plugin tree is separate and Roblox Studio plugin APIs are unavailable there.

## Scope

This fix changed only `plugin/init.plugin.luau`, `plugin/camera/CameraSystemWidget.luau`, and this report. The widget remains callback-driven; the entrypoint owns model, preview, selection/event refresh, and cleanup lifecycle.
