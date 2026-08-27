# Cinematic Letterbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add responsive, smoothly animated cinematic letterboxing that hides the game's main UI while any client cinematic is playing.

**Architecture:** Add a focused `CinematicLetterbox` controller that owns a high-priority `ScreenGui`, calculates `2.39:1` bars from the current viewport, and toggles `DungeonGui`. Inject it optionally into `CinematicController`, which calls it at the existing `playing` and cleanup boundaries. Compose the real instance in `init.client.luau` without changing React `App.luau`.

**Tech Stack:** Strict Luau, Roblox `ScreenGui`/`Frame`, `TweenService`, `workspace.CurrentCamera.ViewportSize`, existing client cinematic lifecycle, Rojo and Selene.

## Global Constraints

- Keep the feature client-only; do not add remotes or server mutations.
- Keep the letterbox target proportion at `2.39:1`.
- Use two black `Frame` instances in a dedicated `ScreenGui` with high `DisplayOrder` and `IgnoreGuiInset = true`.
- Use `TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)` for enter, resize and exit transitions.
- Hide `DungeonGui` during the cinematic and restore its previous `Enabled` value after the exit tween completes.
- Make show/hide lifecycle operations idempotent and invalidate stale tween callbacks with a transition generation.
- Treat letterbox errors as non-fatal; cinematic camera, movement and sound cleanup must still run.
- Keep the letterbox dependency optional in `CinematicController` so existing non-UI callers remain valid.
- Do not modify `src/client/ui/App.luau`, timelines, server code or unit tests.
- Preserve unrelated pre-existing worktree changes, including the current cinematic model-profile changes.
- Do not run `git add`, `git commit`, `git amend` or other commit actions.

---

## File Map

- Create `src/client/cinematics/CinematicLetterbox.luau`: owns the overlay instances, aspect-ratio calculation, tween cancellation, and `DungeonGui` visibility restoration.
- Modify `src/client/cinematics/CinematicController.luau`: add the optional visual dependency and invoke it at playing/cleanup boundaries.
- Modify `src/client/init.client.luau`: create the letterbox with the local `PlayerGui` and inject it into the cinematic controller.
- Do not modify `src/client/ui/App.luau` or any test path.

## Task 1: Build the Letterbox Controller

**Files:**

- Create: `src/client/cinematics/CinematicLetterbox.luau`

**Interfaces:**

- Consumes: `playerGui: Instance` from the composition root and `workspace.CurrentCamera.ViewportSize`.
- Produces: `CinematicLetterbox.new({ playerGui = playerGui })`, `letterbox:show() -> ()`, and `letterbox:hide() -> ()`.

- [ ] **Step 1: Create the strict module and instance contract**

Start the module with `--!strict`, require `TweenService`, `Workspace`, and export this contract:

```luau
export type Dependencies = {
    playerGui: Instance,
}

export type CinematicLetterbox = {
    playerGui: Instance,
    gui: ScreenGui,
    topBar: Frame,
    bottomBar: Frame,
    targetGui: ScreenGui?,
    previousTargetEnabled: boolean?,
    active: boolean,
    transitionId: number,
    topTween: Tween?,
    bottomTween: Tween?,
    show: (self: CinematicLetterbox) -> (),
    hide: (self: CinematicLetterbox) -> (),
}
```

Use `CinematicLetterbox.__index = CinematicLetterbox` and keep all mutable state in `new()`.

- [ ] **Step 2: Create the dedicated overlay instances**

In `CinematicLetterbox.new(dependencies)`, create and parent one `ScreenGui` to `dependencies.playerGui` with these properties:

```luau
gui.Name = "CinematicLetterboxGui"
gui.DisplayOrder = 1000
```

Create two borderless black `Frame`s as children of that GUI. Configure the top bar with `Position = UDim2.fromScale(0, 0)` and `AnchorPoint = Vector2.zero`; configure the bottom bar with `Position = UDim2.fromScale(0, 1)` and `AnchorPoint = Vector2.new(0, 1)`. Both bars start at `Size = UDim2.fromScale(1, 0)`, use `BackgroundColor3 = Color3.new(0, 0, 0)`, `BackgroundTransparency = 0`, and `BorderSizePixel = 0`.

