# Client Inventory And Pickups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar inventario e pickups authored para autoridade local do cliente, remover o mecanismo generico de uso de itens e preservar portas, notificacoes e objetivos sem remotes de inventario.

**Architecture:** `InventoryController` mantem um estado de sessao local sobre o `InventoryStore` puro compartilhado. `PickupManager` descobre, registra e coleta somente pickups authored; `PickupInteraction` adapta o manager ao `InteractionController` e publica `item_collected`. A notificacao escuta um sinal local do manager, enquanto o servidor permanece apenas com servicos que ainda sao necessarios.

**Tech Stack:** Luau `--!strict`, Roblox `CollectionService`, `HttpService`, `Workspace`, `Players.LocalPlayer`, `Signal`, TestEZ no Roblox Studio, Rojo `7.7.0`, Selene `0.29.0` e luau-lsp `1.69.0`.

## Global Constraints

- O inventario e client-authoritative, existe somente na memoria da sessao e inicia vazio em uma nova sessao.
- O inventario e os pickups coletados permanecem durante respawn do personagem.
- Pickups gerados por definicoes, spawn aleatorio, `pendingGenerated` e criacao automatica de loot nao fazem parte desta migracao.
- Pickups authored usam somente `BasePart` ou `Model` com tag `Interactable`, `InteractionType = "Pickup"`, `ItemId` string nao vazia e `Quantity` opcional.
- `PickupManager` e responsavel pelo dominio de pickups; `PickupInteraction` e responsavel somente por adaptar a interacao do jogador.
- `PickupInteraction` e o unico handler registrado para `"Pickup"` no unico binding de `F`.
- `PickupManager` recebe `InventoryController` e `ItemInstanceFactory` por dependencia nomeada.
- `PickupInteraction` publica `item_collected` somente depois de o manager confirmar a insercao no inventario.
- `PickupNotificationController` escuta um sinal local; `PickupEventBridge` e removido.
- `InventoryStore` e `ItemInstanceFactory` ficam em `src/shared/inventory` e nao dependem de services server-side.
- `InventoryController` expoe somente estado, sinal de mudanca e `addInstance` nesta etapa; nenhum uso, consumo, equipar ou descarte sera implementado.
- `ItemUseService`, `ItemBehaviorRegistry` e `UseItem` nao serao migrados; serao removidos.
- `InventoryService`, `PickupService`, `UseItem`, `CollectPickup`, `PickupCollected`, `InventoryChanged` e `GetInventory` serao removidos do runtime.
- A UI permanece inalterada, incluindo as acoes mock de `App.luau`.
- `DoorManager` continua lendo `InventoryController:getState()` e nao usa `ItemUseService`.
- `CharacterLightService` e outros servicos server-side ainda necessarios permanecem ativos.
- Nenhuma spec de UI sera criada.
- Specs que criam Instances, tags, sinais ou estado mutavel usam `beforeEach` e limpam tudo em `afterEach`.
- Todos os modulos Luau e specs permanecem `--!strict`; nao usar `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Nao editar `Packages/` ou `DevPackages/`.
- Depois de alterar scripts ou specs usados pelo TestEZ, parar e iniciar novamente o Play do projeto de testes antes de executar os runners.
- Usar o DataModel real e os imports mapeados pelo Rojo; nao criar indirection virtual ou imports de filesystem.
- Preservar mudancas preexistentes no worktree, incluindo arquivos nao rastreados de design e plano de portas.
- Nao executar `git add`, `git commit`, `git amend`, `git reset`, staging ou qualquer outra operacao de commit.

## File Map

| Arquivo | Acao | Responsabilidade |
|---|---|---|
| `src/shared/inventory/InventoryStore.luau` | Criar, movendo de `src/server/inventory` | Estado puro, validacao, copia e mutacoes imutaveis |
| `src/shared/inventory/ItemInstanceFactory.luau` | Criar, movendo de `src/server/items` | Criacao validada de instancias e UIDs |
| `src/client/inventory/InventoryController.luau` | Modificar | Estado local da sessao e `addInstance` |
| `src/client/pickups/PickupManager.luau` | Criar | Registro, validacao e coleta de pickups authored |
| `src/client/pickups/PickupInteraction.luau` | Criar, substituindo `PickupController` | Handler do sistema generico e evento de gameplay |
| `src/client/pickups/PickupNotificationController.luau` | Modificar | Fonte local da notificacao |
| `src/client/init.client.luau` | Modificar | Composicao do inventario e pickups client-side |
| `src/shared/remotes.luau` | Remover | Remotes de inventario, uso e pickup obsoletos |
| `src/client/events/PickupEventBridge.luau` | Remover | Adaptador remoto obsoleto |
| `src/server/inventory/InventoryService.luau` | Remover | Estado server-side obsoleto |
| `src/server/pickups/PickupService.luau` | Remover | Coleta server-side obsoleta |
| `src/server/items/ItemUseService.luau` | Remover | Uso generico de itens obsoleto |
| `src/server/items/ItemBehaviorRegistry.luau` | Remover | Behaviors genericos obsoletos |
| `src/server/init.server.luau` | Modificar | Manter somente servicos server-side necessarios |
| `tests/shared/inventory/InventoryStore.spec.luau` | Criar, movendo de `tests/server/inventory` | Contrato do store compartilhado |
| `tests/shared/inventory/ItemInstanceFactory.spec.luau` | Criar, movendo de `tests/server/items` | Contrato da factory compartilhada |
| `tests/shared/inventory/items.spec.luau` | Modificar | Usar IDs presentes no catalogo atual |
| `tests/client/inventory/InventoryController.spec.luau` | Criar | Contrato do inventario local |
| `tests/client/pickups/PickupManager.spec.luau` | Criar | Dominio de pickups authored |
| `tests/client/pickups/PickupInteraction.spec.luau` | Criar | Delegacao e evento de gameplay |
| `tests/client/pickups/PickupNotification.spec.luau` | Modificar | Fonte de notificacao local |
| `tests/client/pickups/PickupController.spec.luau` | Remover | Spec do handler antigo |
| `tests/client/events/PickupEventBridge.spec.luau` | Remover | Spec do bridge remoto obsoleto |
| `tests/server/inventory/InventoryStore.spec.luau` | Remover apos mover | Caminho server-side obsoleto |
| `tests/server/pickups/PickupService.spec.luau` | Remover | Spec server-side obsoleto |
| `tests/server/items/ItemUseService.spec.luau` | Remover | Spec server-side obsoleto |
| `tests/server/items/ItemBehaviorRegistry.spec.luau` | Remover | Spec server-side obsoleto |
| `test.project.json` | Modificar | Remover mapeamentos server-side obsoletos |
| `README.md` | Modificar | Atualizar caminhos de typecheck e arquitetura |
| `docs/inventory-architecture.md` | Modificar | Documentar a arquitetura client-side |
| `docs/superpowers/specs/2026-08-17-inventory-pickup-design.md` | Modificar | Marcar design server-side como historico |
| `docs/superpowers/plans/2026-08-22-pickup-interaction-migration-implementation.md` | Modificar | Marcar plano server-side como supersedido |
| `docs/superpowers/specs/2026-08-22-generic-interaction-system-design.md` | Modificar | Atualizar pickup e remotes obsoletos |
| `docs/superpowers/specs/2026-08-22-objective-system-design.md` | Modificar | Atualizar origem de `item_collected` |

---

## Task 1: Move Pure Inventory Modules To Shared

**Goal:** Remover a localizacao server-side dos modulos puros sem alterar seus contratos comportamentais.

**Files:**

- Create: `src/shared/inventory/InventoryStore.luau`
- Create: `src/shared/inventory/ItemInstanceFactory.luau`
- Create: `tests/shared/inventory/InventoryStore.spec.luau`
- Create: `tests/shared/inventory/ItemInstanceFactory.spec.luau`
- Modify: `tests/shared/inventory/items.spec.luau`
- Delete after migration: `src/server/inventory/InventoryStore.luau`
- Delete after migration: `tests/server/inventory/InventoryStore.spec.luau`
- Delete after migration: `src/server/items/ItemInstanceFactory.luau`
- Delete after migration: `tests/server/items/ItemInstanceFactory.spec.luau`

**Interfaces:**

- `InventoryStore.defaultInventory() -> items.InventoryState`
- `InventoryStore.copyState(state) -> items.InventoryState`
- `InventoryStore.addInstance(state, instance) -> items.InventoryState?`
- `InventoryStore.findInstance(state, uid) -> items.ItemInstance?`
- `InventoryStore.removeInstance(state, uid) -> items.InventoryState?`
- `InventoryStore.addQuantity(state, itemId, quantity, uid?) -> items.InventoryState?`
- `InventoryStore.removeQuantity(state, uid, quantity) -> items.InventoryState?`
- `InventoryStore.updateAttributes(state, uid, attributes) -> items.InventoryState?`
- `InventoryStore.equip(state, slot, uid) -> items.InventoryState?`
- `ItemInstanceFactory.new(uidGenerator) -> ItemInstanceFactory.Factory`
- `factory:create(itemId, attributes?, quantity?) -> items.ItemInstance?`

- [ ] **Step 1: Mover os specs para o root shared**

Criar os diretorios e mover os dois specs sem remover cobertura. Atualizar os
imports para o DataModel compartilhado:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryStore = require(ReplicatedStorage.Shared.inventory.InventoryStore)
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)
```

