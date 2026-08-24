# Inventory UI Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir a lista textual do inventário por uma grade de seis slots com estados vazio, ocupado e equipado, além de dropdown flutuante e modal de confirmação alimentados por ações mockadas.

**Architecture:** `App.luau` permanecerá como orquestrador do estado local e da tabela mockada de ações. `InventorySlot`, `DropdownMenu` e `ConfirmationModal` serão componentes React controlados, sem decisões de gameplay, catálogo de capabilities ou acesso a remotes. A grade terá uma camada visual e uma camada irmã de overlay com o mesmo layout, permitindo posicionar o dropdown fora da célula sem deslocar os slots.

**Tech Stack:** Luau `--!strict`, Roblox GUI instances, React `17.2.1`, ReactRoblox `17.2.1`, Rojo `7.7.0`, Selene `0.29.0`, luau-lsp `1.69.0` e TestEZ existente somente para as suites não visuais.

## Global Constraints

- Usar React `17.2.1` e ReactRoblox `17.2.1` já declarados em `wally.toml`; não adicionar dependências.
- Manter `--!strict` em todos os módulos novos e modificados.
- Usar a tecla `T` existente para abrir e fechar o painel; não alterar o atalho.
- Renderizar seis posições em três colunas por duas linhas, incluindo slots vazios.
- Mostrar `equipado` quando o `uid` do item aparecer em qualquer valor de `inventory.equipped`.
- Receber ações por props; `InventorySlot` não consulta o catálogo, não interpreta capabilities e não cria ações.
- Usar uma tabela de ações mockadas na camada de UI; não usar `ItemDefinition.capabilities` para essa decisão.
- Renderizar dropdown como overlay flutuante ao lado do slot, sem participar do layout da grade.
- Fechar o dropdown ao selecionar uma ação ou ao selecionar outro slot.
- Fechar o modal somente pelos callbacks dos botões `não` e `sim`; clique externo e `Escape` não fecham.
- Não alterar `InventoryState`, `catalog.luau`, remotes, controllers, serviços, entrypoints ou o servidor.
- Não adicionar specs de UI, pois specs de UI permanecem fora do escopo deste repositório.
- Preservar a alteração não relacionada já existente em `src/shared/inventory/catalog.luau`.
- Usar fallback para `itemId` quando a definição correspondente não existir no catálogo.

---

## File Map

| Arquivo | Responsabilidade |
| --- | --- |
| `src/client/ui/ConfirmationModal.luau` | Overlay modal controlado, mensagem e botões de confirmação/cancelamento |
| `src/client/ui/DropdownMenu.luau` | Painel flutuante de opções e callbacks das opções |
| `src/client/ui/InventorySlot.luau` | Estado visual de slot vazio, ocupado e equipado |
| `src/client/ui/App.luau` | Estado de seleção, tabela mockada, grade, camadas de overlay e integração |

Não serão criados módulos em `src/shared`, `src/client/inventory` ou
`src/server`. Não haverá arquivo de teste para os componentes porque a política
do projeto exclui UI da suite TestEZ.

## Interfaces entre tarefas

Os três componentes usarão tabelas de props com estes formatos estruturais:

```text
InventorySlot props:
  item: { name: string, quantity: number? }?
  equipped: boolean
  actions: { { label: string, onActivated: () -> () } }
  onActivated: (() -> ())?

DropdownMenu props:
  visible: boolean
  options: { { label: string, onActivated: () -> () } }
  position: UDim2

ConfirmationModal props:
  visible: boolean
  message: string
  confirmLabel: string
  cancelLabel: string
  onConfirm: () -> ()
  onCancel: () -> ()
```

`App` produzirá exatamente esses dados. Os módulos não compartilharão um
arquivo de tipos novo: Luau fará a verificação estrutural das tabelas e a
responsabilidade de cada componente continuará local.

## Task 1: Implement ConfirmationModal

**Files:**
- Create: `src/client/ui/ConfirmationModal.luau`
- Test: none; UI specs are explicitly out of scope

**Interfaces:**
- Consumes: the `ConfirmationModal props` interface above
- Produces: a React component function returned by the module, rendering `nil` when `visible == false`

- [ ] **Step 1: Create the strict component module and props type**

