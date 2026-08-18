# Sistema de Dialogo com Datilografia Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar uma API client-side `show`/`ask` que exibe texto com datilografia, permite perguntas com opcoes e integra a visualizacao ao `App` React existente.

**Architecture:** Um `DialogueController` imperativo sera o dono do estado, do timer de datilografia, dos callbacks e dos bindings de input. Um hook `useDialogue` fara a ponte para o React, enquanto `App.luau` continuara sendo o unico dono da arvore visual. Sequencias nao terao um formato proprio: serao compostas chamando `show` ou `ask` dentro dos callbacks.

**Tech Stack:** Luau `--!strict`, Roblox `ContextActionService`, `Signal`, React, ReactRoblox, Rojo e TestEZ executado em Roblox Studio.

## Global Constraints

- O sistema e exclusivamente client-side; nao adicionar RemoteEvent nem mudanca server-side.
- A API publica tera somente `show` e `ask`; sequencias serao compostas por callbacks.
- Uma nova chamada valida substitui o dialogo ativo; o callback anterior recebe `nil, "replaced"`.
- `F` revela o texto durante a datilografia e fecha/confirma no proximo `F`.
- `Up`/`W` selecionam a opcao anterior; `Down`/`S` selecionam a proxima; `Esc` cancela.
- A velocidade inicial e uma constante do modulo de `0.04` segundos por caractere, sem override por chamada.
- Opcoes usam `{ id: string, text: string }`; IDs vazios ou duplicados invalidam a chamada.
- Enquanto houver dialogo, `F`, `Esc`, setas e `W/S` devem ser consumidos pelo `ContextActionService`.
- O layout e texto simples, centralizado horizontalmente na parte inferior, sem altura maxima, crescendo para cima.
- Specs de UI React permanecem fora do escopo; a renderizacao sera verificada manualmente no Studio.
- Todos os modulos e specs novos permanecem `--!strict`; nao usar `--!nocheck` nem ignorar diagnosticos.
- Nao editar `Packages/` ou `DevPackages/`; sao links/diretorios gerados pelo Wally.
- O projeto de testes deve mapear somente o subdiretorio client necessario e continuar sem iniciar `init.client.luau`.
- O typecheck usa a plataforma Roblox, o sourcemap de `test.project.json` e as definicoes versionadas do repositorio.
- Cada commit deve incluir somente os arquivos da tarefa; preservar `docs/inventory-architecture.md`, que ja estava nao rastreado.

---

## File Map

| Arquivo | Responsabilidade |
|---|---|
| `src/client/dialogue/DialogueController.luau` | API, estado, datilografia, input, callbacks, substituicao e lifecycle |
| `src/client/dialogue/useDialogue.luau` | Assinatura React do estado do controlador |
| `src/client/init.client.luau` | Inicializacao do controlador client-side |
| `src/client/ui/App.luau` | Renderizacao do texto e das opcoes no `ScreenGui` existente |
| `test.project.json` | Mapeamento do diretorio de producao `dialogue` para o projeto TestEZ |
| `tests/client/dialogue/DialogueController.spec.luau` | Testes do contrato e lifecycle sem testar arvore React |
| `README.md` | Inclusao do novo diretorio no comando de typecheck documentado |

## Task 1: Add Test Mapping And Failing Controller Contract

**Files:**
- Create: `src/client/dialogue/DialogueController.luau` (stub de contrato)
- Create: `tests/client/dialogue/DialogueController.spec.luau`
- Modify: `test.project.json:48-67`

**Interfaces:**
- Consumes: `Players.LocalPlayer.PlayerScripts.Client.dialogue.DialogueController`, que ainda nao existira no inicio desta tarefa.
- Produces: contrato testado para `start`, `stop`, `getState`, `show`, `ask` e `changed`; nomes de actions que a implementacao devera bindar.

- [ ] **Step 1: Add the client dialogue mapping to the test project**

Adicionar a pasta de producao ao mesmo nivel dos subdiretorios client existentes,
sem mapear `src/client/init.client.luau`:

