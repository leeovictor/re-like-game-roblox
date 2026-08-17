# Arquitetura de Instâncias e Uso de Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evoluir o inventário de uma lista de `ItemId`s para instâncias authored pelo mapa, pilhas de items e uso server-side orientado por capacidades.

**Architecture:** O servidor será autoritativo sobre `InventoryState`, instâncias e resultados de uso. `ItemDefinition` compartilhada declara capacidades; `ItemInstance` guarda `uid`, atributos e quantidade; `ItemUseService` consulta handlers server-side e coordena mutações do inventário, enquanto sistemas de vida, combate e portas permanecem externos.

**Tech Stack:** Luau strict, Roblox server/client, Rojo, Lune 0.10.4, testes puros no Lune, `RemoteFunction`/`RemoteEvent`, persistência existente em memória/DataStore.

## Global Constraints

- Mantenha `--!strict` nos módulos Luau e não use `--!nocheck`, ignores amplos ou `typeErrors: false`.
- O servidor é a autoridade para posse, atributos, quantidades, capacidades e resultados de uso.
- `src/shared` é mapeado para `ReplicatedStorage.Shared`, `src/server` para `ServerScriptService.Server` e `src/client` para `StarterPlayer.StarterPlayerScripts.Client`.
- Mantenha imports baseados em `script` próprios do Roblox nos módulos de `src/`.
- Não edite `Packages/`; ele é gerado pelo Wally.
- Não implemente portas, vida, combate, animações, sons ou redesign da UI nesta mudança.
- `torch`, `ration` e `crystal` são fixtures demonstrativas e não devem permanecer como seed ou configuração final de gameplay.
- O schema novo deve começar diretamente no formato de instâncias; não criar migração específica para os items demonstrativos.
- Testes Lune rodam com `lune run test` e não simulam um jogo Roblox completo.
- Verificações Roblox usam `selene --config selene.roblox.toml src`, sourcemap/typecheck e `rojo build -o /tmp/dungeon-game-canve.rbxlx`.

---

## Mapa de arquivos

| Arquivo | Responsabilidade após a implementação |
|---|---|
| `src/shared/inventory/items.luau` | Tipos compartilhados, catálogo, categorias e capacidades estáticas |
| `src/shared/remotes.luau` | `InventoryChanged`, `GetInventory`, `PickupCollected` e `UseItem` |
| `src/server/inventory/InventoryStore.luau` | Estado puro, cópia, validação, pilhas e serialização schema `2` |
| `src/server/inventory/InventoryService.luau` | Estado por jogador, persistência, mutações e snapshots |
| `src/server/items/ItemInstanceFactory.luau` | Criação server-side de instâncias authored |
| `src/server/items/ItemBehaviorRegistry.luau` | Registro e lookup de handlers por capacidade |
| `src/server/items/ItemUseService.luau` | Busca, validação, lock por jogador, execução e resultado |
| `src/server/pickups/PickupService.luau` | Transferência de uma instância do mundo ao inventário |
| `src/server/init.server.luau` | Composição de InventoryService, registry, ItemUseService e pickups |
| `src/client/inventory/InventoryController.luau` | Snapshot local e solicitação de uso por `uid` |
| `tests/server/inventory/InventoryStore.spec.luau` | Schema, pilhas, instâncias e validações puras |
| `tests/server/items/ItemInstanceFactory.spec.luau` | Factory e atributos authored |
| `tests/server/items/ItemBehaviorRegistry.spec.luau` | Registro, lookup e duplicidade de capacidades |
| `tests/server/items/ItemUseService.spec.luau` | Uso, compatibilidade, falhas e concorrência com doubles |
| `tests/client/inventory/InventoryController.spec.luau` | Contrato de solicitação, se isolável pelo loader |

## Convenções entre tasks

Todas as tasks devem preservar os nomes abaixo. Se uma implementação precisar
de uma mudança, atualize primeiro as interfaces desta seção e as tasks seguintes.