Create the module with `--!strict`, require `ReplicatedStorage.Packages.React`,
declare the six props fields, and return a local component function. The first
branch must be:

```lua
if not props.visible then
    return nil
end
```

Do not read any inventory module or controller from this file.

- [ ] **Step 2: Add the full-screen blocking layer**

Return a `Frame` that fills its parent with `Size = UDim2.fromScale(1, 1)`, a
dark translucent background, `ZIndex` above the inventory and dropdown, and
`Active = true`. Keep the layer as a regular `Frame`, not an activated button,
so it has no outside-click close behavior. Set `ClipsDescendants = false` so
the centered panel and its children are not clipped.

- [ ] **Step 3: Add the centered confirmation panel and controls**

Add a centered child `Frame` with a bounded width, a fixed height, dark game
palette, rounded corners, and a purple `UIStroke`. Add a message `TextLabel`
using `props.message`, plus two `TextButton`s using `props.cancelLabel` and
`props.confirmLabel`. Wire only these properties:

```lua
CancelButton = React.createElement("TextButton", {
    Text = props.cancelLabel,
    Activated = props.onCancel,
})

ConfirmButton = React.createElement("TextButton", {
    Text = props.confirmLabel,
    Activated = props.onConfirm,
})
```

Use `AutoButtonColor = false`, visible focus/hover-safe contrast, and a
horizontal layout that remains usable when the panel is narrow. Do not add a
close icon, outside callback, or keyboard listener.

- [ ] **Step 4: Run the source lint check**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: the command exits successfully with no diagnostics introduced by the
new component.

- [ ] **Step 5: Commit the component**

```bash
git add -- src/client/ui/ConfirmationModal.luau
git commit -m "feat(inventory): add confirmation modal component"
```

## Task 2: Implement DropdownMenu

**Files:**
- Create: `src/client/ui/DropdownMenu.luau`
- Test: none; UI specs are explicitly out of scope

**Interfaces:**
- Consumes: the `DropdownMenu props` interface above
- Produces: a React component function that renders a positioned options panel or `nil`

- [ ] **Step 1: Create the strict component and visibility guard**

Create the module with `--!strict`, require React, declare the options type and
props type, and return `nil` when `visible` is false or `options` is empty. The
component must not own a selected-option state or a visibility state.

- [ ] **Step 2: Build the floating options panel**

Render a `Frame` with `Position = props.position`, a fixed menu width,
`AutomaticSize = Enum.AutomaticSize.Y`, transparent parent background, a dark
translucent panel, rounded corners, purple stroke, padding, and `ZIndex` above
the slots. Add a `UIListLayout` with vertical ordering. The component must not
be a child of the `UIGridLayout` that lays out the inventory cells; its parent
will be an overlay cell with `ClipsDescendants = false`.

- [ ] **Step 3: Render each option as an activated button**

For each option, create a `TextButton` whose text is the option label and whose
`Activated` property is the option callback. Keep the option order supplied by
the parent. Do not add a click-outside overlay: the approved behavior only
requires closing after an action or when another slot is selected.

Use this callback contract so closing remains parent-controlled:

```lua
Activated = option.onActivated
```

The parent will clear the selected `uid` before performing the mock action.

- [ ] **Step 4: Run the source lint check**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: the command exits successfully with no diagnostics introduced by the
new component.

- [ ] **Step 5: Commit the component**

```bash
git add -- src/client/ui/DropdownMenu.luau
git commit -m "feat(inventory): add floating dropdown component"
```

## Task 3: Implement InventorySlot

**Files:**
- Create: `src/client/ui/InventorySlot.luau`
- Test: none; UI specs are explicitly out of scope

**Interfaces:**
- Consumes: the `InventorySlot props` interface above
- Produces: a reusable slot component that displays an optional item and forwards one activation callback

- [ ] **Step 1: Create the strict component and display types**

Create the module with `--!strict`, require React, and declare the display item
and action option types. The display item must contain only `name` and optional
`quantity`; do not import the catalog or `ItemInstance` into the component.

- [ ] **Step 2: Render the empty-slot state**

When `props.item == nil`, render a square `Frame` with the same dimensions,
corner radius, and stroke used by occupied slots. Use the less prominent
background color, render no text children, set no activation callback, and keep
the cell transparent to input so an empty slot cannot open a menu.

- [ ] **Step 3: Render the occupied-slot state**

