# P1: Componentes Folha da UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extrair quatro componentes React apresentacionais de `src/client/ui/App.luau` — `CombatStatus`, `PickupToast`, `DialogueOverlay` e `ObjectivesPanel` — sem mudança de comportamento visual.

**Architecture:** Cada componente vira um módulo em `src/client/ui/` com contrato de props próprio; `App` deixa de construir essas árvores e apenas compõe. `ObjectivesPanel` consome `ObjectiveState` exportado por `useObjectives`; os demais importam tipos já exportados (`DialogState`, `ItemId`). Todos usam os tokens de `theme.luau` criados no P0.

**Tech Stack:** Luau `--!strict`, React (jsdotlua/react 17.2.1), Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0.

## Global Constraints

- **Pré-requisito:** P0 concluído (`docs/superpowers/plans/2026-09-10-p0-ui-extraction-foundation.md`). O `App.luau` já deve referenciar `combatHud.*` e `theme.*` antes de iniciar este plano.
- **Sem testes unitários** (instrução explícita do usuário). Nenhum spec TestEZ deve ser criado ou alterado.
- **Sem commits** (AGENTS.md). Nenhuma etapa de `git commit`.
- `src/client` exige módulos client-side por caminho absoluto: `local StarterPlayer = game:GetService("StarterPlayer")` + `StarterPlayer.StarterPlayerScripts.Client.<caminho>`.
- `--!strict` em todos os módulos novos; proibido `--!nocheck` ou `any` para silenciar erros.
- Comportamento idêntico: nenhuma propriedade, texto, cor, ordem de filhos, `ZIndex`, `LayoutOrder` ou condição de render pode mudar. Copie os valores de `App.luau` literalmente, trocando apenas as cores pelos tokens equivalentes do `theme`.
- Tipos compartilhados são exportados pelo módulo dono e importados pelo consumidor; não redeclarar `ObjectiveState`/`ObjectiveView`/`DialogState`/`ItemId`.
- Verificação por tarefa: `selene` + `rojo sourcemap` + `luau-lsp analyze`. Build e Play manual no final.
- Após alterar scripts, parar e reiniciar a sessão Play do Studio antes de validar manualmente.

## Mapa de cores P0 → tokens

Todos os componentes novos usam estes tokens (valores já migrados no P0):

| RGB original | Token |
|--------------|-------|
| `20, 22, 30` | `theme.panel` |
| `241, 237, 255` | `theme.text` |
| `173, 179, 198` | `theme.textMuted` |
| `191, 223, 161` | `theme.success` |
| `173, 196, 162` | `theme.successMuted` |
| `225, 222, 239` | `theme.objectiveText` |
| `107, 92, 168` | `theme.accent` |

---

## Estrutura de arquivos

| Ação | Arquivo | Responsabilidade |
|------|---------|------------------|
| Criar | `src/client/ui/CombatStatus.luau` | HUD de arma equipada e munição (props: 3 strings) |
| Criar | `src/client/ui/PickupToast.luau` | Toast "Pegou <nome>" resolvendo o nome pelo `itemId` |
| Criar | `src/client/ui/DialogueOverlay.luau` | Texto de diálogo com formatação de opções e RichText |
| Criar | `src/client/ui/ObjectivesPanel.luau` | Painel de objetivos visível com o inventário |
| Modificar | `src/client/objectives/useObjectives.luau` | Exportar `ObjectiveView` e `ObjectiveState` |
| Modificar | `src/client/ui/App.luau` | Compor os quatro componentes; remover as árvores inline |

---

## Task 1: `CombatStatus.luau`

**Files:**
- Create: `src/client/ui/CombatStatus.luau`
- Modify: `src/client/ui/App.luau` (require; bloco `CombatStatus` no fragmento)

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.React`; `StarterPlayerScripts.Client.ui.theme`
- Produces: componente `CombatStatus` com `Props = { weaponName: string, loadedAmmo: string, reserveAmmo: string }`

- [ ] **Step 1: Criar `src/client/ui/CombatStatus.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	weaponName: string,
	loadedAmmo: string,
	reserveAmmo: string,
}

