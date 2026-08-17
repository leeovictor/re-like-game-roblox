# Inventory List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a read-only, server-authoritative player inventory that loads from DataStore in production, uses seeded memory persistence in Studio, and renders on the client through a React hook.

**Architecture:** Keep the inventory model and serialization free of Roblox APIs. Inject a persistence backend into a server service that owns load gating, remote exposure, and best-effort saves. On the client, an inventory controller owns the replicated snapshot and a Signal; `useInventory()` bridges that Signal to the existing React `App`.

**Tech Stack:** Luau strict mode, Roblox DataStoreService/RemoteEvent/RemoteFunction, Rojo 7.7.0, Lune 0.10.4 tests, React Lua 17.2.1, and `sleitnick/signal@2.0.3` via Wally.

## Global Constraints

- The server is the sole owner of inventory state; the client only receives and reads snapshots.
- The inventory is read-only in this feature: no pickup, use, discard, trade, equipment, or other mutation remote.
- Use `DataStoreService:GetDataStore("PlayerInventory")`, key `tostring(userId)`, and `UpdateAsync` for saves.
- Use `MemoryPersistence` only when `RunService:IsStudio()` is true; it must have no Roblox API dependency.
- Load with five attempts and backoff; a definitive failure kicks with exactly `Falha ao carregar dados` and must not save an empty state.
- Save only as best effort during `PlayerRemoving`; there is no autosave or save-on-change.
- Keep `--!strict`, Roblox and Lune typechecks separate, and preserve imports based on the Roblox `script` tree.
- Do not edit generated `Packages/` manually; update `wally.toml` and run `wally install`.
- Use `script["cave-engine"]` syntax if any existing cave-engine code is referenced; no inventory code needs that folder.

## File Map

- Create `src/shared/inventory/items.luau`: shared item types, item catalog, and `InventoryState`.
- Modify `src/shared/remotes.luau`: ensure `InventoryChanged` (`RemoteEvent`) and `GetInventory` (`RemoteFunction`) in `ReplicatedStorage.Remotes`.
- Create `src/server/inventory/InventoryStore.luau`: pure schema versioning, JSON serialization/deserialization, and seed generation.
- Create `src/server/inventory/persistence/MemoryPersistence.luau`: pure in-memory `userId -> InventoryState` backend.
- Create `src/server/inventory/persistence/DataStorePersistence.luau`: Roblox DataStore adapter for production load/save.
- Create `src/server/inventory/InventoryService.luau`: load gate, player lifecycle connections, remote handlers, and save handling.
- Modify `src/server/init.server.luau`: select the backend using `RunService:IsStudio()` and start `InventoryService`.
- Create `src/client/inventory/InventoryController.luau`: client snapshot, remote subscriptions, Signal, and lifecycle.
- Create `src/client/inventory/useInventory.luau`: React hook backed by `InventoryController`.
- Modify `src/client/init.client.luau`: start the inventory controller before mounting `App` and inject/use the shared controller module.
- Modify `src/client/ui/App.luau`: replace the placeholder-only UI with a read-only inventory list and loading state.
- Create `tests/server/inventory/InventoryStore.spec.luau`: pure serialization, schema, seed, and stable round-trip tests.
- Create `tests/server/inventory/MemoryPersistence.spec.luau`: seed, identity-by-user, and save behavior tests.
- Modify `wally.toml`: add `Signal = "sleitnick/signal@2.0.3"`.
- Regenerate `wally.lock` and `Packages/` with Wally; do not hand-edit generated package files.

---

### Task 1: Add Shared Inventory Model And Remotes

**Files:**
- Create: `src/shared/inventory/items.luau`
- Modify: `src/shared/remotes.luau`
- Modify: `wally.toml`
- Regenerate: `wally.lock`, `Packages/`

**Interfaces:**
- Produces `ItemId`, `ItemDef`, and `InventoryState` types from `items.luau`.
- Produces `items` with exactly `torch`, `ration`, and `crystal`; names are `Tocha`, `Ração`, and `Cristal`; `stackable` is true, true, and false respectively.
- Produces `Remotes.InventoryChanged: RemoteEvent` and `Remotes.GetInventory: RemoteFunction` from the shared remotes module.
- Produces `ReplicatedStorage.Packages.Signal` after Wally installation.

