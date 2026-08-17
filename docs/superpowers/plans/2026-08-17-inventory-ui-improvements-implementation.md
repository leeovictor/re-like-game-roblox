# Inventory UI Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the inventory until the player presses `I` and show a server-confirmed, two-second pickup notification in the lower-left corner.

**Architecture:** Keep `InventoryChanged` as the state synchronization event and add a separate `PickupCollected` `RemoteEvent` for the transient gameplay event. The server fires it only after `InventoryService:addItem` succeeds; a client controller and React hook expose the latest item ID to `App`, which owns the inventory toggle and renders one replaceable notification.

**Tech Stack:** Strict Luau, Roblox `UserInputService`, `RemoteEvent`, `ProximityPrompt`, React/ReactRoblox, existing `Signal` package, Lune 0.10.4, Selene 0.29.0, luau-lsp 1.69.0, and Rojo 7.7.0.

## Global Constraints

- Keep `--!strict` in every Luau module and do not use `--!nocheck`, broad ignores, or disabled diagnostics.
- The server remains the sole owner of inventory state; the client only receives snapshots and pickup events.
- Preserve `InventoryState` as `{ version: number, items: { string } }` and do not add transient notification fields to it.
- Use the existing shared item catalog for notification names: `Tocha`, `Ração`, and `Cristal`.
- Fire `PickupCollected` only after `InventoryService:addItem(player, itemId)` returns `true`.
- Ignore `UserInputService.InputBegan` events with `gameProcessedEvent == true`.
- Start the pickup notification controller before mounting React, matching the existing `InventoryController` startup order.
- Keep the notification as one current message; a new event replaces it and restarts the two-second lifetime.
- Keep Roblox-only code out of Lune runtime tests; use source-level tests for client wiring and Studio for Roblox APIs.
- Preserve imports based on the Rojo `script` tree and do not edit generated `Packages/` manually.
- Do not revert unrelated worktree changes; stage only files belonging to the current task when committing.

---

## File Map

- Modify `src/shared/remotes.luau`: ensure `Remotes.PickupCollected` is a `RemoteEvent`.
- Modify `src/server/pickups/PickupService.luau`: fire the pickup event to the player after a successful inventory mutation.
- Create `src/client/pickups/PickupNotificationController.luau`: subscribe to the remote and publish item IDs through a Signal.
- Create `src/client/pickups/usePickupNotification.luau`: bridge the controller Signal to React and expire the latest notification after two seconds.
- Modify `src/client/init.client.luau`: start `PickupNotificationController` before rendering `App`.
- Modify `src/client/ui/App.luau`: add the hidden-by-default inventory toggle and lower-left notification element.
- Create `tests/client/pickups/PickupNotification.spec.luau`: source-level checks for the remote, server emission, controller, and hook contracts.
- Modify `tests/client/ui/App.spec.luau`: source-level checks for keyboard behavior and conditional UI rendering.

---

### Task 1: Add The Server Pickup Event

**Files:**
- Modify: `src/shared/remotes.luau:39-42`
- Modify: `src/server/pickups/PickupService.luau:1-80`
- Create: `tests/client/pickups/PickupNotification.spec.luau`

**Interfaces:**
- Consumes: existing `InventoryService:addItem(player: Player, itemId: string): boolean` and shared remote factory.
- Produces: `remotes.PickupCollected :: RemoteEvent`, with payload `itemId: string` sent only to the collecting player after successful insertion.

- [ ] **Step 1: Write failing source-contract tests**

Create the test directory and `tests/client/pickups/PickupNotification.spec.luau`:

```lua
--!strict

local fs = require("@lune/fs")
local harness = require("../../support/harness")

local function read(path: string): string
    return fs.readFile(path)
end

local function assertContains(source: string, text: string, message: string): ()
    harness.assert.truthy(string.find(source, text, 1, true), message)
end

harness.describe("Pickup notification server contract", function()
    harness.it("registers a dedicated pickup remote event", function()
        local source = read("src/shared/remotes.luau")
        assertContains(
            source,
            'PickupCollected = _ensureRemote("PickupCollected", "RemoteEvent")',
            "shared remotes must expose PickupCollected as a RemoteEvent"
        )
    end)

    harness.it("sends the item only after a successful inventory mutation", function()
        local source = read("src/server/pickups/PickupService.luau")
        local mutationStart = string.find(source, "if inventoryService:addItem(player, itemId) then", 1, true) or 0
        local eventStart = string.find(source, "pickupCollected:FireClient(player, itemId)", 1, true) or 0

        harness.assert.truthy(mutationStart > 0, "pickup service must guard collection with addItem")
        harness.assert.truthy(eventStart > 0, "pickup service must notify the collecting player")
        harness.assert.truthy(eventStart > mutationStart, "pickup event must be sent after addItem succeeds")
    end)
end)
```

