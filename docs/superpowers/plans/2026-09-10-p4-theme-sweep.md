# P4: Varredura do Theme — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar todas as cores hardcoded restantes de `src/client/ui/` para os tokens de `theme.luau`, adicionando o token `black`, sem nenhuma mudança visual.

**Architecture:** Varredura mecânica por arquivo: adicionar `StarterPlayer` + require do `theme` onde faltar e substituir cada `Color3.fromRGB`/`Color3.new` pelo token de valor idêntico. Ao final, nenhum arquivo de `src/client/ui/` usa cor literal exceto o próprio `theme.luau`.

**Tech Stack:** Luau `--!strict`, React (jsdotlua/react 17.2.1), Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0.

## Global Constraints

- **Pré-requisito:** P0, P1, P2 e P3 concluídos.
- **Sem testes unitários** (instrução explícita do usuário). Nenhum spec TestEZ deve ser criado ou alterado.
- **Sem commits** (AGENTS.md). Nenhuma etapa de `git commit`.
- `src/client` exige módulos client-side por caminho absoluto: `local StarterPlayer = game:GetService("StarterPlayer")` + `StarterPlayer.StarterPlayerScripts.Client.<caminho>`.
- `--!strict`; proibido `--!nocheck` ou `any` para silenciar erros.
- **Paridade visual absoluta:** cada substituição troca um literal pelo token de valor RGB idêntico. Nenhum valor pode mudar.
- Não alterar propriedades, textos, hierarquia, tweens ou lógica; somente a origem da cor muda.
- Verificação por tarefa: `selene` + `rojo sourcemap` + `luau-lsp analyze`. Build, `rg` de conferência e Play manual no final.
- Após alterar scripts, parar e reiniciar a sessão Play do Studio antes de validar manualmente.

## Mapa de tokens

| RGB | Token |
|-----|-------|
| `20, 22, 30` | `theme.panel` |
| `241, 237, 255` | `theme.text` |
| `173, 179, 198` | `theme.textMuted` |
| `39, 42, 56` | `theme.surface` |
| `52, 55, 70` | `theme.surfaceHover` |
| `78, 65, 111` | `theme.surfaceActive` |
| `78, 82, 105` | `theme.stroke` |
| `107, 92, 168` | `theme.accent` |
| `132, 104, 205` | `theme.accentStrong` |
| `175, 142, 255` | `theme.accentBright` |
| `191, 223, 161` | `theme.success` |
| `31, 34, 45` | `theme.slotEmpty` |
| `57, 52, 78` | `theme.slotHighlight` |
| `107, 78, 168` | `theme.equipped` |
| `142, 103, 209` | `theme.equippedHover` |
| `8, 9, 14` | `theme.overlay` |
| `255, 255, 255` | `theme.white` |
| `0, 0, 0` (`Color3.new`) | `theme.black` (novo) |

---

## Estrutura de arquivos

| Ação | Arquivo | Cores restantes |
|------|---------|-----------------|
| Modificar | `src/client/ui/theme.luau` | adicionar `black` |
| Modificar | `src/client/ui/CinematicLetterbox.luau` | `black` (2) |
| Modificar | `src/client/ui/DocumentList.luau` | surface, text, textMuted |
| Modificar | `src/client/ui/ObjectiveNotification.luau` | panel, textMuted, white |
| Modificar | `src/client/ui/DropdownMenu.luau` | surfaceActive, surfaceHover, text, panel, accentStrong |
| Modificar | `src/client/ui/ConfirmationModal.luau` | white, overlay, panel, accentStrong, text, surfaceHover, stroke, equipped, equippedHover |
| Modificar | `src/client/ui/DocumentReaderOverlay.luau` | black, panel, success (4), text, textMuted |
| Modificar | `src/client/ui/InventorySlot.luau` | text, equipped, white (2), slotHighlight (2), surface, accentBright, accent, slotEmpty (2), stroke (2) |

---

## Task 1: Token `black` + `CinematicLetterbox`

**Files:**
- Modify: `src/client/ui/theme.luau`
- Modify: `src/client/ui/CinematicLetterbox.luau`

**Interfaces:**
- Produces: `theme.black = Color3.new(0, 0, 0)`

- [ ] **Step 1: Adicionar `black` ao `theme.luau`**