local function CombatStatus(props: Props)
	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(224, 76),
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = theme.accent,
			Transparency = 0.25,
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 16),
			Font = Enum.Font.Gotham,
			Text = "ARMA EQUIPADA",
			TextColor3 = theme.textMuted,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Weapon = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 24),
			Size = UDim2.new(1, -28, 0, 22),
			Font = Enum.Font.GothamBold,
			Text = props.weaponName,
			TextColor3 = theme.text,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Ammo = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 49),
			Size = UDim2.new(1, -28, 0, 18),
			Font = Enum.Font.GothamBold,
			Text = string.format("CARREGADA  %s    DISPONÍVEL  %s", props.loadedAmmo, props.reserveAmmo),
			TextColor3 = theme.success,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

return CombatStatus
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após `local combatHudState = require(...)` (criado no P0), adicionar:

```lua
local CombatStatus = require(StarterPlayer.StarterPlayerScripts.Client.ui.CombatStatus)
```

- [ ] **Step 3: Substituir a árvore inline pela composição**

Substituir o bloco exato de `App.luau`:

```lua
			CombatStatus = React.createElement("Frame", {
				AnchorPoint = Vector2.new(1, 1),
				BackgroundColor3 = theme.panel,
				BackgroundTransparency = 0.08,
				Position = UDim2.new(1, -24, 1, -24),
				Size = UDim2.fromOffset(224, 76),
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = React.createElement("UIStroke", {
					Color = theme.accent,
					Transparency = 0.25,
				}),
				Title = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 8),
					Size = UDim2.new(1, -28, 0, 16),
					Font = Enum.Font.Gotham,
					Text = "ARMA EQUIPADA",
					TextColor3 = theme.textMuted,
					TextSize = 10,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Weapon = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 24),
					Size = UDim2.new(1, -28, 0, 22),
					Font = Enum.Font.GothamBold,
					Text = combatHud.weaponName,
					TextColor3 = theme.text,
					TextSize = 14,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Ammo = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 49),
					Size = UDim2.new(1, -28, 0, 18),
					Font = Enum.Font.GothamBold,
					Text = string.format("CARREGADA  %s    DISPONÍVEL  %s", combatHud.loadedAmmo, combatHud.reserveAmmo),
					TextColor3 = theme.success,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}),
```

por:

```lua
			CombatStatus = React.createElement(CombatStatus, {
				weaponName = combatHud.weaponName,
				loadedAmmo = combatHud.loadedAmmo,
				reserveAmmo = combatHud.reserveAmmo,
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

Esperado: zero diagnósticos novos em `CombatStatus.luau` e `App.luau`.

---

## Task 2: `PickupToast.luau`

**Files:**
- Create: `src/client/ui/PickupToast.luau`
- Modify: `src/client/ui/App.luau` (require; remoção de `notificationItem`/`notificationName`; bloco `PickupNotification`)

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.React`; `ReplicatedStorage.Shared.inventory.items`; `StarterPlayerScripts.Client.ui.theme`
- Produces: componente `PickupToast` com `Props = { itemId: items.ItemId? }`; retorna `nil` quando `itemId` é `nil`

- [ ] **Step 1: Criar `src/client/ui/PickupToast.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	itemId: items.ItemId?,
}

local function PickupToast(props: Props)
	local itemId = props.itemId
	if itemId == nil then
		return nil
	end

	local item = items[itemId]
	local name = if item ~= nil then item.name else itemId

	return React.createElement("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(240, 42),
		Font = Enum.Font.GothamBold,
		Text = "Pegou " .. name,
		TextColor3 = theme.text,
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
	})
end

return PickupToast
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após o require de `CombatStatus`:

```lua
local PickupToast = require(StarterPlayer.StarterPlayerScripts.Client.ui.PickupToast)
```

- [ ] **Step 3: Remover a resolução inline do nome**

Remover o bloco exato de `App.luau`:

```lua
	local notificationItem = if notificationItemId ~= nil then items[notificationItemId] else nil
	local notificationName = if notificationItem ~= nil then notificationItem.name else notificationItemId
```

Manter `local notificationItemId = usePickupNotification()`. O require de `items` em `App.luau` permanece: ele ainda é usado em `local inventory: items.InventoryState?`.

- [ ] **Step 4: Substituir a árvore inline pela composição**

Substituir o bloco exato de `App.luau`:

```lua
			PickupNotification = if notificationName ~= nil
			then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = theme.panel,
				BackgroundTransparency = 0.08,
				Position = UDim2.new(0, 24, 1, -24),
				Size = UDim2.fromOffset(240, 42),
				Font = Enum.Font.GothamBold,
				Text = "Pegou " .. notificationName,
				TextColor3 = theme.text,
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
			})
				else nil,