```json
"dialogue": {
  "$path": "src/client/dialogue"
},
```

O trecho final de `StarterPlayer.StarterPlayerScripts.Client` devera conter
`camera`, `dialogue`, `inventory`, `pickups`, `player` e `ui`.

Criar tambem o arquivo de stub para que o caminho mapeado exista durante o
primeiro build, sem antecipar nenhuma parte da implementacao:

```lua
--!strict

error("DialogueController contract is not implemented", 2)
```

- [ ] **Step 2: Write the failing controller spec**

Criar um spec TestEZ estrito com fixtures de conexoes isoladas. Use quatro
actions nomeadas para permitir testar o callback sem fabricar `InputObject`:

```lua
--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DialogueController = require(client.dialogue.DialogueController)

local CONFIRM_ACTION = "DungeonDialogueConfirm"
local CANCEL_ACTION = "DungeonDialogueCancel"
local PREVIOUS_ACTION = "DungeonDialoguePrevious"
local NEXT_ACTION = "DungeonDialogueNext"

type SignalConnection = {
    Disconnect: (self: SignalConnection) -> (),
}

local function press(actionName: string): ()
    local actions = ContextActionService:GetAllBoundActionInfo() :: any
    local actionInfo = actions[actionName]
    expect(actionInfo).to.be.ok()
    local callback = actionInfo["function"] :: any
    callback(actionName, Enum.UserInputState.Begin, nil)
end

return function()
    describe("DialogueController", function()
        local signalConnections: { SignalConnection } = {}

        beforeEach(function()
            signalConnections = {}
            DialogueController.start()
        end)

        afterEach(function()
            DialogueController.stop()
            for _, connection in signalConnections do
                connection:Disconnect()
            end
            signalConnections = {}
        end)

        it("publishes a typing message and completes on the second confirm", function()
            local receivedValue: string? = "sentinel"
            local receivedReason: string? = nil
            local latestState: any = nil
            local connection = DialogueController.changed:Connect(function(state: any)
                latestState = state
            end) :: SignalConnection
            table.insert(signalConnections, connection)

            DialogueController.show("Porta trancada", function(value: nil, reason: string)
                receivedValue = value
                receivedReason = reason
            end)

            expect(latestState.kind).to.equal("message")
            expect(latestState.visibleText).to.equal("")
            expect(latestState.isTyping).to.equal(true)

            press(CONFIRM_ACTION)
            expect(latestState.visibleText).to.equal("Porta trancada")
            expect(latestState.isTyping).to.equal(false)

            press(CONFIRM_ACTION)
            expect(latestState).to.equal(nil)
            expect(receivedValue).to.equal(nil)
            expect(receivedReason).to.equal("completed")
        end)

        it("navigates and confirms question options", function()
            local selectedId: string? = nil
            local reason: string? = nil
            DialogueController.ask("Usar Spade Key?", {
                { id = "yes", text = "Sim" },
                { id = "no", text = "Nao" },
                { id = "later", text = "Depois" },
            }, function(optionId: string?, callbackReason: string)
                selectedId = optionId
                reason = callbackReason
            end)

            press(CONFIRM_ACTION)
            press(NEXT_ACTION)
            press(NEXT_ACTION)
            press(NEXT_ACTION)

            local state = DialogueController.getState()
            expect(state).to.be.ok()
            expect(state.selectedIndex).to.equal(3)

            press(PREVIOUS_ACTION)
            expect(DialogueController.getState().selectedIndex).to.equal(2)
            press(CONFIRM_ACTION)

            expect(selectedId).to.equal("no")
            expect(reason).to.equal("completed")
            expect(DialogueController.getState()).to.equal(nil)
        end)

        it("cancels a question with Escape", function()
            local selectedId: string? = "sentinel"
            local reason: string? = nil
            DialogueController.ask("Cancelar?", {
                { id = "yes", text = "Sim" },
            }, function(optionId: string?, callbackReason: string)
                selectedId = optionId
                reason = callbackReason
            end)

            press(CANCEL_ACTION)

            expect(selectedId).to.equal(nil)
            expect(reason).to.equal("cancelled")
            expect(DialogueController.getState()).to.equal(nil)
        end)

        it("replaces the active dialog and notifies the old callback", function()
            local oldReason: string? = nil
            DialogueController.show("Mensagem antiga", function(_: nil, reason: string)
                oldReason = reason
            end)

            DialogueController.show("Mensagem nova")

            expect(oldReason).to.equal("replaced")
            expect(DialogueController.getState().text).to.equal("Mensagem nova")
        end)

        it("keeps the active dialog when a new input is invalid", function()
            DialogueController.show("Mensagem valida")

            local ok = pcall(function()
                DialogueController.ask("Pergunta invalida", {
                    { id = "same", text = "Uma" },
                    { id = "same", text = "Duas" },
                }, function() end)
            end)

            expect(ok).to.equal(false)
            expect(DialogueController.getState().text).to.equal("Mensagem valida")
        end)

        it("binds input above the tank priority and unbinds on stop", function()
            DialogueController.show("Bloquear movimento")
            DialogueController.start()

            local actions = ContextActionService:GetAllBoundActionInfo() :: any
            local expectedActions = {
                [CONFIRM_ACTION] = Enum.KeyCode.F,
                [CANCEL_ACTION] = Enum.KeyCode.Escape,
                [PREVIOUS_ACTION] = Enum.KeyCode.Up,
                [NEXT_ACTION] = Enum.KeyCode.Down,
            }

            for actionName, keyCode in expectedActions do
                local actionInfo = actions[actionName]
                expect(actionInfo).to.be.ok()
                expect(actionInfo.priorityLevel).to.equal(Enum.ContextActionPriority.High.Value + 1)
                expect(table.find(actionInfo.inputTypes, keyCode)).to.be.ok()
            end

            DialogueController.stop()
            actions = ContextActionService:GetAllBoundActionInfo() :: any
            expect(actions[CONFIRM_ACTION]).to.equal(nil)
            expect(actions[CANCEL_ACTION]).to.equal(nil)
            expect(actions[PREVIOUS_ACTION]).to.equal(nil)
            expect(actions[NEXT_ACTION]).to.equal(nil)
        end)
    end)
end
```

