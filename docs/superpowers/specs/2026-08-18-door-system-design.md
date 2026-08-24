# Design: Sistema de Portas e Transicoes

> **Documento historico:** a autoridade server-side descrita aqui, `InteractDoor`,
> `iron_key` e `StudioDoorScene` foram supersedidos pelo design
> `2026-08-24-door-manager-client-side-design.md`. Este documento nao e o
> contrato atual de runtime.

Data: 2026-08-18
Status: Aprovado pelo usuario para especificacao

## Objetivo

Adicionar ao jogo portas entre salas. As portas podem estar trancadas ou nao e,
quando trancadas, exigem um item especifico do inventario (como uma chave) para
serem destrancadas. O jogador interage com a porta quando esta proximo o
suficiente e olhando diretamente para ela. A interacao pode destrancar a porta
usando um item ou atravessa-la, com uma transicao simples de fade in/out e um
som.

O sistema precisa:

- Permitir ao designer criar portas, definir se estao trancadas e qual item e
  necessario para abri-las.
- Ler essa configuracao em runtime e processar a logica de portas no servidor.
- Interagir com o sistema de inventario quando o destrancamento exige um item.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Destino da travessia | Inferido pelo lado da porta em que o jogador esta; nao ha registro central de salas |
| Consumo da chave | A chave nao e consumida; apos o desbloqueio a porta fica permanentemente aberta no servidor atual |
| Persistencia do desbloqueio | Apenas no servidor atual, sem persistencia entre sessoes |
| Tecla de interacao | `F`, seguindo o dialogo |
| Autoria da porta | `Model` com peça `Doorway` e `Attachment` `Center` |
| Comunicacao de estado | Atributos replicaveis no `DoorModel` (`Locked`, `RequiredItemId`) |
| Autoridade | O cliente le os atributos para decidir o fluxo; o servidor revalida toda acao e e a unica autoridade para mutacoes |
| Feedback de porta trancada sem chave | Sequencia de mensagens lidas de `LockedDialogue` no `Model` |
| Confirmacao ao destrancar | O jogador nao e teleportado ao destrancar; apenas na proxima interacao |
| Deteccao de porta | ShapeCast (bloco) a frente do `HumanoidRootPart`; sem verificacao de distancia separada |
| Transicao | Fade para preto, teleporte pelo servidor, som opcional e fade de volta |
| Som | Constante unica `TRANSITION_SOUND_ID`; enquanto vazia, nenhum som e criado |
| Integracao com inventario | `DoorService` usa o `ItemUseService` com capability `"unlock"`; o behavior valida o `itemId` sem consumir a instancia |

## Arquitetura

```text
src/shared/doors/doorTypes.luau
  Tipos de configuracao e resultados da interacao.

src/shared/remotes.luau
  Adiciona InteractDoor (RemoteFunction). O estado das portas e comunicado
  por atributos replicaveis, nao por um RemoteEvent de estado.

src/server/doors/DoorService.luau
  Descobre portas pela tag "Door" via CollectionService.
  Valida a estrutura Model/Doorway/Center.
  Le os atributos Locked e RequiredItemId.
  Mantem o estado destrancado apenas em memoria.
  Calcula o lado do jogador pelo Center.
  Integra o desbloqueio com o ItemUseService.

src/server/doors/StudioDoorScene.luau
  Cria uma cena manual de teste somente no Studio.
  Gera tres portas com estados e configuracoes conhecidos.
  Nao cria pickups nem altera diretamente o inventario.

src/client/doors/DoorController.luau
  Executa o ShapeCast a frente do personagem.
  Le os atributos replicados e o inventario local.
  Envia apenas a acao decidida ao servidor (unlock ou enter).
  Aciona o DialogueController para mensagens especificas.
  Coordena o TransitionController na travessia.

src/client/doors/TransitionController.luau
  Controla um ScreenGui preto client-side.
  Faz fade para preto, aguarda o teleporte, toca o som e faz fade de volta.
  ID do audio em constante unica para troca futura.

src/client/init.client.luau
  Inicia DoorController e TransitionController uma vez.

src/server/init.server.luau
  Compoe o DoorService com InventoryService, ItemUseService e CollectionService.
  Registra o behavior de "unlock" no ItemBehaviorRegistry antes de iniciar o
  DoorService. O comportamento valida o itemId contra o RequiredItemId sem
  consumir a instancia. Em Studio, inicia o PickupService existente e cria a
  StudioDoorScene antes de iniciar o DoorService.

test.project.json
  Mapeia src/server/doors e src/client/doors para o projeto de testes.

tests/server/doors/DoorService.spec.luau
  Cobre descoberta, validacao, desbloqueio e travessia.

tests/client/doors/DoorController.spec.luau
  Cobre deteccao por ShapeCast e decisao de fluxo.

tests/client/doors/TransitionController.spec.luau
  Cobre fade, som e reversao em falha.
```

