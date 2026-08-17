# Design: Melhorias da Interface do Inventário

Data: 2026-08-17  
Status: Aprovado pelo usuário para especificação

## Objetivo

Melhorar o feedback visual do sistema de inventário em duas frentes:

1. manter o painel do inventário oculto por padrão e alterná-lo com a tecla `I`;
2. exibir uma notificação no canto inferior esquerdo quando um pickup for
   adicionado com sucesso ao inventário.

A notificação deverá usar o nome real do item do catálogo, como `Pegou Tocha`,
`Pegou Ração` e `Pegou Cristal`. Ela ficará visível por 2 segundos. Uma coleta
nova substituirá a notificação atual e reiniciará o período de exibição.

## Decisões aprovadas

| Tema | Decisão |
|---|---|
| Visibilidade inicial | Painel do inventário oculto |
| Atalho | Tecla `I` alterna mostrar/ocultar |
| Entrada processada | Ignorar `I` quando `gameProcessedEvent` for `true`, incluindo chat/campos de texto |
| Escopo do atalho | Alternar somente o painel, sem desativar o `ScreenGui` |
| Evento de coleta | Novo `RemoteEvent` explícito `PickupCollected` |
| Autoridade | Servidor dispara o evento somente após `InventoryService:addItem` retornar `true` |
| Texto | `Pegou <nome real do catálogo>` |
| Posição | Canto inferior esquerdo |
| Duração | 2 segundos |
| Coletas consecutivas | A mensagem nova substitui a anterior e reinicia o temporizador |
| Snapshot inicial | Não gera notificação |

## Abordagem rejeitada

O cliente não inferirá a coleta comparando snapshots de `InventoryChanged`.
Embora essa solução evite um remoto novo, ela mistura sincronização de estado
com eventos transitórios de gameplay e pode produzir notificações incorretas
quando outras mutações forem adicionadas.

Também não será adicionado um campo transitório ao `InventoryState`. O snapshot
continua representando somente o estado persistível do inventário, enquanto a
coleta será representada por um evento separado.

## Arquitetura

```text
ProximityPrompt.Triggered(player)
  -> PickupService chama InventoryService:addItem(player, itemId)
  -> falha: pickup preservado, nenhum evento
  -> sucesso: pickup destruído
             -> InventoryChanged dispara o novo snapshot
             -> PickupCollected dispara o itemId para aquele jogador

PickupNotificationController
  -> escuta PickupCollected
  -> publica itemId por Signal

usePickupNotification()
  -> recebe itemId
  -> resolve items[itemId].name
  -> substitui a mensagem atual
  -> remove após 2s, se ainda for a notificação mais recente

App
  -> inventoryVisible começa como false
  -> UserInputService.InputBegan com tecla I alterna inventoryVisible
  -> renderiza InventoryPanel somente quando inventoryVisible
  -> renderiza a notificação independentemente do painel
```

### Contrato do remoto

`src/shared/remotes.luau` passará a garantir:

```lua
PickupCollected: RemoteEvent
```

O payload será um único `itemId: string`. O servidor só enviará o evento depois
da validação existente do catálogo e da mutação bem-sucedida do inventário.
Não haverá RemoteEvent de solicitação de coleta vindo do cliente.

### Servidor

`PickupService` receberá a referência já existente ao `InventoryService` e ao
final do callback de `ProximityPrompt.Triggered` fará:

1. bloquear o pickup durante a tentativa;
2. chamar `inventoryService:addItem(player, itemId)`;
3. em sucesso, destruir a Part e chamar `PickupCollected:FireClient(player, itemId)`;
4. em falha, restaurar o prompt e não enviar notificação.

O fluxo atual de `InventoryChanged` continuará inalterado. O novo evento será
específico para o jogador que coletou o item e não será transmitido aos demais
jogadores.

### Cliente

`PickupNotificationController` seguirá o padrão do `InventoryController`:

- `start()` idempotente conecta ao `PickupCollected.OnClientEvent`;
- `stop()` desconecta a conexão ativa;
- um Signal publica o `itemId` recebido;
- nenhum estado persistente de notificação será salvo no servidor.