Após a linha `overlay = Color3.fromRGB(8, 9, 14),`, adicionar:

```lua
	black = Color3.new(0, 0, 0),
```

- [ ] **Step 2: Adicionar `StarterPlayer` e o require do theme em `CinematicLetterbox.luau`**

Substituir:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
```

por:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

- [ ] **Step 3: Substituir as cores**

Substituir **todas** as ocorrências de `Color3.new(0, 0, 0)` em `CinematicLetterbox.luau` por `theme.black` (são 2: `TopBar` e `BottomBar`).

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

Esperado: zero diagnósticos novos. Conferir com `rg -n "Color3" src/client/ui/CinematicLetterbox.luau` que não sobrou cor literal.

---

## Task 2: `DocumentList`, `ObjectiveNotification` e `DropdownMenu`

**Files:**
- Modify: `src/client/ui/DocumentList.luau`
- Modify: `src/client/ui/ObjectiveNotification.luau`
- Modify: `src/client/ui/DropdownMenu.luau`

**Interfaces:**
- Consumes: `theme` (`surface`, `text`, `textMuted`, `panel`, `white`, `surfaceActive`, `surfaceHover`, `accentStrong`)

- [ ] **Step 1: `DocumentList.luau` — adicionar o require do theme**

Após `local React = require(ReplicatedStorage.Packages.React)`, adicionar:

```lua
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

(`StarterPlayer` já está declarado no arquivo.)

- [ ] **Step 2: `DocumentList.luau` — substituir as cores**

| De | Para |
|----|------|
| `Color3.fromRGB(39, 42, 56)` | `theme.surface` |
| `Color3.fromRGB(241, 237, 255)` | `theme.text` |
| `Color3.fromRGB(173, 179, 198)` | `theme.textMuted` |

- [ ] **Step 3: `ObjectiveNotification.luau` — adicionar o require do theme**

Após `local React = require(ReplicatedStorage.Packages.React)`, adicionar:

```lua
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

(`StarterPlayer` já está declarado no arquivo.)

- [ ] **Step 4: `ObjectiveNotification.luau` — substituir as cores**

| De | Para |
|----|------|
| `Color3.fromRGB(20, 22, 30)` | `theme.panel` |
| `Color3.fromRGB(173, 179, 198)` | `theme.textMuted` |
| `Color3.fromRGB(255, 255, 255)` | `theme.white` |

- [ ] **Step 5: `DropdownMenu.luau` — adicionar `StarterPlayer` e o require do theme**

Substituir:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
```

por:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

- [ ] **Step 6: `DropdownMenu.luau` — substituir as cores**

| De | Para |
|----|------|
| `Color3.fromRGB(78, 65, 111)` | `theme.surfaceActive` |
| `Color3.fromRGB(52, 55, 70)` | `theme.surfaceHover` |
| `Color3.fromRGB(241, 237, 255)` | `theme.text` |
| `Color3.fromRGB(20, 22, 30)` | `theme.panel` |
| `Color3.fromRGB(132, 104, 205)` | `theme.accentStrong` |

- [ ] **Step 7: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos. Conferir com `rg -n "Color3" src/client/ui/DocumentList.luau src/client/ui/ObjectiveNotification.luau src/client/ui/DropdownMenu.luau` que não sobrou cor literal.

---

## Task 3: `ConfirmationModal`, `DocumentReaderOverlay` e `InventorySlot`

**Files:**
- Modify: `src/client/ui/ConfirmationModal.luau`
- Modify: `src/client/ui/DocumentReaderOverlay.luau`
- Modify: `src/client/ui/InventorySlot.luau`

**Interfaces:**
- Consumes: `theme` (`white`, `overlay`, `panel`, `accentStrong`, `text`, `surfaceHover`, `stroke`, `equipped`, `equippedHover`, `black`, `success`, `textMuted`, `slotHighlight`, `surface`, `accentBright`, `accent`, `slotEmpty`)

- [ ] **Step 1: `ConfirmationModal.luau` — adicionar `StarterPlayer` e o require do theme**

