# Design: Pickup de Itens no Inventário

Data: 2026-08-17  
Status: Aprovado pelo usuário para especificação

## Objetivo

Adicionar pickups compartilhados ao mundo que possam ser coletados por meio de
`ProximityPrompt` e inseridos no inventário autoritativo do servidor.

Ao iniciar um servidor, serão criados 30 pickups próximos ao primeiro jogador
que tiver o personagem carregado: 10 tochas (`torch`), 10 rações (`ration`) e
10 cristais (`crystal`). Os pickups serão compartilhados por todos os jogadores
da mesma sessão. Cada pickup poderá ser coletado uma única vez e não haverá
respawn nesta etapa.

O inventário existente já replica snapshots por `InventoryChanged` e a UI já
usa `useInventory()`. Portanto, uma coleta bem-sucedida atualizará a lista
existente sem exigir um novo contrato de cliente.

## Decisões aprovadas

| Tema | Decisão |
|---|---|
| Interação | `ProximityPrompt` nativo do Roblox |
| Autoridade | O servidor valida e aplica cada coleta |
| Compartilhamento | Um conjunto global por servidor, visível a todos os jogadores |
| Quantidade inicial | 30 pickups: 10 `torch`, 10 `ration`, 10 `crystal` |
| Momento do spawn | Uma vez, quando o primeiro personagem carregado estiver disponível |
| Posição | Aleatória em um raio horizontal aproximado de 30 studs ao redor do primeiro jogador |
| Persistência | Fluxo existente de `PlayerRemoving`; sem save por pickup |
| Capacidade | Sem limite de inventário |
| Representação | Cada coleta adiciona uma nova entrada de `itemId` à lista |
| Respawn | Fora de escopo |
| Uso, descarte e trade | Fora de escopo |

## Arquitetura

```text
src/shared/inventory/items.luau
  catálogo e tipos existentes

src/server/inventory/InventoryStore.luau
  validação e cópia da mutação de inventário

src/server/inventory/InventoryService.luau
  estado autoritativo, addItem e InventoryChanged

src/server/pickups/PickupService.luau
  spawn compartilhado, ProximityPrompt e coleta

src/server/init.server.luau
  inicia InventoryService e PickupService

src/client/inventory/InventoryController.luau
  recebe o snapshot já existente

src/client/ui/App.luau
  lista já existente, atualizada pelo snapshot
```

### `PickupService`

O serviço será criado no servidor e receberá uma referência ao
`InventoryService`. Ele terá uma operação `start()` idempotente e manterá o
estado privado que impede o spawn mais de uma vez.

O serviço aguardará um personagem válido, obterá seu `HumanoidRootPart` e
criará uma pasta `Workspace.Pickups`. Cada pickup será uma `Part` ancorada,
sem colisão, com um atributo `ItemId` e um `ProximityPrompt`.

As posições serão geradas com offsets horizontais aleatórios dentro de um
raio aproximado de 30 studs do centro escolhido. A primeira versão não fará
validação de salas, raycast de chão, navegação ou integração com o grid da
dungeon. Isso mantém o spawner independente do `WorldGenerator`.

As aparências serão distintas por tipo usando uma tabela local no serviço. O
catálogo compartilhado continuará sendo a fonte de validade dos IDs, enquanto
cor, material e tamanho serão detalhes visuais do mundo.

### `InventoryService`

O serviço ganhará uma operação server-side equivalente a:

```lua
addItem(player: Player, itemId: string): boolean
```

Ela deverá:

- rejeitar jogadores que ainda não tenham estado carregado;
- rejeitar IDs ausentes no catálogo compartilhado;
- criar uma nova tabela de itens em vez de mutar um snapshot compartilhado;
- atualizar o estado privado do jogador;
- disparar `InventoryChanged` com uma cópia do novo estado;
- retornar `true` apenas quando a inserção for concluída.

O `PickupService` não acessará diretamente o mapa privado de estados. Ele
chamará somente essa operação do serviço de inventário.

