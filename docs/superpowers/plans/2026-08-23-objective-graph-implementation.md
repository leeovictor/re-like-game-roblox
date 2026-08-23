# Objective Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir o modelo de gates do sistema de objetivos por um grafo direcionado com caminhos alternativos, subobjetivos AND e conclusao terminal.

**Architecture:** `ObjectiveConfig` declarara nos e transicoes de saida. `ObjectiveController` continuara dono dos fatos da sessao, mas ativara somente transicoes que saem de objetivos ativos; uma transicao conclui a origem e ativa o destino. Objetivos compostos manterao uma checklist de filhos e seguirao uma transicao interna quando todos forem concluidos.

**Tech Stack:** Luau `--!strict`, Roblox Studio/DataModel, Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0, TestEZ no Roblox Studio, React e ReactRoblox existentes no Wally.

## Global Constraints

- O progresso sera valido somente durante a sessao atual; respawn nao reinicia os objetivos e nao havera persistencia entre servidores ou sessoes.
- O sistema sera client-side; nao criar servico de objetivos no servidor, remoto de progresso ou alteracao de `InventoryState`.
- Usar um barramento geral local sem fila, replay, persistencia ou remotes proprios.
- Publishers nao importam nem conhecem o `ObjectiveController`.
- `door_blocked` significa porta bloqueada por falta do item compativel; `door_entered` somente sera publicado apos uma entrada aceita.
- Usar o atributo estavel `DoorKey`; nunca usar o nome do Model como fallback.
- A porta provisoria de conclusao usara `DoorKey = "facility_test_door"`.
- Eventos anteriores devem poder satisfazer transicoes e subobjetivos de nos ativados posteriormente.
- Um evento pode disparar no maximo uma transicao por objetivo ativo; o mesmo evento pode avancar objetivos ativos diferentes.
- Um objetivo com transicoes conclui pela primeira transicao compativel; um objetivo terminal conclui por `completesWhen` ou `completeIf`.
- Objetivos compostos terao somente um nivel de subobjetivos; a conclusao do pai exige todos os filhos.
- Subobjetivos nao terao transicoes de grafo nem subobjetivos proprios.
- O grafo sera aciclico nesta versao; ciclos e reentrada em nos concluidos serao rejeitados.
- `startsWhen` e `requires` serao removidos da configuracao; nao manter dois modelos de ativacao.
- `completeIf` continuara somente para condicoes compostas que nao possam ser expressas por um filtro simples e recebera fatos somente para leitura.
- O painel de objetivos aparecera somente com o inventario aberto e mostrara filhos indentados.
- Notificacoes mostrarao somente objetivos que continuarem ativos depois do processamento ate ponto fixo; subobjetivos nao notificarao individualmente.
- Specs de UI permanecem fora do escopo TestEZ; o layout sera verificado manualmente no Roblox Studio.
- Specs strict devem criar fixtures em `beforeEach` e destruir ou desconectar tudo em `afterEach`.
- Depois de atualizar scripts ou specs usados pelo TestEZ, parar e iniciar novamente a sessao Play antes de executar os testes.
- Nao editar `Packages/` ou `DevPackages/`; esses diretorios sao gerados pelo Wally.
- Preservar imports baseados em `script` e a pasta `src/server/cave-engine/` se ela for tocada no futuro.

---

## File Map

### Objective engine

- Modify: `src/client/objectives/ObjectiveController.luau` - tipos de transicao, validacao do grafo, fatos, estados dos filhos, processamento ate ponto fixo e views aninhadas.
- Modify: `src/client/objectives/ObjectiveConfig.luau` - grafo de quatro objetivos e dois subobjetivos dos medalhoes.
- Test: `tests/client/objectives/ObjectiveController.spec.luau` - caminhos, subobjetivos, fatos fora de ordem, terminal e validacoes.

### React bridge and rendering

- Modify: `src/client/objectives/useObjectives.luau` - transportar `subobjectives` na view.
- Modify: `src/client/objectives/useObjectiveNotification.luau` - alinhar o tipo da view aninhada sem notificar filhos individualmente.
- Modify: `src/client/ui/App.luau` - renderizar o objetivo pai e suas linhas de subobjetivo.

### Preserved infrastructure