Os nomes e callbacks do spec sao o contrato que a implementacao devera manter.
Se o ambiente TestEZ nao expuser `actionInfo["function"]` como chamavel, manter
os mesmos asserts de binding e mover os asserts de transicao para a verificacao
manual via MCP; nao adicionar metodos publicos de teste ao controlador.

- [ ] **Step 3: Run the project mapping check**

Run: `rojo build -o /tmp/dungeon-game-canve-test-dialogue-contract.rbxlx test.project.json`

Expected: o build deve concluir, pois o mapeamento do novo diretorio e valido e
o stub fornece o primeiro ModuleScript do diretorio.

- [ ] **Step 4: Run the failing client suite in Studio**

Iniciar Play limpo no place de testes e executar no DataModel `Client`:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Expected: falha de carregamento com `DialogueController contract is not
implemented`. Esse resultado confirma que o spec esta apontando para o modulo
real do DataModel, nao para uma dependencia virtual.

- [ ] **Step 5: Commit the test contract**

```bash
git add test.project.json tests/client/dialogue/DialogueController.spec.luau
git commit -m "test: define dialogue controller contract"
```

## Task 2: Implement The Dialogue Controller

**Files:**
- Modify: `src/client/dialogue/DialogueController.luau` (substituir o stub)
- Test: `tests/client/dialogue/DialogueController.spec.luau`

**Interfaces:**
- Consumes: `ReplicatedStorage.Packages.Signal` e os actions descritos na Task 1.
- Produces: `start`, `stop`, `getState`, `show`, `ask` e `changed` para o hook e sistemas client-side.

- [ ] **Step 1: Define strict public and internal types**