## Fluxo de coleta

```text
Jogador aproxima-se da Part
  -> ProximityPrompt.Triggered(player) no servidor
  -> PickupService lê o ItemId associado à Part
  -> trava local do pickup é ativada e o prompt é desabilitado
  -> InventoryService:addItem(player, itemId)
       -> false: jogador não carregado ou item inválido
       -> true: novo snapshot armazenado e InventoryChanged disparado
  -> sucesso: Part destruída
  -> falha: prompt reabilitado e pickup preservado
```

O `itemId` não será recebido de um RemoteEvent do cliente. O valor será
associado pelo servidor ao criar a Part e validado novamente antes da
mutação. A trava por pickup impede que eventos duplicados adicionem o mesmo
objeto duas vezes.

O cliente continuará recebendo o snapshot através de `InventoryChanged`. O
`InventoryController` e o `App` existentes deverão refletir a nova entrada
automaticamente. Não será criado um RemoteEvent específico para pickup.

## Modelo de dados

O formato atual continuará válido:

```lua
export type InventoryState = {
    version: number,
    items: { string },
}
```

Coletar duas tochas adicionará duas entradas:

```lua
{ "torch", "torch" }
```

A propriedade `stackable` continuará no catálogo, mas não será usada para
agrupar itens ou renderizar contadores nesta etapa. O schema persistido não
será alterado.

## Tratamento de erros e limites

- Um jogador cujo inventário ainda está carregando não coleta o item; o pickup
  permanece disponível.
- Um `itemId` inválido não altera o inventário nem destrói a Part.
- A Part só é destruída depois que o inventário confirma a inserção.
- O prompt é desativado durante a tentativa para impedir concorrência local.
- Não haverá limite de distância adicional além do `MaxActivationDistance` do
  `ProximityPrompt` nesta primeira versão; o Roblox controla a ativação do
  prompt.
- Não haverá save imediato. Uma queda do servidor antes de `PlayerRemoving`
  pode perder pickups coletados, seguindo a política atual de persistência.
- Não haverá reposição automática quando um pickup for coletado.
- Entradas previamente existentes no `Workspace.Pickups` não serão usadas como
  fonte de estado; o serviço controla o conjunto criado durante sua sessão.

## Testes e verificação

### Testes puros no Lune

Adicionar testes para a operação pura `InventoryStore.addItem`:

- item válido gera uma nova entrada;
- item desconhecido retorna falha sem alterar o estado original;
- o resultado não compartilha a tabela `items` anterior;
- serialização e desserialização continuam estáveis após a mutação.

### Verificações Roblox

- `selene --config selene.roblox.toml src`
- typecheck Roblox com sourcemap e definições versionadas;
- `rojo build -o /tmp/dungeon-game-canve.rbxlx`;
- teste no Studio com um servidor e múltiplos jogadores.

### Critérios de aceitação no Studio

- o primeiro personagem carregado provoca a criação da pasta
  `Workspace.Pickups`;
- existem exatamente 30 Parts iniciais, com 10 de cada `ItemId`;
- todos os jogadores enxergam o mesmo conjunto;
- cada Part exibe um `ProximityPrompt` funcional;
- coletar um pickup adiciona o item à lista exibida;
- o pickup coletado é removido do mundo;
- uma tentativa duplicada não adiciona o mesmo pickup duas vezes;
- um jogador ainda não carregado não consegue consumir pickups;
- novos jogadores não causam um segundo lote de 30 Parts.

## Fora de escopo

- pickups por jogador;
- respawn ou reposição de itens;
- posicionamento garantidamente livre de paredes ou integrado a salas;
- geração de loot baseada em seed da dungeon;
- limite de slots ou peso;
- agrupamento visual e contadores de stack;
- uso, equipamento, descarte, trade ou crafting;
- save por mudança, autosave ou session lock;
- efeitos, sons e animações especiais de coleta.
