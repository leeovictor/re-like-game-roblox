# P0: Fundação Pura da Extração de UI — Implementation Plan

**Goal:** Remover de `src/client/ui/App.luau` a lógica pura de apresentação de inventário, as ações mockadas, a derivação do HUD de combate e criar o módulo de tokens visuais, sem mudança de comportamento.

**Architecture:** Quatro módulos puros/mecânicos são criados em `src/client/inventory/` e `src/client/ui/`; `App.luau` passa a consumi-los. Nenhum componente React novo, nenhum estado movido, nenhuma mudança visual.

**Tech Stack:** Luau `--!strict`, React (jsdotlua/react 17.2.1), Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0.

## Global Constraints

- P0 são os itens 1-4 do plano de prioridades: `inventoryPresentation`, `inventoryActions`, `combatHudState`, `theme`.
- **Sem testes unitários** (instrução explícita do usuário). Nenhum spec TestEZ deve ser criado ou alterado.
- **Sem commits** (AGENTS.md). Nenhuma etapa de `git commit`.
- `src/client` exige módulos client-side por caminho absoluto: declare `local StarterPlayer = game:GetService("StarterPlayer")` e use `StarterPlayer.StarterPlayerScripts.Client.<caminho>`.
- `--!strict` em todos os módulos novos; proibido `--!nocheck` ou `any` para silenciar erros.
- Comportamento idêntico: nenhuma cor, texto, callback, ordem de render ou dependência de efeito pode mudar.
- Verificação por tarefa: `selene` + `luau-lsp analyze` (sourcemap antes) + `rojo build` dos dois projetos.
- A validação manual de regressões é um documento separado e **não** faz parte das etapas deste plano: `docs/manual-verification/2026-09-10-p0-ui-extraction.md`.
- Ordem do typecheck: `rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json` **antes** de `luau-lsp analyze`.

---

## Estrutura de arquivos

| Ação | Arquivo | Responsabilidade |
|------|---------|------------------|
| Criar | `src/client/inventory/inventoryPresentation.luau` | Funções puras de apresentação do inventário (nome exibido, quantidade, equipado) |
| Criar | `src/client/inventory/inventoryActions.luau` | Configuração de ações por `itemId` + builder puro de `ActionOption` com handlers injetados |
| Criar | `src/client/ui/combatHudState.luau` | Derivação pura dos textos do HUD de combate |
| Criar | `src/client/ui/theme.luau` | Tokens de cor reutilizáveis |
| Modificar | `src/client/ui/App.luau` | Consumir os quatro módulos; remover lógica e cores inline |

---

## Task 1: `inventoryPresentation.luau`

**Files:**
- Create: `src/client/inventory/inventoryPresentation.luau`
- Modify: `src/client/ui/App.luau` (requires; bloco do ramo `else` do inventário)

**Interfaces:**
- Consumes: `ReplicatedStorage.Shared.inventory.items` (`ItemId`, `ItemInstance`); `StarterPlayerScripts.Client.combat.CombatConfig` (`WeaponConfig`)
- Produces:
  - `export type DisplayItem = { name: string, quantity: number? }`
  - `inventoryPresentation.resolveDisplayItem(itemId: items.ItemId, quantity: number?): DisplayItem`
  - `inventoryPresentation.getDisplayQuantity(instance: items.ItemInstance): number?`
  - `inventoryPresentation.isItemEquipped(equipped: { [string]: string }, uid: string): boolean`

