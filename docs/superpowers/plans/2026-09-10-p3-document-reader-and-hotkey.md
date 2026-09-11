# P3: Document Reader e Hotkey — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remover do `App.luau` o efeito de blur, o binding de atalho (ContextActionService/CoreGui) e a máquina de estado de apresentação do leitor de documentos, extraindo-os para `DocumentReaderOverlay`, `useInventoryHotkey` e `useDocumentReaderHost`.

**Architecture:** O blur passa a viver no ciclo de vida de `DocumentReaderOverlay` (que já desmonta quando a apresentação termina). O atalho do inventário vira `useInventoryHotkey(blocked, onToggle)`, mantendo o callback num `useRef` para não rebindar a cada render. A máquina `documentReader`/`presentation`/`visible` vira `useDocumentReaderHost()`, que expõe `active`, `presentation`, `visible` e as callbacks de página; o `App` só compõe o overlay.

**Tech Stack:** Luau `--!strict`, React (jsdotlua/react 17.2.1), Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0.

## Global Constraints

- **Pré-requisito:** P0, P1 e P2 concluídos.
- **Sem testes unitários** (instrução explícita do usuário). Nenhum spec TestEZ deve ser criado ou alterado.
- **Sem commits** (AGENTS.md). Nenhuma etapa de `git commit`.
- `src/client` exige módulos client-side por caminho absoluto: `local StarterPlayer = game:GetService("StarterPlayer")` + `StarterPlayer.StarterPlayerScripts.Client.<caminho>`.
- `--!strict` em todos os módulos novos; proibido `--!nocheck` ou `any` para silenciar erros.
- Comportamento idêntico: mesmos binds, prioridade do atalho, bloqueio com `GetFocusedTextBox`, estado do `CoreGui.PlayerList` restaurado no cleanup, blur com `Name = "DocumentReaderBlur"` e `Size = 18`, overlay com os mesmos props.
- Ordem de execução das tasks: Task 1 (blur) → Task 2 (hotkey) → Task 3 (host). Cada task compila e roda sozinha; a Task 3 é a única que remove as variáveis do leitor.
- Verificação por tarefa: `selene` + `rojo sourcemap` + `luau-lsp analyze`. Build e Play manual no final.
- Após alterar scripts, parar e reiniciar a sessão Play do Studio antes de validar manualmente.

---

## Estrutura de arquivos

| Ação | Arquivo | Responsabilidade |
|------|---------|------------------|
| Modificar | `src/client/ui/DocumentReaderOverlay.luau` | Criar/destruir o `BlurEffect` no próprio ciclo de vida |
| Criar | `src/client/ui/useInventoryHotkey.luau` | Bind do `Tab`, bloqueio e `CoreGui.PlayerList` |
| Criar | `src/client/ui/useDocumentReaderHost.luau` | Máquina `presentation`/`visible`/`active` do leitor |
| Modificar | `src/client/ui/App.luau` | Consumir o hook de hotkey e o host; remover efeitos, estado e requires |

---

## Task 1: Mover o blur para `DocumentReaderOverlay`

**Files:**
- Modify: `src/client/ui/DocumentReaderOverlay.luau`
- Modify: `src/client/ui/App.luau` (remover efeito de blur e require de `Lighting`)

**Interfaces:**
- Consumes: `Lighting` (`BlurEffect`)
- Produces: nenhum contrato novo; o overlay cria o blur ao montar e o destrói ao desmontar

- [ ] **Step 1: Adicionar `Lighting` e o efeito ao `DocumentReaderOverlay.luau`**

Após `local TweenService = game:GetService("TweenService")`, adicionar:

```lua
local Lighting = game:GetService("Lighting")
```

Dentro de `DocumentReaderOverlay`, logo antes do efeito de transição existente (`React.useEffect(function() transitionIdRef.current += 1 ...`), adicionar:

```lua
	React.useEffect(function()
		local blur = Instance.new("BlurEffect")
		blur.Name = "DocumentReaderBlur"
		blur.Size = 18
		blur.Parent = Lighting

		return function()
			blur:Destroy()
		end
	end, {})
```

- [ ] **Step 2: Remover o efeito de blur do `App.luau`**

Remover o bloco exato:

```lua
	React.useEffect(function()
		if not documentReaderMounted then
			return
		end

		local blur = Instance.new("BlurEffect")
		blur.Name = "DocumentReaderBlur"
		blur.Size = 18
		blur.Parent = Lighting

		return function()
			blur:Destroy()
		end
	end, { documentReaderMounted })
```

- [ ] **Step 3: Remover o require de `Lighting` do `App.luau`**

Remover:

```lua
local Lighting = game:GetService("Lighting")
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

Esperado: zero diagnósticos novos. O overlay agora monta exatamente quando `documentReaderPresentation ~= nil`, mesmo ciclo do antigo `documentReaderMounted`.

---

## Task 2: `useInventoryHotkey.luau`

**Files:**
- Create: `src/client/ui/useInventoryHotkey.luau`
- Modify: `src/client/ui/App.luau` (require; substituir o efeito inline; remover constantes e requires)

**Interfaces:**
- Consumes: `ContextActionService`, `StarterGui`, `UserInputService`, `ReplicatedStorage.Packages.React`
- Produces: `useInventoryHotkey(blocked: boolean, onToggle: () -> ())`; o callback é guardado em `useRef` e o efeito depende apenas de `blocked`

- [ ] **Step 1: Criar `src/client/ui/useInventoryHotkey.luau`**

```lua
--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)

local INVENTORY_TOGGLE_ACTION = "DungeonInventoryToggle"
local INVENTORY_TOGGLE_PRIORITY = Enum.ContextActionPriority.High.Value + 3

local function useInventoryHotkey(blocked: boolean, onToggle: () -> ())
	local onToggleRef = React.useRef(onToggle)
	onToggleRef.current = onToggle

	React.useEffect(function()
		local playerListWasEnabled = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		ContextActionService:BindActionAtPriority(
			INVENTORY_TOGGLE_ACTION,
			function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
					return Enum.ContextActionResult.Sink
				end
				if blocked then
					return Enum.ContextActionResult.Sink
				end
				onToggleRef.current()
				return Enum.ContextActionResult.Sink
			end,
			false,
			INVENTORY_TOGGLE_PRIORITY,
			Enum.KeyCode.Tab
		)

		return function()
			ContextActionService:UnbindAction(INVENTORY_TOGGLE_ACTION)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, playerListWasEnabled)
		end
	end, { blocked })
end

return useInventoryHotkey
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após `local InventoryPanel = require(...)`:

```lua
local useInventoryHotkey = require(StarterPlayer.StarterPlayerScripts.Client.ui.useInventoryHotkey)
```

- [ ] **Step 3: Substituir o efeito inline do atalho**

Substituir o bloco exato de `App.luau`:

```lua
	React.useEffect(function()
		local playerListWasEnabled = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		ContextActionService:BindActionAtPriority(
			INVENTORY_TOGGLE_ACTION,
			function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
					return Enum.ContextActionResult.Sink
				end
				if documentReaderActive or documentReaderMounted then
					return Enum.ContextActionResult.Sink
				end
				setInventoryVisible(function(previousVisible: boolean): boolean
					return not previousVisible
				end)
				return Enum.ContextActionResult.Sink
			end,
			false,
			INVENTORY_TOGGLE_PRIORITY,
			Enum.KeyCode.Tab
		)

		return function()
			ContextActionService:UnbindAction(INVENTORY_TOGGLE_ACTION)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, playerListWasEnabled)
		end
	end, { documentReaderActive, documentReaderMounted })
```

por:

```lua
	useInventoryHotkey(documentReaderActive or documentReaderMounted, function()
		setInventoryVisible(function(previousVisible: boolean): boolean
			return not previousVisible
		end)
	end)
```

- [ ] **Step 4: Remover as constantes do atalho do `App.luau`**

Remover:

```lua
local INVENTORY_TOGGLE_ACTION = "DungeonInventoryToggle"
local INVENTORY_TOGGLE_PRIORITY = Enum.ContextActionPriority.High.Value + 3
```

- [ ] **Step 5: Remover os requires que ficaram sem uso**

Remover de `App.luau`:

```lua
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
```

- [ ] **Step 6: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos e nenhum aviso de variável não utilizada. O `App` ainda mantém `documentReaderActive`/`documentReaderMounted` nesta task; eles serão removidos na Task 3.

---

## Task 3: `useDocumentReaderHost.luau`

**Files:**
- Create: `src/client/ui/useDocumentReaderHost.luau`
- Modify: `src/client/ui/App.luau` (require; remover estado/efeito do leitor; compor overlay; ajustar hotkey e painel)

**Interfaces:**
- Consumes: `StarterPlayerScripts.Client.documents.useDocumentReader`; `StarterPlayerScripts.Client.documents.DocumentReaderController` (`DocumentReaderState`, `DocumentReaderController`); `ReplicatedStorage.Shared.locator.locator`
- Produces: `export type DocumentReaderHost = { active: boolean, presentation: DocumentReaderState?, visible: boolean, nextPage: () -> (), previousPage: () -> (), onExitComplete: () -> () }`; hook `useDocumentReaderHost(): DocumentReaderHost`

- [ ] **Step 1: Criar `src/client/ui/useDocumentReaderHost.luau`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local Locator = require(ReplicatedStorage.Shared.locator.locator)
local useDocumentReader = require(StarterPlayer.StarterPlayerScripts.Client.documents.useDocumentReader)
local DocumentReaderControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)

local controller: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")

export type DocumentReaderHost = {
	active: boolean,
	presentation: DocumentReaderControllerModule.DocumentReaderState?,
	visible: boolean,
	nextPage: () -> (),
	previousPage: () -> (),
	onExitComplete: () -> (),
}

local function useDocumentReaderHost(): DocumentReaderHost
	local documentReader = useDocumentReader()
	local documentReaderActive = documentReader ~= nil
	local presentation, setPresentation = React.useState(documentReader)
	local visible, setVisible = React.useState(documentReader ~= nil)

	React.useEffect(function()
		if documentReader ~= nil then
			setPresentation(documentReader)
			setVisible(true)
		elseif presentation ~= nil then
			setVisible(false)
		end
	end, { documentReader })

	return {
		active = documentReaderActive or presentation ~= nil,
		presentation = presentation,
		visible = visible,
		nextPage = function()
			controller.nextPage()
		end,
		previousPage = function()
			controller.previousPage()
		end,
		onExitComplete = function()
			setPresentation(nil)
		end,
	}
end

return useDocumentReaderHost
```

- [ ] **Step 2: Adicionar o require em `src/client/ui/App.luau`**

Após o require de `useInventoryHotkey`:

```lua
local useDocumentReaderHost = require(StarterPlayer.StarterPlayerScripts.Client.ui.useDocumentReaderHost)
```

- [ ] **Step 3: Trocar o estado do leitor pelo host**

Substituir o bloco exato:

```lua
	local documentReader = useDocumentReader()
	local documentReaderActive = documentReader ~= nil
	local documentReaderPresentation, setDocumentReaderPresentation = React.useState(documentReader)
	local documentReaderVisible, setDocumentReaderVisible = React.useState(documentReader ~= nil)
	local documentReaderMounted = documentReaderPresentation ~= nil
```

por:

```lua
	local documentReaderHost = useDocumentReaderHost()
