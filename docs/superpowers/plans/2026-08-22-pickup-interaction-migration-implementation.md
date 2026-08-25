# Pickup Interaction Migration Implementation Plan

> **Superseded:** este plano descreve a migração server-authoritative anterior.
> O fluxo atual está definido em `2026-08-24-client-inventory-pickups-design.md`.

> **For agentic workers:** Use the implementation workflow selected by the user. Steps use checkbox (`- [ ]`) syntax for tracking. Do not create commits; the user explicitly requested that this worktree remain uncommitted.

**Goal:** Migrar pickups authored e pickups gerados para o contrato comum, substituir `ProximityPrompt` por `F` e manter a coleta server-authoritative atraves de `CollectPickup`.

**Architecture:** O `PickupService` sera o dono do registro server-side de cada alvo e da `ItemInstance` associada. O cliente tera apenas um handler fino que envia a referencia do alvo ao servidor. O servidor revalida a configuracao, distancia e concorrencia antes de adicionar a instancia ao `InventoryService`, destruir o alvo e emitir a notificacao existente.

**Tech Stack:** Luau `--!strict`, Roblox `CollectionService`, `HttpService`, `Players`, `Workspace`, `RemoteFunction`, `RemoteEvent`, `ProximityPrompt` desabilitado, TestEZ no Roblox Studio, Rojo `7.7.0`, Selene `0.29.0` e luau-lsp `1.69.0`.

## Global Constraints

- Este plano depende do contrato e do `InteractionController` produzidos pelo Plano 1.
- O Plano 2 ja registra o handler de portas e inicia o controller generico; este plano adiciona somente o handler de pickups ao mesmo binding de `F`.
- A raiz authored pode ser `Part`/`BasePart` ou `Model` e deve possuir tag `Interactable` e `InteractionType = "Pickup"`.
- `ItemId` e obrigatorio; `Quantity` e opcional e ambos sao lidos do alvo no servidor.
- `ItemId`, `Quantity`, `uid` e atributos de instancia nunca sao autoridade do cliente.
- O servidor cria cada `ItemInstance` com `ItemInstanceFactory` e `HttpService:GenerateGUID(false)`.
- `CollectPickup` e um `RemoteFunction`; o cliente envia somente `{ pickup = target }`.
- A coleta valida registro, parent no `Workspace`, tag, tipo, configuracao esperada, personagem, root, distancia de aproximadamente `6` studs e lock por pickup.
- Nao sera exigida linha de visao, preservando `RequiresLineOfSight = false` do caminho anterior.
- `InventoryService:addInstance` deve retornar sucesso antes de o alvo ser removido ou `PickupCollected` ser disparado.
- Em falha do inventario, o pickup permanece no mapa e o lock e liberado.
- `ProximityPrompt` nao e mais caminho de interacao; prompts existentes e prompts gerados ficam desabilitados.
- `PickupNotificationController` continua recebendo `PickupCollected` e nao sera redesenhado.
- `StudioDoorScene.luau` fica fora do escopo: nao alterar, integrar, testar ou usar como fixture.
- Nao criar specs de UI ou simular entrega de remotes entre DataModels no spec client-side.
- Todos os modulos e specs permanecem `--!strict`; nao usar `--!nocheck`, ignores amplos ou tipos globais para esconder diagnosticos.
- Fixtures que criam Instances, tags, conexoes ou estado mutavel devem ser isoladas em `beforeEach` e limpas em `afterEach`.
- Nao editar `Packages/` ou `DevPackages/`.
- Nao usar `git add`, `git commit` ou qualquer operacao de staging nesta implementacao.

## File Map

| Arquivo | Responsabilidade |
|---|---|
| `src/shared/remotes.luau` | Criar/reutilizar `CollectPickup` como `RemoteFunction` |
| `src/server/pickups/PickupService.luau` | Descobrir, registrar, validar e coletar pickups |
| `src/client/pickups/PickupController.luau` | Enviar a referencia do alvo ao servidor |
| `tests/server/pickups/PickupService.spec.luau` | Cobrir registro, autoridade, coleta e concorrencia |
| `tests/client/pickups/PickupController.spec.luau` | Cobrir o payload client-side |
| `src/server/init.server.luau` | Criar factory server-side e iniciar `PickupService` |
| `src/client/init.client.luau` | Registrar `PickupController` no controller generico |