Return the initialized instance with `targetGui = nil`, `previousTargetEnabled = nil`, `active = false`, `transitionId = 0`, and both tween fields set to `nil`.

- [ ] **Step 3: Implement responsive bar sizing**

Define:

```luau
local CINEMATIC_ASPECT_RATIO = 2.39
local MAX_BAR_SCALE = 0.45
```

Implement `getBarScale()` using the current camera. If the camera or its height is unavailable, return the `16:9` fallback scale `(1 - (16 / 9) / 2.39) / 2`. Otherwise compute:

```luau
local viewportAspect = viewportSize.X / viewportSize.Y
local visibleHeightScale = math.min(1, viewportAspect / CINEMATIC_ASPECT_RATIO)
return math.clamp((1 - visibleHeightScale) / 2, 0, MAX_BAR_SCALE)
```

Create `tweenBars(self, barScale, transitionId)` that cancels any existing `topTween` and `bottomTween`, creates simultaneous `TweenService:Create` calls for `Size = UDim2.fromScale(1, barScale)` on the top and bottom bars, and stores both returned tweens.

- [ ] **Step 4: Implement `show()` and `hide()` lifecycle**

`show()` must increment `transitionId`, set `active = true`, enable the dedicated GUI, resolve `playerGui:FindFirstChild("DungeonGui")` as a `ScreenGui`, store its current `Enabled` value only when beginning a new active cycle, set it to `false`, and call `tweenBars(self, getBarScale(), transitionId)`.

`hide()` must safely return only when the dedicated GUI is already disabled and no active transition needs finishing. Otherwise increment `transitionId`, set `active = false`, tween both bars to `UDim2.fromScale(1, 0)`, and attach a completion callback to the bottom tween. The callback may disable the dedicated GUI and restore `targetGui.Enabled = previousTargetEnabled` only when the tween state is `Enum.PlaybackState.Completed` and its captured transition ID still equals `self.transitionId`. Clear the stored target and previous value after restoration.

Wrap property restoration in `pcall` and emit a warning if Roblox rejects it. A callback from a canceled or superseded tween must not re-enable `DungeonGui`.

- [ ] **Step 5: Handle viewport changes while active**

In `new()`, if `Workspace.CurrentCamera` exists, connect its `ViewportSize` property change signal. While `self.active` is true, call `tweenBars(self, getBarScale(), self.transitionId)` using the current transition ID. Do not start a second render loop. Keep the connection for the session because the letterbox instance is owned by the client composition root.

- [ ] **Step 6: Run production lint for the new module**

Run:

```bash
selene --config selene.roblox.toml src/client/cinematics/CinematicLetterbox.luau
```

Expected: exit status `0` with no diagnostics.

## Task 2: Integrate Letterboxing With Cinematic Lifecycle

**Files:**

- Modify: `src/client/cinematics/CinematicController.luau:1-565`

**Interfaces:**

- Consumes: `CinematicLetterbox.CinematicLetterbox?` as an optional `Dependencies.letterbox` field.
- Produces: automatic `show()` before the first effect and `hide()` on every normal, interrupted, failed or explicit-stop cleanup path.

- [ ] **Step 1: Add the optional dependency type**

Require `script.Parent.CinematicLetterbox` for its exported type and add this field without changing the existing dependencies:

```luau
export type Dependencies = {
    camera: CameraController.CameraController,
    movement: TankController.MovementController,
    sound: CinematicSoundPlayer.CinematicSoundPlayer,
    letterbox: CinematicLetterbox.CinematicLetterbox?,
}
```

Keep the field optional so current callers that provide only camera, movement and sound still construct the controller.

- [ ] **Step 2: Add non-fatal visual transition helpers**

Add helpers that read `self.dependencies.letterbox`, do nothing when it is `nil`, and wrap each method call in `pcall`:

```luau
local function showLetterbox(self: Controller): ()
    local letterbox = self.dependencies.letterbox
    if letterbox == nil then
        return
    end
    local ok, errorMessage = pcall(function()
        letterbox:show()
    end)
    if not ok then
        warn("CinematicController letterbox show failed: " .. tostring(errorMessage))
    end
end

local function hideLetterbox(self: Controller): ()
    local letterbox = self.dependencies.letterbox
    if letterbox == nil then
        return
    end
    local ok, errorMessage = pcall(function()
        letterbox:hide()
    end)
    if not ok then
        warn("CinematicController letterbox hide failed: " .. tostring(errorMessage))
    end
end
```

