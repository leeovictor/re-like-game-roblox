# Client Cinematic System Implementation Plan

> **For inline execution:** execute exactly one task at a time, run its
> verification, report the result, and stop for user review before starting
> the next task. Do not create commits; the user will review and commit the
> changes manually.

**Goal:** Implement a client-only sequential cinematic executor with camera
shot overrides, automatic movement restoration, local one-shot audio, and
explicit/manual audio preloading.

**Architecture:** A `CinematicController` owns validation, lifecycle,
generation-based cancellation, sequential scheduling, and effect dispatch. A
`CinematicSoundPlayer` owns local sound templates, preload caching, and
execution-scoped playback instances. The existing `CameraController` remains
the only `PreRender` owner and receives a temporary cinematic override.

**Tech Stack:** Strict Luau, Roblox Studio DataModel, `RunService.PreRender`,
`ContentProvider:PreloadAsync`, TestEZ, Rojo 7.7.0, Selene 0.29.0 and
`luau-lsp` 1.69.0.

## Global Constraints

- Execute in inline mode and stop after every task checkpoint for user review.
- Do not run `git commit`, `git add`, `git amend`, or any other commit action.
- Preserve the unrelated existing modification in `src/client/ui/App.luau`.
- Keep all production modules and specs under `--!strict`.
- Keep the feature client-only; do not add remotes or server mutations.
- Use the existing `CameraController` `PreRender` connection; do not add a
  second camera render loop.
- Keep `set-model-profile` and `change-door-state` out of the initial effect
  registry.
- Keep `set-camera-shot` instantaneous and reference existing camera shot IDs.
- Keep `play-sound` limited to normalized `rbxassetid://<number>` IDs and
  default one-shot playback.
- Do not add UI code or UI specs.
- Use real DataModel imports in TestEZ specs; do not add filesystem or virtual
  module indirection.
- Destroy every fixture Instance and disconnect every fixture connection in
  `afterEach`.
- Re-sync or restart the test Play session after changing scripts used by
  TestEZ.
- Generated `Packages/` and `DevPackages/` remain untouched.
- After each task, report the files changed, verification performed and any
  remaining issue, then stop for user review.

## File Map

### Camera integration

- Modify `src/client/camera/CameraController.luau` to separate the gameplay
  shot from the applied shot and expose the temporary cinematic override.
- Extend `tests/client/camera/CameraController.spec.luau` with override and
  restoration behavior.

### Movement integration

- Modify `src/client/player/TankController.luau` to support idempotent scoped
  movement locks while retaining the existing manual movement API.
- Modify `src/client/dialogue/DialogueController.luau` so dialog ownership uses
  the same scoped lock instead of releasing a shared boolean blindly.
- Extend `tests/client/player/TankController.spec.luau` and
  `tests/client/dialogue/DialogueController.spec.luau` with coexistence cases.

### Audio and timeline runtime

- Create `src/client/cinematics/CinematicSoundPlayer.luau` for local template
  caching, `ContentProvider` preload and execution-scoped one-shots.
- Create `src/client/cinematics/CinematicController.luau` for timeline
  validation, state transitions, effect handlers and cleanup.
- Create `tests/client/cinematics/CinematicSoundPlayer.spec.luau`.
- Create `tests/client/cinematics/CinematicController.spec.luau`.

### Composition and test mapping

- Modify `src/client/init.client.luau` to configure the default cinematic
  controller after the real camera and movement controllers exist.
- Modify `test.project.json` to map the new production and test cinematic
  folders.

## Task 1: Add Camera Cinematic Override

**Files:**

- Modify: `src/client/camera/CameraController.luau:13-129`
- Test: `tests/client/camera/CameraController.spec.luau:37-110`

**Interfaces:**

- Consumes: existing `CameraConfig.Config`, `CameraResolver`, and the current
  player-position resolution behavior.
- Produces: `hasShot(shotId) -> boolean`,
  `setCinematicShot(shotId) -> boolean`, and
  `clearCinematicShot() -> ()` on each camera controller instance.
- Preserves: `start()`, `stop()`, `getCurrentShotId()`, zone resolution,
  `Focus`, `CFrame`, `FieldOfView`, and the last gameplay shot outside zones.