- Do not modify: `src/client/events/GameplayEvents.luau`.
- Do not modify: `src/client/events/PickupEventBridge.luau`.
- Do not modify: `src/client/doors/DoorController.luau` or `src/shared/doors/doorTypes.luau`; os publishers ja fornecem `door_blocked` e `door_entered` com `DoorKey`.
- Do not modify: `test.project.json`; o root client ja mapeia `events` e `objectives`.

---

## API Contracts

Implementar os tipos do controller com estes nomes e campos para manter a
configuracao e a UI consistentes:

```lua
export type EventFilter = {
    event: GameplayEvents.EventName,
    doorKey: string?,
    itemId: string?,
    areaKey: string?,
}

export type TransitionTrigger = EventFilter | {
    type: "subobjectives_completed",
}

export type Transition = {
    to: string,
    when: TransitionTrigger,
}

export type SubobjectiveDefinition = {
    id: string,
    text: string,
    completesWhen: EventFilter?,
    completeIf: ((facts: Facts) -> boolean)?,
}

export type ObjectiveDefinition = {
    id: string,
    text: string,
    initial: boolean?,
    transitions: { Transition }?,
    subobjectives: { SubobjectiveDefinition }?,
    completesWhen: EventFilter?,
    completeIf: ((facts: Facts) -> boolean)?,
}

export type SubobjectiveView = {
    id: string,
    text: string,
    completed: boolean,
}

export type ObjectiveView = {
    id: string,
    text: string,
    completed: boolean,
    subobjectives: { SubobjectiveView }?,
}
```

`startsWhen` e `requires` nao devem reaparecer nos tipos ou na configuracao.
`completesWhen` e `completeIf` sao permitidos no objetivo apenas quando ele nao
possui transicoes. Um objetivo composto usa `subobjectives` e uma unica
transicao com `when.type == "subobjectives_completed"`.

---

## Task 1: Rewrite the graph controller specs

**Files:**
- Modify: `tests/client/objectives/ObjectiveController.spec.luau`

**Interfaces:**
- Consumes: `ObjectiveController.new(definitions, { events = source, playSound = spy })`.
- Produces: failing executable examples for graph transitions, terminal completion and nested views.

- [ ] **Step 1: Replace the old definition fixtures with graph helpers**

Keep the existing `newEventSource()` helper and lifecycle cleanup. Add helpers
that find a view by ID and create a controller with the injected event source:

```lua
local function findObjective(state: any, id: string): any
    for _, objectiveView in state.objectives do
        if objectiveView.id == id then
            return objectiveView
        end
    end
    return nil
end

local function findSubobjective(objectiveView: any, id: string): any
    for _, subobjectiveView in objectiveView.subobjectives or {} do
        if subobjectiveView.id == id then
            return subobjectiveView
        end
    end
    return nil
end

local function newController(source: any, definitions: any): any
    return ObjectiveController.new(definitions, {
        events = source,
        playSound = function() end,
    })
end
```

Register every created controller in the existing `controllers` table so
`afterEach` calls `stop()` even when an assertion fails.

- [ ] **Step 2: Write the failing direct-path and terminal tests**

Add a test using the exact graph contract. It must fail against the current
`startsWhen`/`requires` implementation because `transitions` is not supported:

```lua
it("follows the direct door_entered path and completes the terminal node", function()
    local source, emit = newEventSource()
    local controller = newController(source, {
        {
            id = "find_exit",
            text = "Encontre a saida",
            initial = true,
            transitions = {
                {
                    to = "explore_facility",
                    when = { event = "door_entered", doorKey = "facility_entrance" },
                },
            },
        },
        {
            id = "explore_facility",
            text = "Explore a instalacao",
            completesWhen = { event = "door_entered", doorKey = "facility_test_door" },
        },
    })
    table.insert(controllers, controller)

    controller.start()
    emit({ name = "door_entered", doorKey = "facility_entrance" })

    local active = assert(findObjective(assert(controller.getState()), "explore_facility"))
    expect(active.completed).to.equal(false)
    expect(findObjective(assert(controller.getState()), "find_exit")).to.equal(nil)

    emit({ name = "door_entered", doorKey = "facility_test_door" })

    local completed = assert(findObjective(assert(controller.getState()), "explore_facility"))
    expect(completed.completed).to.equal(true)
end)
```

- [ ] **Step 3: Write the failing alternative-path and active-source tests**

