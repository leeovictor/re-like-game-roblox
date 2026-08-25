# Design: Inventario e Pickups Client-Side

Data: 2026-08-24  
Status: Aprovado para especificacao  
Escopo: inventario local, pickups authored e remocao do uso generico de itens

## Objetivo

Migrar o estado de inventario e o dominio de pickups da autoridade server-side
para o cliente, mantendo o jogo funcional durante uma unica sessao local.

O inventario sera volatil: inicia vazio em uma nova sessao do cliente, continua
disponivel durante respawns e e perdido quando a sessao termina. Nao havera save,
checkpoint ou restauracao nesta etapa. Uma futura solucao de checkpoints podera
reutilizar a logica pura de estado sem reintroduzir a autoridade atual do
servidor.

O trabalho tambem removera o mecanismo generico de uso de itens. `ItemUseService`,
`ItemBehaviorRegistry` e o remote `UseItem` nao serao migrados para o cliente.
Operacoes como usar, consumir, equipar e descartar itens permanecem fora deste
escopo, mesmo que a UI ainda exiba as acoes mock existentes.

## Decisoes Aprovadas

| Tema | Decisao |
|---|---|
| Autoridade | Cliente, adequada ao jogo single-player atual |
| Persistencia | Somente memoria da sessao atual |
| Respawn | Inventario permanece; pickups coletados nao reaparecem |
| Pickups | Somente pickups authored pelo mapa |
| Pickups gerados | Fora do escopo; sera criada outra abordagem futuramente |
| Handler | `PickupInteraction` |
| Dominio | `PickupManager` |
| Inventario | `InventoryController` local |
| Eventos | `PickupInteraction` publica `item_collected` |
| Notificacao | Usa um sinal local, sem `RemoteEvent` |
| Uso generico | Removido, nao migrado |
| UI | Nao sera alterada; acoes mock permanecem |
| Servidor | Mantem somente servicos ainda necessarios, como `CharacterLightService` |
| Commits | A spec e o plano serao criados sem commits |

Esta arquitetura nao e uma fronteira de seguranca para multiplayer ou experiencias
competitivas. O cliente podera alterar o proprio estado local, o que e aceitavel
para o objetivo atual.

## Contexto Atual

O repositorio ja possui a migracao das portas para o cliente:

- `DoorManager` valida portas, consulta `InventoryController:getState()` e altera
  `Locked` localmente;
- `DoorController` coordena interacao, dialogo, transicao e eventos;
- `InteractionController` e o unico dono do binding de `F`;
- `InventoryController` ainda recebe snapshots do servidor;
- `PickupController` atual e apenas um handler que chama `CollectPickup`;
- `PickupService` server-side registra pickups, cria instancias e altera o
  `InventoryService`;
- `PickupNotificationController` e `PickupEventBridge` escutam
  `PickupCollected`;
- `InventoryStore` e `ItemInstanceFactory` estao sob caminhos server-side;
- `ItemUseService` e `ItemBehaviorRegistry` existem apenas no servidor e nao
  possuem behaviors concretos registrados no runtime.

O contrato de autoria dos pickups sera preservado:

```text
PickupRoot [tag: Interactable]
|- InteractionType: "Pickup"
|- ItemId: string nao vazia
`- Quantity: number opcional
```

O root pode ser um `BasePart` ou um `Model` descendente de `Workspace`. Prompts
existentes nao serao usados para coletar itens e permanecerao desabilitados.

## Arquitetura Resultante

```text
src/shared/inventory/InventoryStore.luau
  Logica pura de estado, validacao, copia e mutacoes de inventario.

src/shared/inventory/ItemInstanceFactory.luau
  Cria ItemInstance usando um gerador de UID fornecido pela composicao.

src/client/inventory/InventoryController.luau
  Mantem o estado local da sessao e publica snapshots por Signal.

src/client/pickups/PickupManager.luau
  Descobre e registra pickups authored, valida coleta e altera o inventario.