- [ ] **Step 1: Extend the Wally dependency declaration**

Add the exact dependency below under `[dependencies]`:

```toml
Signal = "sleitnick/signal@2.0.3"
```

- [ ] **Step 2: Implement the shared item catalog**

Create a strict module exporting the types and catalog required by the spec. Keep the catalog as the only source of valid item IDs:

```lua
export type ItemId = string
export type ItemDef = { id: ItemId, name: string, stackable: boolean }
export type InventoryState = { version: number, items: { ItemId } }

local items: { [ItemId]: ItemDef } = {
    torch = { id = "torch", name = "Tocha", stackable = true },
    ration = { id = "ration", name = "Ração", stackable = true },
    crystal = { id = "crystal", name = "Cristal", stackable = false },
}
```

Return the catalog and exported types from the module without requiring Roblox services.

- [ ] **Step 3: Extend remote creation without changing existing callers**

Generalize the existing `_ensureRemote` helper to support both class names, then ensure the module returns:

```lua
return {
    InventoryChanged = _ensureRemote("InventoryChanged", "RemoteEvent"),
    GetInventory = _ensureRemote("GetInventory", "RemoteFunction"),
}
```

Reject an existing instance with the wrong class using the existing error style. The shared module remains responsible for creating/reusing `ReplicatedStorage.Remotes`.

- [ ] **Step 4: Install and verify the dependency tree**

Run: `wally install`

Expected: Wally updates `wally.lock` and generates `Packages/Signal`; no generated package is manually edited.