O spec de `InventoryStore` deve continuar verificando `version = 2`, copia
profunda, validacao de instancias, stacks, atributos, equipar e mutacoes
imutaveis. O spec da factory deve continuar verificando UIDs, item desconhecido,
quantidades, atributos e UIDs repetidos. Como o catalogo atual possui
`access_card` e nao possui `iron_key`, substituir fixtures ativas que ainda usam
`iron_key` por `access_card`, preservando o comportamento testado.

Atualizar tambem `tests/shared/inventory/items.spec.luau` para verificar a
capability `unlock` de `items.access_card` em vez de acessar uma chave removida
do catalogo:

```lua
expect(hasCapability(items.access_card.capabilities, "unlock")).to.be.ok()
```

- [ ] **Step 2: Rodar o runner shared antes da implementacao compartilhada**

Parar e iniciar o Play do projeto de testes e executar o runner client ou shared
correspondente no DataModel real. Como o runner compartilhado atual e executado
pelo `TestEZRunner` server junto com os roots shared e server, usar:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

A tentativa deve falhar ao carregar os novos modulos compartilhados, confirmando
que os specs nao estao silenciosamente desabilitados. Nao adicionar fallback para
o caminho antigo.

- [ ] **Step 3: Mover `InventoryStore` para o shared**

Preservar o corpo atual do modulo e trocar somente o import de tipos para o
irmao compartilhado:

```lua
local items = require(script.Parent.items)
```

Manter a validacao de `InventoryState` schema 2, a copia de atributos e todas as
operacoes puras existentes. O modulo nao deve importar `ServerScriptService`,
`Players`, `RemoteEvent` ou qualquer service Roblox.

- [ ] **Step 4: Mover `ItemInstanceFactory` para o shared**

Preservar a API e alterar o import para:

```lua
local items = require(script.Parent.items)
```

Manter o gerador injetado, o controle de UID emitido, a copia de atributos e as
validacoes de item, quantidade e stackability. Nao colocar `HttpService` dentro
da factory; a composicao fornecera o gerador.

- [ ] **Step 5: Remover os arquivos antigos depois que os novos imports passarem**

Antes de apagar os modulos antigos, atualizar os consumidores server-side que
ainda existem temporariamente para o caminho shared. Em
`src/server/inventory/InventoryService.luau`, usar:

```lua
local InventoryStore = require(ReplicatedStorage.Shared.inventory.InventoryStore)
```

Em `src/server/init.server.luau`, reutilizar o `ReplicatedStorage` ja existente e
usar a factory shared:

```lua
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)
```

Remover os dois arquivos de producao e os dois specs dos roots server-side.
Nao remover ainda os services server-side que continuam dependendo desses
modulos; essa remocao ocorre na Task 8.

- [ ] **Step 6: Verificar o contrato shared**

Executar:

```bash
selene --config selene.roblox.toml src/shared/inventory
selene --config selene.roblox-tests.toml tests/shared/inventory
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Rodar o runner TestEZ no Studio e confirmar que os specs movidos passam.

---

## Task 2: Make `InventoryController` Local

**Goal:** Transformar o controller em dono do estado de inventario da sessao, sem sincronizacao ou uso remoto.

**Files:**

- Modify: `src/client/inventory/InventoryController.luau`
- Create: `tests/client/inventory/InventoryController.spec.luau`
- Use: `src/shared/inventory/InventoryStore.luau`
- Use: `src/shared/inventory/items.luau`

**Interfaces:**

```lua
export type InventoryController = {
    start: () -> (),
    stop: () -> (),
    getState: () -> items.InventoryState?,
    addInstance: (instance: items.ItemInstance) -> boolean,
    changed: typeof(changed),
}
```

- [ ] **Step 1: Criar fixtures do controller antes da implementacao**

Criar `tests/client/inventory/InventoryController.spec.luau` usando o modulo
do DataModel real:

```lua
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local InventoryController = require(client.inventory.InventoryController)
```

O spec nao deve simular `RemoteEvent` ou `RemoteFunction`. Em cada `beforeEach`,
parar o controller para garantir estado vazio; em cada `afterEach`, parar o
controller e desconectar todos os sinais.

- [ ] **Step 2: Escrever os testes de estado e lifecycle**

Adicionar testes com as seguintes assertions observaveis:

```lua
it("starts with an empty local inventory", function()
    InventoryController.start()
    local state = assert(InventoryController.getState())
    expect(state.version).to.equal(2)
    expect(#state.items).to.equal(0)
end)

it("does not reset an active session on repeated start", function()
    InventoryController.start()
    expect(InventoryController.addInstance({ uid = "local-1", itemId = "access_card" })).to.equal(true)
    InventoryController.start()
    expect(#assert(InventoryController.getState()).items).to.equal(1)
end)

it("clears the state on stop and starts a fresh session", function()
    InventoryController.start()
    InventoryController.addInstance({ uid = "local-1", itemId = "access_card" })
    InventoryController.stop()
    expect(InventoryController.getState()).to.equal(nil)
    InventoryController.start()
    expect(#assert(InventoryController.getState()).items).to.equal(0)
end)
```

- [ ] **Step 3: Escrever os testes de adicao e sinal**

Cobrir adicao valida, falha sem mutacao e disparo de `changed` somente em
sucesso:

```lua
it("adds a valid item and publishes the new snapshot", function()
    local received: any = nil
    local connection = InventoryController.changed:Connect(function(snapshot)
        received = snapshot
    end)
    InventoryController.start()

    expect(InventoryController.addInstance({ uid = "local-1", itemId = "access_card" })).to.equal(true)
    expect(received.items[1].uid).to.equal("local-1")
    connection:Disconnect()
end)

it("preserves state and signal count for an invalid item", function()
    local changes = 0
    local connection = InventoryController.changed:Connect(function()
        changes += 1
    end)
    InventoryController.start()

    expect(InventoryController.addInstance({ uid = "invalid-1", itemId = "unknown" })).to.equal(false)
    expect(#assert(InventoryController.getState()).items).to.equal(0)
    expect(changes).to.equal(0)
    connection:Disconnect()
end)
```

Tambem testar `addInstance` antes de `start()` retornando `false` sem criar
estado implicito.

- [ ] **Step 4: Rodar o spec antes da implementacao**

Parar e iniciar o Play e executar o runner client. O spec deve falhar porque o
controller ainda importa remotes, nao expoe `addInstance` e nao possui estado
local. Nao ajustar o spec para aceitar o contrato antigo.

- [ ] **Step 5: Remover a sincronizacao remota do controller**

Remover imports e variaveis de `remotes`, `InventoryChanged`, `GetInventory` e
`UseItem`. Importar o store shared:

```lua
local InventoryStore = require(ReplicatedStorage.Shared.inventory.InventoryStore)
```

Substituir o estado atual por estado criado no modulo e implementar o lifecycle
idempotente:

```lua
local state: InventoryState? = nil
local started = false

function controller.start(): ()
    if started then
        return
    end
    started = true
    state = InventoryStore.defaultInventory()
end

function controller.stop(): ()
    if not started then
        return
    end
    started = false
    state = nil
end
```

- [ ] **Step 6: Implementar `getState` e `addInstance`**

`getState` deve retornar o estado local atual. `addInstance` deve retornar
`false` quando o controller nao estiver iniciado ou quando o store rejeitar a
instancia. Em sucesso, substituir o estado e disparar `changed`:

```lua
function controller.addInstance(instance: ItemInstance): boolean
    if not started or state == nil then
        return false
    end
    local updated = InventoryStore.addInstance(state, instance)
    if updated == nil then
        return false
    end
    state = updated
    changed:Fire(updated)
    return true
end
```

Nao adicionar `use`, `remove`, `equip` ou `discard` ao controller nesta etapa.

- [ ] **Step 7: Rodar os testes do controller**

Executar o runner client no Studio e confirmar que o spec novo e os hooks
existentes de `useInventory` continuam funcionando sem alterar a UI.

---

## Task 3: Define `PickupManager` Fixtures And Failing Specs

**Goal:** Especificar o dominio client-side de pickups authored antes de portar a logica do service.

**Files:**

- Create: `tests/client/pickups/PickupManager.spec.luau`
- Use: `src/client/pickups/PickupManager.luau` ainda inexistente
- Use: `src/client/player/CharacterRoot.luau`
- Use: `src/shared/inventory/items.luau`
- Use: `src/shared/interactions/interactionTypes.luau`

**Interfaces:**

```lua
export type Dependencies = {
    inventory: InventoryController.InventoryController,
    factory: ItemInstanceFactory.Factory,
}

export type PickupFailureReason =
    "invalid_pickup"
    | "not_registered"
    | "too_far"
    | "busy"
    | "inventory_failed"

export type SignalConnection = {
    Disconnect: (self: SignalConnection) -> (),
}

export type CollectedSignal = {
    Connect: (
        self: CollectedSignal,
        callback: (itemId: string) -> ()
    ) -> SignalConnection,
}

export type PickupFailure = {
    success: false,
    reason: PickupFailureReason,
}

export type PickupSuccess = {
    success: true,
    itemId: string,
}

export type PickupResult = PickupFailure | PickupSuccess

export type PickupManager = {
    start: (self: PickupManager) -> (),
    stop: (self: PickupManager) -> (),
    collect: (self: PickupManager, pickup: Instance) -> PickupResult,
    collected: CollectedSignal,
}
```

- [ ] **Step 1: Criar helpers de fixture no DataModel real**

Usar os imports client-side reais:

```lua
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupManager = require(client.pickups.PickupManager)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)
```

O helper `makePartPickup(itemId, quantity, withPrompt)` deve criar um `Part`,
configurar tamanho e ancoragem, aplicar atributos, parentear no `Workspace` e
adicionar a tag por ultimo:

```lua
part:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
part:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, itemId)
if quantity ~= nil then
    part:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, quantity)
end
part.Parent = Workspace
CollectionService:AddTag(part, interactionTypes.INTERACTABLE_TAG)
```

O helper `makeModelPickup` deve fazer o mesmo no `Model`, com uma `Part` filha.
O helper `makeCharacter(position)` deve criar um `HumanoidRootPart`, parentear o
modelo no `Workspace`, atribui-lo a `Players.LocalPlayer.Character` e registrar
todas as instances para destruicao posterior.

- [ ] **Step 2: Criar fakes isolados de inventario e factory**

O fake de inventario deve expor a assinatura local e permitir falha/reentrada:

```lua
local inventory = {
    addCalls = 0,
    added = nil,
    fail = false,
    onAdd = nil,
}

function inventory.addInstance(instance)
    inventory.addCalls += 1
    inventory.added = instance
    if inventory.onAdd ~= nil then
        inventory.onAdd()
    end
    return not inventory.fail
end
```

Usar a factory shared real com um gerador determinista, para que os testes de
item desconhecido e quantidade invalida exercitem a mesma validacao usada no
runtime:

```lua
local function newFactory(): any
    local nextUid = 0
    return ItemInstanceFactory.new(function(): string
        nextUid += 1
        return string.format("pickup-%02d", nextUid)
    end)
end
```

Cada `beforeEach` deve criar um manager novo, inventory novo, factory nova e
personagem novo. Cada `afterEach` deve chamar `manager:stop()`, restaurar o
personagem original, destruir as fixtures e desconectar o sinal `collected`.

- [ ] **Step 3: Escrever os testes de registro**

Adicionar testes explicitos para:

```lua
it("registers an authored Part before collection", function()
    local pickup = makePartPickup("access_card", nil, true)
    manager:start()
    makeCharacter(pickup.Position)

    local result = manager:collect(pickup)
    expect(result.success).to.equal(true)
    expect(inventory.added.itemId).to.equal("access_card")
    expect(pickup.Parent).to.equal(nil)
end)

it("registers an authored Model from its tagged root", function()
    local pickup = makeModelPickup("handgun_ammo", 3)
    manager:start()
    makeCharacter(pickup:GetPivot().Position)

    expect(manager:collect(pickup).success).to.equal(true)
    expect(inventory.added.itemId).to.equal("handgun_ammo")
    expect(inventory.added.quantity).to.equal(3)
end)

it("does not create generated pickups", function()
    manager:start()
    expect(Workspace:FindFirstChild("Pickups")).to.equal(nil)
end)
```

Adicionar tambem testes para tag adicionada depois do `start()`, `start()`
repetido sem duplicar e `stop()` repetido sem erro. Um objeto `Door` tagueado
deve ser ignorado sem registro.

- [ ] **Step 4: Escrever os testes de validacao**

Cobrir sem alterar estado parcial:

- root que nao seja `BasePart` ou `Model`;
- root fora do `Workspace`;
- tag ausente;
- `InteractionType` ausente ou diferente de `Pickup`;
- `ItemId` ausente, vazio ou nao-string;
- `Quantity` zero, negativa, fracionaria ou nao numerica;
- item desconhecido;
- quantidade em item nao empilhavel;
- tag, tipo, `ItemId` ou `Quantity` alterados depois do registro;
- pickup removido do `Workspace` antes da coleta;
- personagem ausente ou sem `HumanoidRootPart`;
- personagem alem de 6 studs.

Cada caso deve afirmar o `reason`, que `inventory.addCalls` continua em zero e
que o objeto permanece no mapa quando a falha ocorre depois do registro.

- [ ] **Step 5: Escrever os testes de sucesso, falha e concorrencia**

Usar assertions de ordem observavel:

```lua
it("preserves the pickup when inventory insertion fails", function()
    local pickup = makePartPickup("access_card", nil, true)
    inventory.fail = true
    manager:start()
    makeCharacter(pickup.Position)

    local result = manager:collect(pickup)
    expect(result.reason).to.equal("inventory_failed")
    expect(pickup.Parent).to.equal(Workspace)
    expect(inventory.addCalls).to.equal(1)

    inventory.fail = false
    expect(manager:collect(pickup).success).to.equal(true)
end)

it("returns busy for a reentrant collection of the same pickup", function()
    local pickup = makePartPickup("access_card")
    makeCharacter(pickup.Position)
    manager:start()
    local nested: any = nil
    inventory.onAdd = function()
        nested = manager:collect(pickup)
    end

    expect(manager:collect(pickup).success).to.equal(true)
    expect(nested.reason).to.equal("busy")
    expect(inventory.addCalls).to.equal(1)
end)
```

Adicionar testes de lock isolado entre dois pickups, entre dois managers, de
prompt desabilitado, de destruicao antes do sinal local e de sinal local
disparado somente apos `addInstance` retornar sucesso. Testar tambem que trocar
`Players.LocalPlayer.Character` depois da coleta nao recria o pickup nem altera
o inventario.

- [ ] **Step 6: Rodar o spec antes de criar o manager**

Parar e iniciar o Play e executar o runner client. O novo spec deve falhar ao
carregar `PickupManager`, sem fallback para `PickupService`.

---

## Task 4: Implement `PickupManager`

**Goal:** Portar apenas o dominio authored do `PickupService` para um manager local, removendo spawn programatico e Player callbacks.

**Files:**

- Create: `src/client/pickups/PickupManager.luau`
- Use: `src/shared/inventory/ItemInstanceFactory.luau`
- Use: `src/client/inventory/InventoryController.luau`
- Use: `src/client/player/CharacterRoot.luau`
- Use: `src/shared/interactions/interactionTypes.luau`
- Use: `src/shared/inventory/items.luau`

**Interfaces:**

```lua
PickupManager.new({
    inventory = InventoryController,
    factory = factory,
}) -> PickupManager
```

- [ ] **Step 1: Criar o modulo estrito e os contratos**

Iniciar com `--!strict` e importar somente `CollectionService`, `Workspace`,
`ReplicatedStorage.Shared.interactions.interactionTypes`,
`ReplicatedStorage.Shared.inventory.items`, o contrato do
`InventoryController`, o contrato da factory e `CharacterRoot`.

Definir as constantes locais:

```lua
local MAX_DISTANCE = 6
```

Definir `RegisteredPickup`, `PickupFailure`, `PickupSuccess`, `PickupResult`,
`CollectedSignal` e `PickupManager` como contratos exportados ou locais conforme
o consumidor precisar. O resultado de sucesso deve exigir `itemId: string`.

- [ ] **Step 2: Validar dependencias no construtor**

`PickupManager.new` deve exigir uma tabela com `inventory.addInstance` e
`factory.create` callable. Falhas de construcao devem produzir uma mensagem
clara e nao criar um manager parcialmente funcional.

Criar em `new` as tabelas privadas `registered`, `busy`, as flags de lifecycle,
a conexao de tag e o `Signal.new()` de `collected`. Nao manter essas tabelas no
escopo compartilhado do modulo.

- [ ] **Step 3: Implementar validacao e registro authored**

Implementar helpers equivalentes a:

```lua
local function getPickupPosition(pickup: Instance): Vector3
    if pickup:IsA("BasePart") then
        return pickup.Position
    end
    return (pickup :: Model):GetPivot().Position
end

local function registerPickup(target: Instance): boolean
    if registered[target] ~= nil then
        return true
    end
    if not target:IsA("BasePart") and not target:IsA("Model") then
        return false
    end
    if not target:IsDescendantOf(Workspace)
        or not CollectionService:HasTag(target, interactionTypes.INTERACTABLE_TAG)
        or target:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE)
            ~= interactionTypes.PICKUP_TYPE
    then
        return false
    end
    local itemId = target:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE)
    local quantity = target:GetAttribute(interactionTypes.QUANTITY_ATTRIBUTE)
    if type(itemId) ~= "string" or itemId == "" then
        return false
    end
    if quantity ~= nil and type(quantity) ~= "number" then
        return false
    end
    local instance = dependencies.factory:create(itemId, nil, quantity :: number?)
    if instance == nil then
        return false
    end
    for _, descendant in target:GetDescendants() do
        if descendant:IsA("ProximityPrompt") then
            descendant.Enabled = false
        end
    end
    registered[target] = { instance = instance, itemId = itemId, quantity = quantity }
    return true