## Cena programatica de teste no Studio

Para permitir a validacao manual da integracao completa, o servidor criara uma
cena de teste somente quando estiver rodando no Studio. A responsabilidade sera
isolada em `src/server/doors/StudioDoorScene.luau`, com uma API pequena:

```lua
StudioDoorScene.create()
```

O modulo sera chamado pelo `init.server.luau` depois de iniciar o
`PickupService` existente e antes de iniciar o `DoorService`. A cena nao criara
outro pickup e nao adicionara itens diretamente ao inventario; o `iron_key`
continuara vindo da configuracao existente do `PickupService`.

O modulo procurara `Workspace.DoorTestScene` antes de criar qualquer instancia.
Se a pasta ja existir, a chamada nao duplicara a cena. A pasta e seus objetos sao
runtime-only e desaparecem ao interromper o Play.

### Cenarios gerados

A cena tera tres portas em um layout fixo e previsivel:

| Modelo | `Locked` | `RequiredItemId` | Objetivo |
|---|---:|---|---|
| `MissingKeyDoor` | `true` | `iron_key` | Exibir `LockedDialogue` antes da coleta da chave |
| `KeyDoor` | `true` | `iron_key` | Destrancar sem consumir a chave e atravessar depois |
| `OpenDoor` | `false` | `""` | Atravessar diretamente |

As duas portas trancadas exigem o mesmo item para que o jogador possa testar o
fluxo sem chave e, depois, o fluxo com chave usando o pickup ja existente. A
`MissingKeyDoor` deve ser testada antes de o jogador coletar o `iron_key`.

Cada cenario sera criado como um `Model` com:

```text
DoorTestScene [Folder]
+-- MissingKeyDoor [Model, tag: "Door"]
|   +-- Doorway [BasePart]
|   |   +-- Center [Attachment]
|   +-- LockedDialogue [Folder]
+-- KeyDoor [Model, tag: "Door"]
|   +-- Doorway [BasePart]
|   |   +-- Center [Attachment]
|   +-- LockedDialogue [Folder]
+-- OpenDoor [Model, tag: "Door"]
    +-- Doorway [BasePart]
        +-- Center [Attachment]
```

O construtor aplicara os atributos `Locked` e `RequiredItemId`, adicionara a tag
`Door` usando `CollectionService` e criara geometrias simples de apoio, como
piso, paredes baixas e uma cor visual distinta por cenario. A fixture nao criara
prompts, UI, remotes ou logica de teleporte; esses comportamentos continuam sob
responsabilidade dos sistemas de portas.

## Autoria e estado replicado

Cada porta sera estruturada assim:

```text
DoorModel [tag: "Door"]
+-- Doorway [BasePart]
|   +-- Center [Attachment]
+-- LockedDialogue [Folder]
    +-- 01_Locked [StringValue]
    +-- 02_Hint [StringValue]
```

Atributos no `DoorModel`:

- `Locked: boolean`
  - Definido inicialmente pelo designer.
  - Alterado pelo servidor para `false` apos o desbloqueio.
  - Replicado automaticamente para todos os clientes.
- `RequiredItemId: string`
  - Identificador do item exigido, como `"iron_key"`.
  - Mantido pelo servidor e lido pelo cliente.
  - A chave nao sera consumida.

Regras client-side:

- `Locked == false`: o cliente solicita a travessia.
- `Locked == true` e o inventario local contem `RequiredItemId`: o cliente
  solicita o desbloqueio.
- `Locked == true` e o item nao esta no inventario: o cliente exibe
  `LockedDialogue` e nao envia acao de desbloqueio.

Regras server-side:

- O servidor valida novamente porta, distancia, direcao, estado e inventario.
- Um pedido valido de desbloqueio altera `DoorModel.Locked = false`.
- A alteracao replica para todos os clientes.
- Um pedido valido de travessia teleporta o jogador para o lado oposto.
- O cliente nunca altera esses atributos.

## Fluxo de interacao e autoridade

O cliente faz a deteccao inicial:

1. ShapeCast a frente do personagem.
2. Confirma que o alvo pertence a um `DoorModel`.
3. Ao pressionar `F`, le `Locked` e o inventario replicado.
4. Envia ao servidor apenas a acao correspondente: `unlock` ou `enter`.

O servidor recebe o `DoorModel` e a acao, mas nao confia na decisao do
cliente. Ele revalida:

- A instancia ainda e uma porta valida e esta no `Workspace`.
- O jogador esta dentro da distancia permitida.
- O jogador esta em um dos lados validos da porta.
- A porta ainda esta trancada ou destrancada conforme o pedido.
- O jogador possui uma instancia do `RequiredItemId` quando o pedido e `unlock`.
- A porta nao esta processando outra acao simultaneamente.