Substituir:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
```

por:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

- [ ] **Step 2: `ConfirmationModal.luau` — substituir as cores**

| De | Para |
|----|------|
| `Color3.fromRGB(255, 255, 255)` | `theme.white` |
| `Color3.fromRGB(8, 9, 14)` | `theme.overlay` |
| `Color3.fromRGB(20, 22, 30)` | `theme.panel` |
| `Color3.fromRGB(132, 104, 205)` | `theme.accentStrong` |
| `Color3.fromRGB(241, 237, 255)` | `theme.text` |
| `Color3.fromRGB(52, 55, 70)` | `theme.surfaceHover` |
| `Color3.fromRGB(78, 82, 105)` | `theme.stroke` |
| `Color3.fromRGB(107, 78, 168)` | `theme.equipped` |
| `Color3.fromRGB(142, 103, 209)` | `theme.equippedHover` |

- [ ] **Step 3: `DocumentReaderOverlay.luau` — adicionar o require do theme**

Após `local React = require(ReplicatedStorage.Packages.React)`, adicionar:

```lua
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

(`StarterPlayer` já está declarado no arquivo.)

- [ ] **Step 4: `DocumentReaderOverlay.luau` — substituir as cores**

| De | Para |
|----|------|
| `Color3.new(0, 0, 0)` | `theme.black` |
| `Color3.fromRGB(20, 22, 30)` | `theme.panel` |
| `Color3.fromRGB(191, 223, 161)` | `theme.success` (4 ocorrências: Stroke, Title, PreviousPage, NextPage) |
| `Color3.fromRGB(241, 237, 255)` | `theme.text` |
| `Color3.fromRGB(173, 179, 198)` | `theme.textMuted` |

- [ ] **Step 5: `InventorySlot.luau` — adicionar `StarterPlayer` e o require do theme**

Substituir:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
```

por:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
```

- [ ] **Step 6: `InventorySlot.luau` — substituir as cores**

Substituir todas as ocorrências, por valor:

| De | Para |
|----|------|
| `Color3.fromRGB(241, 237, 255)` | `theme.text` |
| `Color3.fromRGB(107, 78, 168)` | `theme.equipped` |
| `Color3.fromRGB(255, 255, 255)` | `theme.white` (2) |
| `Color3.fromRGB(57, 52, 78)` | `theme.slotHighlight` (2) |
| `Color3.fromRGB(39, 42, 56)` | `theme.surface` |
| `Color3.fromRGB(175, 142, 255)` | `theme.accentBright` |
| `Color3.fromRGB(107, 92, 168)` | `theme.accent` |
| `Color3.fromRGB(31, 34, 45)` | `theme.slotEmpty` (2) |
| `Color3.fromRGB(78, 82, 105)` | `theme.stroke` (2, incluindo o argumento de `createOccupiedChildren`) |

Atenção no Step 6: o parâmetro `strokeColor` de `createOccupiedChildren` continua existindo; apenas o valor passado na chamada (linha `createOccupiedChildren(itemText, props.equipped, item.quantity, Color3.fromRGB(78, 82, 105))`) vira `theme.stroke`.

- [ ] **Step 7: Verificar**

Repetir os três comandos do Step 4 da Task 1. Esperado: zero diagnósticos novos e nenhum aviso de variável não utilizada em `DropdownMenu.luau`, `ConfirmationModal.luau` e `InventorySlot.luau` (o require do theme precisa estar em uso).

---

## Verificação final do P4

- [ ] Confirmar que só o `theme.luau` contém cores literais:

```bash
rg -n "Color3\.(fromRGB|new)" src/client/ui
```

Esperado: ocorrências apenas em `src/client/ui/theme.luau` (os 20 tokens).

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
  - barras pretas da cinematic (`CinematicLetterbox`) inalteradas;
  - inventário: slots vazios/ocupados, badge `equipado`, quantidade, hover do slot e do dropdown idênticos;
  - `ConfirmationModal` com fundo escuro, borda roxa e botões com os mesmos tons;
  - dropdown do inventário com fundo, borda e hover idênticos;
  - leitor de documentos: fundo preto do shade, painel, título/botões verdes e página branca idênticos;
  - toast de objetivo (`ObjectiveNotification`) com fundo e textos idênticos;
  - toast de pickup e HUD de combate inalterados.
- [ ] Reportar o que foi verificado e qualquer desvio encontrado.

## Fora de escopo (não fazer neste plano)

- Renomear tokens, consolidar valores parecidos ou criar variações de tema (claro/escuro).
- Migrar cores fora de `src/client/ui/`.
- Criar ou alterar specs TestEZ.
- Commits.