Comecar o modulo com `--!strict` e declarar estes tipos:

```lua
export type DialogReason = "completed" | "cancelled" | "replaced"

export type DialogOption = {
    id: string,
    text: string,
}

export type DialogState = {
    kind: "message" | "question",
    text: string,
    visibleText: string,
    isTyping: boolean,
    options: { DialogOption },
    selectedIndex: number?,
}

export type ShowCallback = (value: nil, reason: DialogReason) -> ()
export type AskCallback = (optionId: string?, reason: DialogReason) -> ()
```

O estado de mensagem usara `options = {}` e `selectedIndex = nil`; o estado de
pergunta usara uma copia validada das opcoes e `selectedIndex = 1`.

- [ ] **Step 2: Add signal, state and lifecycle storage**

Criar `changed` com o mesmo casting tipado usado em `PickupNotificationController`
e armazenar:

```lua
local changed = (Signal.new() :: any) :: ChangedSignal
local state: DialogState? = nil
local activeCallback: ((string?, DialogReason) -> ())? = nil
local started = false
local generation = 0
```

`getState()` deve retornar o estado atual. `publish(nextState)` deve atribuir
`state` e chamar `changed:Fire(nextState)`. Quando o dialogo fechar, publicar
`nil` para que o hook remova a UI.

- [ ] **Step 3: Implement validation before replacement**

Validar toda a entrada antes de tocar no estado atual:

```lua
local function validateText(value: any, label: string): string
    if type(value) ~= "string" or value == "" then
        error(label .. " must be a non-empty string", 3)
    end
    return value
end

local function validateOptions(value: any): { DialogOption }
    if type(value) ~= "table" or #value == 0 then
        error("options must contain at least one option", 3)
    end

    local ids: { [string]: boolean } = {}
    local copy = {}
    for index, option in value do
        if type(option) ~= "table" then
            error(string.format("options[%d] must be a table", index), 3)
        end
        local id = validateText(option.id, string.format("options[%d].id", index))
        local text = validateText(option.text, string.format("options[%d].text", index))
        if ids[id] then
            error("option ids must be unique", 3)
        end
        ids[id] = true
        table.insert(copy, { id = id, text = text })
    end
    return copy
end
```

Usar `validateText` para `show` e `ask`; `validateOptions` deve ser chamada
antes de `replaceCurrent("replaced")`. Assim uma chamada invalida preserva o
dialogo ativo.

- [ ] **Step 4: Implement replacement and close semantics**

Criar uma funcao de fechamento que incremente `generation`, invalide o timer,
remova os actions, limpe o estado, publique `nil` e entao execute o callback
capturado. O callback deve receber o `optionId` apenas em conclusao de pergunta;
para cancelamento e substituicao, o primeiro argumento e `nil`.

Para substituicao, validar a nova entrada, fechar a entrada antiga com
`nil, "replaced"` e iniciar a nova entrada. Capturar o valor de `generation`
antes do callback antigo; se esse callback iniciar outro dialogo, nao permitir
que a chamada externa sobrescreva esse dialogo reentrante.

O fechamento normal deve seguir esta ordem:

```text
increment generation
capture callback and clear active callback
unbind actions
set state to nil and fire changed(nil)
invoke callback(value, reason)
```

`start()` deve apenas tornar o controlador disponivel e ser idempotente.
`stop()` deve ser idempotente; se houver estado, fechar com `nil, "cancelled"`,
depois garantir `UnbindAction` para os quatro nomes mesmo quando nao havia
estado ativo.

- [ ] **Step 5: Implement UTF-8-safe typewriter**

Criar um task por dialogo usando a `generation` atual. Dividir a string em
limites de codepoint UTF-8, nunca cortando bytes de um caractere multibyte.
Publicar o estado inicial com `visibleText = ""` e `isTyping = true`, aguardar
`CHARACTER_DELAY = 0.04` entre caracteres e publicar cada prefixo.