### Fluxo de desbloqueio

1. Cliente ve `Locked == true` e encontra a chave no inventario local.
2. Cliente envia `unlock`.
3. Servidor revalida a chave atraves do inventario autoritativo.
4. Servidor define `DoorModel.Locked = false`.
5. Cliente recebe a confirmacao e mostra `"Porta destrancada"`.
6. O jogador permanece no lugar.
7. A proxima interacao seguira o fluxo de entrada.

### Fluxo de entrada

1. Cliente ve `Locked == false`.
2. Cliente inicia o fade para preto.
3. Cliente envia `enter`.
4. Servidor calcula o lado atual do jogador usando o `Center`.
5. Servidor teleporta o jogador para o lado oposto.
6. O servidor confirma a conclusao.
7. Cliente toca o som de transicao e faz o fade para revelar a nova sala.

Se o cliente estiver com atributos desatualizados, o servidor rejeita a acao
sem teleportar. A replicacao posterior de `Locked` corrige o estado local.

O fade e iniciado antes do pedido `enter`; se o servidor rejeitar a acao, o
cliente cancela o fade e exibe o feedback apropriado.

## Geometria da travessia e transicao

O `Center` sera a referencia espacial da porta:

- A posicao do `Center` define o plano de passagem.
- O eixo local `Z` do `Center` define a normal da porta.
- O produto escalar entre a posicao do jogador e essa normal determina em qual
  lado ele esta.
- Se o jogador estiver praticamente sobre o plano da porta, a acao sera
  rejeitada para evitar um teleporte ambiguo.

O destino sera calculado no lado oposto:

- O jogador sera colocado alem da espessura do `Doorway`, com uma margem segura.
- A posicao tera altura adequada para o `HumanoidRootPart`.
- O personagem ficara orientado para longe da porta, entrando na sala oposta.
- Nao sera necessario cadastrar `RoomId`, `EntryId` ou destinos externos.

### Transicao

1. O cliente inicia um `Frame` preto com transparencia animada ate opacidade
   total.
2. Quando a tela estiver completamente preta, o cliente envia `enter`.
3. O servidor valida e teleporta o personagem.
4. Apos a confirmacao, o cliente toca o som configurado.
5. O cliente reduz a opacidade do preto ate revelar a nova sala.

O controlador usara constantes para a duracao do fade e para o audio:

```lua
local TRANSITION_SOUND_ID = ""
```

Enquanto o asset nao existir, nenhum som sera criado ou tocado. A troca futura
ficara limitada ao ID dessa constante.

Se o teleporte falhar, o cliente nao ficara preso em uma tela preta: o fade
sera revertido e a porta permanecera no estado original.

## Deteccao de porta

A deteccao usara `WorldRoot:Shapecast` com um bloco posicionado diretamente a
frente do `HumanoidRootPart`:

- O bloco e centrado em `HumanoidRootPart.Position + LookVector * PROBE_OFFSET`.
- O tamanho do bloco define o volume de interacao (`PROBE_SIZE`).
- A orientacao acompanha o `HumanoidRootPart`.
- O `LookVector` do `HumanoidRootPart` define "olhando diretamente para a porta".
- Se o shapecast atingir uma parte descendente de um `DoorModel` com a tag
  `Door`, a porta e considerada o alvo atual.
- Nao ha verificacao de distancia separada: o volume do probe ja determina a
  proximidade.
- Se multiplas portas forem atingidas, a mais proxima pelo `hitDistance` do
  resultado e selecionada.

Constantes no `DoorController`:

```lua
local PROBE_OFFSET = 2.5
local PROBE_SIZE = Vector3.new(4, 5, 3)
```

O volume cobre de `PROBE_OFFSET - PROBE_SIZE.Z/2` ate `PROBE_OFFSET +
PROBE_SIZE.Z/2` studs a frente do personagem (~1 a ~4 studs).

O servidor continuara validando independentemente, pois nao confia na deteccao
client-side. Usara a posicao do `Center` e do `HumanoidRootPart` para confirmar
que o jogador esta em um lado valido e dentro de uma tolerancia aceitavel em
relacao ao plano da porta.

## Feedback e dialogos das portas

### Porta trancada sem o item

1. O cliente le os `StringValue`s diretos de `LockedDialogue`.
2. Ordena os valores pelo nome, como `01_Locked`, `02_Hint`.
3. Exibe cada mensagem sequencialmente usando `DialogueController.show`.
4. A proxima mensagem so aparece apos o jogador confirmar a anterior com `F`.
5. `Esc` cancela a sequencia.
6. Nenhum pedido de desbloqueio e enviado ao servidor.

Se a pasta estiver ausente ou vazia, sera usado o fallback `"Porta trancada."`.

### Porta trancada com o item