When an item exists, render an interactive `TextButton` with the square visual
style, `Text = ""`, `AutoButtonColor = false`, and
`Activated = props.onActivated` only when `#props.actions > 0`. Use a centered
child `TextLabel` for the item name. Append the quantity in the same visual
label using the existing inventory convention when `quantity ~= nil`, for
example `Medkit x2`.

The slot may use whether the action list is empty to decide whether it is
interactive, but it must not inspect action labels or infer new actions from
the item.

- [ ] **Step 4: Add the equipped indicator**

When `props.equipped` is true, add a small top-right `TextLabel` whose text is
exactly `equipado`, with a contrasting dark/purple background, compact padding,
and a `ZIndex` above the slot content. Do not render this label for empty or
unequipped slots.

- [ ] **Step 5: Run the source lint check**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: the command exits successfully with no diagnostics introduced by the
new component.

- [ ] **Step 6: Commit the component**

```bash
git add -- src/client/ui/InventorySlot.luau
git commit -m "feat(inventory): add reusable inventory slot"
```

## Task 4: Replace the TextList with the Mocked Inventory Grid

**Files:**
- Modify: `src/client/ui/App.luau`
- Consume: `InventorySlot` and `useInventory()`
- Produce: a six-cell, three-column inventory grid with parent-owned mock action lists
- Test: none; UI specs are explicitly out of scope

- [ ] **Step 1: Import the slot component and define grid constants**

Add the `InventorySlot` require beside the existing `ObjectiveNotification`
require. Define local constants in `App.luau` for the six-slot count, three
columns, cell size, gap, and dropdown width. Keep the grid constants local to
the UI; do not add capacity to `InventoryState`.

- [ ] **Step 2: Add the parent-owned mock action table**

Place an explicit local table in `App.luau`, keyed by the current item ids. The
values are labels only and do not use `catalog.capabilities`. Use different
lists so the integration demonstrates item-dependent options:

```lua
local mockActionLabelsByItemId: { [string]: { string } } = {
    access_card = { "usar", "descartar" },
    pliers = { "usar", "descartar" },
    handgun = { "equipar", "descartar" },
    handgun_ammo = { "descartar" },
    medkit = { "usar", "descartar" },
}
```

Treat this table as replaceable UI fixture data. It must not be moved to
`ReplicatedStorage` or used as server validation.

- [ ] **Step 3: Add controlled menu and confirmation state**

Add two nullable string states inside `App`:

```lua
local selectedItemUid, setSelectedItemUid = React.useState(nil :: string?)
local confirmationItemUid, setConfirmationItemUid = React.useState(nil :: string?)
```

The selected state identifies the open menu by stable `uid`, not by the mutable
array index. The confirmation state identifies the item whose discard modal is
shown.

- [ ] **Step 4: Add parent helpers for equipped state and display data**

Create a local helper that returns true when a given `uid` matches any value in
`inventory.equipped`. Create the display mapping that resolves the catalog name
from `item.itemId`, falls back to the `itemId` string when missing, and carries
the optional quantity. These helpers must be used only after `inventory ~= nil`.

- [ ] **Step 5: Create mock action callbacks in the parent**

Build the action list for each item from `mockActionLabelsByItemId[item.itemId]`.
For every label, create a callback that first clears `selectedItemUid`. Only
the `descartar` label additionally sets `confirmationItemUid` to the item UID.
`usar` and `equipar` close the menu and have no inventory side effect.

Use this behavior in the callback body:

```lua
setSelectedItemUid(nil)
if label == "descartar" then
    setConfirmationItemUid(item.uid)
end
```

The action list must be empty for an item id not present in the mock table so
the slot remains visible without opening a menu.

- [ ] **Step 6: Replace `inventoryRows` and `ScrollingFrame` with the grid**

Remove the current per-item `TextLabel` rows and the `ScrollingFrame` used by
the inventory panel. Keep the existing panel title and its visibility logic.

Render a fixed grid `Frame` with a `UIGridLayout` configured for horizontal
fill, three cells per row, the shared cell size, shared cell padding, and
layout-order sorting. Generate indices `1` through `6`; use
`inventory.items[index]` when present and pass `item = nil` otherwise.

