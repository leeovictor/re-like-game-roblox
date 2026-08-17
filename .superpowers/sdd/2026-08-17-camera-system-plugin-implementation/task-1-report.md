# Task 1 Report

## Files Changed

- `src/shared/camera/CameraConfig.luau`
- `src/shared/camera/CameraMapReader.luau`
- `tests/shared/camera/CameraMapReader.spec.luau`

The existing untracked plan and specification files were not modified.

## Implementation Decisions

- Reduced `CameraConfig` to the strict exported `ShotId`, `ZoneId`, `Shot`, `Volume`, `Zone`, and `Config` types, returning an empty runtime table so configuration is no longer hardcoded.
- Implemented `CameraMapReader.read(root)` with the required folder, attribute, part, FOV, order, size, default-shot, and zone-shot validation sequence.
- Kept zone ordering deterministic by sorting on `Order`, then instance name, and did not expose the temporary order value in returned zones.
- Used contextual errors in the `CameraSystem: <tipo> "<nome>" <problema>` format.
- Added fake folder and part fixtures whose `GetChildren()` returns a cloned list, plus the six required behavioral cases.

## Verification

### RED

Command:

```text
lune run test
```

Result before the reader existed:

```text
module not found: src/shared/camera/CameraMapReader.luau
Summary: 9 suite(s), 48 passed, 1 failed, 0.033s
```

### GREEN / Full Test Runner

Command:

```text
lune run test
```

Result:

```text
Summary: 10 suite(s), 52 passed, 2 failed, 0.072s
```

The six `CameraMapReader` cases pass. The two failures are existing `CameraResolver` tests that still require the removed static `CameraConfig` runtime values:

- `CameraResolver :: carrega uma configuracao inicial valida`
- `CameraResolver :: resolve os centros das zonas adicionais`

### Lint

Commands:

```text
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Result:

```text
0 errors
0 warnings
0 parse errors
0 errors
0 warnings
0 parse errors
```

### Roblox Typecheck

Command:

```text
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap sourcemap.json --formatter gnu src
```

Result: the reader itself has no diagnostics after its strict Instance/BasePart narrowing. The command reports two expected consumer errors in `src/client/init.client.luau` because it still passes the now-empty type-only `CameraConfig` to `CameraController.new` and `CameraDebugger.new`, plus the unrelated pre-existing deprecation at `src/server/inventory/InventoryService.luau:100`.

### Lune Typecheck

Command:

```text
luau-lsp analyze --platform standard --base-luaurc typecheck/lune.luaurc --formatter gnu tests lune
```

Result:

```text
No diagnostics.
```

### Rojo Build

Command:

```text
rojo build -o /tmp/dungeon-game-canve.rbxlx
```

Result:

```text
Building project 'dungeon-game-canve'
Built project to dungeon-game-canve.rbxlx
```

## Concerns

- Task 1 removes runtime camera data while `src/client/init.client.luau` and the two existing `CameraResolver` tests still consume the old static module. The full test runner therefore remains at 52 passed and 2 failed, and Roblox typecheck reports the two client consumer type errors. Wiring the reader into the client and updating those consumers appears to belong to a subsequent task.
- The Roblox typecheck also reports the unrelated existing `Player:LoadCharacter` deprecation in `InventoryService.luau`.

## Round 1 Fix

### Change

Added `CameraMapReader :: ordena zonas alfabeticamente quando Order empata` to
`tests/shared/camera/CameraMapReader.spec.luau`. The test assigns the same order
to both zones and reverses the fake folder's child list, proving that output
ordering comes from the alphabetical tie-breaker rather than source traversal
order. No Task 2 consumer changes were made.

### Exact Verification Commands and Output

Command:

```text
lune run test
```

Relevant output:

```text
PASS CameraMapReader :: ordena zonas alfabeticamente quando Order empata
Summary: 10 suite(s), 53 passed, 2 failed, 0.036s
```

The same two existing `CameraResolver` tests continue to fail because the
static runtime configuration was removed in Task 1:

```text
FAIL CameraResolver :: carrega uma configuracao inicial valida
FAIL CameraResolver :: resolve os centros das zonas adicionais
```

Command:

```text
selene --config selene.lune.toml tests/shared/camera/CameraMapReader.spec.luau
```

Exact output:

```text
0 errors
0 warnings
0 parse errors
```