---

### Task 1: Add The CollectPickup Remote

**Files:**
- Modify: `src/shared/remotes.luau`

**Interfaces:**
- Produces `ReplicatedStorage.Remotes.CollectPickup` como `RemoteFunction`.
- Preserves all existing remotes, including `PickupCollected` and `InteractDoor`.

- [ ] **Step 1: Adicionar o remote com a validacao existente**

Adicionar ao retorno de `src/shared/remotes.luau`:

```lua
CollectPickup = _ensureRemote("CollectPickup", "RemoteFunction"),
```

Manter `_ensureRemote` como a unica rotina de criacao/reuso e nao adicionar callback `OnServerInvoke` neste modulo.

- [ ] **Step 2: Verificar classe e reuso do remote**

Executar:

```bash
selene --config selene.roblox.toml src/shared/remotes.luau
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

No spec server ou no console do Studio, confirmar que `CollectPickup:IsA("RemoteFunction")` e que carregar `Shared.remotes` novamente nao cria uma segunda instancia.

---

### Task 2: Define The Client Pickup Handler And Failing Tests

**Files:**
- Create: `src/client/pickups/PickupController.luau`
- Create: `tests/client/pickups/PickupController.spec.luau`

**Interfaces:**
- Produces `PickupController.new(dependencies)` e uma instancia default com `interact(target: Instance) -> ()`.
- The dependency seam is:

```lua
export type Dependencies = {
    collect: (request: { pickup: Instance }) -> (),
}
```

- The default dependency invokes `remotes.CollectPickup` and discards the server result.

- [ ] **Step 1: Criar o spec com imports do DataModel real**

Usar:

```lua
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupController = require(client.pickups.PickupController)
```

Manter `beforeEach` para zerar requests e `afterEach` para destruir parts/models e limpar quaisquer controllers criados.

- [ ] **Step 2: Escrever os testes de payload**

Cobrir:

1. Um handler recebe uma `Part` e envia `{ pickup = part }` exatamente.
2. Um handler recebe um `Model` e envia `{ pickup = model }` exatamente.
3. O request nao inclui `ItemId`, `Quantity`, `uid` ou qualquer valor derivado do alvo.
4. Uma instancia que nao seja `BasePart` nem `Model` nao gera request.
5. O handler nao cria `ProximityPrompt` nem acessa `InventoryController`.

Usar dependencia fake:

```lua
local requests: { any } = {}
local controller = PickupController.new({
    collect = function(request)
        table.insert(requests, request)
    end,
})
```

- [ ] **Step 3: Rodar o spec antes da implementacao**

Executar:

```bash
selene --config selene.roblox-tests.toml tests/client/pickups/PickupController.spec.luau
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Rodar o runner client no Studio. Esperado: falha de require para `PickupController` ou falhas de contrato.

- [ ] **Step 4: Implementar o handler fino**

Criar `PickupController` sem input proprio e sem estado de alvo. A implementacao deve validar a classe e chamar somente:

```lua
dependencies.collect({ pickup = target })
```

O default deve verificar `CollectPickup:IsA("RemoteFunction")`, invocar o remote com o request e ignorar o resultado. Nao adicionar feedback local de coleta; a notificacao continua vindo de `PickupCollected`.

- [ ] **Step 5: Executar os testes client-side**

Executar:

```bash
selene --config selene.roblox.toml src/client/pickups/PickupController.luau
selene --config selene.roblox-tests.toml tests/client/pickups
```

Esperado: `PickupController.spec.luau` e o spec existente de `PickupNotificationController` passam sem simular rede entre DataModels.

---

### Task 3: Define PickupService Tests And Registration Contract

**Files:**
- Create: `tests/server/pickups/PickupService.spec.luau`
- Use: `src/server/items/ItemInstanceFactory.luau`
- Use: `src/shared/interactions/interactionTypes.luau`

**Interfaces:**
- Produces fixtures para `Part`/`Model` authored e definicoes geradas.
- Defines a fake inventory with `addInstance(player, itemInstance): boolean`.
- Uses an optional notification callback seam in tests; production will default to `PickupCollected:FireClient`.