- [ ] **Step 1: Add failing camera override specs**

Add these cases to the existing `CameraController` suite. The first case must
prove that the override survives the next `PreRender`; the second must prove
that clearing it restores the gameplay shot rather than the cinematic shot.

```lua
it("mantem o shot cinematic durante o PreRender", function()
		expect(controller:setCinematicShot("First")).to.equal(true)

		RunService.PreRender:Wait()
		task.wait()

		expect(controller:getCurrentShotId()).to.equal("First")
		expect(camera.CFrame).to.equal(CFrame.new(0, 10, 20))
		expect(camera.FieldOfView).to.equal(65)
end)

it("restaura o shot normal atual ao limpar o override", function()
		rootPart.CFrame = CFrame.new()
		expect(waitFor(function()
			return controller:getCurrentShotId() == "First"
		end)).to.equal(true)

		expect(controller:setCinematicShot("Default")).to.equal(true)
		RunService.PreRender:Wait()
		expect(controller:getCurrentShotId()).to.equal("Default")

		controller:clearCinematicShot()
		RunService.PreRender:Wait()
		task.wait()

		expect(controller:getCurrentShotId()).to.equal("First")
		expect(camera.CFrame).to.equal(CFrame.new(0, 10, 20))
		expect(camera.FieldOfView).to.equal(65)
end)
```

- [ ] **Step 2: Run the camera specs and verify they fail**

Restart the `RE Like Test` Play session so the current scripts are loaded, then
run the client TestEZ runner:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Expected result: the existing camera tests remain available, while the new
cases fail because `setCinematicShot` and `clearCinematicShot` do not yet
exist.

- [ ] **Step 3: Implement the override inside CameraController**

Add `playerShotId` and `cinematicShotId` to the controller state and extend the
exported instance type with the three camera methods. Refactor `update()` so it
performs these operations in this order:

```lua
local zoneShotId = self.resolver:resolve(position)
if zoneShotId ~= nil then
	self.playerShotId = zoneShotId
elseif self.playerShotId == nil then
	self.playerShotId = self.config.defaultShotId
end

local desiredShotId = self.cinematicShotId or self.playerShotId
```

Keep the existing shot lookup and only-when-changed application logic, but
compare the effective shot with `currentShotId`. Implement
`setCinematicShot()` by validating `self.config.shots[shotId]`, storing the
override and calling the existing update path. Return `false` for an unknown
shot. Implement `clearCinematicShot()` by setting the override to `nil` and
running the same update path. Reset both new fields in `stop()`.

Do not assign a cinematic ID to `playerShotId`; if the player enters a zone
while the override is active, update the gameplay state so clearing the
override restores the current gameplay shot.

- [ ] **Step 4: Run the camera specs and verify they pass**

Run the same client TestEZ runner in a clean Play session. Expected result:
`failed == 0`, including both new camera cases and the existing camera suite.

- [ ] **Step 5: Checkpoint and stop**

Report the camera files changed and the structured TestEZ result. Do not begin
Task 2 until the user reviews this task.

## Task 2: Add Scoped Movement Locks

**Files:**

- Modify: `src/client/player/TankController.luau:26-293`
- Modify: `src/client/dialogue/DialogueController.luau:45-299`
- Test: `tests/client/player/TankController.spec.luau:10-65`
- Test: `tests/client/dialogue/DialogueController.spec.luau:18-115`

**Interfaces:**

- Consumes: the existing `TankController.start()`, `stop()`, input bindings
  and `setMovementEnabled()` behavior.
- Produces: `TankController.acquireMovementLock() -> (() -> ())`; the returned
  release function is idempotent.
- Dialogue integration: an active dialog owns one release function and releases
  it on close, replacement and stop.

- [ ] **Step 1: Add failing lock behavior specs**

Keep the current binding tests and add a test that drives the existing forward
action callback through `ContextActionService:GetAllBoundActionInfo()`. The
test must verify that two locks block movement, releasing one still blocks it,
and releasing the second permits a newly pressed forward action.