- [ ] **Step 1: Criar `src/client/inventory/inventoryPresentation.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local items = require(ReplicatedStorage.Shared.inventory.items)
local CombatConfig = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatConfig)

export type DisplayItem = {
	name: string,
	quantity: number?,
}

local function resolveDisplayItem(itemId: items.ItemId, quantity: number?): DisplayItem
	local item = items[itemId]
	return {
		name = if item ~= nil then item.name else itemId,
		quantity = quantity,
	}
end

local function getDisplayQuantity(instance: items.ItemInstance): number?
	if instance.quantity ~= nil then
		return instance.quantity
	end
	local definition = items[instance.itemId]
	if definition == nil or definition.category ~= "weapon" then
		return nil
	end
	local authoredLoadedAmmo = if instance.attributes ~= nil then instance.attributes.loadedAmmo else nil
	if authoredLoadedAmmo ~= nil then
		return if type(authoredLoadedAmmo) == "number" then authoredLoadedAmmo else nil
	end
	local config = CombatConfig[instance.itemId]
	return if config ~= nil then config.magazineSize else nil
end

local function isItemEquipped(equipped: { [string]: string }, uid: string): boolean
	for _, equippedUid in equipped do
		if equippedUid == uid then
			return true
		end
	end
	return false
end

return {
	resolveDisplayItem = resolveDisplayItem,
	getDisplayQuantity = getDisplayQuantity,
	isItemEquipped = isItemEquipped,
}
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Logo após a linha `local useInventory = require(StarterPlayer.StarterPlayerScripts.Client.inventory.useInventory)`, adicionar:

```lua
local inventoryPresentation = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryPresentation)
```

- [ ] **Step 3: Remover as funções locais duplicadas**

Remover, dentro do ramo `else` de `inventoryContent`, o bloco exato:

```lua
		local function isItemEquipped(uid: string): boolean
			for _, equippedUid in inventory.equipped do
				if equippedUid == uid then
					return true
				end
			end
			return false
		end

		local function resolveDisplayItem(itemId: items.ItemId, quantity: number?)
			local item = items[itemId]
			return {
				name = if item ~= nil then item.name else itemId,
				quantity = quantity,
			}
		end

		local function getDisplayQuantity(instance: items.ItemInstance): number?
			if instance.quantity ~= nil then
				return instance.quantity
			end
			local definition = items[instance.itemId]
			if definition == nil or definition.category ~= "weapon" then
				return nil
			end
			local authoredLoadedAmmo = if instance.attributes ~= nil then instance.attributes.loadedAmmo else nil
			if authoredLoadedAmmo ~= nil then
				return if type(authoredLoadedAmmo) == "number" then authoredLoadedAmmo else nil
			end
			local config = CombatConfig[instance.itemId]
			return if config ~= nil then config.magazineSize else nil
		end
```

- [ ] **Step 4: Trocar as chamadas locais pelas do módulo**

Aplicar as três substituições:

```lua
local quantity = if instance ~= nil then inventoryPresentation.getDisplayQuantity(instance) else nil
```

```lua
			local displayItem = if instance ~= nil
				then inventoryPresentation.resolveDisplayItem(
					instance.itemId,
					quantity
				)
				else nil
```

```lua
			local isEquipped = if instance ~= nil then inventoryPresentation.isItemEquipped(inventory.equipped, instance.uid) else false
```

- [ ] **Step 5: Verificar**

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

Esperado: zero diagnósticos novos em `inventoryPresentation.luau` e `App.luau`.

---

## Task 2: `inventoryActions.luau`

**Files:**
- Create: `src/client/inventory/inventoryActions.luau`
- Modify: `src/client/ui/App.luau` (remove tabela mock; troca do builder)

**Interfaces:**
- Consumes: nada além de Luau puro
- Produces:
  - `export type ActionOption = { label: string, onActivated: () -> () }`
  - `export type ActionHandlers = { dismiss: (uid: string) -> (), equip: (uid: string) -> (), requestDiscard: (uid: string) -> () }`
  - `inventoryActions.buildActionOptions(uid: string, itemId: string, handlers: ActionHandlers): { ActionOption }`

- [ ] **Step 1: Criar `src/client/inventory/inventoryActions.luau`**

```lua
--!strict

export type ActionOption = {
	label: string,
	onActivated: () -> (),
}

export type ActionHandlers = {
	dismiss: (uid: string) -> (),
	equip: (uid: string) -> (),
	requestDiscard: (uid: string) -> (),
}

local actionLabelsByItemId: { [string]: { string } } = {
	access_card = { "descartar" },
	bolt_cutter = { "descartar" },
	handgun = { "equipar" },
	handgun_ammo = { "descartar" },
	medkit = { "usar", "descartar" },
}

