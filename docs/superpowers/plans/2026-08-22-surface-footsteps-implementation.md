# Surface-Aware Footsteps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare the local footstep controller to select future audio pools by `Enum.Material` while retaining the current audio IDs as the universal fallback.

**Architecture:** Keep `FootstepConfig.soundIds` as the existing universal pool and add an initially empty `surfaceSounds` map keyed by `Enum.Material`. `FootstepController` will create persistent `Sound` pools for the universal IDs and each non-empty material entry when a character is configured, then choose the material pool at playback time or fall back to the universal pool.

**Tech Stack:** Luau with `--!strict`, Roblox `Humanoid.FloorMaterial`, `Sound` instances parented to `HumanoidRootPart`, Rojo, Selene, and `luau-lsp`.

## Global Constraints

- Keep `--!strict` and do not add `--!nocheck`, broad ignores, or disabled type errors.
- Keep the current `soundIds` values unchanged; do not add new audio IDs.
- Add `surfaceSounds` as an empty configuration table so the current runtime behavior remains unchanged.
- Key future surface entries directly with `Enum.Material`, not material-name strings.
- Use the universal pool when a material has no configured or non-empty specific pool.
- Create and destroy pools per local character; do not change server code, remotes, or `TankController`.
- Keep the existing non-repetition, playback-speed, volume, cadence, air, and movement behavior.
- Do not add a design spec or commit changes unless explicitly requested.

---

### Task 1: Extend Footstep Configuration

**Files:**
- Modify: `src/client/player/FootstepConfig.luau:8-20` for the exported surface-pool type and config field.
- Modify: `src/client/player/FootstepConfig.luau:22-40` to initialize the new map without changing existing IDs.

**Interfaces:**
- Produces `Config.surfaceSounds: { [Enum.Material]: { string } }`.
- Keeps `Config.soundIds: { string }` as the universal fallback pool.

- [ ] **Step 1: Add the surface-pool type to the config contract**

Add a `surfaceSounds` field to the exported `Config` type, using `Enum.Material` keys and string asset-ID arrays:

```lua
export type Config = {
    soundIds: { string },
    surfaceSounds: { [Enum.Material]: { string } },
    playbackSpeed: Range,
    volume: Range,
    referenceSpeed: number,
    referenceStepInterval: number,
    minInterval: number,
    maxInterval: number,
    movementThreshold: number,
    rollOffMode: Enum.RollOffMode,
    rollOffMinDistance: number,
    rollOffMaxDistance: number,
}
```

Preserve the repository's tab indentation when applying the change.

- [ ] **Step 2: Initialize the future surface map as empty**

Add this field immediately after the existing `soundIds` list and leave every existing ID unchanged:

```lua
    surfaceSounds = {},
```

Do not add placeholder IDs, commented asset IDs, or a default material entry. The empty map means every material uses `soundIds` for now.

- [ ] **Step 3: Verify the configuration diff**

Run:

```bash
git diff -- src/client/player/FootstepConfig.luau
```

Expected: only the new type field and the empty `surfaceSounds` field are present; all existing audio IDs and tuning values are unchanged.

---

### Task 2: Create and Select Persistent Surface Pools

**Files:**
- Modify: `src/client/player/FootstepController.luau:15-19` for universal and per-material pool state.
- Modify: `src/client/player/FootstepController.luau:39-78` for pool cleanup and creation.
- Modify: `src/client/player/FootstepController.luau:80-109` so selection and playback operate on the chosen pool.
- Modify: `src/client/player/FootstepController.luau:116-133` to choose the pool from `FloorMaterial` before cadence playback.
- Modify: `src/client/player/FootstepController.luau:149-165` to create all configured pools during character setup.

**Interfaces:**
- Consumes `Config.soundIds` and `Config.surfaceSounds` from Task 1.
- Produces one persistent universal pool and a `{ [Enum.Material]: { Sound } }` map for the active character.
- `chooseSound(sounds: { Sound }): Sound?` selects from the supplied pool without repeating the previous `Sound` when alternatives exist.
- `playFootstep(sounds: { Sound }): ()` applies the existing randomized playback settings and plays the selected sound.

- [ ] **Step 1: Replace the single active pool with two character-scoped pools**

Replace `activeSounds` with these states:

```lua
type SoundPools = { [Enum.Material]: { Sound } }

local universalSounds: { Sound } = {}
local soundsByMaterial: SoundPools = {}
```

Keep `lastSound`, `currentSpeed`, and `timeSinceLastStep` unchanged. The material map stores only pools configured for the current character.

- [ ] **Step 2: Add a reusable sound-pool cleanup helper**

Add a helper that stops, destroys, and clears one pool:

```lua
local function destroySoundPool(sounds: { Sound }): ()
    for _, sound in sounds do
        sound:Stop()
        sound:Destroy()
    end
    table.clear(sounds)
end
```

