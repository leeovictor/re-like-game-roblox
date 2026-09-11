# P2: InventoryPanel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extrair o painel de inventário de `src/client/ui/App.luau` em `InventoryPanel`, `InventoryTabs` e `InventoryGrid`, movendo o estado de aba/seleção para o painel e deixando o `App` só com a orquestração.

**Architecture:** Três módulos novos: `InventoryTabs` (apresentacional), `InventoryGrid` (grade + dropdowns + efeito de validade da seleção) e `InventoryPanel` (shell, estado local, conteúdo). A `ConfirmationModal` **permanece no `App`**: seu backdrop usa `Size = UDim2.fromScale(1, 1)` e precisa continuar como filho direto da `DungeonGui` (ScreenGui), não do painel. O `InventoryPanel` fica sempre montado e retorna `nil` quando `visible` é falso, para preservar a aba selecionada entre aberturas; a seleção é limpa por efeito quando `visible` fica falso.

**Tech Stack:** Luau `--!strict`, React (jsdotlua/react 17.2.1), Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0.

## Global Constraints

- **Pré-requisito:** P0 e P1 concluídos. O `App.luau` já usa `combatHud.*`, `theme.*`, `inventoryPresentation`, `inventoryActions` e os componentes `CombatStatus`/`PickupToast`/`DialogueOverlay`/`ObjectivesPanel`.
- **Sem testes unitários** (instrução explícita do usuário). Nenhum spec TestEZ deve ser criado ou alterado.
- **Sem commits** (AGENTS.md). Nenhuma etapa de `git commit`.
- `src/client` exige módulos client-side por caminho absoluto: `local StarterPlayer = game:GetService("StarterPlayer")` + `StarterPlayer.StarterPlayerScripts.Client.<caminho>`.
- `--!strict` em todos os módulos novos; proibido `--!nocheck` ou `any` para silenciar erros.
- Comportamento idêntico: nenhuma propriedade, texto, cor, ordem de filhos, `ZIndex`, `LayoutOrder`, dependência de efeito ou condição de render pode mudar.
- A `ConfirmationModal` continua no `App.luau` e `confirmationItemUid` continua sendo estado do `App`; o painel apenas emite o pedido de descarte via `onRequestDiscard`.
- Verificação por tarefa: `selene` + `rojo sourcemap` + `luau-lsp analyze`. Build e Play manual no final.
- Após alterar scripts, parar e reiniciar a sessão Play do Studio antes de validar manualmente.

---

## Estrutura de arquivos

| Ação | Arquivo | Responsabilidade |
|------|---------|------------------|
| Criar | `src/client/ui/InventoryTabs.luau` | Abas ITENS/DOCUMENTOS (apresentacional) |
| Criar | `src/client/ui/InventoryGrid.luau` | Grade de 6 slots, `InventorySlot`, `DropdownMenu` e efeito de validade da seleção |
| Criar | `src/client/ui/InventoryPanel.luau` | Shell, estado de aba/seleção, conteúdo (documentos/carregando/grade) |
| Modificar | `src/client/ui/App.luau` | Compor o painel; remover estado, efeitos, constantes e árvores do inventário |

---

## Task 1: `InventoryTabs.luau`

**Files:**
- Create: `src/client/ui/InventoryTabs.luau`
- Modify: `src/client/ui/App.luau` (require; bloco `Tabs` do shell inline)

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.React`; `StarterPlayerScripts.Client.ui.theme`
- Produces: componente `InventoryTabs` com `Props = { activeTab: string, onTabChanged: (tab: string) -> () }`

- [ ] **Step 1: Criar `src/client/ui/InventoryTabs.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	activeTab: string,
	onTabChanged: (tab: string) -> (),
}

local function InventoryTabs(props: Props)
	return React.createElement("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 28),
	}, {
		Items = React.createElement("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = if props.activeTab == "items"
				then theme.surfaceActive
				else theme.surface,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(0.48, -3, 1, 0),
			Text = "ITENS",
			TextColor3 = theme.text,
			TextSize = 11,
			[React.Event.Activated] = function()
				props.onTabChanged("items")
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
		}),
		Documents = React.createElement("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = if props.activeTab == "documents"
				then theme.surfaceActive
				else theme.surface,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0.52, 3, 0, 0),
			Size = UDim2.new(0.48, -3, 1, 0),
			Text = "DOCUMENTOS",
			TextColor3 = theme.text,
			TextSize = 11,
			[React.Event.Activated] = function()
				props.onTabChanged("documents")
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
		}),
	})