```lua
local function invokeForward(inputState: Enum.UserInputState)
	local info = (ContextActionService:GetAllBoundActionInfo() :: any).DungeonTankForward
	expect(info).to.be.ok()
	(info.function :: any)("DungeonTankForward", inputState, nil)
end

it("mantem o movimento bloqueado enquanto qualquer lock estiver ativo", function()
	local firstRelease = TankController.acquireMovementLock()
	local secondRelease = TankController.acquireMovementLock()

	invokeForward(Enum.UserInputState.Begin)
	RunService.PreRender:Wait()
	expect(humanoid.MoveDirection).to.equal(Vector3.zero)

	firstRelease()
	invokeForward(Enum.UserInputState.Begin)
	RunService.PreRender:Wait()
	expect(humanoid.MoveDirection).to.equal(Vector3.zero)

	secondRelease()
	invokeForward(Enum.UserInputState.Begin)
	RunService.PreRender:Wait()
	expect(humanoid.MoveDirection.Magnitude).to.be.greaterThan(0)

	firstRelease()
	secondRelease()
end)
```

Add a dialogue regression case that acquires a separate lock, opens and closes
a dialog, and confirms through the same movement probe that closing the dialog
does not release the other owner's lock.

- [ ] **Step 2: Run the movement and dialogue specs and verify the new cases fail**

Run the client TestEZ runner in a clean Play session. Expected result: the
existing suites load, but the new lock cases fail because the scoped lock API
does not yet exist.

- [ ] **Step 3: Implement owner-safe movement locking**

Add a lock count and a monotonically increasing lock generation to
`TankController`. `acquireMovementLock()` must increment the count, reset
input state, and return a closure that can decrement the count only once and
only for the generation in which it was acquired. Make the movement update and
input callbacks treat `lockCount > 0` as disabled movement. Keep
`setMovementEnabled()` as the existing manual state and combine it with the
lock state instead of deleting it.

Update `DialogueController` with a `movementRelease` field. Replace its direct
movement toggles with this lifecycle:

```lua
movementRelease = TankController.acquireMovementLock()
```

Call and clear that release function in `closeCurrent()` before invoking the
dialog callback. Ensure replacement, cancellation and `stop()` all pass
through `closeCurrent()` or explicitly release the stored lock. Do not release
another system's lock.

- [ ] **Step 4: Run the movement and dialogue specs and verify they pass**

Run the client TestEZ runner again. Expected result: `failed == 0` for the
existing movement/dialogue tests and the new coexistence cases.

- [ ] **Step 5: Checkpoint and stop**

Report the lock lifecycle and TestEZ result. Do not begin Task 3 until the user
reviews this task.

## Task 3: Implement Local Sound Preload and One-Shots

**Files:**

- Create: `src/client/cinematics/CinematicSoundPlayer.luau`
- Test: `tests/client/cinematics/CinematicSoundPlayer.spec.luau`
- Modify: `test.project.json:57-103` to map `src/client/cinematics` and
  `tests/client/cinematics` before running the new spec.

**Interfaces:**

- Consumes: normalized sound IDs and an execution ID.
- Produces: `new(dependencies)`, `preload(soundIds) -> boolean`,
  `play(soundId, executionId) -> ()`, and `stop(executionId) -> ()`.
- Default dependencies: `SoundService`, `ContentProvider`, and
  `ContentProvider:PreloadAsync()`.
- Test dependency seam: injectable preload function, loaded predicate and
  parent folder so specs do not depend on an external audio asset.

- [ ] **Step 1: Add failing sound player specs**

Create the new spec with a real temporary folder for created sounds and fake
preload dependencies. The first test verifies deduplication and caching. The
second verifies that playback instances are grouped by execution and that
stopping one execution does not destroy another execution's instance.