```lua
export type ItemId = string
export type ItemAttribute = string | number | boolean
export type ItemAttributes = { [string]: ItemAttribute }

export type ItemDefinition = {
    id: ItemId,
    name: string,
    category: string,
    stackable: boolean,
    capabilities: { string },
}

export type ItemInstance = {
    uid: string,
    itemId: ItemId,
    quantity: number?,
    attributes: ItemAttributes?,
}

export type InventoryState = {
    version: number,
    items: { ItemInstance },
    equipped: { [string]: string },
}

export type UseContext = { [string]: ItemAttribute }

export type UseRequest = {
    capability: string,
    context: UseContext,
    itemUid: string?,
}

export type UseResult = {
    success: boolean,
    reason: string?,
    itemUid: string?,
    consumed: boolean?,
    effect: { [string]: ItemAttribute }?,
}
```

O `UseContext` deve conter somente dados de contexto serializáveis, como
`target = "self"`, `targetId = "north-door"` e `weaponUid = "handgun-007"`.
Não colocar `Instance`, `Player` ou funções no payload remoto.

---

### Task 1: Modelo compartilhado de definições e instâncias

**Arquivos:**
- Modificar: `src/shared/inventory/items.luau`
- Testar: `tests/server/inventory/InventoryStore.spec.luau` com os tipos carregados pelo loader

**Interfaces:**
- Produz: `ItemDefinition`, `ItemInstance`, `ItemAttributes`, `InventoryState`, `UseContext`, `UseRequest` e `UseResult` com os nomes da seção de convenções.
- Produz: catálogo indexado por `ItemId`, com `stackable` e `capabilities` estáticos.
- Não produz: handlers, efeitos ou estado de jogador no módulo compartilhado.

- [ ] **Step 1: Escrever testes que expressem o schema final**

Adicionar casos ao spec existente que construam estados com:

```lua
local state = {
    version = 2,
    items = {
        {
            uid = "handgun-001",
            itemId = "handgun",
            attributes = { damage = 18, loadedAmmo = 5 },
        },
        {
            uid = "ammo-001",
            itemId = "handgun_ammo",
            quantity = 24,
        },
    },
    equipped = { weapon = "handgun-001" },
}
```

Verificar que o catálogo de teste contém definições com capacidades `heal`,
`equip`, `reload-ammo` e `unlock`, sem depender de `torch`, `ration` ou
`crystal` como comportamento de produção.

- [ ] **Step 2: Rodar o teste para confirmar a falha do schema atual**

Run: `lune run test`

Expected: FAIL nos casos que esperam `version = 2`, objetos `ItemInstance`,
`quantity`, `attributes` e `equipped`.

- [ ] **Step 3: Implementar os tipos e o catálogo estático**

Atualizar `items.luau` com as exportações da seção de convenções. Manter o
catálogo como tabela `{ [ItemId]: ItemDefinition }`. Nenhuma definição deve
conter `function`, referência Roblox ou atributo de uma instância específica.

Retirar os items demonstrativos de `defaultInventory`. Manter a função para
retornar o estado inicial vazio enquanto o catálogo final não existir, usando
`version = 2`, `items = {}` e `equipped = {}`.

- [ ] **Step 4: Rodar os testes e o typecheck compartilhado**

Run: `lune run test`

Expected: PASS nos testes de construção do schema; testes antigos que dependem
de `version = 1` devem ser atualizados para o schema `2`, não acomodados com
compatibilidade de runtime.

Run: `selene --config selene.roblox.toml src`

Expected: PASS sem diagnósticos no módulo compartilhado.

---

### Task 2: InventoryStore para instâncias, pilhas e schema `2`

**Arquivos:**
- Modificar: `src/server/inventory/InventoryStore.luau`
- Modificar: `tests/server/inventory/InventoryStore.spec.luau`

**Interfaces:**
- Consome: tipos e catálogo da Task 1.
- Produz: `defaultInventory() -> InventoryState`, `copyState(state) -> InventoryState`, `addInstance`, `addQuantity`, `findInstance`, `removeInstance`, `removeQuantity`, `updateAttributes`, `equip`, `serialize` e `deserialize`.
- Produz: schema persistido determinístico `version = 2`.

- [ ] **Step 1: Adicionar testes vermelhos para cópia, instâncias e equipamento**

Adicionar casos com nomes explícitos:

```lua
"creates an empty version two inventory"
"adds an individual instance without mutating the source"
"finds an instance by uid"
"removes only the requested instance"
"updates instance attributes without sharing tables"
"equips a known uid in a slot"
"rejects an unknown equipped uid"
```

Cada teste deve verificar que o estado original permanece inalterado e que
`attributes`/`equipped` também são copiados, não apenas `items`.