- [ ] **Step 5: Build the Rojo tree**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx`

Expected: the build succeeds and includes `ReplicatedStorage.Shared.inventory`, `ReplicatedStorage.Shared.remotes`, and `ReplicatedStorage.Packages.Signal`.

- [ ] **Step 6: Commit the shared contract**

```bash
git add src/shared/inventory/items.luau src/shared/remotes.luau wally.toml wally.lock
git commit -m "feat: add inventory shared contracts"
```

### Task 2: Implement Pure Inventory Store With Tests

**Files:**
- Create: `src/server/inventory/InventoryStore.luau`
- Create: `tests/server/inventory/InventoryStore.spec.luau`

**Interfaces:**
- Consumes `src/shared/inventory/items.luau`.
- Produces `InventoryStore.defaultInventory() -> InventoryState`.
- Produces `InventoryStore.serialize(state: InventoryState) -> string`.
- Produces `InventoryStore.deserialize(serialized: string) -> InventoryState?`.
- Uses schema `version = 1`; serialized data contains `version` and `items` as JSON.

- [ ] **Step 1: Write failing tests for the default seed**

Load `InventoryStore` through `tests/support/roblox-loader`, then assert that `defaultInventory()` returns version `1`, exactly three IDs, and the fixed ordered selection `{ "torch", "ration", "crystal" }`. Also assert each seed ID exists in the shared catalog.

- [ ] **Step 2: Write failing serialization tests**

Assert that `serialize({ version = 1, items = { "torch", "ration" } })` returns JSON containing `version` and `items`, that `deserialize` reconstructs both fields, and that serializing the deserialized value produces the same JSON string. Add a malformed/unsupported-version case that returns `nil` rather than producing an invalid state.

- [ ] **Step 3: Run the focused test to verify failure**

Run: `lune run test`

Expected: the new suite fails because `src/server/inventory/InventoryStore.luau` does not exist yet.

- [ ] **Step 4: Implement the minimal pure store**

Keep this module free of Roblox and Lune APIs. Implement the small deterministic JSON encoder/decoder for exactly the schema used here, with output shaped as `{"version":1,"items":["torch","ration"]}`: encode version as a number, encode item IDs as JSON strings with escaped quotes/backslashes, and parse the same object/array/string/number forms on load. The decoder must reject malformed JSON, non-numeric versions, versions other than `1`, non-array `items`, and non-string item IDs. Preserve item order and make `defaultInventory()` construct a fresh table on every call.

- [ ] **Step 5: Run the tests and lint**

Run: `lune run test`

Expected: all existing and inventory store tests pass.

Run: `selene --config selene.roblox.toml src` and `selene --config selene.lune.toml tests lune`

Expected: no diagnostics.

- [ ] **Step 6: Commit the pure store**

```bash
git add src/server/inventory/InventoryStore.luau tests/server/inventory/InventoryStore.spec.luau
git commit -m "feat: add inventory store serialization"
```

### Task 3: Implement Memory Persistence With Tests

**Files:**
- Create: `src/server/inventory/persistence/MemoryPersistence.luau`
- Create: `tests/server/inventory/MemoryPersistence.spec.luau`

**Interfaces:**
- Consumes `InventoryStore` and `InventoryState`.
- Produces `MemoryPersistence.new() -> Persistence`.
- `load(userId: number) -> InventoryState?` seeds the user on first access and returns a snapshot thereafter.
- `save(userId: number, state: InventoryState) -> ()` replaces the stored state for that user.

- [ ] **Step 1: Write failing persistence tests**

Cover three behaviors: first `load(42)` returns the seed; a second `load(42)` returns the saved map value rather than a new seed; and `save(42, replacement)` makes the replacement available while `load(7)` remains independently seeded. Assert returned state tables are not accidentally shared with the default seed.

- [ ] **Step 2: Run the focused test to verify failure**

Run: `lune run test`

Expected: the new suite fails because `MemoryPersistence` is missing.

- [ ] **Step 3: Implement the in-memory backend**

Keep a private `{ [number]: InventoryState }` map. On a missing user ID, call `InventoryStore.defaultInventory()`, store it, and return it. On save, store a fresh snapshot with a copied `items` array so callers cannot mutate the backend through an old table reference.

- [ ] **Step 4: Run pure tests and lint**

Run: `lune run test`

Expected: all tests pass.

Run: `selene --config selene.roblox.toml src` and `selene --config selene.lune.toml tests lune`

Expected: no diagnostics.

- [ ] **Step 5: Commit the memory backend**

```bash
git add src/server/inventory/persistence/MemoryPersistence.luau tests/server/inventory/MemoryPersistence.spec.luau
git commit -m "feat: add memory inventory persistence"
```

### Task 4: Add Production DataStore Persistence

**Files:**
- Create: `src/server/inventory/persistence/DataStorePersistence.luau`

**Interfaces:**
- Consumes `InventoryStore` and `InventoryState`.
- Produces `DataStorePersistence.new() -> Persistence`.
- `load(userId)` reads `PlayerInventory` at key `tostring(userId)`, deserializes valid data, and returns `nil` for a missing/invalid record.
- `save(userId, state)` uses `UpdateAsync` and returns the serialized state from its transform callback.

- [ ] **Step 1: Implement the adapter around one DataStore instance**

Create the adapter with `DataStoreService:GetDataStore("PlayerInventory")`. Do not put retry logic in this module; the service owns retry policy. A missing key should return `nil` so the service can decide whether to seed or treat the load as successful according to the approved design. Ensure the save callback does not read or merge client-provided data; it writes only the server state passed to `save`.

- [ ] **Step 2: Keep Roblox-only APIs out of Lune tests**

Do not add this module to pure test coverage. Its contract is verified by Roblox typechecking and Studio integration because `DataStoreService` is unavailable in the Lune harness.

- [ ] **Step 3: Run Roblox lint and typecheck**

Run:

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap sourcemap.json --formatter gnu src
```

Expected: no diagnostics from the new adapter.

- [ ] **Step 4: Commit the production adapter**

```bash
git add src/server/inventory/persistence/DataStorePersistence.luau
git commit -m "feat: add datastore inventory persistence"
```

### Task 5: Add Server Inventory Service And Load Gate

**Files:**
- Create: `src/server/inventory/InventoryService.luau`
- Modify: `src/server/init.server.luau`