For each occupied cell, pass the resolved display item, equipped boolean,
mocked action list, and an `onActivated` callback that sets the selected item
UID. For an empty cell, pass `item = nil`, `equipped = false`, an empty action
list, and no activation callback.

Keep the grid height large enough for two rows and update the panel size
constraint so the six squares are visible without a scroll frame.

- [ ] **Step 7: Add loading and stale-selection guards**

Keep the current `inventory == nil` loading branch, showing
`Carregando inventário...` rather than rendering empty slots. When a snapshot is
available, verify that `selectedItemUid` still matches one of the six rendered
items inside a `React.useEffect` that depends on `inventory` and
`selectedItemUid`; if it does not, call `setSelectedItemUid(nil)` from that
effect. This prevents a stale dropdown without updating React state during
rendering when a replicated snapshot no longer contains the selected item.

- [ ] **Step 8: Run the source lint check**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: the command exits successfully with no diagnostics in `App.luau` or
the component modules.

- [ ] **Step 9: Commit the grid integration**

```bash
git add -- src/client/ui/App.luau
git commit -m "feat(inventory): render mocked slot grid"
```

## Task 5: Add Floating Dropdown and Confirmation Integration

**Files:**
- Modify: `src/client/ui/App.luau`
- Consume: `DropdownMenu`, `ConfirmationModal`, selected UID, confirmation UID, and mocked action callbacks
- Produce: non-layout dropdown overlay and modal flow for discard confirmation
- Test: none; UI specs are explicitly out of scope

- [ ] **Step 1: Add an overlay grid beside the inventory grid**

Render a transparent overlay `Frame` as a sibling of the inventory grid. Give it
the same position, size, `UIGridLayout` cell size, padding, fill direction, and
three-column limit as the visual grid. Set `ClipsDescendants = false` and a
`ZIndex` above the slots. Its cells must have no background and no activation
behavior.

Using the same layout for the overlay cells makes the menu responsive to the
panel width without measuring screen coordinates or changing the inventory
grid's layout.

- [ ] **Step 2: Mount one dropdown in the selected overlay cell**

Generate six overlay cells in the same index order. Render `DropdownMenu` only
inside the cell whose item UID equals `selectedItemUid`. Pass the matching
mocked action list and `visible = true`.

Position the menu outside its transparent cell: use the right side for the
first two columns and the left side for the third column. Use the fixed menu
width and gap constants for the left-side `UDim2` offset. The cell and the
panel must have `ClipsDescendants = false`, so the menu remains visible over the
neighboring cells without consuming grid space.

- [ ] **Step 3: Add the confirmation modal as a ScreenGui-level sibling**

Require `ConfirmationModal` and render it as a sibling of the inventory panel
inside the root `ScreenGui`. Its props must be:

```lua
visible = confirmationItemUid ~= nil
message = "Deseja descartar o item?"
cancelLabel = "não"
confirmLabel = "sim"
onCancel = function()
    setConfirmationItemUid(nil)
end
onConfirm = function()
    setConfirmationItemUid(nil)
end
```

The confirmation callback must not remove the item, call
`InventoryController.use`, fire a remote, or manufacture a local inventory
snapshot.

- [ ] **Step 4: Keep the dropdown/modal state transitions controlled**

Verify the resulting transitions in `App`:

```text
occupied slot -> selectedItemUid = uid -> matching dropdown visible
empty slot -> no activation -> no dropdown
other occupied slot -> selectedItemUid = other uid -> menu moves
usar/equipar -> selectedItemUid = nil
descartar -> selectedItemUid = nil and confirmationItemUid = uid
não -> confirmationItemUid = nil
sim -> confirmationItemUid = nil, inventory unchanged
```

Do not add global input listeners for the dropdown or modal. The existing `T`
listener remains the only inventory visibility shortcut.

- [ ] **Step 5: Run the source lint check**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: the command exits successfully with no diagnostics in all changed
source files.

- [ ] **Step 6: Commit the overlay integration**

```bash
git add -- src/client/ui/App.luau
git commit -m "feat(inventory): integrate floating actions and confirmation"
```

## Task 6: Run Static Verification and Build Both Places

**Files:**
- Read: `AGENTS.md`, `README.md`, `test.project.json`, `default.project.json`
- Verify: `src/client/ui/ConfirmationModal.luau`, `src/client/ui/DropdownMenu.luau`, `src/client/ui/InventorySlot.luau`, `src/client/ui/App.luau`
- Test: static lint, Roblox typecheck, and Rojo builds