- [ ] **Step 3: Start the letterbox only after preload and movement acquisition**

In `runExecution()`, immediately after `self.movementRelease = release` and `self.state = "playing"`, call `showLetterbox(self)`. Keep it before the `for _, step in timeline` loop so the first effect starts while the bars enter. Do not call it during `preload()` or while the automatic preload is still running.

- [ ] **Step 4: Cover every cleanup path**

Call `hideLetterbox(self)` from `finishNormally`, `finishInterrupted`, `finishWithoutEffects`, and `stop()`. The call must not replace existing `clearCamera`, `stopSound`, or movement-release behavior. Preserve the current rule that normal completion does not stop one-shot sounds still playing, while interrupted and failed paths do stop their execution sounds.

The cleanup functions must mark the execution inactive before starting visual cleanup, so an old worker cannot trigger a second hide. `hide()` itself remains idempotent and performs the delayed `DungeonGui` restoration after the exit tween.

- [ ] **Step 5: Run production lint for the integration**

Run:

```bash
selene --config selene.roblox.toml src/client/cinematics/CinematicController.luau
```

Expected: exit status `0` with no diagnostics.

## Task 3: Compose the Runtime Dependency

**Files:**

- Modify: `src/client/init.client.luau:3-112`

**Interfaces:**

- Consumes: the local `PlayerGui` and the existing `CinematicController.new()` composition.
- Produces: one `CinematicLetterbox` instance injected into the runtime cinematic controller.

- [ ] **Step 1: Require the new module**

Add:

```luau
local CinematicLetterbox = require(script.cinematics.CinematicLetterbox)
```

next to the existing cinematic module requires.

- [ ] **Step 2: Resolve `PlayerGui` before constructing the cinematic controller**

Move the existing `local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")` declaration to before the cinematic controller construction, keeping a single declaration for the later React root. Do not change the `App` props or its rendering logic.

- [ ] **Step 3: Create and inject the visual dependency**

Construct the visual controller and add it to the existing dependencies:

```luau
local cinematicLetterbox = CinematicLetterbox.new({
    playerGui = playerGui,
})

local cinematicController = CinematicController.new({
    camera = cameraController,
    movement = tankController,
    sound = cinematicSoundPlayer,
    letterbox = cinematicLetterbox,
})
```

Keep the `ScreenGui` creation client-side and do not add any server-side object or remote. Reuse the same `playerGui` variable when calling `ReactRoblox.createRoot(playerGui)`.

- [ ] **Step 4: Build the production project**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
```

Expected: exit status `0` and a valid Roblox place build containing the updated client cinematic folder.

## Task 4: Verify Runtime Behavior Without Unit Test Changes

**Files:**

- Inspect only: `src/client/cinematics/CinematicLetterbox.luau`, `src/client/cinematics/CinematicController.luau`, `src/client/init.client.luau`

- [ ] **Step 1: Run complete production lint**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: exit status `0` with no diagnostics.

- [ ] **Step 2: Check the final diff for whitespace errors**

Run:

```bash
git diff --check
```

Expected: no output. Confirm that no test file, `App.luau`, server file or unrelated pre-existing change was modified.

- [ ] **Step 3: Run a clean Roblox Studio visual check**

Use the connected Studio session in Edit mode, start Play, and trigger the existing Machine Room cinematic through its normal gameplay condition. Confirm all of the following in the running client:

1. Bars expand smoothly from the top and bottom when the cinematic enters `playing`.
2. The inventory, objectives, pickup notification and dialogue UI are hidden while the bars are active.
3. The camera shots and cinematic effects continue while the bars animate.
4. Bars retract smoothly after the final timeline step and `DungeonGui` returns to its prior enabled state.
5. Stop the cinematic during playback and confirm movement/camera cleanup still occurs while the bars exit.
6. Repeat after a viewport resize or orientation change and confirm the bars recalculate without a second render loop.

Do not open, edit or add unit-test files during this verification.

- [ ] **Step 4: Report verification results without committing**

Report the three production files changed, the lint/build commands and their exit status, the Studio visual observations, and any residual warning. Leave all changes unstaged for user review.