- [ ] **Step 2: Rodar os testes unitários focados**

Run: `lune run test`

Expected: FAIL nas novas operações ausentes ou incompatíveis.

- [ ] **Step 3: Implementar cópia profunda e mutações puras**

Implementar cópia de `InventoryState`, `ItemInstance`, `attributes` e
`equipped`. Cada mutação deve retornar uma nova tabela de estado.

Regras:

- `uid` deve ser único dentro de `state.items`;
- `itemId` deve existir em `items`;
- item não empilhável não aceita `quantity` diferente de `nil`/`1`;
- item empilhável sem atributos variáveis usa `quantity` positiva;
- `removeQuantity` rejeita quantidade menor ou igual a zero e quantidade maior que a pilha;
- quantidade zero remove a pilha somente quando a operação calcula o novo estado;
- `updateAttributes` só altera uma instância existente;
- `equip` exige que o `uid` exista e que a definição seja equipável por convenção do handler/capacidade.

- [ ] **Step 4: Adicionar testes vermelhos para pilhas e regras de atributos**

Adicionar casos:

```lua
"adds quantity to an existing compatible stack"
"creates a new stack when no compatible stack exists"
"rejects negative and zero quantities"
"removes a stack when its quantity reaches zero"
"does not merge individual instances"
"does not merge stacks with different authored attributes"
"preserves weapon loadedAmmo during an unrelated mutation"
```

- [ ] **Step 5: Implementar regras de pilha e atualização de instância**

Fazer `addQuantity` procurar somente stacks do mesmo `itemId` sem atributos
variáveis na primeira versão. Fazer `removeQuantity` retornar um novo estado
com a quantidade ajustada ou sem a pilha quando chegar a zero.

Adicionar `updateAttributes(state, uid, attributes)` com cópia completa do mapa
de atributos. Não permitir que o chamador mutile a tabela recebida depois da
operação.

- [ ] **Step 6: Adicionar testes vermelhos para serialização JSON schema `2`**

Verificar uma string determinística com a forma:

```json
{"version":2,"items":[{"attributes":{"damage":18,"loadedAmmo":5},"itemId":"handgun","uid":"handgun-001"},{"itemId":"handgun_ammo","quantity":24,"uid":"ammo-001"}],"equipped":{"weapon":"handgun-001"}}
```

Também testar:

```lua
"round-trips string number and boolean attributes"
"round-trips equipped slots"
"sorts attribute and equipped keys deterministically"
"rejects missing uid"
"rejects duplicate uid"
"rejects unknown itemId"
"rejects invalid quantity"
"rejects malformed attributes"
"rejects equipped references to missing instances"
```

- [ ] **Step 7: Implementar parser/serializer schema `2`**

Estender o parser atual para reconhecer `true` e `false`, mantendo strings,
números, arrays e objetos. Serializar campos em ordem fixa:

```text
state: version, items, equipped
instance: attributes, itemId, quantity, uid
attributes/equipped: chaves ordenadas lexicograficamente
```

Omitir `quantity` e `attributes` quando forem `nil`, em vez de serializar
`null`. Validar completamente o objeto antes de retornar `InventoryState`.

- [ ] **Step 8: Rodar o ciclo completo da store**

Run: `lune run test`

Expected: PASS em todos os testes de `InventoryStore` e persistência existente.

Run: `selene --config selene.lune.toml tests lune`

Expected: PASS sem diagnósticos.

---

### Task 3: InventoryService autoritativo para o novo estado

**Arquivos:**
- Modificar: `src/server/inventory/InventoryService.luau`
- Modificar: `src/server/inventory/persistence/MemoryPersistence.luau` se o seed ainda assumir IDs
- Modificar: `tests/server/inventory/MemoryPersistence.spec.luau`
- Modificar: `tests/server/inventory/InventoryStore.spec.luau` somente se o contrato de persistence exigir fixture nova

**Interfaces:**
- Consome: operações puras da Task 2.
- Produz: métodos server-side `addInstance`, `addQuantity`, `find`, `removeInstance`, `removeQuantity`, `updateAttributes`, `equip` e `getSnapshot`.
- Mantém: `InventoryChanged` e `GetInventory` com `InventoryState` schema `2`.