end
```

A implementacao concreta deve seguir estas regras:

- aceitar somente `BasePart` e `Model` descendentes de `Workspace`;
- exigir a tag `Interactable` e `InteractionType == "Pickup"`;
- rejeitar `ItemId` vazio ou nao-string;
- aceitar `Quantity` ausente ou number, deixando a factory validar stackability;
- criar a `ItemInstance` uma vez no registro e manter o UID no mapa privado;
- nao copiar atributos arbitrarios do pickup;
- desabilitar todos os prompts descendentes do root reconhecido;
- retornar sem duplicar quando `registered[target]` ja existir;
- deixar o mapa sem entrada parcial em qualquer falha.

- [ ] **Step 4: Implementar descoberta no lifecycle**

`start()` deve ser idempotente, marcar o manager como iniciado antes de conectar
callbacks, conectar `GetInstanceAddedSignal("Interactable")`, ignorar silenciosamente
tipos que nao sejam `Pickup` e percorrer `GetTagged("Interactable")` para os
objetos existentes.

O callback de tag deve chamar o registro somente quando o atributo de tipo for
`Pickup`. O mapa deve ter atributos configurados antes da tag; nao adicionar
listeners de mudanca de atributos nesta etapa.

`stop()` deve ser idempotente, desconectar a conexao de tag, limpar `registered`
e `busy` e preservar os objetos authored no `Workspace`. Nao criar conexoes de
`Players`, `CharacterAdded` ou tarefas de spawn.

- [ ] **Step 5: Implementar coleta e revalidacao**

Implementar `collect(pickup)` com a seguinte ordem exata:

```lua
local registeredPickup = registered[pickup]
if registeredPickup == nil then
    return { success = false, reason = "not_registered" }