```lua
local preloadCalls = 0
local player = CinematicSoundPlayer.new({
	parent = soundFolder,
	preloadAsync = function(_sounds: { Sound })
		preloadCalls += 1
	end,
	isLoaded = function(_sound: Sound): boolean
		return true
	end,
})

expect(player:preload({ "rbxassetid://10", "rbxassetid://10" })).to.equal(true)
expect(preloadCalls).to.equal(1)
expect(player:preload({ "rbxassetid://10" })).to.equal(true)
expect(preloadCalls).to.equal(1)

player:play("rbxassetid://10", 1)
player:play("rbxassetid://10", 2)
expect(player:getActiveCount(1)).to.equal(1)
expect(player:getActiveCount(2)).to.equal(1)

player:stop(1)
expect(player:getActiveCount(1)).to.equal(0)
expect(player:getActiveCount(2)).to.equal(1)
```

The `getActiveCount(executionId)` method is a read-only inspection method on
the sound player, used to make lifecycle tests deterministic; it does not
control playback.

Add the permanent mappings before running the new spec. Under
`StarterPlayer.StarterPlayerScripts.Client`, place this sibling of `camera`:

```json
"cinematics": {
  "$path": "src/client/cinematics"
}
```

Under `StarterPlayer.StarterPlayerScripts.TestEZTests.Client`, add:

```json
"cinematics": {
  "$path": "tests/client/cinematics"
}
```

- [ ] **Step 2: Run the sound player spec and verify it fails**

After adding the permanent client production and spec mappings to
`test.project.json`, restart the test Play session and run:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Expected result: the new sound player cases fail because the module and its
cache do not yet exist.

- [ ] **Step 3: Implement the sound player**

Create a local template folder under the supplied parent. For each unique ID,
create one non-looped `Sound`, assign the ID exactly as received, and keep it
in a dictionary keyed by `soundId`. Call `ContentProvider:PreloadAsync()` only
for missing templates. Wrap the call with `pcall`, verify every template with
the injected/default loaded predicate, and return `false` with a warning when
preparation fails.

For `play(soundId, executionId)`, clone the prepared template, set
`Looped = false`, parent it locally, add it to the execution's active list and
call `Sound:Play()`. Connect `Ended` to remove and destroy the instance. For
`stop(executionId)`, stop and destroy only that execution's active instances.
Keep templates in the cache after playback ends. Make removal idempotent so an
`Ended` callback after explicit stop cannot remove a different instance.

- [ ] **Step 4: Run the sound player spec and verify it passes**

Run the client TestEZ runner. Expected result: the sound player cases pass with
no external asset dependency and all fixture instances are destroyed.

- [ ] **Step 5: Checkpoint and stop**

Report the cache/preload behavior and TestEZ result. Do not begin Task 4 until
the user reviews this task.

## Task 4: Implement the Sequential Cinematic Controller

**Files:**

- Create: `src/client/cinematics/CinematicController.luau`
- Create: `tests/client/cinematics/CinematicController.spec.luau`

**Interfaces:**

- Consumes: camera methods `hasShot`, `setCinematicShot` and
  `clearCinematicShot`; movement method `acquireMovementLock`; sound methods
  `preload`, `play` and `stop`; and an injected `wait(duration)` function.
- Produces: `new(dependencies)`, module-level `configure(dependencies)`,
  `preload(timeline) -> boolean`, `play(timeline) -> boolean`, `stop() -> ()`,
  and `isPlaying() -> boolean`.
- Timeline fields: `frame: number`, `duration: number`, and
  `effects: { Effect }`.
- Supported effects: `set-camera-shot` with `{ shot: string }` and
  `play-sound` with `{ soundId: string }`.

- [ ] **Step 1: Add failing controller specs and isolated fakes**

Create fakes that record calls instead of touching the real camera, movement or
audio. Use a deterministic `wait` fake that records each duration. Add tests
for validation, effect order, automatic preload, busy rejection, normal
cleanup and generation cancellation.