- [ ] **Step 1: Criar helpers de fixture strict**

O helper de pickup deve aplicar atributos antes da tag e do parent final:

```lua
pickup:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
pickup:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, itemId)
if quantity ~= nil then
    pickup:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, quantity)
end
pickup.Parent = Workspace
CollectionService:AddTag(pickup, interactionTypes.INTERACTABLE_TAG)
```

Criar helpers para `Part` e `Model` com uma `Part` filha. Criar prompts opcionais como filhos para verificar a desabilitacao. Registrar todos os roots em uma lista e destruir em `afterEach`.

- [ ] **Step 2: Criar factory deterministica e fake inventory**

Usar `ItemInstanceFactory.new` com um gerador que produza `test-pickup-01`, `test-pickup-02` e assim por diante. O fake inventory deve capturar o `ItemInstance`, contar chamadas, permitir `fail = true` e permitir uma callback reentrante para exercitar o lock.

O notifier fake deve capturar `(player, itemId)` em uma lista, permitindo verificar a ordem relativa entre `addInstance`, destruicao e notificacao. Esse seam nao altera o comportamento default do runtime.

- [ ] **Step 3: Escrever testes de descoberta e registro**

Cobrir:

1. `start()` registra pickup authored existente antes de qualquer coleta.
2. Um pickup tagueado depois de `start()` e registrado.
3. Uma segunda chamada a `start()` nao duplica registro nem conexoes.
4. Item desconhecido nao cria registro.
5. Quantidade zero, negativa, fracionaria, nao numerica ou quantidade em item nao stackable nao cria registro.
6. Cada pickup gerado a partir de definicoes recebe uma `ItemInstance` e um `uid` independente.
7. `ItemId`, quantidade e atributos authored invalidos nao deixam estado parcial.

O registro deve ser observado atraves do resultado de `CollectPickup`/`service:invoke`, sem acessar tabelas privadas diretamente.

- [ ] **Step 4: Escrever testes de validacao de coleta**

Cobrir:

1. Request com formato invalido ou `pickup` que nao seja `Instance` retorna falha.
2. Alvo nao registrado retorna falha.
3. Alvo registrado mas removido do `Workspace` retorna falha.
4. Alvo com tag removida ou `InteractionType` alterado retorna falha.
5. Alvo com `ItemId` ou `Quantity` alterado depois do registro retorna falha.
6. Jogador sem personagem ou `HumanoidRootPart` retorna falha.
7. Jogador alem de aproximadamente `6` studs retorna falha.
8. Coleta dentro da distancia chama `addInstance` com a instancia criada pelo servidor.

- [ ] **Step 5: Escrever testes de sucesso, falha e concorrencia**

Cobrir:

1. Se `addInstance` falhar, o alvo continua no `Workspace`, o prompt continua desabilitado e uma nova tentativa ainda pode ser feita.
2. Se `addInstance` tiver sucesso, o alvo e destruido e o notifier recebe o jogador e o `itemId` correto.
3. O notifier somente e chamado depois de `addInstance` retornar sucesso e depois de o alvo ser removido.
4. Uma chamada reentrante para o mesmo alvo retorna `busy` e nao adiciona a instancia duas vezes.
5. `stop()` remove `CollectPickup.OnServerInvoke`, desconecta a escuta da tag e pode ser chamado repetidamente.
6. Prompt authored e prompt criado pelo service ficam com `Enabled == false` e nunca acionam coleta por `Triggered`.

- [ ] **Step 6: Rodar a suite server-side antes do service**

Executar:

```bash
selene --config selene.roblox-tests.toml tests/server/pickups/PickupService.spec.luau
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Rodar no Studio:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

Esperado: falha de require para o novo `PickupService` ou falhas de contrato, sem modificar specs existentes de inventario.

---

### Task 4: Implement PickupService

**Files:**
- Modify: `src/server/pickups/PickupService.luau`

**Interfaces:**
- Consumes `InventoryService.addInstance`, `ItemInstanceFactory.create`, `CollectionService`, `Workspace`, `Players`, `remotes.CollectPickup`, `remotes.PickupCollected` e `interactionTypes`.
- Produces:

```lua
PickupService.new(
    inventoryService,
    factory,
    definitions?,
    notify?
): Service
```

- `Service` exposes idempotent `start()`, `stop()` e `invoke(player, request)`.
- `notify` is optional and exists only as a test seam; when omitted it calls `PickupCollected:FireClient(player, itemId)`.

- [ ] **Step 1: Definir os tipos e o registro privado**

Manter a definicao existente:

```lua
type PickupDefinition = {
    itemId: string,
    attributes: items.ItemAttributes?,
    quantity: number?,
}
```

Adicionar um registro privado equivalente a:

```lua
type RegisteredPickup = {
    instance: items.ItemInstance,
    itemId: string,
    quantity: number?,
}
```

Usar:

```lua
local registered: { [Instance]: RegisteredPickup } = {}
local busy: { [Instance]: boolean } = {}
```

Nao expor essas tabelas pelo service.

- [ ] **Step 2: Implementar registro de alvos authored**

Criar uma funcao privada `registerPickup(target: Instance, suppliedInstance: items.ItemInstance?) -> boolean` que:

1. Aceita somente `BasePart` ou `Model`.
2. Exige que o alvo esteja descendente de `Workspace`.
3. Exige a tag `Interactable` e `InteractionType == "Pickup"`.
4. Le `ItemId` como string nao vazia.
5. Le `Quantity` como valor ausente ou numero.
6. Usa `factory:create(itemId, nil, quantity)` para authored.
7. Usa `suppliedInstance` somente para pickups gerados pelo proprio service.
8. Em qualquer falha, emite um warning com caminho ou identificador da configuracao e nao preenche `registered`.
9. Desabilita todos os `ProximityPrompt`s descendentes do alvo reconhecido.
10. Retorna sem duplicar quando `registered[target]` ja existe.

Para configurações authored, nao copiar atributos arbitrarios do Instance para `ItemInstance`; somente `ItemId` e `Quantity` fazem parte deste contrato.

- [ ] **Step 3: Descobrir alvos atuais e futuros**

No `start()`:

1. Marcar `started` antes de instalar callbacks.
2. Conectar `CollectionService:GetInstanceAddedSignal(INTERACTABLE_TAG)` e chamar `registerPickup` para novos alvos.
3. Percorrer `CollectionService:GetTagged(INTERACTABLE_TAG)` e registrar os que tenham tipo `Pickup`.
4. Ignorar silenciosamente tipos `Door`; eles pertencem ao `DoorService`.
5. Instalar `CollectPickup.OnServerInvoke` apontando para `service:invoke`.
6. Manter referencias das conexoes de `PlayerAdded` e `CharacterAdded` para `stop()` desconectar tudo.

O codigo que adiciona tag a objetos runtime deve parentear e configurar atributos antes de adicionar a tag, evitando um sinal que observe uma instancia parcial.

- [ ] **Step 4: Preservar e adaptar pickups gerados por definicoes**

Manter o spawn uma unica vez proximo do primeiro personagem carregado, mas alterar cada Part gerada para:

```lua
part:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
part:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, instance.itemId)
if instance.quantity ~= nil then
    part:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, instance.quantity)
end
```

Cada definicao deve chamar `factory:create` uma vez. Definicoes invalidas devem gerar warning e ser ignoradas sem criar Part parcial. Para preservar a estrutura visual existente, continuar criando um `ProximityPrompt` com `ActionText`, `ObjectText`, `MaxActivationDistance` e `RequiresLineOfSight = false`, mas sempre com `Enabled = false` e sem conexao em `Triggered`.

Parentear a Part, colocar a instancia gerada em um mapa `pendingGenerated`, adicionar a tag e chamar `registerPickup(part, instance)`. O callback de `GetInstanceAddedSignal` deve consultar esse mapa antes de criar uma instancia nova; assim, o registro usa a mesma `ItemInstance` e o mesmo uid. Remover a entrada pending depois do registro. O batch continua sem raycast de chao, navegacao ou reposicionamento automatico.

- [ ] **Step 5: Implementar validacao do request e distancia**

Definir um resultado local com `success: boolean` e `reason: string?`. `invoke` deve rejeitar:

```lua
if type(request) ~= "table" or typeof(request.pickup) ~= "Instance" then
    return { success = false, reason = "invalid_request" }