- [ ] **Step 2: Run the tests and verify the new contract fails**

Run:

```bash
lune run test
```

Expected: the existing tests run, and the new server contract checks fail because
`PickupCollected` is not registered or fired yet.

- [ ] **Step 3: Register the shared remote**

In `src/shared/remotes.luau`, preserve the existing two entries and add the new
entry to the returned table:

```lua
return {
    InventoryChanged = _ensureRemote("InventoryChanged", "RemoteEvent"),
    GetInventory = _ensureRemote("GetInventory", "RemoteFunction"),
    PickupCollected = _ensureRemote("PickupCollected", "RemoteEvent"),
}
```

Do not change `_ensureRemote` behavior or existing remote names.

- [ ] **Step 4: Fire the event from the successful pickup branch**

In `src/server/pickups/PickupService.luau`:

1. Require `ReplicatedStorage.Shared.remotes` beside the existing item catalog import.
2. Bind `local pickupCollected = remotes.PickupCollected :: RemoteEvent`.
3. Keep the existing `collected` guard and prompt disabling.
4. In the existing successful branch, destroy the Part and then fire the event:

```lua
if inventoryService:addItem(player, itemId) then
    part:Destroy()
    pickupCollected:FireClient(player, itemId)
else
    collected = false
    prompt.Enabled = true
end
```

The event must not be fired in the failure branch. Keep the event specific to
`player`; do not use `FireAllClients`.

- [ ] **Step 5: Run the source contract and Roblox lint**

Run:

```bash
lune run test
selene --config selene.roblox.toml src
```

Expected: all Lune tests pass and Selene reports no Roblox diagnostics.

- [ ] **Step 6: Commit the server event contract**

Inspect `git status --short` and stage only the three Task 1 files:

```bash
git add -- src/shared/remotes.luau src/server/pickups/PickupService.luau tests/client/pickups/PickupNotification.spec.luau
git commit -m "feat: notify client after pickup"
```

### Task 2: Add The Client Pickup Notification Pipeline

**Files:**
- Create: `src/client/pickups/PickupNotificationController.luau`
- Create: `src/client/pickups/usePickupNotification.luau`
- Modify: `src/client/init.client.luau:8-27`
- Modify: `tests/client/pickups/PickupNotification.spec.luau`

**Interfaces:**
- Consumes: `remotes.PickupCollected :: RemoteEvent`, `ReplicatedStorage.Packages.Signal`, and the existing React hook pattern.
- Produces: `PickupNotificationController.start()`, `PickupNotificationController.stop()`, `PickupNotificationController.changed`, and `usePickupNotification() -> string?`.

- [ ] **Step 1: Add failing source-contract tests for the client pipeline**

Append this suite to `tests/client/pickups/PickupNotification.spec.luau`:

```lua
harness.describe("Pickup notification client pipeline", function()
    harness.it("has an idempotent controller lifecycle and remote subscription", function()
        local source = read("src/client/pickups/PickupNotificationController.luau")
        assertContains(source, "export type PickupNotificationController", "controller type must be exported")
        assertContains(source, "function controller.start()", "controller must expose start")
        assertContains(source, "function controller.stop()", "controller must expose stop")
        assertContains(source, "pickupCollected.OnClientEvent", "controller must subscribe to PickupCollected")
        assertContains(source, "changed:Fire(itemId)", "controller must publish the received item ID")
    end)

    harness.it("expires only the latest notification after two seconds", function()
        local source = read("src/client/pickups/usePickupNotification.luau")
        assertContains(source, "task.delay(2", "notification lifetime must be two seconds")
        assertContains(source, "notificationGeneration", "hook must track notification generations")
        assertContains(source, "currentGeneration", "old timers must not clear newer notifications")
        assertContains(source, "controller.changed:Connect", "hook must subscribe to controller changes")
    end)

    harness.it("starts the notification controller before mounting the app", function()
        local source = read("src/client/init.client.luau")
        local startPosition = string.find(source, "PickupNotificationController.start()", 1, true) or 0
        local renderPosition = string.find(source, "root:render", 1, true) or 0

        harness.assert.truthy(startPosition > 0, "client init must start the notification controller")
        harness.assert.truthy(renderPosition > 0, "client init must mount the app")
        harness.assert.truthy(startPosition < renderPosition, "controller must start before React renders")
    end)
end)
```