1. O cliente envia `unlock`.
2. Apos a confirmacao do servidor, mostra `"Porta destrancada"`.
3. O jogador nao e teleportado.
4. A mensagem precisa ser encerrada com `F`.
5. Somente uma nova interacao com `F`, ja com `Locked == false`, inicia a
   travessia.

Enquanto outro dialogo estiver ativo, a porta nao processara interacao propria,
pois o `DialogueController` continuara consumindo `F`.

## Integracao com o inventario

O desbloqueio usara o `ItemUseService` existente, mantendo a porta integrada ao
contrato de capacidades dos itens.

O item exigido precisa:

- Existir no catalogo.
- Possuir a capability `"unlock"`.
- Ter `itemId` igual ao `RequiredItemId` da porta.

O cliente enviara apenas:

```lua
{
    door = doorModel,
    action = "unlock",
}
```

Ele nao enviara `RequiredItemId`, `Locked` nem valores de efeito.

`InteractDoor` retorna um resultado do tipo:

```lua
type DoorActionResult = {
    success: boolean,
    reason: string?,        -- "invalid_door" | "too_far" | "ambiguous_side"
                             -- | "locked" | "already_unlocked"
                             -- | "missing_item" | "busy" | "invalid_config"
    action: "unlock" | "enter"?,
}
```

O cliente usa `success` para iniciar o fade em `enter` e o `reason` para
decidir o feedback (silencioso, dialogo de porta trancada ou reversao de fade).

No servidor:

1. `DoorService` le o `RequiredItemId` real da porta.
2. Cria internamente um pedido de uso com capability `"unlock"`.
3. O behavior de desbloqueio verifica se a instancia encontrada possui exatamente
   aquele `itemId`.
4. O behavior nao retorna `consumeInstance` nem `consumeQuantity`.
5. Apos o `ItemUseService` confirmar o item, `DoorService` altera `Locked` para
   `false`.
6. A chave permanece intacta no inventario.

Assim, o `ItemUseService` continua responsavel pela validacao do item, enquanto
o `DoorService` permanece responsavel pela mutacao da porta. O cliente pode
sugerir `unlock`, mas nao consegue escolher um item diferente nem destrancar sem
possuir a chave correta.

Se `RequiredItemId` for invalido, estiver ausente ou nao existir no catalogo, a
porta permanecera trancada e o servidor registrara uma configuracao invalida.

## Testes e verificacao

Specs TestEZ (`--!strict`) cobrirao a logica sem depender de UI.

`tests/server/doors/DoorService.spec.luau`:

- Descoberta de portas pela tag `Door`.
- Validacao da estrutura `Model/Doorway/Center`.
- Rejeicao de porta fora do `Workspace`.
- Rejeicao por distancia, lado ambiguo e estado inconsistente.
- Desbloqueio altera `Locked` para `false` quando o item e valido.
- Desbloqueio rejeitado quando o item nao existe ou nao e o `RequiredItemId`.
- Desbloqueio rejeitado quando a porta ja esta destrancada.
- Travessia teleporta o jogador para o lado oposto.
- Travessia rejeitada quando a porta esta trancada.
- Lock por porta impede acoes concorrentes.

`tests/client/doors/DoorController.spec.luau`:

- Shapecast a frente do personagem detecta a porta.
- Porta fora do volume do probe nao e detectada.
- Multiplas portas: a mais proxima e selecionada.
- `LookVector` do `HumanoidRootPart` define a direcao de "olhar".
- Decisao client-side: `unlock`, `enter` ou exibicao de `LockedDialogue`.
- Sequencia de mensagens le `StringValue`s ordenados.
- Fallback `"Porta trancada."` quando a pasta esta ausente ou vazia.
- Bloqueio de interacao quando um dialogo ja esta ativo.

`tests/client/doors/TransitionController.spec.luau`:

- Fade para preto e de volta em duracoes configuradas.
- Som nao e tocado quando `TRANSITION_SOUND_ID` esta vazio.
- Reversao do fade quando o servidor rejeita a travessia.

Nao sera criado um spec separado para `StudioDoorScene`. Specs de UI permanecem
fora do escopo, conforme as instrucoes do repositorio. A fixture sera validada
manualmente em Play no Roblox Studio:

- As tres portas aparecem sem erros no Output.
- `MissingKeyDoor` exibe o dialogo e nao destranca antes da coleta da chave.
- O pickup existente adiciona `iron_key` ao inventario.
- `KeyDoor` destranca sem consumir a chave e so atravessa na interacao seguinte.
- `OpenDoor` atravessa diretamente.
- Um novo Play recria a cena sem duplicacao persistente.

### Verificacoes estaticas e builds

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
  src/server/inventory src/server/items src/server/pickups src/server/doors \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  src/client/doors \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

`test.project.json` sera atualizado para mapear `src/server/doors` e
`src/client/doors`.
