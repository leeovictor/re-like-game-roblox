# Design: Pickup de Itens no Inventario

> **Historico:** este design descreve a autoridade server-side original. Foi
> supersedido por `2026-08-24-client-inventory-pickups-design.md`; o runtime
> atual usa `InventoryController` e `PickupManager` no cliente.

Data: 2026-08-17  
Status: Aprovado pelo usuario para especificacao

## Objetivo

Adicionar pickups authored pelo mapa que possam ser coletados por meio de
`ProximityPrompt` e inseridos no inventario autoritativo do servidor.

O pickup nao define comportamento de uso. Ele cria uma instancia independente
com `uid`, `itemId`, `quantity` opcional e `attributes` opcionais. O catalogo
compartilhado valida o `itemId`, enquanto efeitos de uso pertencem ao
`ItemBehaviorRegistry` e aos behaviors server-side.

O servidor atual nao possui definicoes authored de pickups. Por isso, a
composicao inicia `PickupService` com uma lista vazia ate que o mapa forneca
definicoes validas. Nenhum seed demonstrativo e criado pelo runtime.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Interacao | `ProximityPrompt` nativo do Roblox |
| Autoridade | O servidor valida e aplica cada coleta |
| Compartilhamento | Um conjunto global por servidor, visivel a todos os jogadores |
| Definicoes | Authored pelo mapa e recebidas por `PickupService.new` |
| Momento do spawn | Uma vez, quando o primeiro personagem carregado estiver disponivel |
| Posicao | Aleatoria em um raio horizontal aproximado de 30 studs ao redor do primeiro jogador |
| Persistencia | Fluxo existente de `PlayerRemoving`; sem save por pickup |
| Identidade | Cada instancia recebe `uid` pela factory server-side |
| Quantidade | `quantity` apenas para itens stackable; validada pela factory |
| Atributos | Valores authored escalares (`string`, `number`, `boolean`) |
| Respawn | Fora de escopo |
| Uso, descarte e trade | Fora de escopo neste design |

## Arquitetura

```text
src/shared/inventory/catalog.luau
  definicoes declarativas e capacidades, sem funcoes

src/shared/inventory/items.luau
  ItemInstance, InventoryState schema 2 e contratos de uso

src/server/inventory/InventoryStore.luau
  validacao, copia e mutacoes imutaveis de instancias

src/server/inventory/InventoryService.luau
  estado por jogador, persistencia e snapshots InventoryChanged

src/server/items/ItemInstanceFactory.luau
  cria uid, itemId, quantity e atributos validados

src/server/items/ItemBehaviorRegistry.luau
  registra behaviors server-side por capability

src/server/items/ItemUseService.luau
  resolve instancia por capability/itemUid e aplica uso atomico

src/server/pickups/PickupService.luau
  spawn authored, ProximityPrompt e coleta server-side

src/server/init.server.luau
  compoe persistence, inventario, registry, uso e pickups

src/client/inventory/InventoryController.luau
  recebe snapshots, sem possuir estado autoritativo

src/client/ui/App.luau
  renderiza o snapshot existente, sem redesign nesta etapa
```

### `PickupService`

O servico e criado no servidor com uma referencia ao `InventoryService`, uma
`ItemInstanceFactory` e uma lista de definicoes authored pelo mapa. Ele tem uma
operacao `start()` idempotente e mantem estado privado que impede o spawn mais
de uma vez.

Cada definicao contem:

```lua
{
    itemId = "...",
    quantity = 1, -- opcional, somente para itens stackable
    attributes = { ... }, -- opcional, valores escalares authored
}
```

Quando o mapa nao fornece uma visual especifica para um item, o servico usa
uma visual neutra default. A visual nao participa da validade da definicao nem
do schema persistido; portanto, uma definicao authored valida pode ser
spawnada sem exigir um registro de cor/material e sem criar seeds implicitos.

O servico valida a definicao pela factory e pelo catalogo antes de criar a
Part. A Part e ancorada, sem colisao, recebe o atributo `ItemId` e um
`ProximityPrompt`. O `uid` nao vem do cliente e nao e usado como fonte de
autoridade no cliente.

As posicoes usam offsets horizontais dentro de um raio aproximado de 30 studs
do primeiro personagem carregado. Nao ha validacao de salas, raycast de chao,
navegacao ou integracao com geracao de dungeon.

O mapa pode fornecer cores e materiais por extensao do servico, mas esses
detalhes nao pertencem ao catalogo nem ao schema persistido. Na composicao
atual, a lista e vazia para evitar inventar loot.