end
```

Depois, localizar `registered[pickup]`, confirmar parent, classe, tag, tipo e igualdade de `ItemId`/`Quantity` com o registro. Obter a posicao por `BasePart.Position` ou `Model:GetPivot().Position`. Obter o root do personagem e rejeitar distancia maior que `6` studs com `too_far`. Nao usar linha de visao.

- [ ] **Step 6: Implementar lock e mutacao atomica do pickup**

A ordem do sucesso deve ser:

```lua
local registeredPickup = registered[pickup]
if registeredPickup == nil then
    return { success = false, reason = "not_registered" }
end
if busy[pickup] then
    return { success = false, reason = "busy" }
end

busy[pickup] = true
local ok, added = pcall(function()
    return inventoryService:addInstance(player, registeredPickup.instance)
end)
busy[pickup] = nil

if not ok or added ~= true then
    return { success = false, reason = "inventory_failed" }
end

registered[pickup] = nil
pickup:Destroy()
notify(player, registeredPickup.itemId)
return { success = true }
```

Capturar a referencia de `registeredPickup` antes de limpar a tabela. Se `addInstance` falhar ou gerar erro, manter alvo e registro. O lock deve ser limpo em todos os caminhos.

- [ ] **Step 7: Implementar lifecycle e callbacks de jogador**

Preservar o spawn por primeiro personagem: conectar `CharacterAdded` de jogadores atuais e futuros, verificar `spawned` antes e depois de `WaitForChild("HumanoidRootPart")`, e criar o batch somente uma vez. `stop()` deve:

1. Desmarcar `started`.
2. Remover `CollectPickup.OnServerInvoke`.
3. Desconectar sinal de tag, `PlayerAdded` e `CharacterAdded`.
4. Limpar `registered` e `busy`.
5. Nao destruir pickups authored ou gerados automaticamente.

Chamadas repetidas a `start()` e `stop()` nao podem duplicar callbacks.

- [ ] **Step 8: Rodar os testes server-side e lint**

Executar:

```bash
selene --config selene.roblox.toml src/server/pickups/PickupService.luau
selene --config selene.roblox-tests.toml tests/server/pickups
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

No DataModel `Server`, rodar o runner e confirmar `failed == 0`. Verificar tambem que os specs existentes de `ItemInstanceFactory`, `InventoryStore` e `ItemUseService` continuam passando.

---

### Task 5: Compose The Server Pickup Service

**Files:**
- Modify: `src/server/init.server.luau`

**Interfaces:**
- Consumes `ItemInstanceFactory.new`, `PickupService.new` e o `InventoryService` ja iniciado.
- Produces um `PickupService` ativo com geracao server-side de uid.
- Does not modify or invoke `StudioDoorScene`.

- [ ] **Step 1: Adicionar dependencias do bootstrap**

Adicionar:

```lua
local HttpService = game:GetService("HttpService")
local ItemInstanceFactory = require(script.items.ItemInstanceFactory)
local PickupService = require(script.pickups.PickupService)
```

Manter requires e ordem atuais de `InventoryService`, `ItemUseService`, `DoorService` e `CharacterLightService`.

- [ ] **Step 2: Criar factory e iniciar pickup depois do inventario**

Depois de `inventoryService:start()`:

```lua
local factory = ItemInstanceFactory.new(function(): string
    return HttpService:GenerateGUID(false)
end)

local pickupService = PickupService.new(inventoryService, factory)
pickupService:start()
```

Nao fornecer seeds ou definicoes implicitas. O mapa continuara sendo a fonte dos pickups authored; definicoes geradas permanecem disponiveis pela API do service.

- [ ] **Step 3: Construir o projeto normal**

Executar:

```bash
selene --config selene.roblox.toml src/server/init.server.luau
rojo build -o /tmp/dungeon-game-canve-pickup-server.rbxlx default.project.json
```

Esperado: o build inclui `ServerScriptService.Server.pickups.PickupService` e o bootstrap nao referencia `StudioDoorScene`.

---

### Task 6: Register The Pickup Handler In The Client Bootstrap

