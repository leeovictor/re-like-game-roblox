# Sealed Door State Implementation Plan

**Goal:** Add a client-authoritative `Sealed` door state that blocks unlocking and entering, supports model-authored dialogue, and exposes a validated API for other client systems to toggle it.

**Architecture:** Extend the existing door attribute contract instead of replacing `Locked`. `DoorManager` owns validation and the `isSealed`/`setSealed` API, while `DoorController` owns interaction feedback and dialogue. `DoorModelInitializer` creates the authored attribute and default dialogue folder; no new server service, remote, singleton, or composition change is needed.

**Tech Stack:** Strict Luau, Roblox Model attributes, CollectionService, existing DoorManager/DoorController, DialogueController, TestEZ project mappings, Rojo, Selene, and luau-lsp.

## Global Constraints

- Do not create, modify, rename, or delete any file under `tests/`, even if existing tests become stale or fail.
- Preserve the existing `Locked`, `RequiredItemId`, `LockedDialogue`, transition, movement-lock, sound, and gameplay-event behavior when `Sealed` is false.
- Treat a missing `Sealed` attribute as `false`; reject a present `Sealed` attribute with a non-boolean value as `invalid_config`.
- `Sealed = true` has precedence over `Locked` but never changes the `Locked` attribute.
- While sealed, `RequiredItemId` must still be a string but may be empty; a non-sealed locked door still requires a catalog item with capability `unlock`.
- `SealedDialogue` contains direct non-empty `StringValue` children sorted by `Name`; its fallback is `A porta esta selada.`.
- Reuse `door_blocked` after sealed dialogue completes; cancellation must not publish it.
- Keep door runtime client-authoritative and session-local. Do not add a RemoteFunction, RemoteEvent, server door service, or persistence.
- Expose state mutation through the injected `DoorManager` instance, not a hidden singleton or scattered direct attribute writes.
- Keep production modules `--!strict` and preserve imports based on the existing Rojo DataModel mapping.
- Do not create commits while implementing this plan, per repository instructions.

## Files And Responsibilities

- Modify `src/shared/doors/doorTypes.luau`: shared attribute names, fallback text, and failure reason.
- Modify `src/client/doors/DoorManager.luau`: validate, read, and mutate `Sealed`; reject sealed unlock/entry actions.
- Modify `src/client/doors/DoorController.luau`: route sealed interactions to `SealedDialogue` and handle stale-state `sealed` results.
- Modify `src/server/utils/DoorModelInitializer.luau`: author `Sealed = false` and create the default `SealedDialogue` folder.
- Do not modify `src/client/init.client.luau`: it already constructs and injects `DoorManager`.
- Do not modify `test.project.json`, runners, or any unit-test file.

### Task 1: Extend The Shared Door Contract

**Files:**
- Modify: `src/shared/doors/doorTypes.luau:5-14,26-35`
- Test: none; test files are explicitly out of scope.

**Interfaces:**
- Produces `doorTypes.SEALED_ATTRIBUTE`, `doorTypes.SEALED_DIALOGUE_NAME`, and `doorTypes.FALLBACK_SEALED_MESSAGE` for production consumers.
- Extends `doorTypes.DoorFailureReason` with the exact literal `"sealed"`.

- [ ] Add `| "sealed"` to `DoorFailureReason` without removing or renaming existing reasons.
- [ ] Add the constants with these exact values:

```luau
SEALED_DIALOGUE_NAME = "SealedDialogue",
SEALED_ATTRIBUTE = "Sealed",
FALLBACK_SEALED_MESSAGE = "A porta esta selada.",
```

- [ ] Keep `DoorAction` limited to `"unlock" | "enter"`; changing a door state is not a door action result.
- [ ] Run the production lint command from Task 5 after the dependent modules are updated.

### Task 2: Add Sealed State Validation And Mutation To DoorManager

**Files:**
- Modify: `src/client/doors/DoorManager.luau:17-25,60-83,94-195`
- Test: none; do not update the existing DoorManager spec.

**Interfaces:**
- Consumes the constants and failure reason from Task 1.
- Produces these methods on `DoorManager.DoorManager`:

```luau
isSealed: (self: DoorManager, door: Model) -> (boolean?, doorTypes.DoorFailureReason?),
setSealed: (self: DoorManager, door: Model, sealed: boolean) -> (boolean, doorTypes.DoorFailureReason?),
```

- [ ] Extend the internal `validateDoor` return tuple with the normalized sealed value. Preserve the current structural validation order for model, tag, interaction type, `Doorway`, and `Center`.
- [ ] Read `door:GetAttribute(doorTypes.SEALED_ATTRIBUTE)` after the existing door attributes. Normalize `nil` to `false`; return `invalid_config` for any other non-boolean value.
- [ ] Keep `RequiredItemId` required as a string. Change the capability/catalog validation so it runs only when `locked == true and sealed == false`; a sealed door may use an empty `RequiredItemId` because no unlock is possible.
- [ ] Update every existing `validateDoor` destructuring site so `isLocked`, `unlock`, and `enter` continue receiving the correct values.
- [ ] Implement `manager:isSealed(door)` by validating the door and returning `sealed, nil`, or `nil, validationFailure.reason`.
- [ ] Implement `manager:setSealed(door, sealed)` with these exact behaviors:
  - return `false, "invalid_config"` if the runtime value is not boolean;
  - validate the door before mutating it;
  - call `door:SetAttribute(doorTypes.SEALED_ATTRIBUTE, sealed)` only after validation;
  - return `true, nil` on success, including when the value is already equal;
  - wrap the attribute write in `pcall` and return `false, "invalid_door"` if the write raises.
- [ ] In `manager:unlock`, return `failure("sealed")` immediately after successful structural validation and before `CharacterRoot.get()`, distance checks, or inventory access when `sealed` is true.
- [ ] In `manager:enter`, return `failure("sealed")` at the same point, before obtaining or moving the character root.
- [ ] Leave the existing per-door busy lock behavior, spatial checks, inventory preservation, local `Locked = false` mutation, and opposite-side teleport logic unchanged.
- [ ] Confirm the manager has no new connections, tasks, remotes, or global mutable state.

### Task 3: Route Sealed Interactions Through DoorController

**Files:**
- Modify: `src/client/doors/DoorController.luau:32-85,89-167`
- Test: none; do not update `tests/client/doors/DoorController.spec.luau`.

**Interfaces:**
- Consumes `SEALED_DIALOGUE_NAME`, `FALLBACK_SEALED_MESSAGE`, and `"sealed"` from Task 1.
- Consumes the `isSealed`, `isLocked`, `unlock`, and `enter` methods from the manager contract in Task 2; state-changing systems call `setSealed` directly through their injected manager dependency.
- Produces no new controller lifecycle or input API.

- [ ] Extract the existing ordered `StringValue` dialogue traversal into one local helper with this shape:

```luau
showDoorDialogue(
    door: Model,
    folderName: string,
    fallback: string,
    onCompleted: () -> ()
)
```

- [ ] Preserve the current helper semantics: read only direct `StringValue` children, ignore empty values, sort by `Name`, advance only on callback reason `"completed"`, and stop without invoking `onCompleted` for cancellation.
- [ ] Replace the locked-only helper with a wrapper or call site using `doorTypes.LOCKED_DIALOGUE_NAME` and `doorTypes.FALLBACK_LOCKED_MESSAGE`.
- [ ] Add an equivalent sealed path using `doorTypes.SEALED_DIALOGUE_NAME` and `doorTypes.FALLBACK_SEALED_MESSAGE`.
- [ ] At the start of `controller.interact`, after confirming the target is a `Model`, call `manager:isSealed(door)`. Return silently for a validation error. If sealed, play the existing `locked` one-shot, show sealed dialogue, publish `door_blocked` only from the completion callback, and return without calling `isLocked`, `unlock`, `enter`, or `transition.run`.
- [ ] Keep the existing non-sealed branch order and behavior: `isLocked`, transition-based `enter` for open doors, and `unlock` for locked doors.
- [ ] Handle `result.reason == "sealed"` from both manager operations. If a state change races with the initial `isSealed` read, clear/reveal the transition through the existing callback flow and show `SealedDialogue`; never publish `door_entered`, never unlock, and never move the character.
- [ ] Keep `door_blocked` publication dependent on a valid `DoorKey` and on dialogue completion, using the existing warning behavior for missing keys.
- [ ] Keep the existing success unlock dialogue, `modelProfiles.setProfile`, movement lock, transition sounds, and gameplay events unchanged.
- [ ] Do not add direct `SetAttribute` calls, inventory lookups, remotes, or input bindings to the controller.