Update `clearCharacter()` to call it for `universalSounds`, call it for every pool in `soundsByMaterial`, then clear `soundsByMaterial`. Keep the existing connection cleanup and state resets.

- [ ] **Step 3: Generalize sound creation to accept an ID list and name prefix**

Change `createFootstepSounds` to accept `(rootPart: BasePart, soundIds: { string }, namePrefix: string)` and iterate the supplied list rather than reading `Config.soundIds` internally. Name instances with the prefix while preserving the existing numbered convention:

```lua
sound.Name = `{namePrefix}_{index}`
```

Keep all existing `Sound` property assignments exactly as they are. Use `Footstep` for the universal pool so its instances keep their current names (`Footstep_1`, `Footstep_2`, and so on). Use `Footstep_{material.Name}` for material-specific prefixes so future pools have distinct names.

- [ ] **Step 4: Create the universal and non-empty material pools during character setup**

After validating `rootPart` and `humanoid`, create the universal pool and each configured non-empty surface pool:

```lua
universalSounds = createFootstepSounds(rootPart, Config.soundIds, "Footstep")
for material, soundIds in Config.surfaceSounds do
    if #soundIds > 0 then
        soundsByMaterial[material] = createFootstepSounds(rootPart, soundIds, `Footstep_{material.Name}`)
    end
end
```

Do not create a `Sound` for an empty material entry. Because `surfaceSounds` is initially empty, setup creates only the current universal sounds.

- [ ] **Step 5: Make selection accept the pool being played**

Change `chooseSound` to receive a sound array. Preserve the current behavior exactly: return `nil` for an empty array, return the sole sound when there is one, and otherwise exclude `lastSound` from candidates.

Change `playFootstep` to receive the selected pool and retain the current `lastSound`, randomized `PlaybackSpeed`, randomized `Volume`, and `sound:Play()` operations.

- [ ] **Step 6: Add material lookup with universal fallback**

Add a helper with this behavior:

```lua
local function soundsForMaterial(material: Enum.Material): { Sound }
    local surfaceSounds = soundsByMaterial[material]
    if surfaceSounds ~= nil and #surfaceSounds > 0 then
        return surfaceSounds
    end
    return universalSounds
end
```

An absent or empty material-specific pool must return `universalSounds`.

- [ ] **Step 7: Use the selected pool in the render update**

Update `update(deltaTime)` as follows:

1. Keep the existing early return for `not started` or no active humanoid.
2. Keep resetting the timer for movement below the threshold or `Enum.Material.Air`.
3. Resolve `local sounds = soundsForMaterial(activeHumanoid.FloorMaterial)`.
4. If `#sounds == 0`, reset `timeSinceLastStep` and return.
5. Preserve the existing interval calculation and timer accumulation.
6. Call `playFootstep(sounds)` when the interval elapses.

This permits a future specific pool to work even if the universal list is empty, while still producing no sound when neither pool has IDs.

- [ ] **Step 8: Check lifecycle references after the refactor**

Search the controller for `activeSounds` and remove every remaining reference. Confirm that `clearCharacter()` destroys both the universal pool and every material pool before resetting `lastSound`.

Run:

```bash
git diff --check
```

Expected: no whitespace errors and no remaining `activeSounds` references.

---

### Task 3: Static and Runtime Verification

**Files:**
- Verify: `src/client/player/FootstepConfig.luau`
- Verify: `src/client/player/FootstepController.luau`
- Verify: generated `test-sourcemap.json` if created by the typecheck workflow; do not manually edit it.

**Interfaces:**
- Verifies the existing controller behavior with an empty `surfaceSounds` map.
- Verifies future material lookup behavior through the typed implementation without introducing new audio assets.

- [ ] **Step 1: Run Roblox lint for production and existing tests**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Expected: both commands exit successfully with no new diagnostics.

- [ ] **Step 2: Generate the test sourcemap**

Run:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Expected: Rojo generates the sourcemap successfully and includes `src/client/player` through the test project mapping.

- [ ] **Step 3: Run the repository Roblox typecheck**

Run:

```bash
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Expected: the new `Enum.Material` map type and controller changes produce no type errors.

- [ ] **Step 4: Build both Rojo projects**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: both builds complete successfully. The production build must still contain the existing local footstep controller and config.

- [ ] **Step 5: Run a clean Roblox Studio smoke test**

In the default game place, start a clean Play session and verify:

- The local character creates the same current universal footstep sounds as before.
- No material-specific sounds are created because `surfaceSounds = {}`.
- Walking on a non-air material still uses the universal pool.
- Standing still and being airborne still produce no steps.
- Respawning does not leave old `Footstep_*` sound instances or connections behind.
- The Output window has no errors.

Do not add temporary material IDs to the committed configuration. Future material-specific audio can be smoke-tested later by adding an actual approved ID under an `Enum.Material` key.
