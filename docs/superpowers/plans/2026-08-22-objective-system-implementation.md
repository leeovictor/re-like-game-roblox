# Sistema de Objetivos Event-Driven Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with automated verification. Do not create git commits; keep the worktree available for the developer's final manual review. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar um sistema client-side de objetivos orientado por eventos, com objetivos paralelos, dependencias, fatos fora de ordem e UI integrada ao inventario.

**Architecture:** Um barramento local `GameplayEvents` distribuira eventos semanticos sem conhecer consumidores. `DoorController` e um adaptador do evento server-side `PickupCollected` publicarao eventos; `ObjectiveController` registrara os fatos da sessao, processara um grafo declarativo de objetivos e emitira sinais para o React. `App.luau` continuara sendo o unico dono da UI.

**Tech Stack:** Luau `--!strict`, Roblox Studio/DataModel, Rojo 7.7.0, TestEZ no Roblox Studio, Selene 0.29.0, luau-lsp 1.69.0, React e ReactRoblox existentes no Wally.

## Global Constraints

- O progresso sera valido somente durante a sessao atual; respawn nao reinicia os objetivos e nao havera persistencia entre servidores ou sessoes.
- O sistema sera client-side; nao criar servico de objetivos no servidor, remoto de progresso ou alteracao de `InventoryState`.
- Usar um barramento geral local sem fila, replay, persistencia ou remotes proprios.
- Publishers nao importam nem conhecem o `ObjectiveController`.
- `door_blocked` significa porta trancada sem item compativel; `door_unlocked` e `door_entered` so serao publicados apos sucesso.
- `item_collected` sera derivado da confirmacao existente `PickupCollected`, nao da comparacao de snapshots do inventario.
- Usar o atributo estavel `DoorKey`; nunca usar o nome do Model como fallback.
- Um ou varios objetivos podem ficar ativos; dependencias podem exigir varios objetivos concluidos.
- Eventos anteriores devem poder satisfazer objetivos ativados posteriormente.
- Condicoes simples usam filtros declarativos; condicoes compostas usam `completeIf` somente para leitura.
- A lista persistente aparece apenas quando o inventario esta aberto, no canto superior direito.
- Avisos de novos objetivos duram tres segundos; um lote toca um unico som e substitui o aviso anterior.
- `OBJECTIVE_SOUND_ID` inicia como string vazia; string vazia nao cria nem reproduz `Sound`.
- `App.luau` continua sendo o unico dono da arvore React e do `ScreenGui` existente.
- Specs de UI permanecem fora do escopo TestEZ; validar o layout manualmente no Roblox Studio.
- Specs strict devem criar fixtures em `beforeEach` e destruir ou desconectar tudo em `afterEach`.
- O projeto de testes deve mapear somente os subdiretorios de producao necessarios e nao deve iniciar os entrypoints normais.
- Nao criar commits durante a implementacao; a revisao de toda a alteracao sera feita manualmente pelo desenvolvedor ao final.
- Nao usar subagentes para reviews isolados entre tarefas.
- Preservar imports baseados em `script`, a pasta `src/server/cave-engine/` se ela for tocada no futuro e o uso de `script["cave-engine"]` nessa pasta.

---

## File Map

### Event infrastructure

- Create: `src/client/events/GameplayEvents.luau` - tipos dos eventos iniciais e barramento local com `emit` e `subscribe`.
- Create: `src/client/events/PickupEventBridge.luau` - converte `PickupCollected.OnClientEvent` em `item_collected`.
- Create: `tests/client/events/GameplayEvents.spec.luau` - contrato de publicacao e assinaturas do barramento.
- Create: `tests/client/events/PickupEventBridge.spec.luau` - lifecycle e conversao do evento de coleta usando fonte injetada.
- Modify: `test.project.json` - mapear `src/client/events` no root client de testes.

### Gameplay publishers

- Modify: `src/shared/doors/doorTypes.luau` - adicionar a constante `DOOR_KEY_ATTRIBUTE`.
- Modify: `src/client/doors/DoorController.luau` - receber um emissor injetado e publicar os resultados semanticos da porta.
- Modify: `tests/client/doors/DoorController.spec.luau` - fixtures com `DoorKey` e assertions dos eventos publicados.

### Objective engine

- Create: `src/client/objectives/ObjectiveConfig.luau` - configuracao da campanha inicial editavel pelo game designer.
- Create: `src/client/objectives/ObjectiveController.luau` - validacao, fatos, ativacao, conclusao, dependencias, sinais e som.
- Create: `tests/client/objectives/ObjectiveController.spec.luau` - cobertura do motor de progresso sem React.
- Modify: `test.project.json` - mapear `src/client/objectives` no root client de testes.

### UI bridge and rendering

- Create: `src/client/objectives/useObjectives.luau` - assinatura React do estado persistente da etapa.
- Create: `src/client/objectives/useObjectiveNotification.luau` - assinatura React do lote transitorio e timer de tres segundos.
- Modify: `src/client/ui/App.luau` - painel no topo direito dentro do inventario e aviso empilhado no mesmo canto.
- Modify: `src/client/init.client.luau` - iniciar `ObjectiveController` antes do bridge e do `InteractionController`.

### Verification

- Regenerate: `test-sourcemap.json` using `rojo sourcemap` after changing `test.project.json`.
- No create: UI specs. The repository intentionally excludes React tree specs from this workflow.

## API Contracts

Implement the following contracts before integrating consumers. These names are the interface between the tasks.

### Gameplay event bus

`GameplayEvents.luau` exports the initial discriminated event union:

```lua
export type EventName =
    "door_blocked"
    | "door_unlocked"
    | "door_entered"
    | "item_collected"
    | "area_entered"
    | "switches_changed"

export type GameplayEvent =
    { name: "door_blocked", doorKey: string }
    | { name: "door_unlocked", doorKey: string }
    | { name: "door_entered", doorKey: string }
    | { name: "item_collected", itemId: string }
    | { name: "area_entered", areaKey: string }
    | { name: "switches_changed", switchesOn: number }

export type SignalConnection = {
    Disconnect: (self: SignalConnection) -> (),
}

export type GameplayEvents = {
    emit: (event: GameplayEvent) -> (),
    subscribe: (callback: (event: GameplayEvent) -> ()) -> SignalConnection,
}
```

