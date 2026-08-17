# Inventory Pickup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 30 shared server-authoritative pickups, collected through `ProximityPrompt` and added to the existing persistent inventory.

**Architecture:** Keep item validation and immutable inventory mutation in the pure `InventoryStore`. Expose that mutation through `InventoryService`, which owns player state and broadcasts `InventoryChanged`. Add a Roblox-only `PickupService` that spawns one shared batch near the first loaded character, attaches prompts, and destroys each Part only after the server confirms the inventory mutation.

**Tech Stack:** Strict Luau, Roblox `Players`, `Workspace`, `Instance`, `ProximityPrompt`, RemoteEvent snapshots, Lune 0.10.4, Selene 0.29.0, luau-lsp 1.69.0, Rojo 7.7.0, and the existing React/Wally inventory client.

## Global Constraints

- The server remains the sole owner of inventory state; the client only receives snapshots.
- Use native `ProximityPrompt`; do not add a pickup RemoteEvent.
- Create exactly 30 shared initial pickups per server: 10 `torch`, 10 `ration`, and 10 `crystal`.
- Spawn the shared batch once, when the first loaded character is available, near that character within an approximately 30-stud horizontal radius.
- Preserve the existing `InventoryState` schema `{ version: number, items: { string } }` and persistence behavior.
- Add items as repeated IDs in the list; do not add stack counters, capacity, respawn, use, discard, trade, or autosave.
- Validate item IDs against `src/shared/inventory/items.luau` on the server.
- Copy item arrays before storing or broadcasting mutated state.
- Disable a prompt and guard its callback while one pickup attempt is in progress.
- Destroy a pickup only after `InventoryService:addItem` returns `true`; restore it after a failed attempt.
- Keep Roblox-only code out of Lune unit tests; validate `Instance`, `Players`, prompts, and Workspace behavior in Studio.
- Keep `--!strict`; do not use `--!nocheck`, broad ignores, or disabled diagnostics.
- Preserve imports based on the Rojo `script` tree and do not edit generated `Packages/` manually.
- Do not revert unrelated worktree changes; stage only files belonging to each task.

## File Map

- Modify `src/server/inventory/InventoryStore.luau`: add pure catalog-backed `addItem` mutation.
- Modify `tests/server/inventory/InventoryStore.spec.luau`: cover valid, invalid, and immutable mutation behavior.
- Modify `src/server/inventory/InventoryService.luau`: expose `addItem`, update loaded state, and fire snapshots.
- Create `src/server/pickups/PickupService.luau`: create the shared batch and handle server-side prompts.
- Modify `src/server/init.server.luau`: construct and start `PickupService` after the inventory service.
- Leave `src/client/inventory/InventoryController.luau`, `src/client/inventory/useInventory.luau`, and `src/client/ui/App.luau` unchanged because their existing snapshot flow already renders new entries.

---

### Task 1: Add Pure Inventory Mutation

**Files:**
- Modify: `src/server/inventory/InventoryStore.luau` near `defaultInventory()` and the public functions at the bottom of the module
- Modify: `tests/server/inventory/InventoryStore.spec.luau` after the fresh-default test

**Interfaces:**
- Consumes: the existing shared catalog returned by `src/shared/inventory/items.luau` and `InventoryState` shape.
- Produces: `InventoryStore.addItem(state: InventoryState, itemId: string): InventoryState?`; it returns a fresh state for a valid catalog ID and `nil` for an unknown ID.

- [ ] **Step 1: Write failing tests for a valid immutable insertion**

Add this test to `tests/server/inventory/InventoryStore.spec.luau`:

```lua
harness.it("adds a valid catalog item without mutating the source state", function()
	local original = { version = 1, items = { "torch", "ration" } }
	local updated = InventoryStore.addItem(original, "crystal")

	harness.assert.truthy(updated)
	harness.assert.falsy(updated == original)
	harness.assert.falsy(updated.items == original.items)
	assertItems(updated.items, { "torch", "ration", "crystal" }, "updated items")
	assertItems(original.items, { "torch", "ration" }, "original items")
end)
```

- [ ] **Step 2: Write failing tests for invalid IDs**

Add this test immediately after the valid insertion test:

```lua
harness.it("rejects an unknown item without changing the source state", function()
	local original = { version = 1, items = { "torch" } }
	local updated = InventoryStore.addItem(original, "unknown-item")

	harness.assert.isNil(updated)
	assertItems(original.items, { "torch" }, "original items")
end)
```

- [ ] **Step 3: Run the tests and verify the new tests fail**

Run:

```bash
lune run test
```

Expected: the existing suites run, and the new tests fail because
`InventoryStore.addItem` is not defined.

- [ ] **Step 4: Implement the minimal immutable mutation**

Add this function before `serialize` in `src/server/inventory/InventoryStore.luau`:

```lua
function InventoryStore.addItem(state: InventoryState, itemId: string): InventoryState?
	if items[itemId] == nil then
		return nil
	end

	local updated = {
		version = state.version,
		items = table.clone(state.items),
	}
	table.insert(updated.items, itemId)
	return updated
end
```

Do not change serialization, schema versioning, default seed order, or the
existing catalog.

- [ ] **Step 5: Run the pure tests and lint**

Run:

```bash
lune run test
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Expected: all tests pass and both lint commands produce no diagnostics.

- [ ] **Step 6: Commit the pure mutation**

Inspect `git status --short` and stage only the two task files:

```bash
git add -- src/server/inventory/InventoryStore.luau tests/server/inventory/InventoryStore.spec.luau
git commit -m "feat: add immutable inventory item mutation"
```

### Task 2: Expose Server Inventory Mutation

**Files:**
- Modify: `src/server/inventory/InventoryService.luau` in the exported `Service` type and after `copyState`

**Interfaces:**
- Consumes: `InventoryStore.addItem(state, itemId)` from Task 1.
- Produces: `InventoryService.new(persistence):Service` where `Service.addItem(self, player, itemId):boolean` is callable by `PickupService` on the server.

- [ ] **Step 1: Extend the service contract before implementation**

Change the exported service type to include the new method:

```lua
export type Service = {
	start: (self: Service) -> (),
	addItem: (self: Service, player: Player, itemId: string) -> boolean,
}
```

The service type must continue to expose `start`; do not make the loaded-state
map public.

- [ ] **Step 2: Implement the guarded mutation**

Inside `InventoryService.new`, add this method to `service` before the
`getInventory.OnServerInvoke` assignment:

```lua
	function service:addItem(player: Player, itemId: string): boolean
		local state = loadedStates[player]
		if state == nil then
			return false
		end

		local updatedState = InventoryStore.addItem(state, itemId)
		if updatedState == nil then
			return false
		end

		loadedStates[player] = updatedState
		inventoryChanged:FireClient(player, copyState(updatedState))
		return true
	end
```

This method must only mutate a player that has completed the existing load
gate. It must not call persistence directly; the existing `PlayerRemoving`
save continues to persist the latest state.

- [ ] **Step 3: Verify the server contract and existing behavior**

Run:

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

Expected: no diagnostics. The existing `lune run test` suite must also remain
green because the mutation logic is still covered by `InventoryStore` tests.

- [ ] **Step 4: Commit the server mutation API**

```bash
git add -- src/server/inventory/InventoryService.luau
git commit -m "feat: expose server inventory item mutation"
```

### Task 3: Implement Shared Pickup Service

**Files:**
- Create: `src/server/pickups/PickupService.luau`

**Interfaces:**
- Consumes: an inventory service with `addItem(self, player, itemId):boolean`, the shared item catalog, Roblox `Players`, `Workspace`, and `Instance` APIs.
- Produces: `PickupService.new(inventoryService):Service` and idempotent `Service.start(self):()`.

- [ ] **Step 1: Define the service contract and constants**

Start the new module with strict mode, the Roblox services, and structural
types for the dependency:

```lua
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local items = require(ReplicatedStorage.Shared.inventory.items)

type InventoryService = {
	addItem: (self: InventoryService, player: Player, itemId: string) -> boolean,
}

export type Service = {
	start: (self: Service) -> (),
}

local pickupDefinitions = {
	{ itemId = "torch", count = 10 },
	{ itemId = "ration", count = 10 },
	{ itemId = "crystal", count = 10 },
}
local spawnRadius = 30
```

Keep the definitions fixed and catalog-backed. The implementation should
assert that each configured ID exists before creating a Part, so a catalog
mistake fails during server setup rather than during a player interaction.

- [ ] **Step 2: Implement one pickup Part with a guarded prompt**

Implement a local `createPickup(folder, inventoryService, itemId, index,
center, random)` helper. It must create an anchored, non-colliding Part,
assign `ItemId`, apply a distinct local visual configuration for the three
types, and parent a `ProximityPrompt` configured as follows:

```lua
prompt.ActionText = "Coletar"
prompt.ObjectText = item.name
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 10
prompt.RequiresLineOfSight = false
```

Use this distinct color/material table in the service, keeping visual data out
of the inventory schema:

```lua
local visuals = {
	torch = { color = Color3.fromRGB(255, 170, 0), material = Enum.Material.Neon },
	ration = { color = Color3.fromRGB(98, 190, 110), material = Enum.Material.SmoothPlastic },
	crystal = { color = Color3.fromRGB(95, 160, 255), material = Enum.Material.Neon },
}
```

Connect `prompt.Triggered` on the server with this exact behavior:

```lua
local collected = false
prompt.Triggered:Connect(function(player: Player)
	if collected then
		return
	end

	collected = true
	prompt.Enabled = false
	if inventoryService:addItem(player, itemId) then
		part:Destroy()
	else
		collected = false
		prompt.Enabled = true
	end
end)
```

Set the Part name to `Pickup_<ItemId>_<two-digit index>` and set its
`ItemId` attribute before parenting it into `Workspace.Pickups`.

- [ ] **Step 3: Implement the one-time shared spawn**

Implement `spawnPickups(center)` using `Random.new()` and the three fixed
definitions. For each count, generate an offset with:

```lua
local offset = Vector3.new(
	random:NextNumber(-spawnRadius, spawnRadius),
	2,
	random:NextNumber(-spawnRadius, spawnRadius)
)
```

Use `center + offset` as the Part position. This intentionally does not do
raycasts, room selection, navigation, or terrain validation in this first
version.

Create `Workspace.Pickups` if it does not exist and reject a pre-existing
object with the same name if it is not a `Folder`. Keep a private `spawned`
boolean so `spawnPickups` can run only once during the service lifetime.

- [ ] **Step 4: Start from the first available character**

Implement `start()` as idempotent. Connect a local `onCharacter(character)`
callback to `PlayerAdded` and to all already-present players. The callback
must wait for the part with
`local root = character:WaitForChild("HumanoidRootPart") :: BasePart` before
using its position. Check `spawned` both before waiting and after waiting, then
return immediately once the batch has been created.

The service must handle both cases:

```lua
for _, player in Players:GetPlayers() do
	if player.Character ~= nil then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacter)