local function buildActionOptions(uid: string, itemId: string, handlers: ActionHandlers): { ActionOption }
	local options: { ActionOption } = {}
	local labels = actionLabelsByItemId[itemId]
	if labels == nil then
		return options
	end
	for _, label in labels do
		table.insert(options, {
			label = label,
			onActivated = function()
				handlers.dismiss(uid)
				if label == "equipar" then
					handlers.equip(uid)
				elseif label == "descartar" then
					handlers.requestDiscard(uid)
				end
			end,
		})
	end
	return options
end

return {
	buildActionOptions = buildActionOptions,
}
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Logo após o require de `inventoryPresentation` criado na Task 1:

```lua
local inventoryActions = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryActions)
```

- [ ] **Step 3: Remover a tabela mock do topo**

Remover o bloco exato de `App.luau`:

```lua
local mockActionLabelsByItemId: { [string]: { string } } = {
	access_card = { "descartar" },
	bolt_cutter = { "descartar" },
	handgun = { "equipar" },
	handgun_ammo = { "descartar" },
	medkit = { "usar", "descartar" },
}
```

- [ ] **Step 4: Substituir a construção de ações**

Substituir o bloco exato:

```lua
			local actionOptions: { { label: string, onActivated: () -> () } } = {}

			if instance ~= nil then
				local actionLabels = mockActionLabelsByItemId[instance.itemId]
				if actionLabels ~= nil then
					for _, label in actionLabels do
						table.insert(actionOptions, {
							label = label,
							onActivated = function()
								setSelectedItemUid(nil)
								if label == "equipar" then
									props.inventoryController:equip(instance.uid)
								elseif label == "descartar" then
									setConfirmationItemUid(instance.uid)
								end
							end,
						})
					end
				end
			end
```

por:

```lua
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
```

- [ ] **Step 5: Verificar**

Repetir os três comandos do Step 5 da Task 1. Esperado: zero diagnósticos novos. Conferir que `ActionHandlers.dismiss` continua sendo chamado antes de `equip`/`requestDiscard`, preservando a ordem original (`setSelectedItemUid(nil)` primeiro).

---

## Task 3: `combatHudState.luau`

**Files:**
- Create: `src/client/ui/combatHudState.luau`
- Modify: `src/client/ui/App.luau` (remove derivação inline; usa `combatHud`)

**Interfaces:**
- Consumes: `ReplicatedStorage.Shared.inventory.items` (`InventoryState`, `ItemInstance`); `StarterPlayerScripts.Client.combat.CombatConfig` (`WeaponConfig`)
- Produces:
  - `export type CombatHudStats = { weaponName: string, loadedAmmo: string, reserveAmmo: string }`
  - `combatHudState.getEquippedWeaponStats(inventory: items.InventoryState?): CombatHudStats`