The module returns one singleton implementing `GameplayEvents`. It uses one
Signal and never stores or replays events. The `ObjectiveController` owns the
session history.

### Objective definitions

`ObjectiveController.luau` exports these conceptual types:

```lua
export type EventFilter = {
    event: GameplayEvents.EventName,
    doorKey: string?,
    itemId: string?,
    areaKey: string?,
}

export type Facts = {
    hasEvent: (
        self: Facts,
        eventName: GameplayEvents.EventName,
        fields: { [string]: string | number | boolean }?
    ) -> boolean,
    latest: (
        self: Facts,
        eventName: GameplayEvents.EventName
    ) -> GameplayEvents.GameplayEvent?,
}

export type ObjectiveDefinition = {
    id: string,
    text: string,
    initial: boolean?,
    startsWhen: EventFilter?,
    requires: { string }?,
    completesWhen: EventFilter?,
    completeIf: ((facts: Facts) -> boolean)?,
}

export type ObjectiveView = {
    id: string,
    text: string,
    completed: boolean,
}

export type ObjectiveState = {
    objectives: { ObjectiveView },
}

export type SignalConnection = GameplayEvents.SignalConnection

export type ChangedSignal = {
    Connect: (self: ChangedSignal, callback: (state: ObjectiveState?) -> ()) -> SignalConnection,
}

export type ActivatedSignal = {
    Connect: (self: ActivatedSignal, callback: (batch: { ObjectiveView }) -> ()) -> SignalConnection,
}

export type ObjectiveController = {
    start: () -> (),
    stop: () -> (),
    getState: () -> ObjectiveState?,
    changed: ChangedSignal,
    activated: ActivatedSignal,
}
```

`completesWhen` and `completeIf` are mutually exclusive. An objective must
have at least one activation gate: `initial`, `startsWhen`, or `requires`.
When multiple activation gates are present, every declared gate must be true.

The controller factory accepts injected dependencies for isolated tests:

```lua
export type EventSource = {
    subscribe: (
        self: EventSource,
        callback: (event: GameplayEvents.GameplayEvent) -> ()
    ) -> SignalConnection,
}

export type Dependencies = {
    events: EventSource,
    playSound: () -> (),
}

new(
    definitions: { ObjectiveDefinition },
    dependencies: Dependencies?
) -> ObjectiveController
```

The default controller uses `GameplayEvents` and the local objective sound
implementation. Tests pass a fake event source and a sound spy.

## Phase 1: Events and Publishers

### Task 1: Add the local GameplayEvents bus

**Files:**
- Create: `src/client/events/GameplayEvents.luau`
- Create: `tests/client/events/GameplayEvents.spec.luau`
- Modify: `test.project.json:57-84` to add the `events` source directory under the client test tree.

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.Signal`.
- Produces: `GameplayEvents.emit(event)` and `GameplayEvents.subscribe(callback)` with the event union in `API Contracts`.

- [ ] **Step 1: Add the client events mapping to the test project**

Insert the `events` child alongside the existing `doors`, `dialogue`, and
`interactions` mappings:

```json
"events": {
  "$path": "src/client/events"
},
```

Do not add the production entrypoint or any UI test root to `test.project.json`.

- [ ] **Step 2: Write the failing bus spec**

Create a strict TestEZ module that requires the real client module from the
DataModel and cleans every subscription:

```lua
--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local GameplayEvents = require(client.events.GameplayEvents)

return function()
    describe("GameplayEvents", function()
        local connections: { any } = {}

        afterEach(function()
            for _, connection in connections do
                connection:Disconnect()
            end
            connections = {}
        end)

        it("delivers the same event to one subscriber", function()
            local received: any = nil
            table.insert(connections, GameplayEvents.subscribe(function(event: any)
                received = event
            end))

            local event: any = { name = "item_collected", itemId = "access_card" }
            GameplayEvents.emit(event)

            expect(received).to.equal(event)
        end)

        it("delivers to multiple subscribers and stops after disconnect", function()
            local firstCalls = 0
            local secondCalls = 0
            local first = GameplayEvents.subscribe(function(_event: any)
                firstCalls += 1
            end)
            local second = GameplayEvents.subscribe(function(_event: any)
                secondCalls += 1
            end)
            table.insert(connections, first)
            table.insert(connections, second)

            GameplayEvents.emit({ name = "door_entered", doorKey = "main_exit" })
            first:Disconnect()
            GameplayEvents.emit({ name = "door_entered", doorKey = "main_exit" })

            expect(firstCalls).to.equal(1)
            expect(secondCalls).to.equal(2)
        end)

        it("does not replay an event to a later subscriber", function()
            GameplayEvents.emit({ name = "item_collected", itemId = "fuse" })
            local received = false
            table.insert(connections, GameplayEvents.subscribe(function(_event: any)
                received = true
            end))

            expect(received).to.equal(false)
        end)
    end)
end
```

- [ ] **Step 3: Run the focused client suite and verify it fails for the missing module**

Run a clean test Play session after syncing the test project:

```bash
rojo sync test.project.json
```

Run from the client DataModel:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Expected: the new `GameplayEvents` spec fails because the module does not yet
exist. Do not treat the production client entrypoint as a test runner.

- [ ] **Step 4: Implement the minimal strict bus**

Create one private Signal and expose only the two public operations. The event
union must include the exact fields from `API Contracts`:

```lua
local Signal = require(ReplicatedStorage.Packages.Signal)
local changed = (Signal.new() :: any) :: ChangedSignal

local function emit(event: GameplayEvent): ()
    changed:Fire(event)
end

local function subscribe(callback: (event: GameplayEvent) -> ()): SignalConnection
    return changed:Connect(callback) :: SignalConnection