**Interfaces:**
- Consumes a persistence object implementing `load(self, userId) -> InventoryState?` and `save(self, userId, state) -> ()`, plus shared remotes.
- Produces `InventoryService.new(persistence)`, `start()`, and lifecycle handling for `Players.PlayerAdded`/`PlayerRemoving`.
- `GetInventory.OnServerInvoke(player) -> InventoryState?` returns the loaded in-memory state for that player only.
- `InventoryChanged:FireClient(player, snapshot)` fires after a successful load.

- [ ] **Step 1: Define the lifecycle and gate behavior before coding**

Set `Players.CharacterAutoLoads = false` before connecting player loading. For each player, attempt `persistence:load(player.UserId)` five times with an increasing backoff. Treat a `nil` result as a missing record and use `InventoryStore.defaultInventory()`; treat thrown errors as retryable. On definitive failure, call `player:Kick("Falha ao carregar dados")` and never add the player to the loaded-state map or save an empty state. On success, store a fresh snapshot, fire `InventoryChanged`, and call `player:LoadCharacter()`.

- [ ] **Step 2: Implement remote and lifecycle handlers**

Keep a private `{ [Player]: InventoryState }` map. `GetInventory` returns the current map value or `nil` while the player is not loaded. In `PlayerRemoving`, capture the loaded snapshot before removing the map entry, perform an immediate protected save with that snapshot, then schedule one short deferred retry with `task.spawn` using the captured snapshot if the first attempt failed. Never save a player that failed the load gate, and do not read the map from the deferred retry after it has been removed.

- [ ] **Step 3: Start the service from the server entry point**

At the live executable portion of `src/server/init.server.luau`, require `RunService`, `MemoryPersistence`, `DataStorePersistence`, and `InventoryService` via the existing `script` tree. Select `MemoryPersistence.new()` when `RunService:IsStudio()` is true and `DataStorePersistence.new()` otherwise, then call `InventoryService.new(backend):start()`. Also process players already present after startup so the service does not miss `PlayerAdded`.

- [ ] **Step 4: Run build, lint, and Roblox typecheck**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx`

Expected: the server inventory tree and live server entry point build successfully.

Run: `selene --config selene.roblox.toml src`

Expected: no diagnostics.

- [ ] **Step 5: Commit the server authority layer**

```bash
git add src/server/inventory/InventoryService.luau src/server/init.server.luau
git commit -m "feat: add server inventory service"
```

### Task 6: Add Client Replication Controller And Hook

**Files:**
- Create: `src/client/inventory/InventoryController.luau`
- Create: `src/client/inventory/useInventory.luau`
- Modify: `src/client/init.client.luau`

**Interfaces:**
- Consumes `ReplicatedStorage.Shared.remotes`, `ReplicatedStorage.Shared.inventory.items`, and `ReplicatedStorage.Packages.Signal`.
- Produces a singleton controller module with `start()`, `stop()`, `getState() -> InventoryState?`, and `changed` Signal.
- `useInventory()` returns `InventoryState?`, initially `nil`, and updates on every Signal notification.

- [ ] **Step 1: Implement controller state and Signal lifecycle**

On `start()`, connect `InventoryChanged.OnClientEvent` before invoking `GetInventory:InvokeServer()`. Each received snapshot must be assigned as a new state reference and fired through `changed`. Apply the invoke result the same way; the last received snapshot wins. Make `start()` idempotent. `stop()` disconnects the remote connection and prevents further updates.

- [ ] **Step 2: Implement the React hook**

Use `React.useState(controller.getState())` and an effect that connects to `controller.changed`, sets state to the event snapshot, and disconnects on cleanup. The hook must not introduce Context. Obtain the shared controller from the inventory module rather than constructing a controller per component.

- [ ] **Step 3: Start the controller in the client entry point**

Require `InventoryController` in `src/client/init.client.luau`, call `start()` before `root:render`, and preserve the existing camera/debugger startup and PlayerGui mounting. `App` should consume the same controller through `useInventory()`.

- [ ] **Step 4: Run Roblox lint, typecheck, and build**

Run:

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap sourcemap.json --formatter gnu src
rojo build -o /tmp/dungeon-game-canve.rbxlx
```