```

por:

```lua
			PickupNotification = React.createElement(PickupToast, {
				itemId = notificationItemId,
			}),
```

- [ ] **Step 5: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos. Confirmar que o fallback `items[itemId] == nil → name = itemId` continua idêntico.

---

## Task 3: `DialogueOverlay.luau`

**Files:**
- Create: `src/client/ui/DialogueOverlay.luau`
- Modify: `src/client/ui/App.luau` (require; remoção da formatação `dialogueText`; bloco `Dialogue`)

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.React`; `StarterPlayerScripts.Client.ui.theme`; `StarterPlayerScripts.Client.dialogue.DialogueController` (`DialogState`)
- Produces: componente `DialogueOverlay` com `Props = { dialogue: DialogueControllerModule.DialogState? }`; retorna `nil` quando `dialogue` é `nil`

- [ ] **Step 1: Criar `src/client/ui/DialogueOverlay.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
local DialogueControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueController)

type Props = {
	dialogue: DialogueControllerModule.DialogState?,
}

local function resolveDialogueText(dialogue: DialogueControllerModule.DialogState): string
	local text = dialogue.visibleText
	if dialogue.kind == "question" and not dialogue.isTyping then
		local renderedOptions = {}
		for index, option in dialogue.options do
			local marker = if index == dialogue.selectedIndex then "> " else "  "
			table.insert(renderedOptions, marker .. option.text)
		end
		text = (dialogue.visibleText or "") .. "\n" .. table.concat(renderedOptions, "    ")
	end
	return text
end

local function DialogueOverlay(props: Props)
	local dialogue = props.dialogue
	if dialogue == nil then
		return nil
	end

	return React.createElement("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0.8, 0),
		Size = UDim2.new(0.6, 0, 0, 0),
		Font = Enum.Font.RobotoMono,
		RichText = true,
		Text = "<b>" .. resolveDialogueText(dialogue) .. "</b>",
		TextColor3 = theme.success,
		TextSize = 20,
		TextStrokeColor3 = theme.panel,
		TextStrokeTransparency = 0.05,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = 20,
	})
end

return DialogueOverlay
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após o require de `PickupToast`:

```lua
local DialogueOverlay = require(StarterPlayer.StarterPlayerScripts.Client.ui.DialogueOverlay)
```

- [ ] **Step 3: Remover a formatação inline**

Remover o bloco exato de `App.luau`:

```lua
	local dialogueText: string? = nil

	if dialogue ~= nil then
		dialogueText = dialogue.visibleText
		if dialogue.kind == "question" and not dialogue.isTyping then
			local renderedOptions = {}
			for index, option in dialogue.options do
				local marker = if index == dialogue.selectedIndex then "> " else "  "
				table.insert(renderedOptions, marker .. option.text)
			end
			local visibleText: string = dialogue.visibleText or ""
			dialogueText = visibleText .. "\n" .. table.concat(renderedOptions, "    ")
		end
	end
```

- [ ] **Step 4: Substituir a árvore inline pela composição**

Substituir o bloco exato de `App.luau`:

```lua
			Dialogue = if dialogueText ~= nil
			then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, 0, 0.8, 0),
				Size = UDim2.new(0.6, 0, 0, 0),
				Font = Enum.Font.RobotoMono,
				RichText = true,
				Text = '<b>' .. dialogueText .. "</b>",
				TextColor3 = theme.success,
				TextSize = 20,
				TextStrokeColor3 = theme.panel,
				TextStrokeTransparency = 0.05,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				ZIndex = 20,
			})
				else nil,
```

por:

```lua
			Dialogue = React.createElement(DialogueOverlay, {
				dialogue = dialogue,
			}),