end
```

Do not add a queue, event history, wildcard event registry, `start()`,
`stop()`, RemoteEvent, or ObjectiveController import to this module.

- [ ] **Step 5: Run the focused spec and verify it passes**

Run the same client runner again. Expected: the three `GameplayEvents` tests
pass with zero failures. Stop Play after the run so the singleton Signal does
not leak into the next test session.

- [ ] **Step 6: Keep the phase 1 changes available for final review**

Do not create a commit. Keep the bus, its spec, the test-project mapping, and
the generated sourcemap in the working tree so the complete implementation can
be reviewed together.

### Task 2: Publish semantic door events

**Files:**
- Modify: `src/shared/doors/doorTypes.luau:26-34`
- Modify: `src/client/doors/DoorController.luau:18-124`
- Modify: `tests/client/doors/DoorController.spec.luau:8-77` and add event cases near the existing action tests.

**Interfaces:**
- Consumes: `GameplayEvents.GameplayEvent` and `doorTypes.DOOR_KEY_ATTRIBUTE`.
- Produces: a new `Dependencies.emit` callback in `DoorController.new()`; the default points to `GameplayEvents.emit`.

- [ ] **Step 1: Extend the shared door constants**

Add this exact constant to the returned table in `doorTypes.luau`:

```lua
DOOR_KEY_ATTRIBUTE = "DoorKey",
```

Do not set `DoorKey` automatically from the Model name in
`DoorModelInitializer`; level authors must choose the stable logical key.

- [ ] **Step 2: Update the existing DoorController fixture to provide DoorKey**

Import `doorTypes` in the spec and change the fixture helper to accept a logic
key separately from its display name:

```lua
local function makeDoor(
    name: string,
    locked: boolean,
    requiredItem: string,
    doorKey: string?
): Model
    local door = Instance.new("Model")
    door.Name = name
    door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, locked)
    door:SetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE, requiredItem)
    if doorKey ~= nil then
        door:SetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE, doorKey)
    end
    door:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DOOR_TYPE)
    door.Parent = workspace
    return door
end
```

Pass a non-empty key in existing tests that exercise a valid door. Keep one
test without a key for the missing-key behavior.

- [ ] **Step 3: Add event assertions before changing the publisher**

Add an `events` table in the spec and inject an emitter into every controller
fixture:

```lua
local events: { any } = {}

controller = DoorController.new({
    getInventory = function()
        return { version = 1, items = inventoryItems, equipped = {} }
    end,
    invokeDoor = function(request: any)
        table.insert(requests, request)
        return invokeResult
    end,
    emit = function(event: any)
        table.insert(events, event)
    end,
    dialogue = {
        show = function(text: string, callback: any)
            table.insert(shown, text)
            if callback ~= nil then
                table.insert(dialogueCallbacks, callback)
            end
        end,
    },
    transition = {
        run = function(request: any, callback: any)
            transitionCalls += 1
            table.insert(transitionRequests, request)
            table.insert(transitionCallbacks, callback)
            return true
        end,
    },
})
```

Add these failing cases:

```lua
it("publishes door_blocked when a locked door has no compatible item", function()
            local door = addInstance(makeDoor("VisualExit", true, "iron_key", "facility_entrance"))

    controller.interact(door)

    expect(events[1].name).to.equal("door_blocked")
            expect(events[1].doorKey).to.equal("facility_entrance")
end)

it("publishes door_unlocked only after a successful unlock", function()
    local door = addInstance(makeDoor("VisualExit", true, "iron_key", "logical_exit"))
    table.insert(inventoryItems, { uid = "key-1", itemId = "iron_key" })
    invokeResult = { success = true, action = "unlock" }

    controller.interact(door)

    expect(events[1].name).to.equal("door_unlocked")
    expect(events[1].doorKey).to.equal("logical_exit")
end)

it("publishes door_entered only after the transition request succeeds", function()
    local door = addInstance(makeDoor("DoorVisual", false, "", "facility_entrance"))
    invokeResult = { success = true, action = "enter" }

    controller.interact(door)
    transitionCallbacks[1]({ success = true, action = "enter" })

    expect(events[1].name).to.equal("door_entered")
    expect(events[1].doorKey).to.equal("facility_entrance")
end)

it("does not publish a progress event for a door without DoorKey", function()
    local door = addInstance(makeDoor("NoLogicalKey", true, "iron_key", nil))

    controller.interact(door)

    expect(#events).to.equal(0)
end)
```

- [ ] **Step 4: Implement the injected semantic publisher**

Add `emit` to the `Dependencies` type and use `GameplayEvents.emit` in the
default dependencies. Add one helper that reads `DoorKey`, warns once for a
missing or empty key, and returns without publishing when the key is invalid:

```lua
local warnedDoors: { [Model]: boolean } = {}

local function publishDoorEvent(
    door: Model,
    eventName: "door_blocked" | "door_unlocked" | "door_entered"
): ()
    local doorKey = door:GetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE)
    if type(doorKey) ~= "string" or doorKey == "" then
        if not warnedDoors[door] then
            warnedDoors[door] = true
            warn(string.format("Door has no valid DoorKey: %s", door:GetFullName()))
        end
        return
    end
    dependencies.emit({ name = eventName, doorKey = doorKey })