end

return InventoryTabs
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após `local InventorySlot = require(...)`:

```lua
local InventoryTabs = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryTabs)
```

- [ ] **Step 3: Substituir o bloco `Tabs` do shell inline**

Substituir o bloco exato de `App.luau`:

```lua
			Tabs = React.createElement("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 40),
				Size = UDim2.new(1, -32, 0, 28),
			}, {
				Items = React.createElement("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = if inventoryTab == "items"
						then theme.surfaceActive
						else theme.surface,
					Font = Enum.Font.GothamBold,
					Size = UDim2.new(0.48, -3, 1, 0),
					Text = "ITENS",
					TextColor3 = theme.text,
					TextSize = 11,
					[React.Event.Activated] = function()
						setInventoryTab("items")
					end,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 5),
					}),
				}),
				Documents = React.createElement("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = if inventoryTab == "documents"
						then theme.surfaceActive
						else theme.surface,
					Font = Enum.Font.GothamBold,
					Position = UDim2.new(0.52, 3, 0, 0),
					Size = UDim2.new(0.48, -3, 1, 0),
					Text = "DOCUMENTOS",
					TextColor3 = theme.text,
					TextSize = 11,
					[React.Event.Activated] = function()
						setInventoryTab("documents")
					end,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 5),
					}),
				}),
			}),
```

por:

```lua
			Tabs = React.createElement(InventoryTabs, {
				activeTab = inventoryTab,
				onTabChanged = function(nextTab: string)
					setInventoryTab(nextTab)
				end,
			}),
```

- [ ] **Step 4: Verificar**

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/player \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Esperado: zero diagnósticos novos em `InventoryTabs.luau` e `App.luau`.

---

## Task 2: `InventoryGrid.luau`

**Files:**
- Create: `src/client/ui/InventoryGrid.luau`
- Modify: `src/client/ui/App.luau` (require; ramo `else` do conteúdo; efeito de validade; constantes e requires que ficam sem uso)

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.React`; `ReplicatedStorage.Shared.inventory.items`; `StarterPlayerScripts.Client.inventory.inventoryPresentation`; `StarterPlayerScripts.Client.inventory.inventoryActions` (`ActionOption`); `StarterPlayerScripts.Client.ui.InventorySlot`; `StarterPlayerScripts.Client.ui.DropdownMenu`
- Produces: componente `InventoryGrid` com `Props = { inventory: items.InventoryState, selectedItemUid: string?, onSelectItem: (uid: string?) -> (), onEquip: (uid: string) -> (), onRequestDiscard: (uid: string) -> () }`; o componente roda o efeito que limpa a seleção quando o `uid` selecionado não está nos 6 primeiros itens

- [ ] **Step 1: Criar `src/client/ui/InventoryGrid.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local inventoryPresentation = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryPresentation)
local inventoryActions = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryActions)
local InventorySlot = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventorySlot)
local DropdownMenu = require(StarterPlayer.StarterPlayerScripts.Client.ui.DropdownMenu)

type Props = {
	inventory: items.InventoryState,
	selectedItemUid: string?,
	onSelectItem: (uid: string?) -> (),
	onEquip: (uid: string) -> (),
	onRequestDiscard: (uid: string) -> (),
}

local INVENTORY_SLOT_COUNT = 6
local INVENTORY_GRID_COLUMNS = 3
local INVENTORY_GAP = 8
local INVENTORY_CELL_SIZE = UDim2.new(
	1 / INVENTORY_GRID_COLUMNS,
	-6,
	0.5,
	-(INVENTORY_GAP / 2)
)
local INVENTORY_CONTENT_ASPECT_RATIO = 280 / 184
local DROPDOWN_WIDTH = 144