```lua
local waited: { number } = {}
local calls: { string } = {}
local releasedLocks = 0
local preloaded: { { string } } = {}
local active = true

local dependencies = {
	camera = {
		hasShot = function(shotId: string): boolean
			return shotId == "Default" or shotId == "Generator"
		end,
		setCinematicShot = function(shotId: string): boolean
			table.insert(calls, "camera:" .. shotId)
			return true
		end,
		clearCinematicShot = function()
			table.insert(calls, "camera:clear")
		end,
	},
	movement = {
		acquireMovementLock = function(): () -> ()
			return function()
				releasedLocks += 1
			end
		end,
	},
	sound = {
		preload = function(soundIds: { string }): boolean
			table.insert(preloaded, soundIds)
			return true
		end,
		play = function(soundId: string, _executionId: number)
			table.insert(calls, "sound:" .. soundId)
		end,
		stop = function(_executionId: number)
			table.insert(calls, "sound:stop")
		end,
	},
	wait = function(duration: number)
		table.insert(waited, duration)
		while active do
			task.wait()
		end
	end,
}
```

Use a separate non-blocking wait fake for the normal order test so it can
assert that the calls occur as `sound`, `camera`, then cleanup, with the
durations recorded in the same sequence as the timeline. Use a blocking wait
fake for the `stop()` test and release it only after calling `stop()`.

- [ ] **Step 2: Run the cinematic specs and verify they fail**

Restart the test Play session and run the client TestEZ runner. Expected result:
the new controller cases fail because the module and validator do not exist.

- [ ] **Step 3: Implement timeline types and validation**

Define strict exported types for the two supported effects and the timeline,
but validate external tables through `any` before casting. Reject these cases
with a warning and `false`:

```text
timeline vazia
frame diferente do indice sequencial
frame nao inteiro ou nao finito
duration negativo ou nao finito
effects nao contiguo
campo desconhecido em etapa, efeito ou attributes
nome de efeito desconhecido
shot inexistente
soundId fora de ^rbxassetid://%d+$
```

Allow an empty `effects` list as a timed pause. Extract unique sound IDs during
validation so both `preload()` and `play()` use the same validated input.

- [ ] **Step 4: Implement controller state, registry and scheduling**

Use `idle`, `preloading` and `playing` as the internal states. Reserve a new
execution ID before automatic preload, and execute the worker in a spawned
task so `play()` returns `true` immediately after accepting the request.

The worker must follow this structure:

```lua
if not ensureCurrentGeneration(executionId) then
	return
end

if not sound.preload(soundIds) then
	finishWithoutEffects(executionId)
	return
end

local releaseMovement = movement.acquireMovementLock()
state = "playing"

for _, step in timeline do
	if not ensureCurrentGeneration(executionId) then
		return
	end

	for _, effect in step.effects do
		if not ensureCurrentGeneration(executionId) then
			return
		end
		executeEffect(effect, executionId)
	end

	wait(step.duration)
end

finishNormally(executionId, releaseMovement)
```

Use a local effect registry with exactly these handlers:

```lua
local effectHandlers = {
	["set-camera-shot"] = function(effect)
		return camera.setCinematicShot(effect.attributes.shot)
	end,
	["play-sound"] = function(effect, executionId)
		sound.play(effect.attributes.soundId, executionId)
	end,
}
```

The real implementation must use the validated typed fields rather than
trusting the raw table inside handlers. Wrap runtime handler execution in
`pcall`; on failure warn and perform interrupted cleanup.

`preload(timeline)` uses the same validator and sound cache while remaining in
`preloading`; it never acquires movement or camera state. `play(timeline)`
rejects all non-`idle` states, auto-preloads missing IDs, then acquires the
movement lock only after preload succeeds. `stop()` increments the generation,
sets the state to `idle`, releases the current movement lock if present,
clears the camera override and stops sounds for the current execution.

Normal completion clears the camera override and releases movement but does not
stop one-shot sounds that are still naturally playing. Interrupted and failed
executions stop only their own execution ID. Every cleanup path must be
idempotent.

- [ ] **Step 5: Run the cinematic specs and verify they pass**

Run the client TestEZ runner. Expected result: `failed == 0` for validation,
sequencing, preload, rejection, cancellation and cleanup cases.

- [ ] **Step 6: Checkpoint and stop**

Report the controller API, state behavior and TestEZ result. Do not begin Task
5 until the user reviews this task.

## Task 5: Configure the Runtime and Test Project

**Files:**

- Modify: `src/client/init.client.luau:3-57`

**Interfaces:**

- Consumes: the concrete `CameraController` instance created by `init`, the
  existing `TankController` module and `CinematicSoundPlayer.new()`.