### Task 4: Update DoorModelInitializer Authoring Output

**Files:**
- Modify: `src/server/utils/DoorModelInitializer.luau:12-15,61-76,86-108`
- Test: none; no initializer or unit-test fixture changes are allowed.

**Interfaces:**
- Consumes the shared names and fallback text from Task 1.
- Produces authored door models with an explicit `Sealed` attribute and a default `SealedDialogue` folder.

- [ ] Add a `createSealedDialogue(): Folder` helper that creates a folder named `doorTypes.SEALED_DIALOGUE_NAME`.
- [ ] Add one direct `StringValue` named `01_Sealed` with value `doorTypes.FALLBACK_SEALED_MESSAGE` and parent it to the new folder.
- [ ] Create the sealed dialogue folder alongside the existing center and locked dialogue fixtures.
- [ ] Remove any existing child named `doorTypes.SEALED_DIALOGUE_NAME` before parenting the newly created folder, matching the initializer's current replacement behavior for `LockedDialogue`.
- [ ] Set `model:SetAttribute(doorTypes.SEALED_ATTRIBUTE, false)` during initialization. This establishes the authored default; designers can change it afterward for a sealed door.
- [ ] Leave the existing `Locked`, `RequiredItemId`, `DoorKey`, interaction attributes, and tags unchanged.
- [ ] Verify no runtime code requires the initializer to run. Existing models without `SealedDialogue` must use the controller fallback.

### Task 5: Verify Production Code And Manual Runtime Behavior

**Files:**
- No source or test files are changed by this task.

- [ ] Run production lint:

```bash
selene --config selene.roblox.toml src
```

- [ ] Generate the test-project sourcemap before typechecking:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

- [ ] Run the repository Roblox typecheck with the existing source and test paths. Do not edit tests to resolve diagnostics:

```bash
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

- [ ] Build both Rojo projects:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

- [ ] In a clean Roblox Studio Play session, verify manually that:
  - a door without `Sealed` behaves exactly as before;
  - a door with `Sealed = true` cannot unlock or enter, even when `Locked = false` or the inventory contains the required item;
  - `SealedDialogue` messages display in name order and the fallback displays when the folder is absent or empty;
  - `door_blocked` is emitted only after sealed dialogue completion and not after cancellation;
  - `setSealed(door, true)` and `setSealed(door, false)` change only the `Sealed` attribute, with `Locked` preserved;
  - unsealing a locked door returns it to the normal unlock flow, while unsealing an open door returns it to the normal enter flow;
  - the initializer creates `Sealed = false`, `SealedDialogue`, and `01_Sealed`.
- [ ] If existing TestEZ specs fail because their fake manager does not implement `isSealed`, record that result and leave the test files untouched as explicitly requested.

## Acceptance Criteria

- `Sealed` is a model attribute and missing `Sealed` remains backward-compatible as `false`.
- `Sealed = true` has precedence over `Locked` and blocks both `unlock` and `enter` without inventory access or character movement.
- `DoorManager:isSealed` and `DoorManager:setSealed` are typed, validated, instance-scoped APIs available to future injected client systems.
- `setSealed(false)` never changes `Locked`.
- `SealedDialogue` supports ordered custom messages and the exact fallback `A porta esta selada.`.
- Sealed interactions reuse `door_blocked` and preserve cancellation semantics.
- The initializer authors `Sealed = false` and a default sealed dialogue folder.
- No test file, test mapping, runner, remote, server door service, or client composition root is changed.
- Production lint, typecheck/build checks, and the requested manual behavior are verified or any failures are reported without editing tests.