end
-- revalidar Workspace, classe, tag, InteractionType, ItemId e Quantity
-- obter CharacterRoot.get() e validar distancia <= MAX_DISTANCE
if busy[pickup] then
    return { success = false, reason = "busy" }
end
busy[pickup] = true
local ok, added = pcall(function()
    return dependencies.inventory.addInstance(registeredPickup.instance)
end)
busy[pickup] = nil
if not ok or added ~= true then
    return { success = false, reason = "inventory_failed" }
end
registered[pickup] = nil
pickup:Destroy()
collected:Fire(registeredPickup.itemId)
return { success = true, itemId = registeredPickup.itemId }
```

O codigo real deve capturar `registeredPickup` antes de limpar o registro,
preservar o pickup em qualquer falha de inventario e usar `pcall` para impedir
que erro do controller quebre o lifecycle do manager. A posicao de `Model` deve
vir de `GetPivot().Position`; a de `BasePart`, de `Position`.

- [ ] **Step 6: Rodar os specs do manager**

Parar e iniciar o Play de testes novamente e executar o runner client. Confirmar
os testes de registro, revalidacao, distancia, prompt, lock, ordem de destruicao
e sinal local. Corrigir contratos e fixtures, nao relaxar assertions de
autoridade ou ignorar diagnosticos.

- [ ] **Step 7: Rodar lint e typecheck parcial**

Executar:

```bash
selene --config selene.roblox.toml src/client/pickups src/shared/inventory
selene --config selene.roblox-tests.toml tests/client/pickups tests/shared/inventory
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Verificar que o manager nao referencia `RemoteFunction`, `RemoteEvent`,
`Players.PlayerAdded`, `PickupService` ou a antiga pasta server-side.

---

## Task 5: Create `PickupInteraction`

**Goal:** Substituir o handler `PickupController` por um adapter pequeno que delega ao manager e publica o evento semantico.

**Files:**

- Create: `src/client/pickups/PickupInteraction.luau`
- Create: `tests/client/pickups/PickupInteraction.spec.luau`
- Delete after migration: `src/client/pickups/PickupController.luau`
- Delete after migration: `tests/client/pickups/PickupController.spec.luau`
- Use: `src/client/pickups/PickupManager.luau`
- Use: `src/client/events/GameplayEvents.luau`

**Interfaces:**

```lua
export type Dependencies = {
    manager: PickupManager.PickupManager,
}

PickupInteraction.new(dependencies) -> interactionTypes.InteractionHandler
```

- [ ] **Step 1: Criar o spec com fake de manager**

Usar um fake por fixture que registre chamadas e retorne resultados configuraveis:

```lua
local managerCalls = 0
local lastTarget: Instance? = nil
local managerResult: any = { success = true, itemId = "access_card" }
local manager = {
    collect = function(_self: any, target: Instance): any
        managerCalls += 1
        lastTarget = target
        return managerResult
    end,
}
```

Assinar `GameplayEvents.subscribe` em `beforeEach` e desconectar em `afterEach`.
Nao importar `InventoryController`, remotes ou `PickupNotificationController`
no spec.