local function InventoryGrid(props: Props)
	React.useEffect(function()
		if props.selectedItemUid == nil then
			return
		end

		for index = 1, INVENTORY_SLOT_COUNT do
			local instance = props.inventory.items[index]
			if instance ~= nil and instance.uid == props.selectedItemUid then
				return
			end
		end

		props.onSelectItem(nil)
	end, { props.inventory, props.selectedItemUid })

	local gridChildren = {}
	local overlayChildren = {}
	for index = 1, INVENTORY_SLOT_COUNT do
		local instance = props.inventory.items[index]
		local quantity = if instance ~= nil then inventoryPresentation.getDisplayQuantity(instance) else nil
		local displayItem = if instance ~= nil
			then inventoryPresentation.resolveDisplayItem(instance.itemId, quantity)
			else nil
		local isEquipped = if instance ~= nil
			then inventoryPresentation.isItemEquipped(props.inventory.equipped, instance.uid)
			else false
		local actionOptions: { inventoryActions.ActionOption } = if instance ~= nil
			then inventoryActions.buildActionOptions(instance.uid, instance.itemId, {
				dismiss = function()
					props.onSelectItem(nil)
				end,
				equip = function(uid: string)
					props.onEquip(uid)
				end,
				requestDiscard = function(uid: string)
					props.onRequestDiscard(uid)
				end,
			})
			else {}

		gridChildren[tostring(index)] = React.createElement("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
		}, {
			Slot = React.createElement(InventorySlot, {
				item = displayItem,
				equipped = isEquipped,
				actions = actionOptions,
				onActivated = if instance ~= nil
					then function()
						props.onSelectItem(instance.uid)
					end
					else nil,
			}),
		})

		local column = ((index - 1) % INVENTORY_GRID_COLUMNS) + 1
		local dropdownPosition = if column < INVENTORY_GRID_COLUMNS
			then UDim2.new(1, INVENTORY_GAP, 0, 0)
			else UDim2.new(0, -DROPDOWN_WIDTH - INVENTORY_GAP, 0, 0)
		overlayChildren[tostring(index)] = React.createElement("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = false,
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
		}, {
			Menu = if instance ~= nil and props.selectedItemUid == instance.uid
				then React.createElement(DropdownMenu, {
					visible = true,
					options = actionOptions,
					position = dropdownPosition,
				})
				else nil,
		})
	end

	gridChildren.Layout = React.createElement("UIGridLayout", {
		CellPadding = UDim2.fromOffset(INVENTORY_GAP, INVENTORY_GAP),
		CellSize = INVENTORY_CELL_SIZE,
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = INVENTORY_GRID_COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	overlayChildren.Layout = React.createElement("UIGridLayout", {
		CellPadding = UDim2.fromOffset(INVENTORY_GAP, INVENTORY_GAP),
		CellSize = INVENTORY_CELL_SIZE,
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = INVENTORY_GRID_COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	return React.createElement("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.new(1, -32, 0, 184),
	}, {
		SizeConstraint = React.createElement("UISizeConstraint", {
			MaxSize = Vector2.new(280, 184),
		}),
		AspectRatio = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = INVENTORY_CONTENT_ASPECT_RATIO,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		Grid = React.createElement("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}, gridChildren),
		Overlay = React.createElement("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
		}, overlayChildren),
	})
end

return InventoryGrid
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após o require de `InventoryTabs`:

```lua
local InventoryGrid = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryGrid)
```

- [ ] **Step 3: Substituir o ramo `else` do conteúdo do inventário**

Substituir todo o ramo exato de `App.luau` (do `else` que abre o ramo de itens até o `end` que o fecha):

```lua
	else
		local gridChildren = {}
		local overlayChildren = {}
		for index = 1, INVENTORY_SLOT_COUNT do
			local instance = inventory.items[index]
			local quantity = if instance ~= nil then inventoryPresentation.getDisplayQuantity(instance) else nil
			local displayItem = if instance ~= nil
				then inventoryPresentation.resolveDisplayItem(
					instance.itemId,
					quantity
				)
				else nil
			local isEquipped = if instance ~= nil then inventoryPresentation.isItemEquipped(inventory.equipped, instance.uid) else false
			local actionOptions: { inventoryActions.ActionOption } = if instance ~= nil
				then inventoryActions.buildActionOptions(instance.uid, instance.itemId, {
					dismiss = function()
						setSelectedItemUid(nil)
					end,
					equip = function(uid: string)
						props.inventoryController:equip(uid)
					end,
					requestDiscard = function(uid: string)
						setConfirmationItemUid(uid)
					end,
				})
				else {}

			gridChildren[tostring(index)] = React.createElement("Frame", {
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Size = UDim2.fromScale(1, 1),
			}, {
				Slot = React.createElement(InventorySlot, {
					item = displayItem,
					equipped = isEquipped,
					actions = actionOptions,
					onActivated = if instance ~= nil
						then function()
							setSelectedItemUid(instance.uid)
						end
						else nil,
				}),
			})

			local column = ((index - 1) % INVENTORY_GRID_COLUMNS) + 1
			local dropdownPosition = if column < INVENTORY_GRID_COLUMNS
				then UDim2.new(1, INVENTORY_GAP, 0, 0)
				else UDim2.new(0, -DROPDOWN_WIDTH - INVENTORY_GAP, 0, 0)
			overlayChildren[tostring(index)] = React.createElement("Frame", {
				BackgroundTransparency = 1,
				ClipsDescendants = false,
				LayoutOrder = index,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 10,
			}, {
				Menu = if instance ~= nil and selectedItemUid == instance.uid
					then React.createElement(DropdownMenu, {
						visible = true,
						options = actionOptions,
						position = dropdownPosition,
					})
					else nil,
			})
		end

		gridChildren.Layout = React.createElement("UIGridLayout", {
			CellPadding = UDim2.fromOffset(INVENTORY_GAP, INVENTORY_GAP),
			CellSize = INVENTORY_CELL_SIZE,
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = INVENTORY_GRID_COLUMNS,
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local overlayLayout = React.createElement("UIGridLayout", {
			CellPadding = UDim2.fromOffset(INVENTORY_GAP, INVENTORY_GAP),
			CellSize = INVENTORY_CELL_SIZE,
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = INVENTORY_GRID_COLUMNS,
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		overlayChildren.Layout = overlayLayout
		inventoryContent = React.createElement("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = false,
			Position = UDim2.fromOffset(16, 80),
			Size = UDim2.new(1, -32, 0, 184),
		}, {
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(280, 184),
			}),
			AspectRatio = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = INVENTORY_CONTENT_ASPECT_RATIO,
				DominantAxis = Enum.DominantAxis.Width,
			}),
			Grid = React.createElement("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 1,
			}, gridChildren),
			Overlay = React.createElement("Frame", {
				BackgroundTransparency = 1,
				ClipsDescendants = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 10,
			}, overlayChildren),
		})
	end
```

por:

```lua
	else
		inventoryContent = React.createElement(InventoryGrid, {
			inventory = inventory,
			selectedItemUid = selectedItemUid,
			onSelectItem = function(uid: string?)
				setSelectedItemUid(uid)
			end,
			onEquip = function(uid: string)
				props.inventoryController:equip(uid)
			end,
			onRequestDiscard = function(uid: string)
				setConfirmationItemUid(uid)
			end,
		})
	end
```

- [ ] **Step 4: Remover o efeito de validade do `App.luau`**

Remover o bloco exato:

```lua
	local selectionEffectDependencies: { unknown } = { inventory, selectedItemUid }
	React.useEffect(function()
		if inventory == nil or selectedItemUid == nil then
			return
		end

		for index = 1, INVENTORY_SLOT_COUNT do
			local instance = inventory.items[index]
			if instance ~= nil and instance.uid == selectedItemUid then
				return
			end
		end

		setSelectedItemUid(nil)
	end, selectionEffectDependencies)
```

- [ ] **Step 5: Remover constantes e requires que ficaram sem uso**

Remover de `App.luau`:

```lua
local INVENTORY_SLOT_COUNT = 6
local INVENTORY_GRID_COLUMNS = 3
local INVENTORY_GAP = 8
local INVENTORY_CELL_SIZE = UDim2.new(
	1 / INVENTORY_GRID_COLUMNS,
	-6,
	0.5,
	-(INVENTORY_GAP / 2)
)
local INVENTORY_CONTENT_ASPECT_RATIO = 280 / 184
local DROPDOWN_WIDTH = 144
```

Remover os requires que passaram a ser usados só pelo `InventoryGrid`:

```lua
local InventorySlot = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventorySlot)
local DropdownMenu = require(StarterPlayer.StarterPlayerScripts.Client.ui.DropdownMenu)
local inventoryPresentation = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryPresentation)
local inventoryActions = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryActions)
```

Não remover `local items = require(ReplicatedStorage.Shared.inventory.items)`: ele ainda é usado em `local inventory: items.InventoryState?`. Não remover `INVENTORY_TOGGLE_ACTION` nem `INVENTORY_TOGGLE_PRIORITY` (usados pelo atalho).

- [ ] **Step 6: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos e nenhum aviso de variável não utilizada. Conferir que o dropdown continua com `ZIndex = 50`, que a posição à esquerda/direita depende da coluna e que o efeito de validade agora roda dentro do `InventoryGrid`.

---

## Task 3: `InventoryPanel.luau`

**Files:**
- Create: `src/client/ui/InventoryPanel.luau`
- Modify: `src/client/ui/App.luau` (require; remover estado, efeito de fechar, conteúdo e shell; compor o painel)

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.React`; `ReplicatedStorage.Shared.inventory.items`; `StarterPlayerScripts.Client.inventory.InventoryController` (`InventoryController`); `StarterPlayerScripts.Client.ui.DocumentList`; `StarterPlayerScripts.Client.ui.InventoryTabs`; `StarterPlayerScripts.Client.ui.InventoryGrid`; `StarterPlayerScripts.Client.ui.theme`
- Produces: componente `InventoryPanel` com `Props = { visible: boolean, inventory: items.InventoryState?, inventoryController: InventoryControllerModule.InventoryController, onDocumentActivated: () -> (), onRequestDiscard: (uid: string) -> () }`

- [ ] **Step 1: Criar `src/client/ui/InventoryPanel.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local InventoryControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController)
local DocumentList = require(StarterPlayer.StarterPlayerScripts.Client.ui.DocumentList)
local InventoryTabs = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryTabs)
local InventoryGrid = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryGrid)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	visible: boolean,
	inventory: items.InventoryState?,
	inventoryController: InventoryControllerModule.InventoryController,
	onDocumentActivated: () -> (),
	onRequestDiscard: (uid: string) -> (),
}