src/client/pickups/PickupInteraction.luau
  Handler do InteractionController; delega a coleta e publica eventos.

src/client/pickups/PickupNotificationController.luau
  Traduz o sinal local de coleta para o estado usado pela UI.

src/client/events/GameplayEvents.luau
  Recebe item_collected para o sistema de objetivos.

src/client/init.client.luau
  Cria o inventario, factory, manager, handler e conexao da notificacao.
```

### `InventoryStore`

`InventoryStore` sera movido para `src/shared/inventory/InventoryStore.luau`.
Ele e logica pura e nao deve depender de servicos Roblox. As operacoes existentes
de copia, validacao, adicao, remocao, quantidade, atributos e equipar serao
preservadas para evitar perder contratos ja testados. A disponibilidade dessas
funcoes puras nao significa que a UI ou o controller implementarao uso, consumo,
equipar ou descarte nesta migracao.

`defaultInventory()` continuara retornando:

```lua
{
    version = 2,
    items = {},
    equipped = {},
}
```

O store continuara rejeitando item desconhecido, UID vazio ou repetido,
quantidades invalidas, atributos invalidos e estados inconsistentes. As
mutacoes continuarao imutaveis: cada sucesso retorna uma nova estrutura sem
alterar o estado de entrada.

### `ItemInstanceFactory`

`ItemInstanceFactory` sera movida para `src/shared/inventory/ItemInstanceFactory.luau`.
O modulo continuara recebendo um `uidGenerator` em `new()` e validando item,
quantidade, atributos e unicidade de UID.

O composition root client-side criara a factory com:

```lua
HttpService:GenerateGUID(false)
```

O UID continua sendo uma identidade da instancia durante a sessao. Ele nao sera
tratado como mecanismo de persistencia ou seguranca.

### `InventoryController`

O controller deixara de receber snapshots e passara a possuir o estado local.
Seu contrato sera:

```lua
export type InventoryController = {
    start: () -> (),
    stop: () -> (),
    getState: () -> items.InventoryState?,
    addInstance: (instance: items.ItemInstance) -> boolean,
    changed: typeof(changed),
}
```

Comportamento:

- `start()` e idempotente e inicia um inventario vazio;
- `getState()` retorna o snapshot local atual;
- `addInstance()` chama `InventoryStore.addInstance()`;
- uma adicao valida substitui o estado e dispara `changed`;
- uma adicao invalida preserva o estado e nao dispara `changed`;
- `stop()` limpa o estado local;
- um novo `start()` inicia uma sessao vazia;
- o controller nao importa `remotes`, `Players` ou services server-side;
- o campo `equipped` permanece no schema para compatibilidade com a UI e futuras
  operacoes, sem implementar equipar agora.

O modulo continuara sendo usado como instancia operacional composta no bootstrap
client-side, conforme o padrao existente no projeto. O estado nao sera criado
por personagem e nao sera reinicializado durante respawn.

## `PickupManager`

`PickupManager` sera o dono do dominio de pickups authored. Ele nao conhecera
`GameplayEvents`, React, dialogo ou `ContextActionService`.

### Construcao

```lua
export type Dependencies = {
    inventory: InventoryController.InventoryController,
    factory: ItemInstanceFactory.Factory,
}

PickupManager.new({
    inventory = InventoryController,
    factory = factory,
})
```

O manager criara estado privado por instancia:

```lua
type RegisteredPickup = {
    instance: items.ItemInstance,
    itemId: string,
    quantity: number?,
}