end)
```

Because `InventoryService` disables automatic character loading until the
inventory succeeds, this hook will naturally spawn near the first player who
passes the existing load gate. Do not spawn a second batch for later players
or character respawns.

- [ ] **Step 5: Verify the Roblox-only service statically**

Run:

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

Expected: no diagnostics for `PickupService`. Do not add Roblox APIs to the
Lune typecheck or attempt to unit-test real `Instance` behavior through the
Lune loader.

- [ ] **Step 6: Commit the pickup service**

```bash
git add -- src/server/pickups/PickupService.luau
git commit -m "feat: add shared proximity pickups"
```

### Task 4: Integrate Pickup Service Into Server Bootstrap

**Files:**
- Modify: `src/server/init.server.luau`

**Interfaces:**
- Consumes: the existing persistence selection and `InventoryService.new(backend)` plus `PickupService.new(inventoryService)` from Tasks 2 and 3.
- Produces: one running inventory service and one running shared pickup service in the live server entry point.

- [ ] **Step 1: Preserve the existing backend selection**

Change the executable setup from an anonymous service construction to named
service instances:

```lua
local inventoryService = InventoryService.new(backend)
inventoryService:start()

local PickupService = require(script.pickups.PickupService)
PickupService.new(inventoryService):start()
```

Keep `RunService:IsStudio()` selecting `MemoryPersistence` and production
selecting `DataStorePersistence`. Start `InventoryService` before
`PickupService` so the existing `CharacterAutoLoads = false` load gate remains
the authority for the first character used as the spawn center.

- [ ] **Step 2: Build the complete Rojo tree**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx
```

Expected: the build succeeds and includes
`ServerScriptService.Server.pickups.PickupService`.

- [ ] **Step 3: Commit the bootstrap integration**

```bash
git add -- src/server/init.server.luau
git commit -m "feat: start pickup service with server"
```

### Task 5: Run End-to-End Verification

**Files:**
- Verify: all files changed by Tasks 1-4
- No new source file is needed for the Studio acceptance test.

**Interfaces:**
- Consumes: the running server bootstrap, inventory snapshots, and the shared pickup folder.
- Produces: evidence that the complete pickup flow works in pure tests, static checks, Rojo, and Roblox Studio.

- [ ] **Step 1: Run all Lune behavioral tests**

Run:

```bash
lune run test
```

Expected: all existing tests and the new `InventoryStore.addItem` tests pass.

- [ ] **Step 2: Run both Selene configurations**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Expected: no diagnostics. The Roblox and Lune configurations must remain
separate.

- [ ] **Step 3: Run the Roblox typecheck**

Run exactly:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

Expected: no type diagnostics.

- [ ] **Step 4: Verify the shared flow in Roblox Studio**

Open the place built from `/tmp/dungeon-game-canve.rbxlx`, run a server with
one player, and check:

1. `Workspace.Pickups` appears after the first character loads.
2. The folder contains exactly 30 generated Parts.
3. Counting the `ItemId` attributes gives 10 `torch`, 10 `ration`, and 10 `crystal`.
4. Each Part has a working `ProximityPrompt` with action text `Coletar`.
5. Activating a prompt removes only that Part and adds the corresponding name to the inventory UI.
6. Activating the same prompt concurrently or repeatedly does not add duplicate entries.
7. A second player sees the same remaining Parts and can collect one of them.
8. A second player joining does not create another batch of 30.
9. Leaving the server saves the updated list through the existing persistence path.

- [ ] **Step 5: Inspect final worktree scope**

Run:

```bash
git status --short
git log --oneline -10
```

Confirm that only intentional pickup implementation commits and the already
present unrelated worktree changes exist. Do not stage or revert unrelated
files.