- Produces: a configured module-level `CinematicController` available to every
  client module that requires its ModuleScript.

- [ ] **Step 1: Wire the default controller in `init.client.luau`**

Require `CinematicController` and `CinematicSoundPlayer` with the other client
controllers. After the existing camera controller has been created and
`TankController.start()` has run, configure the default cinematic controller:

```lua
local cinematicSoundPlayer = CinematicSoundPlayer.new()

CinematicController.configure({
	camera = {
		hasShot = function(shotId: string): boolean
			return controller:hasShot(shotId)
		end,
		setCinematicShot = function(shotId: string): boolean
			return controller:setCinematicShot(shotId)
		end,
		clearCinematicShot = function()
			controller:clearCinematicShot()
		end,
	},
	movement = TankController,
	sound = {
		preload = function(soundIds: { string }): boolean
			return cinematicSoundPlayer:preload(soundIds)
		end,
		play = function(soundId: string, executionId: number)
			cinematicSoundPlayer:play(soundId, executionId)
		end,
		stop = function(executionId: number)
			cinematicSoundPlayer:stop(executionId)
		end,
	},
	wait = task.wait,
})
```

Do not call `play()` from `init`; initialization only composes dependencies.
Do not add a server entrypoint or a remote to trigger cinematics.

- [ ] **Step 2: Verify the runtime composition with both Rojo projects**

The mappings for the production and test cinematic folders were added in Task
3. Rebuild both projects and inspect that the production build contains the
client cinematic folder while the test build contains both production modules
and specs without the normal `init.client.luau` entrypoint.

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected result: both builds complete successfully.

- [ ] **Step 3: Run the client suite and verify runtime composition**

Restart the test Play session after the entrypoint changes.
Run the client TestEZ runner and verify `failed == 0`. Confirm the normal
entrypoint does not create any server-side cinematic objects or remotes.

- [ ] **Step 4: Checkpoint and stop**

Report the runtime composition, project mapping and TestEZ result. Do not begin
Task 6 until the user reviews this task.

## Task 6: Run Complete Static and Studio Verification

**Files:**

- Inspect only: all files changed by Tasks 1-5
- Generated verification output: `test-sourcemap.json` may be refreshed by
  `rojo sourcemap`; do not edit generated package directories.

**Interfaces:**

- Consumes: completed client cinematic implementation and the existing server,
  shared and client test roots.
- Produces: verified clean lint, typecheck, Rojo builds and TestEZ Play results.

- [ ] **Step 1: Run production and test lint**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Expected result: both commands exit with status 0 and produce no diagnostics.

- [ ] **Step 2: Regenerate the test sourcemap and run Roblox typecheck**

Run the project-prescribed sourcemap command first:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Then run typecheck with the new cinematic directory included:

```bash
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/doors src/server/player \
  src/client/camera src/client/cinematics src/client/doors src/client/dialogue \
  src/client/interactions src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Expected result: no type diagnostics.

- [ ] **Step 3: Build both Rojo projects**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected result: both builds complete successfully. The production build must
contain the new client folder through the existing `src/client` mapping, and
the test build must contain the cinematic production and spec folders without
starting the normal production entrypoints.

- [ ] **Step 4: Run a clean server/client TestEZ Play session**

Use the `RE Like Test` Studio session. Stop Play, start a fresh Play session,
wait for `TestEZAutoServer` and `TestEZAutoClient`, and inspect the structured
server and client summaries. The required result is `failed == 0` in both
summaries. Inspect Output only for additional details.

Repeat the clean Play sequence a second time, stopping Play between runs, and
confirm that no cinematic fixtures, active sound instances or movement locks
remain after each run.

- [ ] **Step 5: Review final worktree without staging or committing**

Run:

```bash
git status --short
git diff --check
```

Confirm that the unrelated `src/client/ui/App.luau` modification remains
untouched, the cinematic files are present, and no commit or staging operation
was performed.

- [ ] **Step 6: Final checkpoint and stop**

Report every verification command, both TestEZ summaries and any residual
warning. Stop for the user's manual review and commit decision.