### `InventoryService`

O servico expoe mutacoes server-side de instancias, incluindo:

```lua
addInstance(player: Player, instance: ItemInstance): boolean
```

Ele rejeita jogadores sem estado carregado, aplica a mutacao pelo
`InventoryStore`, armazena uma nova estrutura e dispara `InventoryChanged` com
uma copia do snapshot. O `PickupService` nao acessa o estado privado.

O schema persistido atual e versionado como:

```lua
export type InventoryState = {
    version: number, -- atualmente 2
    items: { ItemInstance },
    equipped: { [string]: string },
}
```

Cada item tem a forma:

```lua
export type ItemInstance = {
    uid: string,
    itemId: string,
    quantity: number?,
    attributes: { [string]: string | number | boolean }?,
}
```

Nao existe compatibilidade com schema 1 nem conversao de listas de IDs. O
catalogo continua declarativo e nao contem funcoes.

### `ItemUseService`

O cliente envia apenas um pedido de uso por `UseItem`. O servidor valida
capability, contexto, `itemUid` quando presente e a instancia encontrada no
inventario. O behavior registrado server-side decide o resultado e as
mutacoes. O payload do cliente nao define valores de efeito.

O contrato de `behavior.use` nesta arquitetura e produzir apenas um
`ItemBehaviorResult` com dados de efeito e mutacoes declaradas. Ele nao deve
mutar `HealthService`, combate, portas ou qualquer outro dominio externo antes
da confirmacao das mutacoes transacionais do inventario. Esses dominios e seus
behaviors concretos permanecem fora de escopo; nenhum handler falso e
registrado no runtime.

O servico revalida a instancia antes do uso e usa lock por jogador para impedir
duplo consumo concorrente. Falhas nao aplicam mutacoes; sucesso atualiza o
snapshot por `InventoryChanged`.

## Fluxo de coleta

```text
Jogador aproxima-se da Part
  -> ProximityPrompt.Triggered(player) no servidor
  -> PickupService usa a instancia criada pela factory
  -> trava local do pickup e desabilita o prompt
  -> InventoryService:addInstance(player, instance)
       -> false: jogador nao carregado ou instancia invalida
       -> true: snapshot schema 2 armazenado e InventoryChanged disparado
  -> sucesso: Part destruida e notificacao existente enviada
  -> falha: prompt reabilitado e pickup preservado
```

O `itemId`, `uid`, quantidade e atributos sao authored pelo servidor. Nenhum
RemoteEvent de pickup e necessario.

## Tratamento de erros e limites

- Jogador cujo inventario ainda esta carregando nao coleta o item.
- Definicao com item desconhecido, quantidade invalida ou atributos invalidos nao cria pickup.
- A Part so e destruida depois que o inventario confirma a insercao.
- O prompt e desativado durante a tentativa para impedir concorrencia local.
- Nao ha limite de distancia adicional alem do `MaxActivationDistance` do prompt.
- Nao ha save imediato; o save continua no fluxo de `PlayerRemoving`.
- Nao ha reposicao automatica quando um pickup e coletado.
- Entradas existentes em `Workspace.Pickups` nao sao fonte de estado.
- A lista authored vazia atual significa que nenhum pickup e criado ate o mapa fornecer definicoes.

## Testes e verificacao

Testes puros cobrem `InventoryStore`, `ItemInstanceFactory`, registry e

Verificacoes Roblox:

- `selene --config selene.roblox.toml src`
- typecheck Roblox com sourcemap e definicoes versionadas
- `rojo build -o /tmp/dungeon-game-canve.rbxlx`
- teste no Studio com um servidor e multiplos jogadores

O Studio deve validar, quando houver definicoes authored, a coleta server-side,
replica de `uid`, `itemId`, `quantity` e atributos, preservacao em falha,
revalidacao de uso, atualizacao de `InventoryChanged` e bloqueio de duas
solicitacoes simultaneas. Essa validacao nao substitui os testes puros.

## Fora de escopo

- seeds demonstrativos ou loot implicito no runtime;
- pickups por jogador;
- respawn ou reposicao de itens;
- posicionamento garantidamente livre de paredes ou integrado a salas;
- geracao de loot baseada em seed da dungeon;
- limite de slots ou peso;
- agrupamento visual e contadores de stack;
- implementacao de portas, HealthService ou combate;
- efeitos de uso concretos ainda nao fornecidos por sistemas de gameplay;
- redesign visual de `App.luau`;
- save por mudanca, autosave ou session lock;
- efeitos, sons e animacoes especiais de coleta.