Expected: no diagnostics and a successful place build.

- [ ] **Step 5: Commit client replication**

```bash
git add src/client/inventory/InventoryController.luau src/client/inventory/useInventory.luau src/client/init.client.luau
git commit -m "feat: replicate inventory to client"
```

### Task 7: Render The Read-Only Inventory List

**Files:**
- Modify: `src/client/ui/App.luau`

**Interfaces:**
- Consumes `useInventory()`, shared `items` catalog, and `InventoryState`.
- Produces a visible loading message `Carregando inventário...` while state is `nil`.
- Produces one read-only row per inventory item, resolving IDs through the catalog and displaying the item name. No row has an interaction handler or mutation remote.

- [ ] **Step 1: Add the loading and populated UI branches**

Keep the existing `ScreenGui` and visual language. Add an inventory panel that renders `Carregando inventário...` when `useInventory()` returns `nil`; otherwise iterate `state.items` in order and render each catalog item's `name`. Use stable keys based on the item index plus ID so duplicate stackable IDs remain renderable. If an unknown ID is ever received, display the ID as a safe fallback without mutating state.

- [ ] **Step 2: Preserve existing map behavior**

Do not remove the current map toggle or alter its state semantics. Resize/position panels so the inventory list remains readable on desktop and narrow screens; use relative width constraints or scrolling rather than assuming the existing fixed panel is the only content.

- [ ] **Step 3: Run lint and typecheck**

Run: `selene --config selene.roblox.toml src`

Expected: no diagnostics.

Run the Roblox typecheck command from Task 6.

Expected: no diagnostics for the hook, catalog access, or React element properties.

- [ ] **Step 4: Commit the UI**

```bash
git add src/client/ui/App.luau
git commit -m "feat: render read-only inventory"
```

### Task 8: Execute End-To-End Verification

**Files:**
- Verify: all changed source, tests, `wally.toml`, and `wally.lock`
- Do not add new feature scope or edit generated `Packages/` by hand.

**Interfaces:**
- Verifies the pure contracts with Lune and the Roblox tree with Rojo/typecheck.
- Verifies Studio-only behavior manually because the Lune loader cannot execute DataStoreService, RemoteEvents, Player lifecycle, or ReactRoblox.

- [ ] **Step 1: Run all behavioral tests**

Run: `lune run test`

Expected: all suites pass, including `InventoryStore` and `MemoryPersistence`.

- [ ] **Step 2: Run both lint configurations**

Run: `selene --config selene.roblox.toml src`

Run: `selene --config selene.lune.toml tests lune`

Expected: no diagnostics from either platform.

- [ ] **Step 3: Run both typechecks**

Run the exact Roblox and Lune typecheck commands documented in `AGENTS.md`, generating `sourcemap.json` immediately before the Roblox analysis.

Expected: both analyses complete without errors; no Roblox globals leak into `tests/` or `lune/`.

- [ ] **Step 4: Build the place**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx`

Expected: build succeeds and includes the shared remotes, server inventory modules, client inventory modules, React UI, and Signal package.

- [ ] **Step 5: Verify Studio integration manually**

Open the generated place in Roblox Studio and run with the server/client. Verify all of the following:

```text
1. In Studio, the server selects MemoryPersistence and a new player receives torch, ration, and crystal.
2. The player does not spawn until inventory loading succeeds.
3. The client first shows "Carregando inventário..." and then lists Tocha, Ração, and Cristal in order.
4. GetInventory returns the loaded snapshot and InventoryChanged reaches the client.
5. No inventory UI action mutates the server state.
6. On player removal, the server attempts the best-effort save without creating an empty record.
```

- [ ] **Step 6: Review the final diff for scope**

Run: `git diff --check` and `git status --short`.

Expected: no whitespace errors; only intended inventory files and dependency metadata are part of the implementation changes. Preserve unrelated pre-existing worktree changes.