Ao revelar o ultimo caractere, publicar `visibleText = text` e
`isTyping = false`. A task deve verificar a geracao antes de cada publicacao e
retornar quando a geracao ou o estado ativo nao corresponder mais.

O helper de reveal imediato deve publicar o texto completo e `isTyping = false`
sem incrementar a geracao; a task pendente vera que nao esta mais digitando e
terminara sem alterar o estado.

- [ ] **Step 6: Bind confirm, cancel and navigation actions**

Usar `ContextActionService:BindActionAtPriority` com prioridade
`Enum.ContextActionPriority.High.Value + 1`, acima dos actions do tanque que
usam `High`. Criar quatro bindings:

```lua
local CONFIRM_ACTION = "DungeonDialogueConfirm" -- F
local CANCEL_ACTION = "DungeonDialogueCancel" -- Escape
local PREVIOUS_ACTION = "DungeonDialoguePrevious" -- Up, W
local NEXT_ACTION = "DungeonDialogueNext" -- Down, S
```

Cada callback deve retornar `Enum.ContextActionResult.Sink`. Processar somente
`Enum.UserInputState.Begin`:

- confirm: se `isTyping`, revelar; senao fechar mensagem com completed ou
  confirmar `options[selectedIndex]`;
- cancel: fechar com `nil, "cancelled"`;
- previous: em pergunta completa, `math.max(1, selectedIndex - 1)`;
- next: em pergunta completa, `math.min(#options, selectedIndex + 1)`.

Alteracoes de selecao devem criar uma nova tabela de estado antes de publicar,
preservando o texto revelado e as opcoes. Em mensagens simples, previous e next
continuam consumidos, mas nao alteram estado.

- [ ] **Step 7: Run the client spec until it passes**

Gerar o place e iniciar Play limpo:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

No DataModel `Client`, executar:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Expected: `failed == 0`. Se o spec falhar por o timer avancar antes da primeira
acao, manter o estado inicial sincrono e iniciar a espera antes do primeiro
prefixo; nao aumentar artificialmente a velocidade nem adicionar API de teste.

- [ ] **Step 8: Commit the controller**

```bash
git add src/client/dialogue/DialogueController.luau tests/client/dialogue/DialogueController.spec.luau
git commit -m "feat: add client dialogue controller"
```

## Task 3: Add React Hook And Render The Dialogue

**Files:**
- Create: `src/client/dialogue/useDialogue.luau`
- Modify: `src/client/init.client.luau:5-17,38-43`
- Modify: `src/client/ui/App.luau:3-16,120-155`
- Modify: `README.md:132-142`

**Interfaces:**
- Consumes: `DialogueController.getState`, `DialogueController.changed`, `DialogueController.start` e `DialogState` da Task 2.
- Produces: UI React que reflete `visibleText`, `isTyping`, `options` e `selectedIndex` sem expor detalhes de React para os consumidores.

- [ ] **Step 1: Write the hook with initial state and cleanup**

Criar `useDialogue.luau` seguindo `useInventory.luau`:

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local controller = require(script.Parent.DialogueController)

local function useDialogue()
    local dialogue, setDialogue = React.useState(controller.getState())

    React.useEffect(function()
        local connection = controller.changed:Connect(function(nextDialogue)
            setDialogue(nextDialogue)
        end)

        return function()
            connection:Disconnect()
        end
    end, {})

    return dialogue
end

return useDialogue
```

O hook deve retornar `nil` quando o controlador publicar fechamento.

- [ ] **Step 2: Start the controller from the client entrypoint**

Adicionar o require de `script.dialogue.DialogueController` em
`src/client/init.client.luau` e chamar `DialogueController.start()` antes de
renderizar o `App`. O controlador nao deve ser iniciado ao ser requerido, para
que os specs e o lifecycle continuem deterministas.

Manter a ordem dos controladores existentes e nao mover a inicializacao de
camera, tanque, inventario ou pickups.

- [ ] **Step 3: Build the derived display text in `App`**

Importar `useDialogue` e calcular o texto visual somente quando houver estado:

```lua
local dialogue = useDialogue()
local dialogueText: string? = nil