- [ ] **Step 1: Atualizar testes de persistence para o estado vazio schema `2`**

Verificar que o primeiro acesso retorna um estado independente com:

```lua
{ version = 2, items = {}, equipped = {} }
```

Verificar que `save` e `load` preservam instâncias, atributos, quantidade e
equipamento sem compartilhar tabelas.

- [ ] **Step 2: Atualizar os tipos internos do serviço**

Substituir `items: { string }` por `items: { ItemInstance }` e adicionar
`equipped`. Fazer `copyState` delegar a cópia profunda do `InventoryStore`.

- [ ] **Step 3: Implementar métodos públicos delegando ao InventoryStore**

Cada método deve:

1. retornar falha se o jogador ainda não estiver carregado;
2. chamar uma mutação pura;
3. rejeitar `nil`/estado inválido;
4. armazenar o novo estado;
5. disparar `InventoryChanged` com uma cópia;
6. retornar sucesso.

Não expor `loadedStates[player]` nem uma referência mutável interna.

- [ ] **Step 4: Atualizar o load/save e remover seed demonstrativa**

Fazer `defaultInventory()` retornar o estado vazio final enquanto o catálogo de
gameplay ainda não estiver definido. Preservar retries, kick após falha de load e
save best-effort existentes.

- [ ] **Step 5: Rodar testes de inventário e persistence**

Run: `lune run test`

Expected: PASS nos testes de `InventoryStore`, `MemoryPersistence` e nos testes
existentes que exercitam o contrato de load/save.

---

### Task 4: Factory de instâncias e pickup authored pelo mapa

**Arquivos:**
- Criar: `src/server/items/ItemInstanceFactory.luau`
- Criar: `tests/server/items/ItemInstanceFactory.spec.luau`
- Modificar: `src/server/pickups/PickupService.luau`
- Modificar: `tests/client/pickups/PickupNotification.spec.luau` somente se o payload mudar

**Interfaces:**
- Produz: `ItemInstanceFactory.new(uidGenerator) -> Factory` e `factory:create(itemId, attributes?, quantity?) -> ItemInstance?`.
- Consome: `InventoryService:addInstance(player, instance) -> boolean`.
- `PickupService.new(inventoryService, factory, definitions?)` aceita definições de instância do mundo sem receber instâncias do cliente.

- [ ] **Step 1: Escrever testes da factory**

Adicionar casos:

```lua
"creates a unique individual instance"
"preserves authored numeric string and boolean attributes"
"creates a positive stack quantity for stackable items"
"rejects unknown item ids"
"rejects quantity for non-stackable items"
"rejects non-positive quantity"
"returns independent attribute tables"
```

Injetar um gerador determinístico de UID no teste para esperar IDs concretos sem
depender de `HttpService` ou aleatoriedade.

- [ ] **Step 2: Rodar o spec da factory para confirmar a falha**

Run: `lune run test`

Expected: FAIL porque o módulo e a factory ainda não existem.

- [ ] **Step 3: Implementar a factory sem APIs Roblox**

Receber uma função geradora de UID no construtor ou no argumento de criação. A
factory deve validar catálogo, quantidade e tipos primitivos, copiar atributos e
retornar uma instância nova.

Não permitir que o cliente forneça `uid`; o servidor sempre o gera.

- [ ] **Step 4: Atualizar o PickupService para transferir instâncias**

Trocar `inventoryService:addItem(player, itemId)` por
`inventoryService:addInstance(player, instance)`. Cada definição de pickup deve
conter `itemId`, `attributes` e `quantity` opcionais. Criar a instância uma vez
no servidor ao spawnar o pickup e fechar essa instância no callback do prompt.

Manter a trava local, destruir a Part somente após sucesso e disparar
`PickupCollected` usando o `itemId` da instância.

Não manter os 30 pickups demonstrativos como configuração final. O serviço deve
aceitar definições fornecidas pela composição do servidor, permitindo que o
mapa final substitua as fixtures.

- [ ] **Step 5: Rodar testes e lint Roblox**

Run: `lune run test`

Expected: PASS nos testes puros da factory e nos testes existentes.

Run: `selene --config selene.roblox.toml src`

Expected: PASS sem erros de tipos ou nomes antigos como `addItem`.

---

### Task 5: Registry de capacidades e contrato dos handlers