**Files:**
- Modify: `src/client/init.client.luau`

**Interfaces:**
- Consumes `PickupController` e `InteractionController` default.
- Produces o registro dos tipos `Door` e `Pickup` antes de um unico `InteractionController.start()`.

- [ ] **Step 1: Requerer `PickupController`**

Adicionar:

```lua
local PickupController = require(script.pickups.PickupController)
```

Manter `PickupNotificationController.start()` separado, pois ele continua escutando `PickupCollected`.

- [ ] **Step 2: Registrar ambos os handlers no binding unico**

Substituir o trecho de integracao do Plano 2 por:

```lua
InteractionController.register("Door", DoorController)
InteractionController.register("Pickup", PickupController)
InteractionController.start()
```

As duas chamadas `register` devem ocorrer depois de os modulos serem requeridos e antes de `start()`. Remover qualquer `PickupController.start()` ou binding adicional de `F`.

- [ ] **Step 3: Verificar o bootstrap client-side**

Executar:

```bash
selene --config selene.roblox.toml src/client/init.client.luau
rojo build -o /tmp/dungeon-game-canve-pickup-client.rbxlx default.project.json
```

Esperado: um unico binding de interacao no runtime, com `DoorController` e `PickupController` registrados.

---

### Task 7: Complete Static And Studio Verification

**Files:**
- Verify: all files changed by Tasks 1-6
- Do not modify: `src/server/doors/StudioDoorScene.luau`

- [ ] **Step 1: Rodar lint dos dois roots**

Executar exatamente:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Esperado: exit code `0` sem supressions novas.

- [ ] **Step 2: Gerar sourcemap e rodar typecheck Roblox**

Executar na ordem:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/doors src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Esperado: nenhum diagnostico e nenhuma inclusao dos entrypoints normais na analise.

- [ ] **Step 3: Construir os dois projetos Rojo**

Executar:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Confirmar que `CollectPickup`, `PickupService`, `PickupController` e `InteractionController` aparecem nos caminhos esperados.

- [ ] **Step 4: Rodar duas sessoes Play limpas**

Servir ou sincronizar `test.project.json` na sessao Studio `RE Like Test`. Em cada uma de duas sessoes independentes:

1. Iniciar Play pelo MCP.
2. Aguardar `TestEZAutoServer` e `TestEZAutoClient`.
3. Confirmar `failed == 0` no servidor e no cliente.
4. Se necessario, repetir os runners explicitos:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

5. Parar Play.
6. Confirmar que fixtures, conexoes, callbacks remotos e GUI temporarias foram limpos.

- [ ] **Step 5: Verificar manualmente o fluxo integrado sem StudioDoorScene**

No projeto normal, usando portas e pickups authored reais do mapa:

1. Pressionar `F` diante de uma porta com contrato comum e confirmar o fluxo de unlock/enter.
2. Pressionar `F` diante de um pickup `Part` e de um pickup `Model` e confirmar coleta.
3. Confirmar que prompts authored nao exibem nem coletam pickups.
4. Confirmar que o inventario recebe a `ItemInstance` com `uid` gerado pelo servidor.
5. Confirmar que a notificacao existente aparece somente depois da coleta confirmada.
6. Forcar falha de inventario e confirmar que o pickup permanece disponivel.
7. Executar `InteractionController.setEnabled(false)` no client e confirmar que portas e pickups nao respondem a `F`.
8. Executar `InteractionController.setEnabled(true)` e confirmar que ambos voltam a responder.
9. Confirmar que dois jogadores ou duas tentativas concorrentes nao coletam o mesmo alvo duas vezes.

Nao criar ou alterar `StudioDoorScene` para realizar esta verificacao.

- [ ] **Step 6: Inspecionar o worktree sem staging**

Executar:

```bash
git status --short
git diff --check
```

Confirmar que nao ha arquivos gerados rastreados, que as alteracoes preexistentes em `AGENTS.md` e na spec de design foram preservadas e que nenhum commit foi criado.

## Handoff

Este plano encerra a integracao dos tipos `Door` e `Pickup` no unico controller generico. Nenhum novo tipo de interacao, remoto generico, persistencia de pickups, indicador visual ou alteracao de UI deve ser adicionado sem nova spec.