- [ ] **Step 1: Confirm only intended source files changed**

Run:

```bash
git status --short
git diff -- src/client/ui/App.luau src/shared/inventory/catalog.luau
```

Expected: the UI component files and `App.luau` are the only implementation
changes. The pre-existing modification to
`src/shared/inventory/catalog.luau` remains untouched and unstaged.

- [ ] **Step 2: Run both Selene configurations**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Expected: both commands exit with status zero.

- [ ] **Step 3: Regenerate the test sourcemap**

Run:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Expected: the generated sourcemap includes the production client UI modules
through the paths mapped by `test.project.json`.

- [ ] **Step 4: Run the Roblox-platform typecheck**

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

Expected: no type errors for the component prop tables, React elements,
`InventoryState` access, or strict Luau code.

- [ ] **Step 5: Build the normal and test Rojo projects**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: both builds complete successfully. Do not edit generated package
directories or generated sourcemaps by hand.

## Task 7: Verify the UI in a Clean Roblox Studio Play Session

**Files:**
- Verify in Studio: `StarterPlayer.StarterPlayerScripts.Client.ui.App` and the three component modules through the normal place
- Test: clean Play session through the Roblox Studio MCP workflow

- [ ] **Step 1: Start a clean Play session and wait for the client UI**

Use the connected Roblox Studio session, start Play, wait for the local player
and `PlayerGui`, and verify that the normal client entrypoint mounts `DungeonGui`.
Do not use the TestEZ place as a substitute for the normal gameplay UI check.

- [ ] **Step 2: Verify the grid and loading states**

Check that the panel remains hidden until `T` is pressed. After opening it,
verify that it contains three columns and two rows, that empty positions remain
visible as squares, and that a loaded item shows its catalog name or `itemId`
fallback. Confirm that the loading branch does not present six empty slots
before the inventory snapshot arrives.

- [ ] **Step 3: Verify equipped and item display states**

Use the current inventory fixture to verify that an item whose `uid` appears in
`inventory.equipped` displays the exact label `equipado`, while empty and
unequipped slots do not. Confirm that a quantity, when present, is visible with
the item name.

- [ ] **Step 4: Verify floating menu behavior**

Click an occupied slot and confirm that its menu appears beside the slot above
the interface, without moving or resizing any grid cell. Click a slot in a
different column and confirm that the menu changes side when needed while
remaining visible. Click an empty slot and confirm that no menu opens.

- [ ] **Step 5: Verify mocked action behavior**

Select `usar` or `equipar` where present and confirm that the dropdown closes
without changing the inventory. Select `descartar` and confirm that the
dropdown closes immediately and the modal appears.

- [ ] **Step 6: Verify confirmation behavior**

Confirm that the modal displays `Deseja descartar o item?` with buttons `não`
and `sim`. Click outside the panel and press `Escape`; the modal must remain
open. Click `não` and verify it closes without a state change. Reopen it, click
`sim`, and verify it closes without removing the item or changing the snapshot.

- [ ] **Step 7: Stop Play and inspect the final worktree**

Stop the Studio session, then run:

```bash
git status --short
git diff --check
```

Expected: no generated or unrelated files are added, no whitespace errors are
reported, and the existing catalog modification remains preserved.

## Completion Criteria

The implementation is complete when all of the following are true:

- `ConfirmationModal`, `DropdownMenu`, and `InventorySlot` are independent
  strict React modules under `src/client/ui/`.
- `App` renders six slots in a three-by-two grid using the real inventory
  snapshot and local mock action data.
- Empty slots are visible and inert.
- Occupied slots display names and optional quantities.
- Equipped slots display `equipado` based on `inventory.equipped` values.
- The dropdown is floating, side-aware, and does not change grid layout.
- Selecting a different slot replaces the current dropdown.
- Selecting an action closes the dropdown.
- Discard opens a confirmation modal with the agreed Portuguese copy.
- The modal can be closed only through `não` or `sim`.
- Confirming does not mutate gameplay state in this phase.
- Selene, typecheck, both Rojo builds, and the clean Studio checklist succeed.
- `catalog.luau` and all server/shared inventory behavior remain unchanged.