**Arquivos:**
- Criar: `src/server/items/ItemBehaviorRegistry.luau`
- Criar: `tests/server/items/ItemBehaviorRegistry.spec.luau`

**Interfaces:**
- Produz: `ItemBehaviorRegistry.new()`.
- Produz: `registry:register(capability, behavior) -> boolean`.
- Produz: `registry:get(capability) -> ItemBehavior?`.
- Produz: `ItemBehavior.canUse(player, instance, context) -> (boolean, string?)`.
- Produz: `ItemBehavior.use(player, instance, context) -> ItemBehaviorResult`.

Usar um resultado interno explícito para que o `ItemUseService` saiba quais
alterações de inventário confirmar:

```lua
export type ItemBehaviorResult = {
    success: boolean,
    reason: string?,
    consumeInstance: boolean?,
    consumeQuantity: number?,
    updateAttributes: ItemAttributes?,
    equipSlot: string?,
    effect: { [string]: ItemAttribute }?,
}
```

Quando `updateAttributes` existir, ele representa o mapa completo de atributos
resultante da instância. O handler deve copiar os atributos que não mudaram,
como `damage` e `magazineSize`, antes de retornar a atualização de
`loadedAmmo`.

- [ ] **Step 1: Escrever testes do registry**

Adicionar casos:

```lua
"registers and retrieves a behavior"
"rejects an empty capability"
"rejects duplicate registration"
"returns nil for an unknown capability"
"keeps behavior identity without mutating it"
```

- [ ] **Step 2: Rodar o spec do registry para confirmar a falha**

Run: `lune run test`

Expected: FAIL porque o registry ainda não existe.

- [ ] **Step 3: Implementar o registry**

Usar tabela privada por capacidade. Validar nome não vazio, rejeitar
duplicidade e retornar `nil` para lookup desconhecido. O registry não deve
conhecer `InventoryService`, `Player` ou o catálogo internamente.

- [ ] **Step 4: Adicionar um fake behavior reutilizável nos testes**

Criar no spec um handler que:

- retorna `false, "not_compatible"` quando `context.target` não é `"self"`;
- retorna sucesso com `consumeInstance = true` e `effect.amount = 25` quando é compatível.

Esse fake será usado novamente na Task 6 para testar o orquestrador sem
implementar HealthService, WeaponService ou portas.

- [ ] **Step 5: Rodar testes e lint Lune/Roblox**

Run: `lune run test`

Expected: PASS nos testes do registry.

Run: `selene --config selene.lune.toml tests lune`

Expected: PASS sem diagnósticos.

---

### Task 6: ItemUseService server-side

**Arquivos:**
- Criar: `src/server/items/ItemUseService.luau`
- Criar: `tests/server/items/ItemUseService.spec.luau`
- Modificar: `src/server/inventory/InventoryService.luau` somente para expor mutações necessárias à confirmação do resultado

**Interfaces:**
- Consome: `InventoryService`, `ItemBehaviorRegistry`, catálogo e `UseRequest`.
- Produz: `ItemUseService.new(inventoryService, registry) -> Service`.
- Produz: `service:findCompatibleItem(player, request) -> ItemInstance?`.
- Produz: `service:use(player, request) -> UseResult`.
- Produz: binding server-side do `UseItem.OnServerInvoke` para a Task 7.

- [ ] **Step 1: Criar doubles puros para jogador, inventário e behaviors**

No spec, representar um jogador como uma tabela com `UserId`/nome mínimo e usar
um fake `InventoryService` com estado por jogador. O fake deve contar chamadas de
`removeInstance`, `removeQuantity`, `updateAttributes` e `equip`.

- [ ] **Step 2: Escrever testes vermelhos de busca e uso**

Adicionar casos:

```lua
"finds the first compatible instance by capability and context"
"does not mutate inventory during compatibility lookup"
"uses the requested uid when it is compatible"
"rejects a requested uid owned by another player"
"rejects an unknown capability"
"returns the handler reason when context is incompatible"
"consumes an individual instance after behavior success"
"reduces a stack by the behavior requested quantity"
"updates instance attributes after behavior success"
"equips the requested uid in the returned mutation"
"does not mutate inventory after behavior failure"
```

- [ ] **Step 3: Rodar o spec focado para confirmar a falha**

Run: `lune run test`

Expected: FAIL porque `ItemUseService` ainda não existe.