- [ ] **Step 2: Escrever testes de delegacao e evento**

Adicionar testes com comportamento explicito:

```lua
it("delegates a Part to the manager", function()
    local part = Instance.new("Part")
    table.insert(fixtures, part)
    local interaction = PickupInteraction.new({ manager = manager })

    interaction.interact(part)

    expect(managerCalls).to.equal(1)
    expect(lastTarget).to.equal(part)
end)

it("publishes item_collected only after manager success", function()
    local part = Instance.new("Part")
    table.insert(fixtures, part)
    local interaction = PickupInteraction.new({ manager = manager })
    local events: { any } = {}
    local connection = GameplayEvents.subscribe(function(event)
        table.insert(events, event)
    end)

    interaction.interact(part)

    expect(events[1].name).to.equal("item_collected")
    expect(events[1].itemId).to.equal("access_card")
    connection:Disconnect()
end)
```

Cobrir Model, Folder ignorado, resultado de falha sem evento, ausencia de
acesso direto ao inventario e ausencia de criacao de ProximityPrompt.

- [ ] **Step 3: Rodar o spec antes da implementacao**

Executar o runner client no Studio. O spec deve falhar porque o novo modulo
nao existe. Nao adaptar o teste para chamar `CollectPickup`.

- [ ] **Step 4: Implementar o adapter**

Criar um modulo `--!strict` que importe somente `interactionTypes`,
`PickupManager` e `GameplayEvents`. A implementacao deve ser equivalente a:

```lua
local function createInteraction(dependencies: Dependencies): interactionTypes.InteractionHandler
    local interaction = {} :: interactionTypes.InteractionHandler

    function interaction.interact(target: Instance): ()
        if not target:IsA("BasePart") and not target:IsA("Model") then
            return
        end
        local result = dependencies.manager:collect(target)
        if result.success then
            GameplayEvents.emit({ name = "item_collected", itemId = result.itemId })
        end
    end

    return interaction
end
```

Nao adicionar estado, lifecycle, input, remote ou acesso direto ao inventario.

- [ ] **Step 5: Remover o handler antigo e rodar os testes**

Remover `PickupController.luau` e seu spec somente depois de todos os
consumidores planejados serem atualizados na Task 7. Nesta task, o nome novo
deve estar coberto por seu spec e passar no lint.

---

## Task 6: Adapt Local Pickup Notification

**Goal:** Trocar a origem remota da notificacao por uma fonte local injetada, preservando o hook e o tempo visual.

**Files:**

- Modify: `src/client/pickups/PickupNotificationController.luau`
- Modify: `tests/client/pickups/PickupNotification.spec.luau`
- Use: `src/client/pickups/PickupManager.luau`
- Preserve: `src/client/pickups/usePickupNotification.luau`

**Interfaces:**

```lua
export type Source = {
    Connect: (
        self: Source,
        callback: (itemId: string) -> ()
    ) -> SignalConnection,
}

export type Dependencies = {
    source: Source,
}

PickupNotificationController.start(dependencies)
PickupNotificationController.stop()
PickupNotificationController.changed
```

- [ ] **Step 1: Adaptar o spec para uma fonte fake local**

Remover a verificacao de `ReplicatedStorage.Remotes.PickupCollected` e criar
uma fonte fake que capture o callback e o disconnect:

```lua
local callback: ((string) -> ())? = nil
local disconnected = false
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
```

Iniciar com `PickupNotificationController.start({ source = source })`, disparar
`callback("medkit")` e afirmar que `changed` recebe o item. Preservar testes de
start/stop idempotentes, callback antigo invalidado e disconnect.

Usar IDs presentes no catalogo nos casos que representam itens do jogo; por
exemplo, trocar fixtures antigas com `iron_key` por `access_card`.

- [ ] **Step 2: Rodar o spec antes da alteracao do controller**

O spec deve falhar porque o controller ainda espera `PickupCollected` e
`start()` sem dependencias.

- [ ] **Step 3: Remover a dependencia de remotes**

Apagar import e variavel de `PickupCollected`. Alterar `start` para receber
`Dependencies`, conectar `dependencies.source:Connect` e encaminhar o item para
o sinal local `changed`.

Manter as garantias de lifecycle existentes:

- segunda chamada a `start` nao cria segunda conexao;
- `stop` invalida callback da sessao anterior;
- `stop` repetido nao gera erro;
- callbacks antigos nao atualizam `changed` depois de `stop`.

- [ ] **Step 4: Rodar notificacao e hooks**

Executar o spec adaptado e confirmar que `usePickupNotification.luau` nao
precisa de alteracao e que o timeout de dois segundos continua exclusivo do
hook, sem mover logica visual para o manager.

---

## Task 7: Compose The Client Runtime

**Goal:** Criar a composicao explicita do inventario, factory, manager, interaction e notificacao sem segundo binding.

**Files:**

- Modify: `src/client/init.client.luau`
- Use: `src/client/inventory/InventoryController.luau`
- Use: `src/shared/inventory/ItemInstanceFactory.luau`
- Use: `src/client/pickups/PickupManager.luau`
- Use: `src/client/pickups/PickupInteraction.luau`
- Use: `src/client/pickups/PickupNotificationController.luau`

**Interfaces:**

O bootstrap deve compor as instancias nesta ordem:

```lua
InventoryController.start()

local factory = ItemInstanceFactory.new(function(): string
    return HttpService:GenerateGUID(false)
end)

local pickupManager = PickupManager.new({
    inventory = InventoryController,
    factory = factory,
})
pickupManager:start()

local pickupInteraction = PickupInteraction.new({
    manager = pickupManager,
})

PickupNotificationController.start({
    source = pickupManager.collected,
})
```

- [ ] **Step 1: Atualizar imports do bootstrap**

Adicionar `HttpService` e os novos modulos. Remover `PickupController` e
`PickupEventBridge`. Manter `InventoryController.start()` antes de criar o
manager e manter a ordem ja aprovada de camera, tank, dialogo, porta,
objetivos e interacao.

- [ ] **Step 2: Compor factory, manager e interaction**

Inserir a composicao depois de iniciar `InventoryController` e antes do registro
dos handlers. O gerador de UID deve ser local e nao deve ser armazenado em um
service server-side.

- [ ] **Step 3: Registrar handlers no unico `InteractionController`**

Substituir o registro antigo por:

```lua
interactionController:register("Door", doorController)
interactionController:register("Pickup", pickupInteraction)
interactionController:register("Dialogue", dialogueInteractionController)
interactionController:start()
```

Nao criar `PickupInteraction.start`, `PickupInteraction.stop`, segundo
`ContextActionService` binding ou input proprio.

- [ ] **Step 4: Iniciar a notificacao com a fonte do manager**

Chamar `PickupNotificationController.start({ source = pickupManager.collected })`
uma vez. A UI sera renderizada depois, como ja ocorre hoje, e continuara lendo
o sinal exposto pelo controller de notificacao.

- [ ] **Step 5: Rodar lint e build do projeto normal**

Executar:

```bash
selene --config selene.roblox.toml src/client/init.client.luau src/client/inventory src/client/pickups
rojo build -o /tmp/dungeon-game-canve-client-inventory.rbxlx default.project.json
```

Inspecionar o build e confirmar que nao ha require de `PickupController`,
`PickupEventBridge`, `Shared.remotes` ou `CollectPickup` no client bootstrap.

---

## Task 8: Remove Obsolete Server Runtime And Remotes

**Goal:** Eliminar a autoridade server-side de inventario, pickups e uso de itens depois que nenhum consumidor restante depender dela.

**Files:**

- Modify: `src/server/init.server.luau`
- Delete: `src/server/inventory/InventoryService.luau`
- Delete: `src/server/pickups/PickupService.luau`
- Delete: `src/server/items/ItemUseService.luau`
- Delete: `src/server/items/ItemBehaviorRegistry.luau`
- Delete: `src/shared/remotes.luau`
- Delete: `src/client/events/PickupEventBridge.luau`
- Delete: `tests/server/pickups/PickupService.spec.luau`
- Delete: `tests/server/items/ItemUseService.spec.luau`
- Delete: `tests/server/items/ItemBehaviorRegistry.spec.luau`
- Delete: `tests/client/events/PickupEventBridge.spec.luau`
- Modify: `test.project.json`
- Modify: `README.md`

- [ ] **Step 1: Confirmir consumidores antes da remocao**

Pesquisar todos os scripts e docs relevantes:

```bash
git grep -n -E "PickupService|InventoryService|ItemUseService|ItemBehaviorRegistry|CollectPickup|PickupCollected|InventoryChanged|GetInventory|UseItem|PickupEventBridge|PickupController" -- src tests README.md test.project.json docs
```

Os unicos resultados esperados antes da limpeza devem ser os arquivos que serao
removidos, os testes que serao atualizados e a documentacao historica. Qualquer
uso operacional restante deve ser corrigido antes de apagar o modulo.

- [ ] **Step 2: Reduzir o bootstrap server-side**

Remover requires, criacao e binding de `InventoryService`, `ItemUseService`,
`ItemBehaviorRegistry`, `PickupService`, factory e `HttpService`. Manter somente
servicos ainda necessarios, por exemplo:

```lua
local CharacterLightService = require(script.player.CharacterLightService)

local characterLightService = CharacterLightService.new()
characterLightService:start()
```

Nao remover `CharacterLightService` sem uma dependencia concreta demonstrar que
ele tambem saiu do escopo.

- [ ] **Step 3: Remover os modulos server-side obsoletos**

Apagar os quatro services/registry indicados e os specs associados. O antigo
`InventoryStore` e a factory ja devem estar no shared pela Task 1 e nao devem
ser recriados no servidor.

- [ ] **Step 4: Remover remotes e bridge**

Apagar `src/shared/remotes.luau`, `PickupEventBridge.luau` e o spec do bridge.
Nao deixar um modulo de remotes vazio ou um alias de compatibilidade. Nenhuma
criacao de `ReplicatedStorage.Remotes` deve ocorrer pelo runtime migrado.

- [ ] **Step 5: Atualizar o projeto de testes**

Remover de `test.project.json` os mapeamentos de `Server.inventory`,
`Server.items` e `Server.pickups`. Manter `Server.player` e os roots client e
shared necessarios:

```json
"Server": {
  "$className": "Folder",
  "player": {
    "$path": "src/server/player"
  }
}
```

Nao mapear os entrypoints `init.server.luau` ou `init.client.luau` no projeto de
testes.

- [ ] **Step 6: Atualizar os caminhos oficiais do README**

No comando de typecheck do README, remover `src/server/inventory`,
`src/server/items` e `src/server/pickups`, mantendo `src/server/player` e os
roots shared/client. Atualizar tambem o texto que descreve o servidor como
autoridade do inventario.

- [ ] **Step 7: Rodar busca de referencias e build**

Executar:

```bash
git grep -n -E "PickupService|InventoryService|ItemUseService|ItemBehaviorRegistry|CollectPickup|PickupCollected|InventoryChanged|GetInventory|UseItem|PickupEventBridge|PickupController" -- src tests README.md test.project.json
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Os resultados operacionais devem ser zero, exceto nomes deliberadamente
mantidos em comentarios historicos fora de `src` e `tests`. Os dois builds
devem concluir sem referencia quebrada.

---

## Task 9: Update Architecture Documentation

**Goal:** Remover documentacao que descreve o fluxo server-authoritative anterior e registrar a arquitetura atual sem apagar historico util.

**Files:**

- Modify: `docs/inventory-architecture.md`
- Modify: `docs/superpowers/specs/2026-08-17-inventory-pickup-design.md`
- Modify: `docs/superpowers/plans/2026-08-22-pickup-interaction-migration-implementation.md`
- Modify: `docs/superpowers/specs/2026-08-22-generic-interaction-system-design.md`
- Modify: `docs/superpowers/specs/2026-08-22-objective-system-design.md`
- Preserve: `docs/superpowers/specs/2026-08-24-client-inventory-pickups-design.md`

- [ ] **Step 1: Atualizar `docs/inventory-architecture.md`**

Substituir a visao que apresenta `InventoryService`, `PickupService`,
`ItemUseService` e remotes como runtime ativo por uma visao com:

```text
InventoryController local
  -> InventoryStore shared
  -> estado vazio da sessao

PickupManager
  -> pickups authored
  -> InventoryController.addInstance
  -> sinal local collected

PickupInteraction
  -> GameplayEvents.item_collected
  -> ObjectiveController