```

- [ ] **Step 4: Remover o efeito de sincronização da apresentação**

Remover:

```lua
	React.useEffect(function()
		if documentReader ~= nil then
			setDocumentReaderPresentation(documentReader)
			setDocumentReaderVisible(true)
		elseif documentReaderPresentation ~= nil then
			setDocumentReaderVisible(false)
		end
	end, { documentReader })
```

- [ ] **Step 5: Atualizar a call do hotkey**

Substituir:

```lua
	useInventoryHotkey(documentReaderActive or documentReaderMounted, function()
```

por:

```lua
	useInventoryHotkey(documentReaderHost.active, function()
```

- [ ] **Step 6: Atualizar o efeito que fecha o inventário**

Substituir:

```lua
	React.useEffect(function()
		if documentReaderActive or documentReaderMounted then
			setInventoryVisible(false)
		end
	end, { documentReaderActive, documentReaderMounted })
```

por:

```lua
	React.useEffect(function()
		if documentReaderHost.active then
			setInventoryVisible(false)
		end
	end, { documentReaderHost.active })
```

- [ ] **Step 7: Atualizar a visibilidade do `InventoryPanel`**

Substituir:

```lua
				visible = inventoryVisible and not documentReaderActive and not documentReaderMounted,
```

por:

```lua
				visible = inventoryVisible and not documentReaderHost.active,
```

- [ ] **Step 8: Reconstruir o overlay a partir do host**

Substituir o bloco exato:

```lua
	local documentReaderOverlay = if documentReaderPresentation ~= nil
		then React.createElement(DocumentReaderOverlayComponent, {
			enabled = not dungeonGuiHidden,
			onNextPage = function()
				documentReaderController.nextPage()
			end,
			onExitComplete = function()
				setDocumentReaderPresentation(nil)
			end,
			onPreviousPage = function()
				documentReaderController.previousPage()
			end,
			state = documentReaderPresentation,
			visible = documentReaderVisible,
		})
		else nil
```

por:

```lua
	local documentReaderState = documentReaderHost.presentation
	local documentReaderOverlay = if documentReaderState ~= nil
		then React.createElement(DocumentReaderOverlayComponent, {
			enabled = not dungeonGuiHidden,
			onNextPage = documentReaderHost.nextPage,
			onExitComplete = documentReaderHost.onExitComplete,
			onPreviousPage = documentReaderHost.previousPage,
			state = documentReaderState,
			visible = documentReaderHost.visible,
		})
		else nil
```

- [ ] **Step 9: Remover requires e locals que ficaram sem uso**

Remover de `App.luau`:

```lua
local Locator = require(ReplicatedStorage.Shared.locator.locator)
local useDocumentReader = require(StarterPlayer.StarterPlayerScripts.Client.documents.useDocumentReader)
local DocumentReaderControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)
local documentReaderController: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")
```

- [ ] **Step 10: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos e nenhum aviso de variável não utilizada. Conferir que `dungeonGuiHidden`, `cinematicPlaying`, `ConfirmationModal` e o efeito de blur (agora no overlay) não mudaram.

---

## Verificação final do P3

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
  - abrir um documento: blur aparece, overlay faz fade-in, páginas navegam com `<`/`>`;
  - fechar o documento: overlay faz fade-out e o blur some ao final da animação;
  - com o leitor aberto (ou fechando), o `Tab` não alterna o inventário;
  - abrir um documento com o inventário aberto fecha o inventário; fechar o leitor não reabre;
  - abrir uma cinematic com o leitor aberto desabilita o overlay (`enabled`) enquanto `dungeonGuiHidden` for verdadeiro;
  - coleta de item, diálogo e HUD de combate continuam funcionando.

## Fora de escopo (não fazer neste plano)

- Migrar `theme` para os arquivos que ainda não foram tocados (P4).
- Mover a composição do overlay para dentro do host (o `App` continua criando o elemento do `DocumentReaderOverlay`).
- Criar ou alterar specs TestEZ.
- Commits.