registered: { [Instance]: RegisteredPickup }
busy: { [Instance]: boolean }
```

Tambem exposara um sinal local de coleta:

```lua
type CollectedSignal = {
    Connect: (
        self: CollectedSignal,
        callback: (itemId: string) -> ()
    ) -> SignalConnection,
}
```

O sinal sera disparado somente depois de a instancia ser adicionada ao
inventario e o pickup ser destruido.

### Lifecycle

O contrato sera:

```lua
export type PickupManager = {
    start: (self: PickupManager) -> (),
    stop: (self: PickupManager) -> (),
    collect: (self: PickupManager, pickup: Instance) -> PickupResult,
    collected: CollectedSignal,
}
```

`start()`:

1. retorna sem efeito se ja estiver iniciado;
2. conecta `CollectionService:GetInstanceAddedSignal("Interactable")`;
3. percorre `CollectionService:GetTagged("Interactable")`;
4. registra somente roots com `InteractionType == "Pickup"`;
5. desabilita os prompts dos pickups validos.

O mapa deve configurar atributos e parentear o objeto antes de adicionar a tag.
Objetos parcialmente configurados serao ignorados e receberao warning quando
apropriado. Nenhuma definicao de spawn, raio aleatorio, `pendingGenerated` ou
criacoes automaticas sera mantida.

`stop()` desconecta a escuta de tag, limpa os registros e os locks, mas nao
destroi objetos authored do mapa. O manager nao sera reiniciado em respawn.

### Registro

O registro aceitara somente:

- `BasePart` ou `Model`;
- descendente de `Workspace`;
- tag `Interactable`;
- `InteractionType == "Pickup"`;
- `ItemId` string nao vazia;
- `Quantity` ausente ou numerica.

Para um root valido, o manager chamara `factory:create(itemId, nil, quantity)` e
armazenara a instancia criada no registro. A factory rejeitara item desconhecido,
quantidade zero, negativa, fracionaria, nao numerica, ou quantidade em item nao
empilhavel. Falhas nao deixam registro parcial.

Todos os `ProximityPrompt`s descendentes de um pickup reconhecido receberao
`Enabled = false`. Nenhuma conexao com `Triggered` sera criada.

### Coleta

`collect(pickup)` seguira esta ordem:

1. procurar o pickup no registro;
2. retornar `not_registered` quando ausente;
3. revalidar parent no `Workspace`, classe, tag e `InteractionType`;
4. revalidar igualdade de `ItemId` e `Quantity` com o registro;
5. obter `CharacterRoot.get()`;
6. retornar `invalid_pickup` quando o personagem ou root nao existir;
7. calcular a posicao do `BasePart` ou do pivot do `Model`;
8. retornar `too_far` quando a distancia ao root exceder 6 studs;
9. retornar `busy` quando o mesmo pickup ja estiver em coleta;
10. marcar `busy[pickup] = true`;
11. chamar `inventory:addInstance(registeredPickup.instance)` em `pcall`;
12. liberar o lock em todos os caminhos;
13. retornar `inventory_failed` e preservar o pickup em falha;
14. remover o registro e destruir o pickup em sucesso;
15. disparar `collected:Fire(itemId)`;
16. retornar sucesso com `itemId`.

O resultado sera equivalente a:

```lua
type PickupFailure = {
    success: false,
    reason: "invalid_pickup"
        | "not_registered"
        | "too_far"
        | "busy"
        | "inventory_failed",
}

type PickupSuccess = {
    success: true,
    itemId: string,
}