local function InventoryPanel(props: Props)
	local inventoryTab, setInventoryTab = React.useState("items")
	local selectedItemUid: string?, setSelectedItemUid: (string?) -> () = React.useState(nil :: string?)

	React.useEffect(function()
		if not props.visible then
			setSelectedItemUid(nil)
		end
	end, { props.visible })

	if not props.visible then
		return nil
	end

	local inventory = props.inventory
	local content
	if inventoryTab == "documents" then
		content = React.createElement(DocumentList, {
			onDocumentActivated = props.onDocumentActivated,
		})
	elseif inventory == nil then
		content = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 80),
			Size = UDim2.new(1, -32, 0, 28),
			Font = Enum.Font.Gotham,
			Text = "Carregando inventário...",
			TextColor3 = theme.textMuted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	else
		content = React.createElement(InventoryGrid, {
			inventory = inventory,
			selectedItemUid = selectedItemUid,
			onSelectItem = function(uid: string?)
				setSelectedItemUid(uid)
			end,
			onEquip = function(uid: string)
				props.inventoryController:equip(uid)
			end,
			onRequestDiscard = props.onRequestDiscard,
		})
	end

	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		Position = UDim2.fromOffset(24, 154),
		Size = UDim2.new(0, 0, 0, 0),
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		SizeConstraint = React.createElement("UISizeConstraint", {
			MaxSize = Vector2.new(360, 300),
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 24),
			Font = Enum.Font.GothamBold,
			Text = "INVENTÁRIO",
			TextColor3 = theme.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Tabs = React.createElement(InventoryTabs, {
			activeTab = inventoryTab,
			onTabChanged = function(nextTab: string)
				setInventoryTab(nextTab)
			end,
		}),
		Content = content,
	})