- [ ] **Step 4: Implementar `findCompatibleItem`**

Implementar o fluxo:

1. obter snapshot do jogador;
2. se `itemUid` existir, avaliar somente essa instância;
3. caso contrário, iterar instâncias em ordem estável;
4. filtrar definições que contenham `request.capability`;
5. buscar o handler no registry;
6. chamar `canUse` sem mutação;
7. retornar a primeira instância compatível.

Não interpretar `itemId` com condicionais específicas no orquestrador.

- [ ] **Step 5: Implementar `use` com lock por jogador**

O lock deve ser uma tabela privada `busy[player]`. Se já estiver ativo, retornar
`{ success = false, reason = "operation_in_progress" }` sem chamar o handler.

Dentro do lock:

1. obter a instância atual;
2. revalidar capacidade e contexto;
3. chamar `behavior.use`;
4. se falhar, retornar a razão sem mutação;
5. aplicar `consumeInstance`, `consumeQuantity`, `updateAttributes` ou `equip`;
6. retornar `UseResult` com `itemUid`, `consumed` e `effect`;
7. liberar o lock em todos os caminhos, inclusive erro protegido.

As mutações devem ocorrer somente depois do resultado de sucesso do behavior.
Se uma mutação previamente validada falhar, retornar `mutation_failed` e não
emitir feedback de sucesso; os testes devem cobrir esse caminho.

- [ ] **Step 6: Adicionar testes de concorrência e autoridade**

Verificar que:

```lua
"two uses of the same uid cannot both consume it"
"client healAmount in context is ignored"
"a stale compatibility result is revalidated by use"
"a failed domain behavior leaves the original state intact"
```

- [ ] **Step 7: Rodar toda a suíte server-side**

Run: `lune run test`

Expected: PASS nos specs de store, persistence, factory, registry e use service.

Run: `selene --config selene.lune.toml tests lune`

Expected: PASS sem diagnósticos.

---

### Task 7: RemoteFunction e controller de uso no cliente

**Arquivos:**
- Modificar: `src/shared/remotes.luau`
- Modificar: `src/server/items/ItemUseService.luau`
- Modificar: `src/server/init.server.luau`
- Modificar: `src/client/inventory/InventoryController.luau`
- Testar: `InventoryController` por typecheck Roblox e Studio; não criar um spec Lune que simule `RemoteFunction`

**Interfaces:**
- Produz: `Remotes.UseItem: RemoteFunction`.
- Produz no servidor: `UseItem.OnServerInvoke(player, request) -> UseResult`.
- Produz no cliente: `InventoryController.use(request) -> UseResult`.
- Mantém: `getState`, `changed`, `start` e `stop` existentes.

- [ ] **Step 1: Adicionar o contrato remoto**

Em `src/shared/remotes.luau`, garantir `UseItem` como `RemoteFunction` no mesmo
folder de `InventoryChanged` e `GetInventory`. Não criar um remote separado para
cada capacidade.

- [ ] **Step 2: Definir o request produzido pelo controller**

O controller deve encaminhar uma tabela com esta forma:

```lua
{
    itemUid = "medkit-001",
    capability = "heal",
    context = { target = "self" },
}
```

Verificar no typecheck e na inspeção do código que o controller não inclui
`healAmount`, vida nova ou outras informações calculadas pelo cliente. O
contrato remoto será exercitado na validação de Studio da Task 8, sem mockar
`RemoteFunction` no Lune.

- [ ] **Step 3: Bindar o remote no servidor**

Expor em `ItemUseService` uma função de binding ou configurar no

```lua
remotes.UseItem.OnServerInvoke = function(player, request)
    return itemUseService:use(player, request)
end
```

Validar o formato básico do payload antes de encaminhar ao serviço e retornar
uma falha estável para payloads que não sejam tabela, não tenham `capability` ou
tenham contexto não serializável.

- [ ] **Step 4: Adicionar `InventoryController.use`**

Implementar uma função que invoque `UseItem:InvokeServer(request)` e retorne o
`UseResult`. O controller não deve alterar o snapshot local otimisticamente; a
mudança de estado chega por `InventoryChanged`.

Enquanto uma UI futura aguarda o resultado, ela deve desabilitar seu botão para
evitar requests duplicados. Esse estado de pending não precisa entrar no
snapshot persistido.