type PickupResult = PickupFailure | PickupSuccess
```

O lock e o registro sao locais e servem apenas para impedir duplicacao e
reentrancia no cliente. Eles nao oferecem protecao contra manipulacao local.

## `PickupInteraction`

O antigo `PickupController` sera substituido por `PickupInteraction`. Este
modulo sera um handler compativel com `interactionTypes.InteractionHandler`.

```lua
export type Dependencies = {
    manager: PickupManager.PickupManager,
}
```

`interact(target)`:

- ignora qualquer target que nao seja `BasePart` ou `Model`;
- chama `manager:collect(target)`;
- nao acessa `InventoryController` diretamente;
- nao cria prompts;
- nao conhece `InventoryStore` ou `ItemInstanceFactory`;
- nao emite evento quando a coleta falha;
- em sucesso, chama:

```lua
GameplayEvents.emit({
    name = "item_collected",
    itemId = result.itemId,
})
```

Esse evento sera emitido pelo handler, e nao pelo `InventoryController`, para
que uma adicao futura por checkpoint ou outro sistema nao seja interpretada
automaticamente como uma coleta de mapa.

`PickupInteraction` nao tera `start()` ou `stop()`, pois nao criara conexoes.
O lifecycle pertence ao `PickupManager`.

## Notificacao Local

`PickupNotificationController` deixara de acessar `remotes.PickupCollected`.
Sua API de inicio recebera uma fonte local, conceitualmente:

```lua
PickupNotificationController.start({
    source = pickupManager.collected,
})
```

O controller continuara expondo o sinal `changed` usado por
`usePickupNotification`. O timeout de dois segundos e o cancelamento de
notificacoes antigas permanecem sem alteracao funcional.

O controller de notificacao continuara responsavel somente por converter o
evento de coleta em estado da UI. Ele nao alterara inventario e nao publicara
eventos de objetivos.

`PickupEventBridge` sera removido porque nao existira mais um evento remoto para
adaptar. O fluxo de objetivos recebera `item_collected` diretamente do
`PickupInteraction`.

## Composicao Client-Side

O `src/client/init.client.luau` preservara os sistemas existentes de camera,
dialogo, portas, objetivos e interacao. A composicao de inventario e pickups
seguira esta ordem:

1. iniciar `InventoryController`;
2. criar a factory com `HttpService:GenerateGUID(false)`;
3. criar `PickupManager` com inventario e factory;
4. iniciar `PickupManager`;
5. criar `PickupInteraction` com o manager;
6. iniciar `PickupNotificationController` com `manager.collected`;
7. registrar `PickupInteraction` para o tipo `"Pickup"`;
8. iniciar o unico `InteractionController`.

O `DoorManager` continuara recebendo `InventoryController` e nao sera alterado
alem de ajustes de tipos ou imports causados pela migracao. A porta continuara
consultando o snapshot local, preservando item de unlock e alterando `Locked`
somente na copia client-side.

Nenhum segundo binding de `F` sera criado.

## Remocao Server-Side

Serao removidos do runtime:

- `src/server/pickups/PickupService.luau`;
- `src/server/inventory/InventoryService.luau`;
- `src/server/items/ItemUseService.luau`;
- `src/server/items/ItemBehaviorRegistry.luau`;
- `src/shared/remotes.luau` e os remotes de inventario/pickup/uso;
- `src/client/events/PickupEventBridge.luau`.

`src/server/init.server.luau` permanecera somente com servicos ainda necessarios,
incluindo `CharacterLightService` enquanto ele continuar fazendo parte do jogo.

`default.project.json` continuara mapeando `src/server` de forma ampla; a remocao
dos arquivos server-side sera suficiente para o projeto normal. O
`test.project.json` deixara de mapear subdiretorios server-side removidos e
passara a consumir os modulos puros pelo root shared.

Nenhuma fixture programatica de pickup sera criada para substituir os pickups
gerados que estao sendo removidos.

## UI

`src/client/ui/App.luau` e os componentes React nao serao modificados. Acoes
mock como `usar`, `equipar` e `descartar` continuarao aparecendo exatamente como
estao hoje, mesmo sem uma implementacao de uso de itens.

Nenhuma spec de UI sera criada.

## Testes

### Testes Shared

Mover `InventoryStore.spec.luau` e `ItemInstanceFactory.spec.luau` para roots
shared correspondentes, ajustando apenas imports e mapeamento. Preservar a
cobertura existente de validacao, copia imutavel, stacks, atributos, equipar e
UIDs.

### `InventoryController`

Criar `tests/client/inventory/InventoryController.spec.luau` para cobrir:

- estado vazio no inicio;
- `start()` idempotente;
- `getState()` local;
- adicao valida e atualizacao do snapshot;
- `changed` disparado somente em sucesso;
- adicao invalida sem mutacao;
- `stop()` limpando o estado;
- novo `start()` criando estado vazio;
- ausencia de remote no caminho local.

Cada fixture deve parar o controller e desconectar sinais em `afterEach`.

### `PickupManager`

Criar `tests/client/pickups/PickupManager.spec.luau` para cobrir:

- registro de `Part` e `Model` authored;
- registro de tag adicionado depois do `start()`;
- `start()` e `stop()` idempotentes;
- rejeicao de classe, parent, tag ou interaction type invalidos;
- rejeicao de `ItemId` e `Quantity` invalidos;
- prompts authored desabilitados;
- revalidacao no momento da coleta;
- ausencia de personagem ou root;
- distancia excessiva;
- `busy` em reentrada;
- isolamento do lock entre pickups e entre managers;
- uso da instancia produzida pela factory;
- preservacao do pickup em falha do inventario;
- destruicao somente apos sucesso;
- emissao do sinal local somente apos sucesso;
- ausencia de spawn por definicoes;
- pickup destruido permanecendo ausente depois de respawn;
- manager e inventario sobrevivendo a troca do personagem.

As fixtures devem configurar atributos antes da tag, parentear no `Workspace`,
restaurar `Players.LocalPlayer.Character` e destruir todas as instances em
`afterEach`.

### `PickupInteraction`

Criar `tests/client/pickups/PickupInteraction.spec.luau` para cobrir:

- ignorar targets nao coletaveis;
- delegar o target correto ao manager;
- nao acessar inventario diretamente;
- nao criar prompt;
- nao emitir evento quando o manager falhar;
- emitir `item_collected` somente em sucesso;
- nao duplicar eventos para targets invalidos.

### Notificacao

Adaptar `PickupNotification.spec.luau` para uma fonte local fake. Preservar o
contrato do sinal `changed`, o timeout, o lifecycle idempotente e o cancelamento
de conexoes. Remover `PickupEventBridge.spec.luau`.

### Server

Remover specs que dependem de `InventoryService`, `PickupService`,
`ItemUseService` ou `ItemBehaviorRegistry`. O runner server continuara cobrindo
somente os servicos server-side que permanecerem no projeto.

## Verificacao

Depois da implementacao, executar:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
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
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

No Roblox Studio, executar Play limpo com o projeto de testes e confirmar:

- `failed == 0` nos runners client e server;
- inventario iniciando vazio;
- pickup authored sendo coletado por `F`;
- item aparecendo no inventario local;
- notificacao sendo exibida pelo sinal local;
- objetivo recebendo `item_collected`;
- pickup desaparecendo depois da coleta;
- inventario e ausencia do pickup sobrevivendo a respawn;
- porta usando o item local para unlock;
- nenhum remote de inventario, pickup ou uso sendo criado;
- server iniciando sem os services removidos.

As alteracoes serao sincronizadas no Studio conforme o fluxo do repositorio. A
spec e o plano de implementacao serao apenas arquivos no worktree; nenhum
`git commit`, `git add` ou outra operacao de staging sera executada.

## Criterios de Aceitacao

- `PickupManager` e `PickupInteraction` possuem responsabilidades separadas.
- `PickupInteraction` e o unico handler de `"Pickup"` no binding generico.
- `PickupManager` processa somente pickups authored pelo mapa.
- Nao existe spawn automatico ou API de definitions nesta migracao.
- O inventario e local, inicia vazio e sobrevive ao respawn.
- Itens coletados nao reaparecem durante a sessao.
- `DoorManager` usa o inventario local sem `ItemUseService`.
- `ItemUseService` e `ItemBehaviorRegistry` nao sao migrados.
- `UseItem`, `CollectPickup`, `PickupCollected`, `InventoryChanged` e
  `GetInventory` nao sao utilizados nem criados pelo runtime.
- `PickupEventBridge` e removido.
- `PickupInteraction` publica `item_collected` somente apos sucesso.
- A notificacao funciona por evento local.
- A UI permanece inalterada.
- O servidor permanece somente com os servicos ainda necessarios.
- Nao ha persistencia entre sessoes, save ou checkpoint.
- Specs, lint, typecheck, builds e verificacao no Studio passam.