`usePickupNotification` fará a ponte entre o Signal e o React. O hook manterá
uma única notificação ativa. Cada evento incrementará um identificador de
geração; o callback agendado para remover uma notificação só poderá limpar o
estado se sua geração ainda for a mais recente. Isso impede que um temporizador
antigo apague uma mensagem nova, inclusive quando duas coletas têm o mesmo
item.

O nome será obtido de `src/shared/inventory/items.luau`, a mesma fonte usada na
lista do inventário. Se um payload inválido escapar de uma versão incompatível
do cliente, a UI usará o `itemId` como fallback textual, sem alterar o estado do
inventário.

## Comportamento visual

O `ScreenGui` continuará montado com `ResetOnSpawn = false`. Apenas o
`InventoryPanel` será condicional:

- início: `inventoryVisible = false`;
- `I` com `gameProcessedEvent == false`: alterna a visibilidade;
- `I` processado pelo chat ou por outro campo: nenhuma alteração;
- desmontagem: remove a conexão de entrada.

A notificação será um único elemento condicional no mesmo `ScreenGui`,
independente da visibilidade do painel. Ela usará uma posição ancorada no canto
inferior esquerdo com margem da borda e seguirá a linguagem visual existente do
inventário: fundo escuro translúcido, borda roxa e tipografia clara.

O texto renderizado será exatamente no formato `Pegou <nome>`, sem fila de
mensagens. Uma nova coleta substitui imediatamente o texto anterior e mantém
a notificação visível por mais 2 segundos.

## Tratamento de erros e limites

- Falhas em `addItem` não destroem o pickup e não exibem notificação.
- O cliente não poderá criar nem solicitar uma notificação de coleta por conta
  própria.
- A notificação não será reconstruída a partir do snapshot inicial do
  inventário.
- O evento não altera o schema `InventoryState` nem a persistência existente.
- Não haverá fila, contador agregado, som, animação especial ou histórico de
  notificações nesta etapa.
- O painel permanecerá fechado após o carregamento inicial; a abertura será
  uma escolha local do jogador.

## Arquivos previstos

- Modificar `src/shared/remotes.luau` para registrar `PickupCollected`.
- Modificar `src/server/pickups/PickupService.luau` para disparar o evento após
  uma coleta confirmada.
- Criar `src/client/pickups/PickupNotificationController.luau`.
- Criar `src/client/pickups/usePickupNotification.luau`.
- Modificar `src/client/init.client.luau` para iniciar o controller.
- Modificar `src/client/ui/App.luau` para o toggle do painel e a notificação.
- Modificar `tests/client/ui/App.spec.luau` com verificações do novo contrato de
  UI e entrada.

## Testes e verificação

### Testes no Lune

Os testes estáticos existentes de `App.luau` serão ampliados para verificar que
o painel não é renderizado incondicionalmente e que o código contém o caminho
de entrada com `InputBegan`, tecla `I` e filtro de `gameProcessedEvent`.

Também serão verificadas a duração de 2 segundos e a substituição da mensagem
em vez de uma lista de notificações.

Controllers que dependem diretamente de APIs Roblox serão validados pelo
typecheck, lint e Studio, sem simular `RemoteEvent` ou `UserInputService` no
Lune.

### Verificações Roblox

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
rojo build -o /tmp/dungeon-game-canve.rbxlx
```

### Critérios de aceitação no Studio

- o painel do inventário não aparece ao iniciar;
- pressionar `I` mostra e oculta o painel;
- digitar no chat não alterna o painel;
- coletar uma tocha mostra `Pegou Tocha` no canto inferior esquerdo;
- coletar uma ração mostra `Pegou Ração`;
- coletar um cristal mostra `Pegou Cristal`;
- a mensagem desaparece após 2 segundos;
- uma nova coleta substitui imediatamente a mensagem anterior;
- uma tentativa de coleta que falhar não mostra mensagem;
- a coleta continua atualizando a lista do inventário quando o painel é aberto.

## Fora de escopo

- fila ou histórico de notificações;
- contagem de itens agrupados;
- efeitos sonoros, partículas ou animações de coleta;
- botão visual adicional para abrir o inventário;
- alteração do modelo, persistência ou autoridade do inventário;
- notificações para alterações de inventário que não sejam pickups.