end

return InventoryPanel
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau` e remover o require do `theme`**

Adicionar após o require de `InventoryGrid`:

```lua
local InventoryPanel = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryPanel)
```

Remover o require que fica sem uso após a extração:

```lua
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

- [ ] **Step 3: Remover o estado de aba e seleção do `App.luau`**

Remover:

```lua
	local inventoryTab, setInventoryTab = React.useState("items")
	local selectedItemUid: string?, setSelectedItemUid: (string?) -> () = React.useState(nil :: string?)
```

- [ ] **Step 4: Remover o efeito que limpava a seleção ao fechar**

Remover:

```lua
	React.useEffect(function()
		if not inventoryVisible then
			setSelectedItemUid(nil)
		end
	end, { inventoryVisible })
```

- [ ] **Step 5: Remover a construção de conteúdo e do shell**

Remover o bloco exato do conteúdo:

```lua
	local inventoryContent
	if inventoryTab == "documents" then
		inventoryContent = React.createElement(DocumentList, {
			onDocumentActivated = function()
				setInventoryVisible(false)
			end,
		})
	elseif inventory == nil then
		inventoryContent = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 80),
			Size = UDim2.new(1, -32, 0, 28),
			Font = Enum.Font.Gotham,
			Text = "Carregando inventário...",
			TextColor3 = theme.textMuted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	else
		inventoryContent = React.createElement(InventoryGrid, {
			inventory = inventory,
			selectedItemUid = selectedItemUid,
			onSelectItem = function(uid: string?)
				setSelectedItemUid(uid)
			end,
			onEquip = function(uid: string)
				props.inventoryController:equip(uid)
			end,
			onRequestDiscard = function(uid: string)
				setConfirmationItemUid(uid)
			end,
		})
	end
```