- [ ] **Step 2: Run the tests and verify the client checks fail**

Run:

```bash
lune run test
```

Expected: the new suite fails because the `src/client/pickups` modules and the
startup call do not exist yet.

- [ ] **Step 3: Implement the notification controller**

Create `src/client/pickups/PickupNotificationController.luau` with strict mode,
the existing shared remotes import, and the existing Signal package. Keep the
controller independent from React:

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = require(ReplicatedStorage.Shared.remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

type Connection = RBXScriptConnection
type SignalConnection = {
    Disconnect: (self: SignalConnection) -> (),
}
type ChangedSignal = {
    Fire: (self: ChangedSignal, itemId: string) -> (),
    Connect: (self: ChangedSignal, callback: (itemId: string) -> ()) -> SignalConnection,
}

local pickupCollected = remotes.PickupCollected :: RemoteEvent
local changed = (Signal.new() :: any) :: ChangedSignal
local connection: Connection? = nil
local started = false
local sessionGeneration = 0

export type PickupNotificationController = {
    start: () -> (),
    stop: () -> (),
    changed: typeof(changed),
}

local controller = {
    changed = changed,
} :: PickupNotificationController

function controller.start(): ()
    if started then
        return
    end

    sessionGeneration += 1
    local generation = sessionGeneration
    started = true
    connection = pickupCollected.OnClientEvent:Connect(function(itemId: string)
        if not started or generation ~= sessionGeneration then
            return
        end
        changed:Fire(itemId)
    end)
end

function controller.stop(): ()
    if not started then
        return
    end

    started = false
    sessionGeneration += 1
    if connection ~= nil then
        connection:Disconnect()
        connection = nil
    end
end

return controller
```

Use the same lifecycle and stale-session protection as
`src/client/inventory/InventoryController.luau`.

- [ ] **Step 4: Implement the React hook with replacement-safe expiration**

Create `src/client/pickups/usePickupNotification.luau`. The hook must keep one
item ID, replace it on every signal, and prevent an earlier `task.delay` from
clearing a later message:

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local controller = require(script.Parent.PickupNotificationController)

local function usePickupNotification(): string?
    local itemId, setItemId = React.useState(nil :: string?)

    React.useEffect(function()
        local active = true
        local notificationGeneration = 0
        local connection = controller.changed:Connect(function(nextItemId: string)
            notificationGeneration += 1
            local currentGeneration = notificationGeneration
            setItemId(nextItemId)

            task.delay(2, function()
                if active and currentGeneration == notificationGeneration then
                    setItemId(nil)
                end
            end)
        end)

        return function()
            active = false
            notificationGeneration += 1
            connection:Disconnect()
        end
    end, {})

    return itemId
end

return usePickupNotification
```

Do not queue notifications and do not expose a second notification state.

- [ ] **Step 5: Start the controller from client initialization**

In `src/client/init.client.luau`, require the controller beside
`InventoryController`, then start it before `InventoryController.start()` or at
least before `root:render(...)`:

```lua
local PickupNotificationController = require(script.pickups.PickupNotificationController)

PickupNotificationController.start()
InventoryController.start()
```

The controller must be started before any possible pickup event is processed by
the mounted UI.

- [ ] **Step 6: Run the pipeline tests and lint**

Run:

```bash
lune run test
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Expected: all source-contract tests pass and both lint configurations report no
diagnostics.

- [ ] **Step 7: Commit the client notification pipeline**

Inspect the worktree and stage only the Task 2 files:

```bash
git add -- src/client/pickups/PickupNotificationController.luau src/client/pickups/usePickupNotification.luau src/client/init.client.luau tests/client/pickups/PickupNotification.spec.luau
git commit -m "feat: add client pickup notifications"
```

### Task 3: Make The Inventory Toggleable And Render The Notification

**Files:**
- Modify: `src/client/ui/App.luau:1-100`
- Modify: `tests/client/ui/App.spec.luau:6-15`

**Interfaces:**
- Consumes: `usePickupNotification() -> string?`, shared `items` catalog, and Roblox `UserInputService`.
- Produces: an inventory panel hidden by default, toggled by `Enum.KeyCode.I`, and a lower-left notification displaying `Pegou <item name>` for the latest pickup.

- [ ] **Step 1: Add failing source-level UI tests**

Extend `tests/client/ui/App.spec.luau` with a helper and these cases:

```lua
local function assertContains(source: string, text: string, message: string): ()
    harness.assert.truthy(string.find(source, text, 1, true), message)
end

harness.describe("App inventory controls", function()
    harness.it("starts the inventory hidden and listens for the I key", function()
        local source = fs.readFile("src/client/ui/App.luau")
        assertContains(source, "React.useState(false)", "inventory visibility must start false")
        assertContains(source, "UserInputService.InputBegan", "App must listen for keyboard input")
        assertContains(source, "Enum.KeyCode.I", "App must use the I key")
        assertContains(source, "gameProcessedEvent", "App must receive the processed-input flag")
        assertContains(source, "gameProcessedEvent or", "processed input must be ignored")
        assertContains(source, "if inventoryVisible then", "inventory panel must be conditional")
    end)

    harness.it("renders one lower-left pickup notification", function()
        local source = fs.readFile("src/client/ui/App.luau")
        assertContains(source, "usePickupNotification", "App must consume pickup notifications")
        assertContains(source, 'Text = "Pegou "', "notification must use the Pegou prefix")
        assertContains(source, "AnchorPoint = Vector2.new(0, 1)", "notification must anchor at the lower-left")
        assertContains(source, "Position = UDim2.new(0, 24, 1, -24)", "notification must have lower-left offset")
        assertContains(source, "PickupNotification", "notification must have a single keyed UI child")
    end)
end)
```

Keep the existing test that rejects an element array as a nested React child.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
lune run test
```

Expected: the new UI cases fail because `App` currently renders the panel
unconditionally and has no keyboard or notification code.

- [ ] **Step 3: Add the visibility state and input effect**

In `src/client/ui/App.luau`:

1. Acquire `UserInputService` beside the existing services.
2. Require `usePickupNotification` beside `useInventory`.
3. At the start of `App`, initialize:

```lua
local inventoryVisible, setInventoryVisible = React.useState(false)
local notificationItemId = usePickupNotification()

React.useEffect(function()
    local connection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
        if gameProcessedEvent or input.KeyCode ~= Enum.KeyCode.I then
            return
        end

        setInventoryVisible(function(previousVisible: boolean): boolean
            return not previousVisible
        end)
    end)

    return function()
        connection:Disconnect()
    end
end, {})
```

Use the functional state setter so repeated key events do not capture a stale
`inventoryVisible` value. Do not listen for `InputEnded`, and do not change the
`ScreenGui` visibility.

- [ ] **Step 4: Make the inventory panel conditional**

Keep the existing item list-building code and panel styling. Store the current
panel element in a local variable:

```lua
local inventoryPanel = if inventoryVisible
    then React.createElement("Frame", {
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = Color3.fromRGB(20, 22, 30),
        BackgroundTransparency = 0.08,
        Position = UDim2.fromOffset(24, 154),
        Size = UDim2.new(1, -48, 0, 220),
    }, {
        Corner = React.createElement("UICorner", {
            CornerRadius = UDim.new(0, 10),
        }),
        Stroke = React.createElement("UIStroke", {
            Color = Color3.fromRGB(107, 92, 168),
            Transparency = 0.25,
        }),
        SizeConstraint = React.createElement("UISizeConstraint", {
            MaxSize = Vector2.new(360, 220),
        }),
        Title = React.createElement("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(16, 12),
            Size = UDim2.new(1, -32, 0, 24),
            Font = Enum.Font.GothamBold,
            Text = "INVENTÁRIO",
            TextColor3 = Color3.fromRGB(241, 237, 255),
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextSize = 16,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        List = React.createElement("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(16, 44),
            Size = UDim2.new(1, -32, 1, -56),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarImageColor3 = Color3.fromRGB(107, 92, 168),
            ScrollBarThickness = 4,
        }, listChildren),
    })
    else nil
```

Use `InventoryPanel = inventoryPanel` in the `ScreenGui` children. Do not move
the inventory data fetching into the server or change the existing loading text.

- [ ] **Step 5: Resolve the item name and add the notification element**

After obtaining `notificationItemId`, resolve the catalog name with the same
fallback convention already used by the inventory list:

```lua
local notificationItem = if notificationItemId ~= nil then items[notificationItemId] else nil
local notificationName = if notificationItem ~= nil then notificationItem.name else notificationItemId
```

Add one keyed child to the `ScreenGui` only when `notificationName` is not nil:

```lua
PickupNotification = if notificationName ~= nil
    then React.createElement("TextLabel", {
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = Color3.fromRGB(20, 22, 30),
        BackgroundTransparency = 0.08,
        Position = UDim2.new(0, 24, 1, -24),
        Size = UDim2.fromOffset(240, 42),
        Font = Enum.Font.GothamBold,
        Text = "Pegou " .. notificationName,
        TextColor3 = Color3.fromRGB(241, 237, 255),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, {
        Padding = React.createElement("UIPadding", {
            PaddingLeft = UDim.new(0, 14),
            PaddingRight = UDim.new(0, 14),
        }),
        Corner = React.createElement("UICorner", {
            CornerRadius = UDim.new(0, 8),
        }),
        Stroke = React.createElement("UIStroke", {
            Color = Color3.fromRGB(107, 92, 168),
            Transparency = 0.25,
        }),
    })
    else nil,
```

Preserve the existing `ScreenGui` name, `ResetOnSpawn = false`, and sibling
z-index behavior. The notification must remain visible when the inventory panel
is hidden.

- [ ] **Step 6: Run the UI tests and lint**

Run:

```bash
lune run test
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Expected: all tests pass, including the existing React child-shape regression
test, and both lint configurations report no diagnostics.

- [ ] **Step 7: Commit the UI behavior**

Inspect `git status --short`, then stage only the Task 3 files:

```bash
git add -- src/client/ui/App.luau tests/client/ui/App.spec.luau
git commit -m "feat: toggle inventory and show pickup toast"
```

### Task 4: Run Full Repository Verification

**Files:**
- Verify: all changed source and test files from Tasks 1-3
- Generate: ignored `sourcemap.json` through Rojo

**Interfaces:**
- Consumes: the completed server remote, client notification pipeline, and conditional React UI.
- Produces: a clean test, lint, typecheck, and Rojo build result suitable for Studio validation.

- [ ] **Step 1: Run all behavioral tests**

Run:

```bash
lune run test
```

Expected: every discovered suite passes, including inventory, UI, remote
contract, and notification pipeline source checks.

- [ ] **Step 2: Run both platform-specific lint configurations**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Expected: no diagnostics from either command.

- [ ] **Step 3: Run the Roblox typecheck with the project sourcemap**

Run exactly in this order:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

Expected: the Roblox analysis completes without errors or warnings.

- [ ] **Step 4: Run the Lune typecheck separately**

Run:

```bash
luau-lsp analyze --platform standard \
  --base-luaurc typecheck/lune.luaurc --formatter gnu tests lune
```

Expected: the standard-platform analysis completes without Roblox-global
diagnostics.

- [ ] **Step 5: Build the Rojo place**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx
```

Expected: the build succeeds and includes `ReplicatedStorage.Remotes`, the
client pickup modules, and the server pickup service in the generated place.

- [ ] **Step 6: Perform Studio acceptance checks**

Start the generated place in Roblox Studio and verify each behavior manually:

1. The inventory panel is absent at startup.
2. Pressing `I` shows the panel; pressing it again hides the panel.
3. Type in the chat and confirm that `I` does not toggle the panel while the
   chat input is processed.
4. Collect one torch and confirm `Pegou Tocha` appears at the lower-left.
5. Confirm the message disappears after 2 seconds.
6. Collect another item before the first message expires and confirm the new
   message replaces it and remains for 2 more seconds.
7. Open the inventory after collection and confirm the item list still comes
   from the normal `InventoryChanged` snapshot.
8. Confirm a failed `addItem` path does not show a notification or destroy the
   pickup.

- [ ] **Step 7: Inspect the final diff and worktree**

Run:

```bash
git status --short
```

Review that only the intended feature files and commits are present, that no
generated `Packages/` files were edited, and that no unrelated worktree changes
were reverted.