Add a graph where `find_exit` has both outgoing transitions. Emit
`item_collected(access_card)` first and assert that no card objective appears;
then emit `door_entered(facility_entrance)` and assert that only
`explore_facility` is active. This protects the rule that facts do not activate
an inactive node and that only an active source can route the graph.

Add a second assertion that `door_blocked(facility_entrance)` routes to
`find_medallions`, while an unrelated `door_blocked(other_door)` leaves
`find_exit` active.

- [ ] **Step 4: Run the rewritten focused spec and verify the expected failure**

Run a clean test Play after syncing the test project:

```bash
rojo sync test.project.json
```

Run the client TestEZ runner from the test DataModel. The new graph tests must
fail before the runtime change because the current validator does not accept
graph-only definitions. A validation failure about the old activation or
completion contract is the expected red state; syntax errors and missing test
fixtures are not acceptable.

- [ ] **Step 5: Commit the graph contract tests**

```bash
git add tests/client/objectives/ObjectiveController.spec.luau
git commit -m "test(objectives): define graph transition behavior"
```

---

## Task 2: Implement graph transitions, terminal nodes and validation

**Files:**
- Modify: `src/client/objectives/ObjectiveController.luau`
- Test: `tests/client/objectives/ObjectiveController.spec.luau`

**Interfaces:**
- Consumes: `GameplayEvents.GameplayEvent`, injected `EventSource`, and the graph types in `API Contracts`.
- Produces: `ObjectiveController.new()` with `start()`, `stop()`, `getState()`, `changed` and `activated` using graph definitions.

- [ ] **Step 1: Replace the activation and completion types**

Replace the current `startsWhen`, `requires` and single `completesWhen`-based
definition type with `TransitionTrigger`, `Transition`,
`SubobjectiveDefinition` and the new `ObjectiveDefinition`. Keep `Facts`,
`EventSource`, dependency injection, sound cleanup and exported signal types.

Keep `EventFilter` fields limited to `event`, `doorKey`, `itemId` and `areaKey`.
The known event names must include the existing union:

```text
door_blocked, door_unlocked, door_entered,
item_collected, area_entered, switches_changed
```

- [ ] **Step 2: Implement trigger matching against the complete fact history**

Keep the existing field-by-field event matcher, but add a trigger dispatcher:

```text
matchesTrigger(trigger, facts):
    if trigger.type == "subobjectives_completed":
        return false here; the caller evaluates child state
    return some recorded GameplayEvent matches trigger
```

Use the full `facts` array, not only the event currently being processed. This
allows an item collected before a parent objective activates to complete the
corresponding child during activation.

- [ ] **Step 3: Implement graph validation before state mutation**

Build `definitionById` and validate the complete list before setting
`started = true` or subscribing to the event source. Implement these checks
with error messages containing the relevant objective or subobjective ID:

```text
definitions is a non-empty array with at least one initial objective
objective ids and texts are non-empty and unique
every transition has a string target and a valid trigger
every transition target exists
every non-initial objective is reachable from an initial objective
the directed graph has no cycle
event trigger fields are compatible with the event name
two transitions from one source cannot overlap
an objective with transitions has no completesWhen or completeIf
an objective without transitions has exactly one terminal completion condition
a compound objective has children and exactly one subobjectives_completed transition
a compound objective has no terminal completion condition
subobjective ids are unique within their parent and texts are non-empty
each subobjective has exactly one of completesWhen or completeIf
subobjectives cannot contain transitions or nested subobjectives
```

For transition overlap, compare triggers with the same event name: two filters
overlap when every field specified by both has the same value and neither
contradicts the other. Reject exact duplicates and broad/specific overlaps.
Use a DFS from all initial IDs for reachability and a visiting/visited DFS for
cycle detection.

- [ ] **Step 4: Add runtime status for all nodes and compound children**

Keep statuses for every graph node:

```lua
type Status = "inactive" | "active" | "completed"

statuses: { [string]: Status }
subobjectiveStatuses: {
    [string]: { [string]: Status },
}
```

Initialize child status maps when `start()` initializes definitions. A child is
eligible for completion only while its parent is active, but its condition is
checked against all facts when the parent becomes active.

- [ ] **Step 5: Implement activation and historical hydration**

Add one local activation operation with idempotent behavior:

```text
activateObjective(id, newlyActivated):
    if statuses[id] ~= "inactive": return false
    statuses[id] = "active"
    mark all child definitions as active or completed from facts
    add id to newlyActivated
    return true
```

For a child with `completesWhen`, scan the history with the event matcher. For a
child with `completeIf`, call the predicate with the read-only `Facts` object;
catch predicate errors, warn once per child, and leave it pending.

- [ ] **Step 6: Implement the fixed-point graph processor**

Replace the current dependency loop with a loop that repeatedly performs these
operations until no status changes:

```text
for every active compound objective:
    refresh child statuses from facts

for every active objective with transitions:
    scan transitions in declaration order
    if the first trigger is satisfied:
        mark source completed
        activate target if inactive
        stop scanning this source

for every active terminal objective:
    if completesWhen matches facts or completeIf returns true:
        mark objective completed

repeat while any activation or completion happened
```

The internal trigger is satisfied only when every child status is `completed`.
When it fires, it completes the compound source and activates its target in the
same processing pass. Do not emit `subobjectives_completed` through
`GameplayEvents`.

Only active source nodes are scanned. A historical event can satisfy a newly
activated source, but an inactive source is never advanced directly by a fact.
An event may advance one transition from each independently active source.

- [ ] **Step 7: Preserve the visible frontier and signals**

Update `makeView()` to include child views. Keep completed parallel siblings
visible while another sibling remains pending. When a transition activates a
new target, remove completed predecessor IDs from `visibleIds` and add targets
that remain active after the fixed-point pass. When a terminal objective
completes without activating a target, keep it visible as completed.

Fire `changed` once after the final state is built. Fire `activated` once with
only newly activated objectives whose final status is still `active`; do not
include intermediate nodes that were immediately completed by historical facts.
Play the injected sound once when that batch is non-empty.

- [ ] **Step 8: Run the core graph tests**

Before running the suite, retain an explicit predicate regression for a terminal
node. It must prove that `completeIf` still reads the full history in either
order:

```lua
it("evaluates completeIf for a terminal node in either fact order", function()
    local source, emit = newEventSource()
    local controller = newController(source, {
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
    })
    table.insert(controllers, controller)

    controller.start()
    emit({ name = "switches_changed", switchesOn = 3 })
    expect(assert(controller.getState()).objectives[1].completed).to.equal(false)
    emit({ name = "item_collected", itemId = "fuse" })
    expect(assert(controller.getState()).objectives[1].completed).to.equal(true)
end)
```

Restart the TestEZ Play session, run the client suite, and verify that the
direct path, alternative path, terminal completion, unrelated-event filtering,
historical matching and lifecycle tests pass. Fix implementation errors before
adding campaign-specific tests.

- [ ] **Step 9: Commit the graph runtime**

```bash
git add src/client/objectives/ObjectiveController.luau tests/client/objectives/ObjectiveController.spec.luau
git commit -m "feat(objectives): process graph transitions"
```

---

## Task 3: Add compound medalion objectives and campaign regressions

**Files:**
- Modify: `src/client/objectives/ObjectiveConfig.luau`
- Modify: `tests/client/objectives/ObjectiveController.spec.luau`

**Interfaces:**
- Consumes: graph runtime from Task 2 and existing `item_collected`, `door_blocked` and `door_entered` events.
- Produces: the four-node campaign graph and regression coverage for both gameplay paths.

- [ ] **Step 1: Replace the old campaign configuration**

Make `ObjectiveConfig.luau` return this graph, preserving the existing logical
IDs where possible and using `door_blocked` rather than `door_locked`:

```lua
local config = {
    {
        id = "find_exit",
        text = "Encontre a saida",
        initial = true,
        transitions = {
            {
                to = "find_medallions",
                when = { event = "door_blocked", doorKey = "facility_entrance" },
            },
            {
                to = "explore_facility",
                when = { event = "door_entered", doorKey = "facility_entrance" },
            },
        },
    },
    {
        id = "find_medallions",
        text = "Encontre os medalhoes",
        subobjectives = {
            {
                id = "silver_medallion",
                text = "Medalhao prata",
                completesWhen = { event = "item_collected", itemId = "silver_medallion" },
            },
            {
                id = "gold_medallion",
                text = "Medalhao ouro",
                completesWhen = { event = "item_collected", itemId = "gold_medallion" },
            },
        },
        transitions = {
            {
                to = "access_facility",
                when = { type = "subobjectives_completed" },
            },
        },
    },
    {
        id = "access_facility",
        text = "Acesse a instalacao subterranea",
        transitions = {
            {
                to = "explore_facility",
                when = { event = "door_entered", doorKey = "facility_entrance" },
            },
        },
    },
    {
        id = "explore_facility",
        text = "Explore a instalacao",
        completesWhen = { event = "door_entered", doorKey = "facility_test_door" },
    },
}

return config
```