Remover o bloco exato do shell:

```lua
	local inventoryPanel = if inventoryVisible and not documentReaderActive and not documentReaderMounted then React.createElement("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		Position = UDim2.fromOffset(24, 154),
		Size = UDim2.new(0, 0, 0, 0),
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		SizeConstraint = React.createElement("UISizeConstraint", {
			MaxSize = Vector2.new(360, 300),
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 24),
			Font = Enum.Font.GothamBold,
			Text = "INVENTÁRIO",
			TextColor3 = theme.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Tabs = React.createElement(InventoryTabs, {
			activeTab = inventoryTab,
			onTabChanged = function(nextTab: string)
				setInventoryTab(nextTab)
			end,
		}),
		Content = inventoryContent,
	})
		else nil
```

- [ ] **Step 6: Remover os requires do `DocumentList`, `InventoryTabs` e `InventoryGrid` do `App.luau`**

Remover:

```lua
local DocumentList = require(StarterPlayer.StarterPlayerScripts.Client.ui.DocumentList)
local InventoryTabs = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryTabs)
local InventoryGrid = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryGrid)
```

- [ ] **Step 7: Compor o painel no fragmento**

Substituir:

```lua
			InventoryPanel = inventoryPanel,
```

por:

```lua
			InventoryPanel = React.createElement(InventoryPanel, {
				visible = inventoryVisible and not documentReaderActive and not documentReaderMounted,
				inventory = inventory,
				inventoryController = props.inventoryController,
				onDocumentActivated = function()
					setInventoryVisible(false)
				end,
				onRequestDiscard = function(uid: string)
					setConfirmationItemUid(uid)
				end,
			}),
```

- [ ] **Step 8: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos e nenhum aviso de variável não utilizada. Conferir que:
- `confirmationItemUid`, a `ConfirmationModal` e seus callbacks continuam no `App.luau`, inalterados;
- o efeito `if documentReaderActive or documentReaderMounted then setInventoryVisible(false)` continua no `App.luau`;
- `inventoryVisible`, o atalho `Tab` e o efeito de blur/leitura continuam no `App.luau`;
- a aba selecionada persiste ao fechar/abrir o painel (o componente fica montado e retorna `nil` quando `visible` é falso).

---

## Verificação final do P2

- [ ] Rodar lint completo:

```bash
selene --config selene.roblox.toml src
```

- [ ] Rodar typecheck conforme o passo da Task 1 (sourcemap antes) e confirmar zero diagnósticos novos.
- [ ] Buildar os dois projetos:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

- [ ] Parar e iniciar uma sessão Play limpa no Studio e confirmar:
  - Output sem erros novos de runtime;
  - `TestEZAutoServer`/`TestEZAutoClient` com `failed == 0` (suites existentes; nenhuma spec nova);
  - `Tab` abre/fecha o inventário; a aba ativa persiste entre aberturas;
  - os 6 slots, o badge `equipado`, a quantidade e o estado "Carregando inventário..." se comportam como antes;
  - clicar num item com ações abre o dropdown na posição correta (direita nas colunas 1-2, esquerda na coluna 3);
  - `equipar` equipa a arma e fecha o dropdown; `descartar` abre a `ConfirmationModal` em tela cheia; `usar` apenas fecha o dropdown;
  - abrir um documento pela aba DOCUMENTOS fecha o inventário e abre o leitor;
  - abrir o leitor de documentos com o inventário aberto fecha o inventário;
  - objetivos continuam aparecendo/sumindo junto com o inventário.

## Fora de escopo (não fazer neste plano)

- Mover `DocumentReaderHost` ou `useInventoryHotkey` (P3).
- Migrar `theme` para os arquivos que ainda não foram tocados (P4).
- Mover a `ConfirmationModal` para dentro do `InventoryPanel` (a hierarquia do overlay mudaria).
- Criar ou alterar specs TestEZ.
- Commits.