if dialogue ~= nil then
    dialogueText = dialogue.visibleText
    if dialogue.kind == "question" and not dialogue.isTyping then
        local renderedOptions = {}
        for index, option in dialogue.options do
            local marker = if index == dialogue.selectedIndex then "> " else "  "
            table.insert(renderedOptions, marker .. option.text)
        end
        dialogueText ..= "\n" .. table.concat(renderedOptions, "    ")
    end
end
```

Nao mostrar opcoes enquanto a pergunta ainda estiver em datilografia; o primeiro
`F` revela o prompt e faz a linha de opcoes aparecer.

- [ ] **Step 4: Add the bottom-centered auto-growing label**

Adicionar uma chave `Dialogue` ao retorno do `ScreenGui`, sem criar outro
`ScreenGui`. O elemento deve usar as propriedades essenciais:

```lua
Dialogue = if dialogueText ~= nil
    then React.createElement("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Position = UDim2.new(0.5, 0, 1, -24),
        Size = UDim2.new(1, -48, 0, 0),
        Font = Enum.Font.Gotham,
        Text = dialogueText,
        TextColor3 = Color3.fromRGB(241, 237, 255),
        TextSize = 18,
        TextStrokeColor3 = Color3.fromRGB(20, 22, 30),
        TextStrokeTransparency = 0.35,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Bottom,
        ZIndex = 20,
    })
    else nil,
```

O `TextLabel` deve crescer somente no eixo Y, permanecer com a borda inferior
ancorada e nao ter `UISizeConstraint`, `ScrollingFrame` ou limite de altura.
Preservar a UI de inventario e pickup notification exatamente como esta.

- [ ] **Step 5: Document the new typecheck path**

No comando de `luau-lsp analyze` em `README.md`, inserir
`src/client/dialogue` entre `src/client/camera` e `src/client/inventory`,
mantendo os demais caminhos, flags e definicoes inalterados.

- [ ] **Step 6: Build both Rojo projects**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: ambos os builds concluem e o place normal inclui o entrypoint client,
enquanto o place de testes inclui `Client.dialogue` sem executar
`init.client.luau`.

- [ ] **Step 7: Commit the UI integration**

```bash
git add src/client/dialogue/useDialogue.luau src/client/init.client.luau src/client/ui/App.luau README.md
git commit -m "feat: render client dialogue UI"
```

## Task 4: Run Static Checks And Manual Studio Verification

**Files:**
- Modify: nenhum arquivo de producao esperado; corrigir somente diagnosticos introduzidos pelas Tasks 1-3 antes de concluir.
- Verify: `src/client/dialogue`, `src/client/init.client.luau`, `src/client/ui/App.luau`, `tests/client/dialogue`, `test.project.json` e `README.md`.

**Interfaces:**
- Consumes: todos os artefatos das Tasks 1-3.
- Produces: suite TestEZ client com `failed == 0`, lint/typecheck/build limpos e confirmacao manual de comportamento.

- [ ] **Step 1: Run lint for production and tests**

Run:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Expected: exit code `0` em ambos. Corrigir apenas os arquivos da feature e
preservar o arquivo nao rastreado `docs/inventory-architecture.md`.

- [ ] **Step 2: Generate the test sourcemap**

Run:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Expected: o sourcemap inclui `StarterPlayer.StarterPlayerScripts.Client.dialogue`

- [ ] **Step 3: Run Roblox typecheck**

Run exatamente:

```bash
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups \
  src/client/camera src/client/dialogue src/client/inventory \
  src/client/pickups src/client/player src/client/ui \
  tests