- [ ] **Step 1: Criar `src/client/ui/combatHudState.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local items = require(ReplicatedStorage.Shared.inventory.items)
local CombatConfig = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatConfig)

export type CombatHudStats = {
	weaponName: string,
	loadedAmmo: string,
	reserveAmmo: string,
}

local function getEquippedWeaponStats(inventory: items.InventoryState?): CombatHudStats
	local equippedWeapon: items.ItemInstance? = nil
	local weaponConfig: CombatConfig.WeaponConfig? = nil
	local loadedAmmo: number? = nil
	local reserveAmmo = 0

	if inventory ~= nil then
		local equippedWeaponUid = inventory.equipped.weapon
		if equippedWeaponUid ~= nil then
			for _, instance in inventory.items do
				if instance.uid == equippedWeaponUid then
					equippedWeapon = instance
					break
				end
			end
		end
		if equippedWeapon ~= nil then
			weaponConfig = CombatConfig[equippedWeapon.itemId]
			if equippedWeapon.attributes ~= nil then
				local value = equippedWeapon.attributes.loadedAmmo
				if type(value) == "number" then
					loadedAmmo = value
				end
			end
			if loadedAmmo == nil and weaponConfig ~= nil
				and (equippedWeapon.attributes == nil or equippedWeapon.attributes.loadedAmmo == nil)
			then
				loadedAmmo = weaponConfig.magazineSize
			end
			if weaponConfig ~= nil then
				for _, instance in inventory.items do
					if instance.itemId == weaponConfig.ammoItemId and instance.quantity ~= nil then
						reserveAmmo += instance.quantity
					end
				end
			end
		end
	end

	local equippedWeaponDefinition = if equippedWeapon ~= nil then items[equippedWeapon.itemId] else nil
	return {
		weaponName = if equippedWeaponDefinition ~= nil then equippedWeaponDefinition.name else "SEM ARMA",
		loadedAmmo = if loadedAmmo ~= nil then tostring(loadedAmmo) else "--",
		reserveAmmo = if weaponConfig ~= nil then tostring(reserveAmmo) else "--",
	}
end

return {
	getEquippedWeaponStats = getEquippedWeaponStats,
}
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após os requires de UI existentes (por exemplo, após `local ConfirmationModal = require(...)`):

```lua
local combatHudState = require(StarterPlayer.StarterPlayerScripts.Client.ui.combatHudState)
```

- [ ] **Step 3: Substituir a derivação inline**

Remover o bloco exato de `App.luau`:

```lua
	local equippedWeapon: items.ItemInstance? = nil
	local weaponConfig: typeof(CombatConfig.handgun)? = nil
	local loadedAmmo: number? = nil
	local reserveAmmo = 0
	if inventory ~= nil then
		local equippedWeaponUid = inventory.equipped.weapon
		if equippedWeaponUid ~= nil then
			for _, instance in inventory.items do
				if instance.uid == equippedWeaponUid then
					equippedWeapon = instance
					break
				end
			end
		end
		if equippedWeapon ~= nil then
			weaponConfig = CombatConfig[equippedWeapon.itemId]
			if equippedWeapon.attributes ~= nil then
				local value = equippedWeapon.attributes.loadedAmmo
				if type(value) == "number" then
					loadedAmmo = value
				end
			end
			if loadedAmmo == nil and weaponConfig ~= nil
				and (equippedWeapon.attributes == nil or equippedWeapon.attributes.loadedAmmo == nil)
			then
				loadedAmmo = weaponConfig.magazineSize
			end
			if weaponConfig ~= nil then
				for _, instance in inventory.items do
					if instance.itemId == weaponConfig.ammoItemId and instance.quantity ~= nil then
						reserveAmmo += instance.quantity
					end
				end
			end
		end
	end
	local equippedWeaponDefinition = if equippedWeapon ~= nil then items[equippedWeapon.itemId] else nil
	local combatHudWeaponName = if equippedWeaponDefinition ~= nil then equippedWeaponDefinition.name else "SEM ARMA"
	local combatHudLoadedAmmo = if loadedAmmo ~= nil then tostring(loadedAmmo) else "--"
	local combatHudReserveAmmo = if weaponConfig ~= nil then tostring(reserveAmmo) else "--"
```

por:

```lua
	local combatHud = combatHudState.getEquippedWeaponStats(inventory)
```

- [ ] **Step 4: Trocar os usos no HUD**

Duas substituições no bloco `CombatStatus`:

```lua
					Text = combatHud.weaponName,
```

```lua
					Text = string.format("CARREGADA  %s    DISPONÍVEL  %s", combatHud.loadedAmmo, combatHud.reserveAmmo),
```

- [ ] **Step 5: Remover o require de `CombatConfig` do `App.luau`**

Depois das Tasks 1 e 3, o `App.luau` não usa mais `CombatConfig`. Remover a linha exata:

```lua
local CombatConfig = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatConfig)
```

- [ ] **Step 6: Verificar**

Repetir os três comandos do Step 5 da Task 1. Esperado: zero diagnósticos novos e nenhum aviso de variável não utilizada.

---

## Task 4: `theme.luau` + migração das cores do `App.luau`

**Files:**
- Create: `src/client/ui/theme.luau`
- Modify: `src/client/ui/App.luau` (require; substituição das cores)

**Interfaces:**
- Consumes: nada além de `Color3`
- Produces: `theme` (tabela de tokens) e `export type Theme = typeof(theme)`; nenhum outro módulo consome nesta fase

- [ ] **Step 1: Criar `src/client/ui/theme.luau`**

```lua
--!strict