end
```

Use the helper at these exact semantic points:

1. In the locked/no-compatible-item branch, publish `door_blocked` before
   showing the locked dialogue.
2. In the locked/has-item branch, publish `door_unlocked` only when the result
   has `success == true` and `action == "unlock"`.
3. In the same branch, publish `door_blocked` when the server returns
   `reason == "missing_item"`.
4. In the open-door transition callback, publish `door_entered` only when the
   result has `success == true` and `action == "enter"`.
5. Do not publish for distance, invalid configuration, busy, stale, or other
   failures.

The existing dialogue, transition, and inventory behavior must remain
unchanged. The controller must not import `ObjectiveController`.

- [ ] **Step 5: Run the focused DoorController spec**

Run the client runner with only the client suite available. Expected: the
updated DoorController tests pass and the prior action/dialogue tests remain
green. Inspect Output for exactly one warning in the missing-`DoorKey` case;
do not assert warning counts globally because other tests can use Roblox
warnings.

- [ ] **Step 6: Keep the door publisher changes available for final review**

Do not create a commit. Run `git diff --check` after the focused tests and keep
the door constants, controller, and spec changes in the same working tree.

### Task 3: Bridge confirmed pickup events

**Files:**
- Create: `src/client/events/PickupEventBridge.luau`
- Create: `tests/client/events/PickupEventBridge.spec.luau`

**Interfaces:**
- Consumes: `remotes.PickupCollected.OnClientEvent`, with payload `itemId: string`.
- Produces: `GameplayEvents.emit({ name = "item_collected", itemId = itemId })`.

The bridge factory and lifecycle use this contract:

```lua
export type Source = {
    Connect: (
        self: Source,
        callback: (itemId: string) -> ()
    ) -> GameplayEvents.SignalConnection,
}

export type Dependencies = {
    source: Source,
    emit: (event: GameplayEvents.GameplayEvent) -> (),
}

new(dependencies: Dependencies) -> PickupEventBridge
start: () -> ()
stop: () -> ()
```

The publisher is an adapter for the existing server-confirmed remote rather
than a call from `PickupController` immediately after requesting collection.
This prevents an objective event from being emitted by a request that the
server rejected and avoids deriving gameplay events from inventory snapshots.
`PickupController` remains responsible only for sending `CollectPickup`.

- [ ] **Step 1: Write the bridge spec with an injected source**

The bridge factory must accept a source with `Connect` and an injected `emit`
function so the test does not pretend to deliver `RemoteEvent:FireClient` from
the client DataModel:

```lua
--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local Bridge = require(client.events.PickupEventBridge)

return function()
    describe("PickupEventBridge", function()
        it("converts a confirmed item id into item_collected", function()
            local callback: ((string) -> ())? = nil
            local disconnected = false
            local events: { any } = {}
            local source = {
                Connect = function(_self: any, nextCallback: (string) -> ())
                    callback = nextCallback
                    return {
                        Disconnect = function()
                            disconnected = true
                        end,
                    }
                end,
            }
            local bridge = Bridge.new({
                source = source,
                emit = function(event: any)
                    table.insert(events, event)
                end,
            })

            bridge.start()
            callback = assert(callback, "bridge callback")
            callback("access_card")

            expect(events[1].name).to.equal("item_collected")
            expect(events[1].itemId).to.equal("access_card")
            bridge.stop()
            expect(disconnected).to.equal(true)
        end)

        it("does not duplicate the source connection on repeated start", function()
            local connections = 0
            local disconnects = 0
            local source = {
                Connect = function(_self: any, _callback: (string) -> ())
                    connections += 1
                    return {
                        Disconnect = function()
                            disconnects += 1
                        end,
                    }
                end,
            }
            local bridge = Bridge.new({
                source = source,
                emit = function(_event: any) end,
            })

            bridge.start()
            bridge.start()
            bridge.stop()
            bridge.stop()

            expect(connections).to.equal(1)
            expect(disconnects).to.equal(1)
        end)
    end)
end
```

- [ ] **Step 2: Run the bridge spec and verify it fails before the module exists**

Run the client TestEZ runner. Expected: the bridge spec fails because
`PickupEventBridge` does not exist. The test must not call `FireClient` from a
client runner.

- [ ] **Step 3: Implement the bridge lifecycle**

Implement `new({ source, emit })`, `start()`, and `stop()`. The default source
must be `remotes.PickupCollected.OnClientEvent`; the default emitter must be
`GameplayEvents.emit`. Ignore an invalid empty/non-string item payload instead
of publishing a malformed event. Repeated `start()` and `stop()` must be
idempotent.

- [ ] **Step 4: Run the bridge and existing pickup notification specs**

Run the client TestEZ runner. Expected: the new bridge tests and the existing
`tests/client/pickups/PickupNotification.spec.luau` pass, with the existing
pickup notification signal still delivering its item IDs.

The production entrypoint is intentionally wired in Task 4, after the
`ObjectiveController` exists. Do not start the bridge from `init.client.luau`
before there is an objective subscriber, and do not add a second pickup event
publisher to `PickupController`.

- [ ] **Step 5: Run phase 1 static checks**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Expected: Selene returns zero diagnostics and the generated sourcemap contains
the `Client.events` tree. Typechecking will be repeated after the objective
engine and UI are added.

- [ ] **Step 6: Keep the pickup bridge changes available for final review**

Do not create a commit. Confirm the bridge spec and phase 1 static checks pass,
then leave all phase 1 changes in the working tree for the final manual review.

## Phase 2: Objective Controller

### Task 4: Implement the declarative objective engine

**Files:**
- Create: `src/client/objectives/ObjectiveConfig.luau`
- Create: `src/client/objectives/ObjectiveController.luau`
- Create: `tests/client/objectives/ObjectiveController.spec.luau`
- Modify: `test.project.json:57-84` to add the `objectives` source directory under the client test tree.
- Modify: `src/client/init.client.luau` to start the controller before the event bridge and interaction controller.

**Interfaces:**
- Consumes: `EventSource`, `GameplayEvents.GameplayEvent`, and the approved event definitions.
- Produces: `ObjectiveController.new(definitions, dependencies?)`, `start()`, `stop()`, `getState()`, `changed`, and `activated`.

- [ ] **Step 1: Add the objectives mapping to the test project**

Insert:

```json
"objectives": {
  "$path": "src/client/objectives"
},
```

Keep `src/client/init.client.luau` excluded from `test.project.json`.

- [ ] **Step 2: Write the objective controller fixture and failing behavior specs**

Create a fake event source with an explicit `emit` helper. The source must
implement the same `subscribe` contract as the production bus:

```lua
local function newEventSource(): (any, (event: any) -> ())
    local listeners: { [number]: (event: any) -> () } = {}
    local nextId = 0
    local source = {}

    function source:subscribe(callback: (event: any) -> ())
        nextId += 1
        local id = nextId
        listeners[id] = callback
        return {
            Disconnect = function()
                listeners[id] = nil
            end,
        }
    end

    local function emit(event: any): ()
        local snapshot = table.clone(listeners)
        for _, callback in snapshot do
            callback(event)
        end
    end

    return source, emit