Do not add medalion catalog entries in this task. The objective engine consumes
the event IDs; actual pickup definitions are separate gameplay work.

- [ ] **Step 2: Add the blocked-door path test with ordered subobjective completion**

Use a local definition or `ObjectiveConfig` with an injected event source. Emit
`door_blocked(facility_entrance)` and assert the parent has two child views,
both pending. Emit silver and assert only silver is complete and the parent is
still active. Emit gold and assert `find_medallions` is replaced by active
`access_facility`.

The assertions must inspect child IDs rather than relying on row positions:

```lua
local medallions = assert(findObjective(state, "find_medallions"))
expect(medallions.completed).to.equal(false)
expect(assert(findSubobjective(medallions, "silver_medallion")).completed).to.equal(true)
expect(assert(findSubobjective(medallions, "gold_medallion")).completed).to.equal(false)
```

The `findSubobjective()` helper from Task 1 intentionally treats child views as
an array, matching `subobjectives: { SubobjectiveView }?` in the controller
contract.

- [ ] **Step 3: Add out-of-order child hydration tests**

Emit both medalion collection events before `door_blocked`. Then emit
`door_blocked(facility_entrance)`. Assert that the parent and both children are
not exposed as a pending state and that `access_facility` is the active result
after the same fixed-point pass.

Add the one-medalion variant and assert that the parent remains active with one
completed child and one pending child.

- [ ] **Step 4: Add direct-card path and terminal-door tests**

Use the complete `ObjectiveConfig` and emit:

```text
item_collected(access_card)
door_entered(facility_entrance)
door_entered(facility_test_door)
```

Assert that `find_medallions` and `access_facility` never become visible,
`explore_facility` becomes active after the facility entry, and it becomes
completed only after `facility_test_door` is entered.

- [ ] **Step 5: Replace old validation cases with graph validation cases**

Keep duplicate IDs and lifecycle coverage, and add malformed definitions for:

```text
no initial objective
unknown transition target
unreachable objective
dependency-free graph cycle
unknown event trigger
incompatible filter field
overlapping outgoing triggers
transitions combined with completesWhen
terminal objective without completesWhen or completeIf
compound objective without children
compound objective without subobjectives_completed transition
duplicate child IDs
child without a completion condition
child with both completesWhen and completeIf
child with nested subobjectives
```

Wrap each `controller.start()` in `pcall` and assert the error contains the
case name or relevant ID. Assert that no invalid controller publishes a state
before the validation error.

- [ ] **Step 6: Run all objective specs**

Restart Play, run the client TestEZ runner, and require zero failures for the
new graph tests plus the existing unrelated client specs. Inspect Output for
the expected single warning behavior of any predicate test; do not make global
warning counts part of the assertions.

- [ ] **Step 7: Commit the campaign graph and regressions**

```bash
git add src/client/objectives/ObjectiveConfig.luau tests/client/objectives/ObjectiveController.spec.luau
git commit -m "feat(objectives): add medalion graph path"
```

---

## Task 4: Propagate nested views to React and render the checklist

**Files:**
- Modify: `src/client/objectives/useObjectives.luau`
- Modify: `src/client/objectives/useObjectiveNotification.luau`
- Modify: `src/client/ui/App.luau`

**Interfaces:**
- Consumes: `ObjectiveState` and `ObjectiveView` from `ObjectiveController` with optional `subobjectives`.
- Produces: the existing inventory panel with one-level indented child rows and unchanged objective notification behavior.

- [ ] **Step 1: Update hook view types**

Add the same `SubobjectiveView` shape to both hook-local types and add
`subobjectives: { SubobjectiveView }?` to `ObjectiveView`. Keep the hooks'
subscription and cleanup behavior unchanged. `useObjectiveNotification` may
carry children in its type, but it will continue returning only the controller's
activated top-level batch.