```

- [ ] **Step 5: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos. Conferir que as opções continuam concatenadas com `"    "` e que o marcador `"> "`/`"  "` usa `selectedIndex`.

---

## Task 4: `ObjectivesPanel.luau`

**Files:**
- Create: `src/client/ui/ObjectivesPanel.luau`
- Modify: `src/client/objectives/useObjectives.luau` (exportar tipos)
- Modify: `src/client/ui/App.luau` (require; remoção de `objectiveRows`/`objectivePanel`; composição do painel)

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.React`; `StarterPlayerScripts.Client.ui.theme`; `StarterPlayerScripts.Client.objectives.useObjectives` (`ObjectiveState`)
- Produces: tipos `useObjectives.ObjectiveView` e `useObjectives.ObjectiveState`; componente `ObjectivesPanel` com `Props = { visible: boolean, objectives: useObjectives.ObjectiveState? }`

- [ ] **Step 1: Exportar os tipos em `src/client/objectives/useObjectives.luau`**

Substituir:

```lua
type ObjectiveView = {
	id: string,
	text: string,
	completed: boolean,
}

type ObjectiveState = {
	objectives: { ObjectiveView },
}
```

por:

```lua
export type ObjectiveView = {
	id: string,
	text: string,
	completed: boolean,
}

export type ObjectiveState = {
	objectives: { ObjectiveView },
}
```

- [ ] **Step 2: Criar `src/client/ui/ObjectivesPanel.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
local useObjectives = require(StarterPlayer.StarterPlayerScripts.Client.objectives.useObjectives)

type Props = {
	visible: boolean,
	objectives: useObjectives.ObjectiveState?,
}

local function ObjectivesPanel(props: Props)
	if not props.visible then
		return nil
	end
	local objectives = props.objectives
	if objectives == nil then
		return nil
	end

	local objectiveRows = {}
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
				then theme.successMuted
				else theme.objectiveText,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		})
	end
	objectiveRows.ListLayout = React.createElement("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	return React.createElement("Frame", {
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		SizeConstraint = React.createElement("UISizeConstraint", {
			MaxSize = Vector2.new(340, 1000),
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 24),
			Font = Enum.Font.GothamBold,
			Text = "OBJETIVOS",
			TextColor3 = theme.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 44),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, objectiveRows),
	})
end

return ObjectivesPanel
```

- [ ] **Step 3: Adicionar o require em `src/client/ui/App.luau`**

Após o require de `DialogueOverlay` (ou junto aos demais componentes de UI, por exemplo após `local ObjectiveNotification = require(...)`):

```lua
local ObjectivesPanel = require(StarterPlayer.StarterPlayerScripts.Client.ui.ObjectivesPanel)
```

- [ ] **Step 4: Remover as construções inline**

Remover o bloco exato de `App.luau`:

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
					then theme.successMuted
					else theme.objectiveText,
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

	local objectivePanel = if inventoryVisible and objectives ~= nil then React.createElement("Frame", {
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		SizeConstraint = React.createElement("UISizeConstraint", {
			MaxSize = Vector2.new(340, 1000),
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 24),
			Font = Enum.Font.GothamBold,
			Text = "OBJETIVOS",
			TextColor3 = theme.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 44),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, objectiveRows),
	}) else nil
```

Manter `local objectives = useObjectives()` no `App.luau`.

- [ ] **Step 5: Compor o painel no `ObjectiveStack`**

Substituir:

```lua
			Panel = objectivePanel,
```

por:

```lua
			Panel = React.createElement(ObjectivesPanel, {
				visible = inventoryVisible,
				objectives = objectives,
			}),
```

- [ ] **Step 6: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos. Conferir que:
- `objectiveRows` continua usando `objective.id` como chave e `index` como `LayoutOrder`;
- o painel aparece somente com `inventoryVisible == true` e `objectives ~= nil`;
- `ObjectiveNotification` continua como filho `Notice` do `ObjectiveStack`, sem mudança.

---

## Verificação final do P1

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
  - HUD de combate com arma/munição corretos (equipar e atirar mudam os valores);
  - Toast de pickup aparece ao coletar item e some após ~2s;
  - Diálogo tipo `message` e `question` renderiza texto, opções e marcador `>` como antes;
  - Painel de objetivos aparece/some junto com o inventário (`Tab`) com os mesmos textos e cores.
- [ ] Reportar o que foi verificado e qualquer desvio encontrado.

## Fora de escopo (não fazer neste plano)

- Extrair `InventoryPanel` e seus subcomponentes (P2).
- Mover `DocumentReaderHost` ou `useInventoryHotkey` (P3).
- Migrar `theme` para os arquivos que ainda não foram tocados (P4).
- Criar ou alterar specs TestEZ.
- Commits.