```

Documentar que `DoorManager` consulta o inventario local, que nao ha save,
checkpoint ou persistencia entre sessoes nesta etapa e que a UI permanece sem
implementacao das acoes mock.

- [ ] **Step 2: Marcar designs e planos antigos como historicos**

Adicionar no topo de `2026-08-17-inventory-pickup-design.md` e do plano de
2026-08-22 uma nota explicita de que a autoridade server-side e os remotes
descritos foram supersedidos por
`2026-08-24-client-inventory-pickups-design.md`. Preservar o texto para
referencia historica, mas nao deixa-lo parecer a arquitetura ativa.

- [ ] **Step 3: Atualizar integracao de interacao e objetivos**

Em `2026-08-22-generic-interaction-system-design.md`, remover o fluxo de
`CollectPickup`/`PickupService` como arquitetura atual e descrever
`PickupInteraction` + `PickupManager`. Em
`2026-08-22-objective-system-design.md`, substituir a origem
`PickupCollected.OnClientEvent` por `GameplayEvents.emit` vindo do
`PickupInteraction`.

- [ ] **Step 4: Procurar referencias obsoletas nos docs**

Executar:

```bash
git grep -n -E "autoridade server-side|PickupService|InventoryService|ItemUseService|ItemBehaviorRegistry|CollectPickup|PickupCollected|InventoryChanged|GetInventory|UseItem|PickupEventBridge" -- docs README.md
```

Cada ocorrencia deve ser removida, atualizada para o fluxo local ou marcada
explicitamente como historica. Nao alterar docs nao relacionados a esta
migracao.

---

## Task 10: Full Static And Studio Verification

**Goal:** Confirmar que os contratos client-side, a remocao server-side, o projeto de testes e o fluxo integrado funcionam juntos.

**Files:**

- Verify: todos os arquivos das Tasks 1-9
- Do not modify: `Packages/`, `DevPackages/`, arquivos preexistentes nao relacionados

- [ ] **Step 1: Executar lint completo**

Executar exatamente:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Corrigir diagnosticos nos contratos reais. Nao adicionar suppression para
silenciar incompatibilidade de tipo ou import.

- [ ] **Step 2: Gerar sourcemap e executar typecheck Roblox**

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
  src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Nao incluir `src/server/inventory`, `src/server/items` ou `src/server/pickups`.
Nao incluir os entrypoints normais. Corrigir imports `script` e contratos do
DataModel de acordo com o sourcemap real.

- [ ] **Step 3: Construir os dois projetos Rojo**

Executar:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Confirmar nos builds que existem `InventoryController`, `PickupManager`,
`PickupInteraction`, `InventoryStore` shared e `ItemInstanceFactory` shared,
sem `PickupService`, `InventoryService`, `ItemUseService`,
`ItemBehaviorRegistry` ou `PickupEventBridge`.

- [ ] **Step 4: Rodar o Play limpo no projeto de testes**

Servir ou sincronizar `test.project.json` na sessao Studio `RE Like Test`,
parar o Play atual, iniciar um Play limpo e aguardar `TestEZAutoServer` e
`TestEZAutoClient`.

Confirmar:

- resultado server com `failed == 0` para os servicos que permanecem;
- resultado client com `failed == 0`;
- specs shared de store e factory executados no root correto;
- specs client de inventario, manager, interaction e notificacao executados;
- nenhuma suite removida aparece como skipped sem motivo de mapeamento.

Se for necessario rerun, executar os runners explicitos:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Parar o Play ao fim da rodada e confirmar que fixtures, personagens, tags,
sinais e conexoes foram liberados.

- [ ] **Step 5: Repetir a suite em uma segunda sessao limpa**

Parar e iniciar novamente o Play, rodar os dois runners e confirmar novamente
`failed == 0`. A segunda sessao deve iniciar com inventario vazio, demonstrando
que nao existe estado compartilhado entre sessoes do cliente.

- [ ] **Step 6: Verificar manualmente o fluxo no projeto normal**

Usar somente pickups authored e portas authored existentes no mapa; nao criar
fixture programatica de substituicao. Confirmar:

- inventario inicia vazio;
- `F` diante de um pickup authored coleta `Part` ou `Model` valido;
- o item aparece em `useInventory` e a notificacao local aparece;
- `item_collected` chega ao `ObjectiveController`;
- pickup coletado e destruido;
- prompt authored nao inicia coleta;
- falha de inventario preserva o pickup e permite nova tentativa;
- respawn preserva inventario e nao recria pickup coletado;
- porta consulta item local, desbloqueia sem consumir a chave e atravessa no fluxo existente;
- nenhuma operacao de inventario chama `UseItem` ou qualquer remote;
- nenhum `ReplicatedStorage.Remotes` de inventario/pickup/uso e criado pelo runtime.

- [ ] **Step 7: Fazer verificacao final de referencias e worktree**

Executar:

```bash
git grep -n -E "PickupService|InventoryService|ItemUseService|ItemBehaviorRegistry|CollectPickup|PickupCollected|InventoryChanged|GetInventory|UseItem|PickupEventBridge|PickupController" -- src tests README.md test.project.json
git diff --check
git status --short
```

O grep nao deve encontrar referencias operacionais obsoletas. O `status` deve
mostrar somente alteracoes intencionais, incluindo a spec e este plano. Nao
executar staging ou commit.

## Acceptance Checklist

- [ ] `InventoryController` possui estado local vazio por sessao.
- [ ] O estado local sobrevive a respawn e e limpo em nova sessao.
- [ ] `InventoryStore` e `ItemInstanceFactory` estao no root shared.
- [ ] `PickupManager` processa somente pickups authored.
- [ ] Nenhum pickup e gerado por definicao ou automaticamente.
- [ ] `PickupManager` possui lifecycle idempotente e lock privado por pickup.
- [ ] Falha de inventario preserva pickup e libera lock.
- [ ] Sucesso adiciona item, destrui pickup e dispara sinal local na ordem correta.
- [ ] `PickupInteraction` delega sem conhecer detalhes de inventario.
- [ ] `PickupInteraction` publica `item_collected` somente em sucesso.
- [ ] `PickupNotificationController` usa fonte local injetada.
- [ ] `PickupEventBridge` nao existe mais.
- [ ] `DoorManager` continua usando `InventoryController:getState()` local.
- [ ] `ItemUseService` e `ItemBehaviorRegistry` foram removidos, nao migrados.
- [ ] Nenhum remote de inventario, pickup ou uso e criado ou utilizado.
- [ ] `App.luau` e as acoes mock da UI permanecem inalteradas.
- [ ] O servidor continua somente com servicos ainda necessarios.
- [ ] Specs, lint, typecheck, builds e duas sessoes Play passam.
- [ ] Spec e plano foram criados sem commits ou staging.