```

Expected: nenhum diagnostico. Nao adicionar suppressions ou globais amplos para
esconder erros de tipos.

- [ ] **Step 4: Build production and test places**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: os dois arquivos `.rbxlx` sao gerados sem erro.

- [ ] **Step 5: Run the full server/client TestEZ sequence twice**

Servir ou sincronizar `test.project.json` na sessao Studio `RE Like Test`.
Para cada rodada:

1. Iniciar Play limpo pelo MCP.
2. No DataModel `Server`, executar:

   ```lua
   return require(game.ServerScriptService.TestEZRunner).run()
   ```

3. No DataModel `Client`, executar:

   ```lua
   return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
   ```

4. Confirmar `failed == 0` nos dois resultados estruturados.
5. Parar Play e confirmar no Output que nao restaram erros de require, callbacks
   ou bindings.

Repetir do passo 1 em uma segunda sessao Play, sem reutilizar estado de fixtures.

- [ ] **Step 6: Manually verify a simple message through the client API**

Com Play ativo no place de testes, executar no DataModel `Client`:

```lua
local playerScripts = game.Players.LocalPlayer:WaitForChild("PlayerScripts")
local client = playerScripts:WaitForChild("Client")
local Dialogue = require(client.dialogue.DialogueController)

Dialogue.show("Porta trancada: acao bloqueada.")
```

Confirmar visualmente:

- texto centralizado na parte inferior;
- caracteres aparecendo um por vez;
- primeiro `F` revelando o restante;
- segundo `F` removendo o texto;
- varias linhas crescendo para cima;
- `W/S` sem movimentar o tanque durante o dialogo;
- `W/S` movimentando normalmente depois do fechamento.

- [ ] **Step 7: Manually verify question, cancellation and replacement**

Executar no DataModel `Client`:

```lua
local playerScripts = game.Players.LocalPlayer:WaitForChild("PlayerScripts")
local client = playerScripts:WaitForChild("Client")
local Dialogue = require(client.dialogue.DialogueController)

Dialogue.ask("Usar Spade Key?", {
    { id = "yes", text = "Sim" },
    { id = "no", text = "Nao" },
}, function(optionId, reason)
    print("dialogue result", optionId, reason)
end)
```

Confirmar que:

- primeiro `F` revela a pergunta e mostra as opcoes;
- setas e `W/S` movem o marcador `>` sem sair do primeiro/ultimo item;
- segundo `F` fecha e imprime o ID correto;
- `Esc` fecha e imprime `nil, "cancelled"`;
- uma nova chamada `show` substitui a pergunta e o callback anterior imprime
  `nil, "replaced"`;
- uma chamada `ask` com IDs duplicados gera erro e nao substitui o dialogo.

- [ ] **Step 8: Inspect final worktree and commit verification**

Run:

```bash
git status --short
git diff --check
git log --oneline -6
```

Expected: nenhum arquivo de build gerado rastreado, nenhum erro de whitespace,
os commits das Tasks 1-3 presentes e o arquivo preexistente
`docs/inventory-architecture.md` ainda nao incluido.

Se todas as verificacoes passarem, criar o commit final somente para correcoes
da Task 4:

```bash
git add src/client/dialogue src/client/init.client.luau src/client/ui/App.luau tests/client/dialogue test.project.json README.md
git commit -m "test: verify client dialogue system"
```

## Self-Review Checklist

- [ ] `show` e `ask` validam entradas antes de substituir o dialogo atual.
- [ ] Mensagens simples exigem dois `F`: reveal e fechamento.
- [ ] Perguntas exigem reveal, navegacao e confirmacao em etapas distintas.
- [ ] `Esc` e substituicao entregam `nil` com razoes diferentes.
- [ ] A geracao invalida tasks de datilografia antigas.
- [ ] O binding do dialogo usa prioridade acima de `TankController`.
- [ ] `stop()` desconecta bindings e cancela callback ativo.
- [ ] O hook desconecta seu `SignalConnection` no cleanup.
- [ ] O texto usa codepoints UTF-8 e nao quebra acentos.
- [ ] O bloco React cresce em Y a partir da borda inferior sem limite.
- [ ] O projeto TestEZ nao inicia `init.client.luau`.
- [ ] O typecheck inclui `src/client/dialogue`.
- [ ] Nenhum RemoteEvent, som, fila ou spec de UI foi adicionado.