end
```

Require the production controller through the mapped DataModel path:

```lua
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local ObjectiveController = require(client.objectives.ObjectiveController)
```

Track every controller and Signal connection in the spec. In `afterEach`, call
`stop()` on every controller, disconnect every Signal connection, and clear the
tables before destroying any Instance fixture.

Use a `playSoundCalls` counter and capture `changed` and `activated` signals.
The spec must cover at least these concrete cases:

```lua
it("starts the initial objective and emits one activation batch", function()
    local source, emit = newEventSource()
    local soundCalls = 0
    local controller = ObjectiveController.new({
        {
            id = "find_exit",
            text = "Ache uma saida",
            initial = true,
            completesWhen = { event = "door_blocked", doorKey = "facility_entrance" },
        },
    }, {
        events = source,
        playSound = function()
            soundCalls += 1
        end,
    })
    local batches: { { any } } = {}
    controller.activated:Connect(function(batch: { any })
        table.insert(batches, batch)
    end)

    controller.start()

    local state = assert(controller.getState(), "objective state")
    expect(#state.objectives).to.equal(1)
    expect(state.objectives[1].id).to.equal("find_exit")
    expect(state.objectives[1].completed).to.equal(false)
    expect(#batches).to.equal(1)
    expect(#batches[1]).to.equal(1)
    expect(soundCalls).to.equal(1)
    emit({ name = "door_entered", doorKey = "other_door" })
    expect(assert(controller.getState()).objectives[1].completed).to.equal(false)
end)

it("records an item event before the item objective is activated", function()
    local source, emit = newEventSource()
    local controller = ObjectiveController.new({
        {
            id = "find_exit",
            text = "Ache uma saida",
            initial = true,
            completesWhen = { event = "door_blocked", doorKey = "cave_exit" },
        },
        {
            id = "find_card",
            text = "Encontre o cartao de acesso",
            startsWhen = { event = "door_blocked", doorKey = "facility_entrance" },
            completesWhen = { event = "item_collected", itemId = "access_card" },
        },
        {
            id = "access_facility",
            text = "Acesse a instalacao",
            requires = { "find_card" },
            completesWhen = { event = "door_entered", doorKey = "facility_entrance" },
        },
    }, {
        events = source,
        playSound = function() end,
    })
    controller.start()
    emit({ name = "item_collected", itemId = "access_card" })
    emit({ name = "door_blocked", doorKey = "facility_entrance" })

    local state = assert(controller.getState())
    expect(#state.objectives).to.equal(1)
    expect(state.objectives[1].id).to.equal("access_facility")
    expect(state.objectives[1].completed).to.equal(false)
end)

it("keeps parallel objectives marked independently until both are complete", function()
    local source, emit = newEventSource()
    local controller = ObjectiveController.new({
        {
            id = "find_gold",
            text = "Encontre o medalhao de ouro",
            startsWhen = { event = "door_blocked", doorKey = "main_exit" },
            completesWhen = { event = "item_collected", itemId = "gold_medallion" },
        },
        {
            id = "find_silver",
    text = "Encontre o medalhao de prata",
            startsWhen = { event = "door_blocked", doorKey = "main_exit" },
            completesWhen = { event = "item_collected", itemId = "silver_medallion" },
        },
        {
            id = "open_exit",
    text = "Abra a saida principal",
            requires = { "find_gold", "find_silver" },
            completesWhen = { event = "door_entered", doorKey = "main_exit" },
        },
    }, {
        events = source,
        playSound = function() end,
    })
    controller.start()
    emit({ name = "door_blocked", doorKey = "main_exit" })
    emit({ name = "item_collected", itemId = "gold_medallion" })

    local partial = assert(controller.getState())
    expect(#partial.objectives).to.equal(2)
    expect(partial.objectives[1].completed).to.equal(true)
    expect(partial.objectives[2].completed).to.equal(false)

    emit({ name = "item_collected", itemId = "silver_medallion" })

    local complete = assert(controller.getState())
    expect(#complete.objectives).to.equal(1)
    expect(complete.objectives[1].id).to.equal("open_exit")
end)

it("evaluates completeIf after either order of facts", function()
    local source, emit = newEventSource()
    local controller = ObjectiveController.new({
        {
            id = "restore_power",
            text = "Restabeleca a energia",
            initial = true,
            completeIf = function(facts: any): boolean
                local switches = facts:latest("switches_changed")
                return facts:hasEvent("item_collected", { itemId = "fuse" })
                    and switches ~= nil
                    and switches.switchesOn >= 3
            end,
        },
    }, {
        events = source,
        playSound = function() end,
    })
    controller.start()
    emit({ name = "switches_changed", switchesOn = 3 })
    expect(assert(controller.getState()).objectives[1].completed).to.equal(false)
    emit({ name = "item_collected", itemId = "fuse" })
    expect(assert(controller.getState()).objectives[1].completed).to.equal(true)
end)
```

Add the remaining validation and lifecycle cases with concrete malformed
definition tables. Use `pcall` around `start()` because validation is required
to fail before state mutation:

```lua
it("rejects malformed objective graphs before starting", function()
    local invalidCases = {
        {
            name = "duplicate ids",
            definitions = {
                { id = "duplicate", text = "One", initial = true, completesWhen = { event = "door_entered", doorKey = "a" } },
                { id = "duplicate", text = "Two", initial = true, completesWhen = { event = "door_entered", doorKey = "b" } },
            },
        },
        {
            name = "unknown dependency",
            definitions = {
                { id = "child", text = "Child", requires = { "missing" }, completesWhen = { event = "door_entered", doorKey = "a" } },
            },
        },
        {
            name = "dependency cycle",
            definitions = {
                { id = "one", text = "One", requires = { "two" }, completesWhen = { event = "door_entered", doorKey = "a" } },
                { id = "two", text = "Two", requires = { "one" }, completesWhen = { event = "door_entered", doorKey = "b" } },
            },
        },
        {
            name = "missing activation gate",
            definitions = {
                { id = "orphan", text = "Orphan", completesWhen = { event = "door_entered", doorKey = "a" } },
            },
        },
        {
            name = "missing completion condition",
            definitions = {
                { id = "unfinished", text = "Unfinished", initial = true },
            },
        },
        {
            name = "two completion conditions",
            definitions = {
                {
                    id = "ambiguous",
                    text = "Ambiguous",
                    initial = true,
                    completesWhen = { event = "door_entered", doorKey = "a" },
                    completeIf = function(_facts: any): boolean
                        return false
                    end,
                },
            },
        },
    }

    for _, invalidCase in invalidCases do
        local source = newEventSource()
        local ok, message = pcall(function()
            local controller = ObjectiveController.new(invalidCase.definitions, {
                events = source,
                playSound = function() end,
            })
            controller.start()
        end)
        expect(ok).to.equal(false)
        expect(type(message)).to.equal("string")
        expect(string.find(message :: string, invalidCase.name, 1, true) ~= nil).to.equal(true)
    end
end)

it("does not duplicate lifecycle work or complete on an unrelated event", function()
    local source, emit = newEventSource()
    local soundCalls = 0
    local controller = ObjectiveController.new({
        {
            id = "find_exit",
            text = "Ache uma saida",
            initial = true,
            completesWhen = { event = "door_blocked", doorKey = "cave_exit" },
        },
    }, {
        events = source,
        playSound = function()
            soundCalls += 1
        end,
    })

    controller.start()
    controller.start()
    emit({ name = "door_blocked", doorKey = "other_door" })
    expect(assert(controller.getState()).objectives[1].completed).to.equal(false)
    emit({ name = "door_blocked", doorKey = "cave_exit" })
    emit({ name = "door_blocked", doorKey = "cave_exit" })
    expect(assert(controller.getState()).objectives[1].completed).to.equal(true)
    expect(soundCalls).to.equal(1)
    controller.stop()
    controller.stop()
    expect(controller.getState()).to.equal(nil)
end)

it("keeps a failing completeIf objective active and reports the failure once", function()
    local source, emit = newEventSource()
    local controller = ObjectiveController.new({
        {
            id = "failing_predicate",
            text = "Predicate",
            initial = true,
            completeIf = function(_facts: any): boolean
                error("predicate failure")
            end,
        },
    }, {
        events = source,
        playSound = function() end,
    })

    controller.start()
    emit({ name = "item_collected", itemId = "fuse" })
    emit({ name = "item_collected", itemId = "fuse" })

    expect(assert(controller.getState()).objectives[1].completed).to.equal(false)
end)
```

The implementation must warn with the stable prefix
`Objective <id> completeIf failed`, so capture `LogService.MessageOut` in the
last test and assert that this prefix occurs exactly once. Disconnect that
connection in `afterEach` together with every Signal connection created by the
spec.

- [ ] **Step 3: Run the focused objective specs before implementation**

Run the client TestEZ runner. Expected: the new specs fail because the
controller and config modules do not exist. Existing client specs must still
load; a missing objective module should be the only new failure.

- [ ] **Step 4: Implement ObjectiveConfig with the approved initial campaign**

Return a list containing the first flow and use the stable door keys agreed in
the design:

```lua
return {
    {
        id = "find_exit",
        text = "Ache uma saida",
        initial = true,
        completesWhen = {
            event = "door_blocked",
            doorKey = "facility_entrance",
        },
    },
    {
        id = "find_access_card",
        text = "Encontre o cartao de acesso",
        startsWhen = {
            event = "door_blocked",
            doorKey = "cave_exit",
        },
        completesWhen = {
            event = "item_collected",
            itemId = "access_card",
        },
    },
    {
        id = "access_facility",
        text = "Acesse a instalacao",
        requires = { "find_access_card" },
        completesWhen = {
            event = "door_entered",
            doorKey = "cave_exit",
        },
    },
}
```

The medalion graph stays in the controller spec as an injected definition set
until the map has those `DoorKey` and item values. The configuration module must
not include objectives for map content that is not part of the current
campaign config.

- [ ] **Step 5: Implement config validation and event facts**

Validate the full definition list before `start()` mutates controller state:

1. Every `id` and `text` is a non-empty string.
2. Every ID is unique.
3. At least one of `initial`, `startsWhen`, and `requires` is present.
4. Exactly one of `completesWhen` and `completeIf` is present.
5. Every required ID exists.
6. The dependency graph has no cycle.
7. Every event filter has a known event and only compatible payload fields.
8. `requires` contains unique non-empty strings.

Store the events in a private array. Implement a read-only facts object with:

```lua
facts:hasEvent("item_collected", { itemId = "access_card" })
```

`hasEvent` scans the stored event history using the same equality matcher as
`completesWhen`. `latest` scans backward and returns the latest matching event
name. Do not expose the mutable array to `completeIf`.

- [ ] **Step 6: Implement the fixed-point objective processor**

Use private statuses `inactive`, `active`, and `completed`, plus an ordered
list of currently visible IDs. On `start()`:

1. Validate definitions.
2. Reset statuses, facts, visible IDs, and the current state.
3. Subscribe to the injected event source.
4. Activate `initial` definitions and process the fixed point.

On each event:

1. Append the event to the private facts.
2. Activate every inactive objective whose declared gates are true.
3. Evaluate completion for active objectives.
4. Mark matching objectives completed.
5. Re-evaluate requirements and activation gates.
6. Repeat until no status changes.

An objective with `completesWhen` is complete when any recorded event matches
the filter. An objective with `completeIf` is evaluated when activated and
after every new event while active. Wrap `completeIf` in `pcall`; on failure,
warn once with the objective ID and leave it active.

When one or more new objectives remain active after the fixed point, remove
completed objectives from the previous visible set, preserve the newly
activated completed objectives in the new set, publish a copied
`ObjectiveState`, fire `activated` once with the remaining new views, and call
`playSound` once. If all newly activated objectives were immediately completed,
continue through the fixed point and notify only the next objectives that remain
active. If no objective remains active, keep the final completed set visible and
do not play a new-objective sound.

When no new objective is activated, keep completed objectives in the current
visible set so parallel progress remains visible. A repeated event must not
change a completed status or emit another activation batch.

- [ ] **Step 7: Implement lifecycle, state copies, and default sound**

Expose these methods/signals on the controller:

```lua
start: () -> ()
stop: () -> ()
getState: () -> ObjectiveState?
changed: Signal
activated: Signal
```

`start()` and `stop()` are idempotent. `stop()` disconnects the event source,
stops/destroys the one local objective `Sound`, clears facts and state, and
increments a generation if needed to invalidate asynchronous work in the UI
hook. A later `start()` begins the initial objectives as a new session.

The default sound behavior uses:

```lua
local OBJECTIVE_SOUND_ID = ""
```

When the ID is non-empty, create one `Sound` parented to `SoundService`, set
its `SoundId`, and call `SoundService:PlayLocalSound(sound)` once per batch.
Reuse the same Sound for later batches and destroy it on `stop()`. When the ID
is empty, do not create the Sound and do not call the sound API. Inject a no-op
or spy in tests so the objective engine does not depend on audio playback.

- [ ] **Step 8: Wire the production controller and bridge in init.client**

Add requires:

```lua
local PickupEventBridge = require(script.events.PickupEventBridge)
local ObjectiveController = require(script.objectives.ObjectiveController)
```

Start them after the existing domain controllers are prepared but before the
interaction detector can receive player input. The final relevant order must
be:

```lua
PickupNotificationController.start()
InventoryController.start()
DialogueController.start()
TransitionController.start()
ObjectiveController.start()
PickupEventBridge.start()
InteractionController.register("Door", DoorController)
InteractionController.register("Pickup", PickupController)
InteractionController.register("Dialogue", DialogueInteractionController)
InteractionController.start()
```

`ObjectiveController.start()` must precede `PickupEventBridge.start()` so a
confirmed pickup cannot be published before the objective subscriber exists.

- [ ] **Step 9: Run objective tests and the complete client TestEZ suite**

Run the client runner twice in two clean Play sessions, stopping Play between
runs. Expected: all objective tests, event tests, DoorController tests, and
existing client specs report zero failures. Check that no connection from the
previous run receives events in the second run.

- [ ] **Step 10: Finish the objective-engine checkpoint without committing**

Run `git diff --check`, confirm the objective tests and complete client suite
pass, and leave the event and objective changes together in the working tree.
Do not create a commit or request an isolated subagent review.

## Phase 3: UI

### Task 5: Add React state and objective notification hooks

**Files:**
- Create: `src/client/objectives/useObjectives.luau`
- Create: `src/client/objectives/useObjectiveNotification.luau`

**Interfaces:**
- Consumes: `ObjectiveController.getState()`, `ObjectiveController.changed`, and `ObjectiveController.activated`.
- Produces: `useObjectives() -> ObjectiveState?` and `useObjectiveNotification() -> { ObjectiveView }?`.

- [ ] **Step 1: Implement `useObjectives` using the existing hook pattern**

Match `useInventory.luau` and `useDialogue.luau`:

```lua
local function useObjectives(): ObjectiveState?
    local objectives, setObjectives = React.useState(controller.getState())

    React.useEffect(function()
        local connection = controller.changed:Connect(function(nextState: ObjectiveState?)
            setObjectives(nextState)
        end)

        return function()
            connection:Disconnect()
        end
    end, {})

    return objectives
end
```

Do not create a new controller per render and do not add React Context.

- [ ] **Step 2: Implement the three-second notification hook**

Subscribe to `controller.activated`. Keep the latest batch and a local
`notificationGeneration` counter. Clear the batch after three seconds only when
the captured generation is still current and the hook is still mounted.

```lua
local function useObjectiveNotification(): { ObjectiveView }?
    local batch, setBatch = React.useState(nil :: { ObjectiveView }?)

    React.useEffect(function()
        local active = true
        local notificationGeneration = 0
        local connection = controller.activated:Connect(function(nextBatch: { ObjectiveView })
            notificationGeneration += 1
            local currentGeneration = notificationGeneration
            setBatch(nextBatch)
            task.delay(3, function()
                if active and currentGeneration == notificationGeneration then
                    setBatch(nil)
                end
            end)
        end)

        return function()
            active = false
            notificationGeneration += 1
            connection:Disconnect()
        end
    end, {})

    return batch
end
```

The hook must not play audio; audio is owned by the controller so a batch has
one sound independent of React mounting.

- [ ] **Step 3: Typecheck the hooks before rendering them**

Run:

```bash
selene --config selene.roblox.toml src/client/objectives
```

Expected: zero Selene diagnostics. Full luau-lsp verification runs after the
`App.luau` integration.

- [ ] **Step 4: Keep the React state bridge available for final review**

Run `git diff --check` and leave both hooks uncommitted with the rest of the
implementation. The developer will review the complete diff manually.

### Task 6: Render the objective panel and transient notice

**Files:**
- Modify: `src/client/ui/App.luau:3-191`

**Interfaces:**
- Consumes: `useObjectives()`, `useObjectiveNotification()`, and existing `inventoryVisible`.
- Produces: objective list only while inventory is open and a top-right notice for three seconds.

- [ ] **Step 1: Add the two objective hooks to App**

Import the hooks beside the existing inventory and pickup hooks:

```lua
local useObjectiveNotification = require(script.Parent.Parent.objectives.useObjectiveNotification)
local useObjectives = require(script.Parent.Parent.objectives.useObjectives)
```

Inside `App`, call them unconditionally on every render:

```lua
local objectives = useObjectives()
local objectiveNotification = useObjectiveNotification()
```

- [ ] **Step 2: Build stable objective row children**

Render rows from `objectives.objectives` with the objective ID as the React key.
Use `[x]` for completed rows and `*` for pending rows. Preserve the existing
Gotham/RobotoMono visual language and fallback safely if the state is nil.

```lua
local objectiveRows = {}
if objectives ~= nil then
    for index, objective in objectives.objectives do
        local marker = if objective.completed then "[x] " else "* "
        objectiveRows[objective.id] = React.createElement("TextLabel", {
            BackgroundTransparency = 1,
            LayoutOrder = index,
            Size = UDim2.new(1, -24, 0, 28),
            AutomaticSize = Enum.AutomaticSize.Y,
            Font = Enum.Font.Gotham,
            Text = marker .. objective.text,
            TextColor3 = if objective.completed
                then Color3.fromRGB(173, 196, 162)
                else Color3.fromRGB(225, 222, 239),
            TextSize = 14,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
        })
    end
end
objectiveRows.ListLayout = React.createElement("UIListLayout", {
    Padding = UDim.new(0, 2),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
```

- [ ] **Step 3: Add the conditional top-right ObjectivePanel**

Create `objectivePanel` only when `inventoryVisible` and `objectives` are both
present. Anchor it to the top-right with a 24-pixel margin, dark translucent
background, purple stroke, automatic vertical size, and a max width of 340
pixels. The panel title is `OBJETIVOS`; the list uses the rows above.

Do not move or resize the existing inventory panel in this step. The objective
panel must be a new child of the existing `DungeonGui`.

- [ ] **Step 4: Add the transient notice above the panel**

Create a top-right `ObjectiveStack` Frame with a vertical `UIListLayout`. Add a
notice child when `objectiveNotification` is non-nil, then add the conditional
objective panel below it. For one objective use `NOVO OBJETIVO`; for multiple
objectives use `NOVOS OBJETIVOS`. Render every text from the batch in one
notice, not one React element per notification and not one sound per row.

The stack must have:

```lua
AnchorPoint = Vector2.new(1, 0)
Position = UDim2.new(1, -24, 0, 24)
Size = UDim2.new(1, -48, 0, 0)
AutomaticSize = Enum.AutomaticSize.Y
```

Use a `UISizeConstraint` with a max width of 340 pixels, `TextWrapped = true`,
and the existing dark/purple/clear-text palette. This keeps the toast and
panel from overlapping when the inventory is open and remains usable on narrow
screens.

- [ ] **Step 5: Preserve existing UI behavior**

Keep `ScreenGui.Name = "DungeonGui"`, `ResetOnSpawn = false`,
`ZIndexBehavior = Enum.ZIndexBehavior.Sibling`, the existing `T` inventory
shortcut, dialogue rendering, pickup notification, and inventory list. The
persistent objective panel must not be rendered while `inventoryVisible` is
false; the transient notice must remain independent of that flag.

- [ ] **Step 6: Run all static checks after the UI edit**

Run exactly:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/doors src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/events \
  src/client/interactions src/client/inventory src/client/objectives \
  src/client/pickups src/client/player src/client/ui \
  tests
```

Expected: zero Selene diagnostics and zero luau-lsp diagnostics. Do not add
`--!nocheck`, broad ignore directives, or `typeErrors: false` to bypass a
diagnostic.

- [ ] **Step 7: Build both Rojo projects**

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: both builds complete successfully and the test build contains
`Client.events` and `Client.objectives` without the production entrypoints.

- [ ] **Step 8: Leave the complete UI implementation uncommitted**

Do not create a commit. Keep the complete worktree available for the developer
to inspect after the final verification and Studio checkpoint.

## Final Verification

### Automated TestEZ run

- [ ] Start a clean test Play session through Roblox Studio MCP.
- [ ] Confirm `TestEZAutoServer` reports `failed == 0`.
- [ ] Confirm `TestEZAutoClient` reports `failed == 0`.
- [ ] Inspect Output only for details; do not replace the structured summaries with Output text.
- [ ] Stop Play and confirm temporary fixtures and connections are gone.
- [ ] Repeat the complete Play sequence a second time with Play stopped between sessions.

### Manual gameplay checkpoint

- [ ] Confirm `Ache uma saida` activates at session start and its notice remains visible for three seconds.
- [ ] Configure a non-empty `OBJECTIVE_SOUND_ID` in a local verification run and confirm the initial batch plays one local sound.
- [ ] Confirm the persistent objective list is absent with inventory closed.
- [ ] Press `T` and confirm the objective panel appears in the top-right corner beside the existing inventory layout.
- [ ] Interact with a locked `DoorKey = "facility_entrance"` without `iron_key`; confirm `door_blocked` advances to `Encontre o cartao de acesso`.
- [ ] Repeat with a compatible key; confirm the door publishes `door_unlocked` and does not advance through `door_blocked`.
- [ ] Collect `access_card` before attempting the locked door; confirm the later door event skips the already-completed card objective and leaves only `Acesse a instalacao` active.
- [ ] Enter an open facility door; confirm `door_entered` completes the facility objective.
- [ ] Use a test configuration with two medalion objectives sharing `door_blocked(main_exit)`; confirm both appear in one notice and one sound.
- [ ] Collect one medalion; confirm it remains in the panel with `[x]` while the other remains pending.
- [ ] Collect the second medalion; confirm the two completed rows are replaced by `Abra a saida principal`.
- [ ] Trigger another objective batch before three seconds; confirm the new notice replaces the previous one and the old timer cannot clear it early.
- [ ] Confirm a missing `DoorKey` warns and does not advance an objective while normal door behavior remains available.

### Final status inspection

- [ ] Run `git status --short` and ensure only intended implementation files and generated sourcemap changes are present.
- [ ] Run `git diff --check` and confirm no whitespace errors.
- [ ] Review `git diff` for accidental changes to server authority, persistence, UI test scope, or unrelated systems.