- [ ] **Step 2: Add a one-level nested row renderer in `App.luau`**

Keep the current parent row styling and create child `TextLabel` rows beneath
each parent. Use stable React keys composed from both IDs:

```lua
local childKey = objective.id .. ":sub:" .. subobjective.id
```

Render child rows with:

```text
completed marker [x] for completed children and * for pending children
smaller or equal text size with left indentation
completed color matching the parent completed color
TextWrapped true and AutomaticSize.Y
LayoutOrder after the parent and before the next top-level objective
```

Do not add recursive rendering. The spec supports exactly one child level.
Ensure `objectiveRows.ListLayout` still orders all generated labels and that
the panel keeps `AutomaticSize.Y` for mobile-sized layouts.

- [ ] **Step 3: Preserve notification semantics**

Keep the notification text based on top-level `objective.text`. A parent with
subobjectives creates one notification for the parent when it remains active;
silver and gold child completions do not replace the notification batch.
Keep the existing five-second delay currently configured in
`useObjectiveNotification.luau` unless the user changes that tuning separately.

- [ ] **Step 4: Run static checks for the UI changes**

Run the Roblox lint and typecheck commands from Task 5 after regenerating the
sourcemap. Fix strict type errors by aligning the local view types with the
controller contract; do not add `--!nocheck`, broad type suppressions or UI
specs.

- [ ] **Step 5: Commit the nested objective UI**

```bash
git add src/client/objectives/useObjectives.luau src/client/objectives/useObjectiveNotification.luau src/client/ui/App.luau
git commit -m "feat(objectives): render nested subobjectives"
```

---

## Task 5: Full verification and Studio gameplay check

**Files:**
- No new production files.
- Regenerate: `test-sourcemap.json`.

**Interfaces:**
- Consumes: the completed graph engine, campaign config, hooks and UI.
- Produces: verified client/server tests, static analysis, Rojo builds and manual confirmation of both graph paths.

- [ ] **Step 1: Inspect the final worktree before verification**

Run:

```bash
git status --short
git diff --check
git log --oneline -10
```

Do not revert unrelated changes. Confirm that only intended objective files,
the graph spec/plan, and existing user work are present.

- [ ] **Step 2: Run lint and regenerate the test sourcemap**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Expected: zero Selene diagnostics and a sourcemap containing the existing
`Client.events` and `Client.objectives` mappings.

- [ ] **Step 3: Run the Roblox typecheck**

Run exactly:

```bash
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups src/client/player \
  src/client/doors src/client/dialogue src/client/events src/client/interactions \
  src/client/objectives src/client/ui \
  tests
```

Expected: no diagnostics. Do not include `src/server/init.server.luau` or
`src/client/init.client.luau` in this test-project analysis.

- [ ] **Step 4: Build both Rojo projects**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: both builds complete successfully without modifying generated package
directories.

- [ ] **Step 5: Run clean TestEZ server and client sessions in Roblox Studio**

Use the connected Studio test session and perform a clean Play cycle through
the Roblox Studio MCP. Because scripts and specs changed, stop the existing
Play session, start it again, and wait for `TestEZAutoServer` and
`TestEZAutoClient` to finish.

Confirm both runner results report:

```text
failed == 0
```

Inspect Output only for additional warnings or runtime errors after the zero
failure result.

- [ ] **Step 6: Manually verify the graph paths and nested UI**

With the production client running:

```text
Path A:
  reach facility_entrance without access_card
  confirm door_blocked activates Encontre os medalhoes
  collect silver_medallion and verify only silver is checked
  collect gold_medallion and verify access_facility activates
  enter facility_entrance and verify explore_facility activates
  enter the test door with DoorKey facility_test_door
  verify explore_facility is checked

Path B:
  collect access_card before facility_entrance
  enter facility_entrance
  verify medalion and access objectives never appear
  verify explore_facility activates directly
  enter the test door and verify it completes
```

Open the inventory during the checks and confirm the two medalions are
displayed as indented child rows. Confirm no child notification is emitted and
that a chain completed immediately from historical facts does not flash
intermediate objectives.

- [ ] **Step 7: Record verification results without altering unrelated files**

If a check fails, fix the smallest relevant objective change, restart Play if a
script/spec changed, and rerun the affected check. Finish with `git status
--short` and `git diff --check`; do not reset, checkout, or remove work that was
not part of this feature.