local theme = {
	panel = Color3.fromRGB(20, 22, 30),
	text = Color3.fromRGB(241, 237, 255),
	textMuted = Color3.fromRGB(173, 179, 198),
	surface = Color3.fromRGB(39, 42, 56),
	surfaceHover = Color3.fromRGB(52, 55, 70),
	surfaceActive = Color3.fromRGB(78, 65, 111),
	stroke = Color3.fromRGB(78, 82, 105),
	accent = Color3.fromRGB(107, 92, 168),
	accentStrong = Color3.fromRGB(132, 104, 205),
	accentBright = Color3.fromRGB(175, 142, 255),
	success = Color3.fromRGB(191, 223, 161),
	successMuted = Color3.fromRGB(173, 196, 162),
	slotEmpty = Color3.fromRGB(31, 34, 45),
	slotHighlight = Color3.fromRGB(57, 52, 78),
	equipped = Color3.fromRGB(107, 78, 168),
	equippedHover = Color3.fromRGB(142, 103, 209),
	overlay = Color3.fromRGB(8, 9, 14),
	white = Color3.fromRGB(255, 255, 255),
	objectiveText = Color3.fromRGB(225, 222, 239),
}

export type Theme = typeof(theme)

return theme
```

Nota: tokens sem uso imediato (`stroke`, `surfaceHover`, `slotEmpty`, `slotHighlight`, `accentStrong`, `accentBright`, `equipped`, `equippedHover`, `overlay`, `white`) são intencionais e serão consumidos na varredura do P4; não removê-los.

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após os requires de UI existentes (por exemplo, após `local DocumentReaderOverlayComponent = require(...)`):

```lua
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

- [ ] **Step 3: Substituir todas as cores inline no `App.luau`**

Cada token tem valor único; a substituição é mecânica e sem ambiguidade:

| De | Para |
|----|------|
| `Color3.fromRGB(20, 22, 30)` | `theme.panel` |
| `Color3.fromRGB(241, 237, 255)` | `theme.text` |
| `Color3.fromRGB(173, 179, 198)` | `theme.textMuted` |
| `Color3.fromRGB(39, 42, 56)` | `theme.surface` |
| `Color3.fromRGB(78, 65, 111)` | `theme.surfaceActive` |
| `Color3.fromRGB(173, 196, 162)` | `theme.successMuted` |
| `Color3.fromRGB(225, 222, 239)` | `theme.objectiveText` |
| `Color3.fromRGB(191, 223, 161)` | `theme.success` |
| `Color3.fromRGB(107, 92, 168)` | `theme.accent` |

Não substituir `Color3.fromRGB(255, 255, 255)` nem `Color3.fromRGB(132, 104, 205)` em `App.luau`: essas não aparecem no arquivo.

- [ ] **Step 4: Verificar que não sobrou cor migrável**

```bash
rg -n "Color3.fromRGB" src/client/ui/App.luau
```

Esperado: nenhuma das nove cores da tabela do Step 3; apenas cores não mapeadas (se houver).

- [ ] **Step 5: Verificar build dos dois projetos**

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Esperado: os dois builds terminam sem erro.

---

## Verificação final do P0

- [ ] Rodar lint completo:

```bash
selene --config selene.roblox.toml src
```

- [ ] Rodar typecheck conforme o passo da Task 1 (sourcemap antes) e confirmar zero diagnósticos novos.
- [ ] Buildar os dois projetos (comando da Task 4, Step 5).
- [ ] Reportar o que foi verificado e qualquer desvio encontrado.

A verificação funcional/manual de regressões não é executada neste plano. Ela está descrita em `docs/manual-verification/2026-09-10-p0-ui-extraction.md` para execução por um agente no Roblox Studio.

## Fora de escopo (não fazer neste plano)

- Extrair qualquer componente React (`InventoryPanel`, `CombatStatus`, `ObjectivesPanel`, `DialogueOverlay`, `PickupToast`).
- Mover efeitos/hooks (`useInventoryHotkey`, `DocumentReaderHost`).
- Migrar `theme.luau` para os demais arquivos de `src/client/ui/` (fica para P4).
- Criar ou alterar specs TestEZ.
- Commits.