- [ ] **Step 5: Rodar testes e typecheck Roblox**

Run: `lune run test`

Expected: PASS nos testes que podem ser executados sem APIs Roblox reais.

Run: `selene --config selene.roblox.toml src`

Expected: PASS sem diagnósticos.

Run: `rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json`

Run: `luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap sourcemap.json --formatter gnu src`

Expected: PASS sem erros de tipos ou imports.

---

### Task 8: Composição, integração e verificação final

**Arquivos:**
- Modificar: `src/server/init.server.luau`
- Modificar: `src/server/pickups/PickupService.luau` somente para composição final das definições
- Modificar: `README.md` somente se comandos ou limites novos precisarem ser documentados
- Testar: todos os arquivos em `tests/`

**Interfaces:**
- Consome: serviços e contratos das Tasks 1-7.
- Produz: servidor iniciado com InventoryService, ItemBehaviorRegistry, ItemUseService e PickupService ligados sem dependências cíclicas.

- [ ] **Step 1: Compor os serviços no init do servidor**

Manter a seleção existente de `MemoryPersistence` no Studio e

```text
persistence
  -> InventoryService
  -> ItemBehaviorRegistry
  -> registrar behaviors disponíveis
  -> ItemUseService
  -> bindar UseItem
  -> iniciar InventoryService
  -> iniciar PickupService com definições do mapa
```

Não registrar handlers de portas, vida ou combate nesta task. Se um behavior
concreto ainda não existir, usar somente fakes em testes, não adicionar efeito
falso ao runtime.

- [ ] **Step 2: Rodar todos os testes Lune**

Run: `lune run test`

Expected: PASS em toda a suíte sem depender de `workspace`, `Humanoid` ou
`Terrain` reais.

- [ ] **Step 3: Rodar os dois lints**

Run: `selene --config selene.roblox.toml src`

Expected: PASS.

Run: `selene --config selene.lune.toml tests lune`

Expected: PASS.

- [ ] **Step 4: Rodar os dois typechecks**

Run:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

Run:

```bash
luau-lsp analyze --platform standard \
  --base-luaurc typecheck/lune.luaurc --formatter gnu tests lune
```

Expected: PASS sem diagnósticos em ambas as plataformas.

- [ ] **Step 5: Construir o DataModel com Rojo**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx`

Expected: arquivo `.rbxlx` criado sem erro e com `UseItem`/módulos novos
resolvidos no sourcemap.

- [ ] **Step 6: Validar o fluxo no Roblox Studio**

Executar um servidor Studio e confirmar:

```text
pickup server-side com atributos -> instância no inventário
snapshot replica uid, itemId, quantity e atributos
UI futura poderia selecionar uid e chamar UseItem
payload com healAmount adulterado não altera o resultado
falha de uso preserva o item
uso bem-sucedido atualiza InventoryChanged
duas solicitações simultâneas não duplicam o consumo
```

Não usar a validação de Studio para substituir testes puros de Store, Registry
ou ItemUseService.

- [ ] **Step 7: Fazer revisão final contra a especificação**

Conferir explicitamente que o resultado não adicionou:

```text
implementação de portas
implementação de HealthService
implementação de combate
redesign de App.luau
compatibilidade com o seed demonstrativo
funções dentro de ItemDefinition
autoridade de estado no cliente
```

Também verificar que o documento de design continua coerente com os nomes dos
módulos e contratos implementados.

## Verificação do plano contra a especificação

- Instâncias com `uid`, atributos e quantidade: Tasks 1-4.
- Capacidades declarativas sem funções no catálogo: Tasks 1 e 5.
- `InventoryStore` puro e schema versionado: Task 2.
- Estado por jogador e snapshots autoritativos: Task 3.
- Pickup authored pelo mapa: Task 4.
- Registry e handlers server-side: Task 5.
- Busca por contexto e uso com `itemUid`: Task 6.
- Lock, revalidação e razões de falha: Task 6.
- Fluxo remoto para UI sem estado otimista: Task 7.
- Persistência, lint, typecheck, build e Studio: Tasks 3 e 8.
- Portas, vida, combate e UI visual fora do escopo: Global Constraints e Task 8.

Não há placeholders de implementação no plano; cada task define arquivos,
interfaces, testes, comando de execução e resultado esperado.
