# Design: DoorManager Client-Side

Data: 2026-08-24
Status: Proposta revisada para aprovacao

## Objetivo

Migrar a autoridade runtime do dominio de portas para o cliente, partindo do
estado atual do projeto e preservando o comportamento de gameplay existente:

- a chave nao e consumida;
- o desbloqueio dura a sessao atual;
- o estado aberto permanece depois de um respawn;
- o desbloqueio e uma interacao separada da travessia;
- a travessia usa fade e teleporte para o lado oposto;
- a normal da porta usa o eixo local X do `Center`;
- eventos de objetivos continuam sendo publicados somente apos resultados locais
  bem-sucedidos.

O servidor nao recebera pedidos de porta, nao validara a porta e nao alterara o
atributo `Locked` durante o runtime. O servidor Roblox continuara existindo para
inventario, pickups e os demais sistemas, mas nao sera uma autoridade customizada
do gameplay de portas.

Esta decisao e deliberadamente client-authoritative e adequada ao jogo
single-player atual. Ela nao deve ser tratada como uma fronteira de seguranca
para experiencias multiplayer ou competitivas.

## Estado atual e ponto de partida

A migracao nao e uma implementacao inicial do sistema generico. O repositorio ja
possui:

- `InteractionController` como unico dono do binding de `F` e da deteccao;
- contrato comum com a tag `Interactable` e o atributo `InteractionType`;
- `DoorController.new(...)` como handler de porta;
- `TransitionController` como controller local de fade;
- `InventoryController` com snapshots locais recebidos do servidor;
- `DoorService` ainda ativo no servidor e ligado a `InteractDoor`;
- `DoorController` ainda chamando `InteractDoor` diretamente;
- `DoorModelInitializer` ja aplicando o contrato comum, mas ainda usando
  `iron_key`;
- catalogo com `access_card` e `pliers` como itens com capability `unlock`, sem
  `iron_key`;
- `StudioDoorScene` removida e sem uso planejado.

A implementacao deve extrair as regras de porta do `DoorController` e portar as
regras atuais de `DoorService` para um manager client-side. O detector generico,
o dialogo, a transicao e o inventario nao serao refatorados fora do necessario.

## Decisoes

| Tema | Decisao |
|---|---|
| Detector | Preservar `InteractionController` e seu unico binding de `F` |
| Handler | Preservar `DoorController.new(...)` como handler registrado para `Door` |
| Dominio | Criar `DoorManager` em `src/client/doors/DoorManager.luau` |
| Construção | Usar `DoorManager.new({ inventory = InventoryController })` |
| Inventario | O manager apenas le `InventoryController:getState()` |
| Personagem | Usar utilitario direto `CharacterRoot.get()` |
| Estado runtime | Atributo local `Locked` na copia client-side do modelo |
| Autoridade | Cliente valida, desbloqueia e teleporta localmente |
| Remoto de portas | Remover `InteractDoor` depois de eliminar todos os consumidores |
| Servidor | Remover `DoorService` e `DoorUnlockBehavior` do runtime |
| Chave de autoria | Usar `access_card`, que existe no catalogo |
| Tag legada | O initializer pode manter `Door` para ferramentas antigas; runtime nao a exige |
| `DoorKey` | Estavel quando presente; opcional para gameplay, obrigatorio para eventos de objetivos |
| Fixture de Studio | Nao recriar nem usar `StudioDoorScene` |
| Streaming | Portas nao podem ser descarregadas e recriadas durante a run |
| Escopo | Sessao atual; respawn preserva, nova sessao restaura os atributos authored |

## Arquitetura resultante

```text
src/client/player/CharacterRoot.luau
  Le o HumanoidRootPart do LocalPlayer sem manter estado.

src/client/doors/DoorManager.luau
  Valida portas, consulta inventario, altera Locked localmente e teleporta.

src/client/doors/DoorController.luau
  Handler do InteractionController; coordena dialogo, transicao e eventos.

src/client/doors/TransitionController.luau
  Mantem fade, callback, cancelamento e som opcional.

src/client/interactions/InteractionController.luau
  Mantem deteccao volumetrica, binding de F e despacho do handler.

src/client/inventory/InventoryController.luau
  Continua fornecendo o snapshot local do inventario.

src/client/init.client.luau
  Cria o manager e o DoorController e registra o handler.

src/server/init.server.luau
  Continua iniciando inventario, uso de itens, pickups e outros services,
  mas nao inicia nenhum service de portas.
```

O manager nao sera um singleton operacional criado dentro do modulo. Ele sera
uma instancia criada pelo composition root, conforme
`docs/controller-service-pattern.md`. O `DoorController` recebera essa instancia
explicitamente.

## Contrato de autoria

Cada porta authored sera um `Model` com esta estrutura:

```text
DoorModel [tag: Interactable]
|- Doorway [BasePart]
|  `- Center [Attachment]
`- LockedDialogue [Folder, opcional]
   |- 01_Locked [StringValue, opcional]
   `- 02_Hint [StringValue, opcional]
```

O contrato comum e:

```text
tag: Interactable
InteractionType: "Door"
```

Os atributos especificos sao:

| Atributo | Tipo | Regra |
|---|---|---|
| `InteractionType` | string | Deve ser `Door` |
| `Locked` | boolean | `true` para porta fechada, `false` para aberta |
| `RequiredItemId` | string | Pode ser vazio somente quando a porta esta aberta |
| `DoorKey` | string | Deve ser estavel e unico quando usado por objetivos |

`DoorKey` nao sera usado como fallback para o nome do model. Uma porta sem
`DoorKey` continuara funcionando, mas o `DoorController` emitira um warning uma
vez e nao publicara eventos de porta para o sistema de objetivos.

O `DoorModelInitializer` continuara sendo uma ferramenta de autoria e nao sera
executado como logica runtime. Ele devera:

- aplicar `Locked = true`;
- aplicar `RequiredItemId = "access_card"`;
- aplicar `InteractionType = "Door"`;
- adicionar a tag `Interactable`;
- manter a tag legada `Door` para ferramentas existentes;
- preservar um `DoorKey` existente e valido, ou gerar um valor inicial somente
  quando o atributo estiver ausente ou invalido;
- atualizar o texto do hint para mencionar o cartao de acesso, nao uma chave de
  ferro;
- criar `Doorway.Center` e `LockedDialogue` conforme o contrato atual.

Nao existira cena programatica de portas. A validacao manual dependera de um
model authored no mapa aberto no Studio. Se o fluxo completo de unlock for
validado manualmente, o mapa de desenvolvimento devera fornecer um pickup
authored de `access_card`; esta migracao nao criara um pickup de teste.

## `CharacterRoot`

Criar `src/client/player/CharacterRoot.luau` como utilitario sem estado:

```lua
CharacterRoot.get(): BasePart?
```

O utilitario consultara `Players.LocalPlayer.Character`, procurara
`HumanoidRootPart` e retornara a peca somente quando ela for um `BasePart`.
Personagem ausente, modelo invalido ou root ausente retornarao `nil`.

O `DoorManager` importara esse utilitario diretamente. `getCharacterRoot` nao
sera uma dependencia injetada. Os testes configurarao e restaurarao
`Players.LocalPlayer.Character` em suas fixtures.

## Contrato do `DoorManager`

O modulo exportara os tipos e a construcao abaixo:

```lua
export type Dependencies = {
    inventory: InventoryController.InventoryController,
}

export type DoorManager = {
    isLocked: (self: DoorManager, door: Model) -> (boolean?, doorTypes.DoorFailureReason?),
    unlock: (self: DoorManager, door: Model) -> doorTypes.DoorActionResult,
    enter: (self: DoorManager, door: Model) -> doorTypes.DoorActionResult,
}

DoorManager.new(dependencies): DoorManager
```

`inventory` e a unica dependencia de runtime do manager. O manager usara os
contratos ja exportados por `InventoryController` e `doorTypes`; nao redeclarara
tipos de inventario ou de resultado.

O manager importara diretamente:

- `CollectionService`;
- `Workspace`;
- `doorTypes`;
- `interactionTypes`;
- `InventoryController` para o contrato da dependencia;
- catalogo de itens;
- `CharacterRoot`.

Ele nao dependera de `RemoteFunction`, `InteractDoor`, `ItemUseService`,
`DialogueController`, `TransitionController`, `GameplayEvents`,
`InteractionController` ou `ContextActionService`.

O manager nao tera `start()` ou `stop()`. Ele nao cria bindings, conexoes ou
tarefas. O lock de concorrencia sera criado em `new` e permanecera isolado entre
instancias.

### Validacao estrutural

`isLocked` validara a configuracao estrutural e retornara `nil` com o motivo de
falha quando a porta nao for utilizavel. A ordem sera:

1. O alvo e um `Model` descendente de `Workspace`.
2. O modelo possui a tag `Interactable`.
3. O atributo `InteractionType` e `Door`.
4. `Doorway` e um `BasePart` filho direto.
5. `Center` e um `Attachment` filho direto de `Doorway`.
6. `Locked` e booleano.
7. `RequiredItemId` e string.
8. Quando `Locked` e `true`, `RequiredItemId` nao e vazio e existe no catalogo
   com capability `unlock`.

`DoorKey` nao sera uma validacao de dominio. Sua ausencia e tratada somente na
publicacao de eventos pelo `DoorController`.

`isLocked` retornara `true, nil` ou `false, nil` para uma porta valida. Ele nao
validara distancia, lado do jogador ou estado de concorrencia.

### Unlock local

`unlock` repetira a validacao estrutural, obterá o root por `CharacterRoot.get()`
e preservara as validacoes espaciais atuais:

- distancia maxima de `6` studs entre root e `Center`;
- lado determinado pelo produto escalar com `Center.WorldCFrame.XVector`;
- rejeicao quando o jogador estiver dentro de `SIDE_EPSILON = 0.001` do plano;
- lock por porta durante a operacao.

Depois dessas validacoes:

- se `Locked == false`, retornara `already_unlocked`;
- consultara `dependencies.inventory.getState()`;
- procurara uma instancia com `itemId == RequiredItemId`;
- exigira que o item do catalogo possua capability `unlock`;
- nao consumira a instancia e nao chamara `InventoryController.use`;
- definira `door.Locked = false` somente na copia local;
- retornara `{ success = true, action = "unlock" }`.

Quando o snapshot estiver ausente, o item nao existir ou o item for
incompativel, retornara `missing_item` sem alterar `Locked`. Falhas de distancia,
lado, configuracao, porta ou concorrencia retornarao os motivos existentes:
`invalid_door`, `too_far`, `ambiguous_side`, `invalid_config` e `busy`.

### Entrada local

`enter` repetira a validacao estrutural, obterá o root atual e aplicara as
validacoes de distancia, lado e concorrencia. Depois:

- retornara `locked` sem mover o personagem se `Locked == true`;
- calculara `signedDistance` com `Center.WorldCFrame.XVector`;
- definira `side` como `1` ou `-1` conforme o sinal da distancia;
- definira a direcao de saida como `-Center.WorldCFrame.XVector * side`;
- calculara a posicao com `Doorway.Size.X / 2 + EXIT_MARGIN`;
- preservara `root.Position.Y`;
- aplicara `CFrame.lookAt(destination, destination + direction)`;
- retornara `{ success = true, action = "enter" }`.

`EXIT_MARGIN` permanecera `3`, como no `DoorService` atual. O destino devera
ficar alem da espessura do `Doorway` e no lado oposto ao jogador.

## `DoorController`

O controller continuara sendo um handler compatível com
`interactionTypes.InteractionHandler`. Suas dependencias serao:

```lua
export type Dependencies = {
    manager: DoorManager.DoorManager,
    dialogue: DialogueController.DialogueController,
    transition: TransitionController.TransitionController,
}
```

Ele removera os imports e usos diretos de `InventoryController` e
`remotes.InteractDoor`. O controller nao calculara destino, nao alterara
atributos e nao implementara input ou deteccao.

O fluxo de `interact(target)` sera:

1. Ignorar qualquer target que nao seja `Model`.
2. Consultar `manager:isLocked(target)`.
3. Encerrar sem feedback quando a validacao retornar erro.
4. Para uma porta aberta, iniciar `transition.run` com `manager:enter(target)`.
5. Publicar `door_entered` somente para sucesso com `action = "enter"`.
6. Para uma porta fechada, chamar `manager:unlock(target)`.
7. Em sucesso com `action = "unlock"`, mostrar `Porta destrancada.` sem iniciar
   entrada na mesma interacao.
8. Publicar `door_unlocked` somente depois que a mensagem de sucesso for
   concluida.
9. Em `missing_item`, mostrar `LockedDialogue` ou o fallback `Porta trancada.`.
10. Publicar `door_blocked` somente depois que toda a sequencia de dialogo for
    concluida.
11. Em cancelamento, nao mostrar a mensagem seguinte e nao publicar o evento de
    bloqueio.
12. Para falhas de configuracao, distancia, lado, concorrencia ou estado, nao
    iniciar uma acao adicional.

As mensagens continuarao sendo `StringValue`s filhos diretos da pasta
`LockedDialogue`, filtradas por valor nao vazio e ordenadas por `Name`. A
sequencia avancara somente quando o callback receber `completed`.

O warning de `DoorKey` continuara sendo emitido uma vez por modelo. O controller
continuara usando `GameplayEvents.emit` diretamente, como no estado atual, sem
conhecer ou importar `ObjectiveController`.

## Transicao

`TransitionController` nao sera alterado funcionalmente. Para entrada:

1. O `DoorController` chama `transition.run`.
2. `TransitionController` faz fade para preto.
3. O callback de request chama `manager:enter(door)` com a tela opaca.
4. O resultado retorna ao callback do controller.
5. Em sucesso, a transicao toca o som configurado e revela a nova sala.
6. Em falha, a tela e restaurada e `door_entered` nao e publicado.

A API atual `run(request, callback)`, chamada com ponto no modulo
`TransitionController`, o `TRANSITION_SOUND_ID` vazio e o cancelamento por
`stop()` permanecem.

## Composicao e remocao server-side

Em `src/client/init.client.luau`:

1. Manter `InventoryController.start()` e `TransitionController.start()`.
2. Criar `DoorManager.new({ inventory = InventoryController })`.
3. Criar `DoorController.new({ manager = doorManager, dialogue = dialogueController, transition = TransitionController })`.
4. Registrar o controller no `InteractionController` existente para `Door`.
5. Manter um unico `interactionController:start()`.

Nao criar um segundo binding de `F` e nao adicionar ciclo de vida ao manager.

Em `src/server/init.server.luau`:

- remover os requires de `DoorService` e `DoorUnlockBehavior`;
- remover o registro da capability `unlock` especifica de portas;
- remover `doorService = DoorService.new(...)` e `doorService:start()`;
- manter o `ItemBehaviorRegistry`, `ItemUseService` e o binding de `UseItem` para
  o contrato generico de uso de itens;
- manter os demais services sem criar ou configurar portas.

Depois de eliminar os consumidores:

- remover `InteractDoor` de `src/shared/remotes.luau`;
- remover `src/server/doors/DoorService.luau`;
- remover `src/server/doors/DoorUnlockBehavior.luau`;
- remover `tests/server/doors/DoorService.spec.luau`;
- remover o mapeamento `Server.doors` de `test.project.json`.

`StudioDoorScene` permanece removida e nao deve ser recriada. O projeto normal
continua usando o mapeamento amplo de `src/server`; nao e necessario adicionar
nenhum mapa ou fixture ao `default.project.json`.

## Testes

### `DoorManager`

Criar `tests/client/doors/DoorManager.spec.luau` como ModuleScript `--!strict`.
As fixtures devem ser criadas em `beforeEach` e limpas em `afterEach`.

Cada fixture deve criar uma porta real em `Workspace` com:

- tag `Interactable`;
- `InteractionType = "Door"`;
- `Doorway` `Part` e `Center` `Attachment`;
- atributos de porta configuraveis;
- personagem local com `HumanoidRootPart`;
- fake de `InventoryController` com `getState()`.

O spec deve cobrir:

- construcao com `{ inventory = fakeInventory }`;
- porta valida aberta e fechada;
- modelo invalido, fora do `Workspace`, sem tag ou tipo incorreto;
- `Doorway` ou `Center` ausentes;
- `Locked` e `RequiredItemId` com tipos invalidos;
- porta fechada sem item requerido, item desconhecido ou item sem `unlock`;
- distancia excessiva e jogador sobre o plano do `Center`;
- entrada bloqueada sem mover o root;
- unlock em porta aberta retornando `already_unlocked`;
- unlock com `access_card` e item compativel sem consumo;
- item ausente ou incompatível retornando `missing_item`;
- `Locked` alterado para `false` apenas localmente;
- entrada em cada lado produzindo destinos opostos;
- destino alem da espessura da porta, altura preservada e orientacao afastada;
- `busy` em reentrada da mesma porta;
- isolamento do lock entre portas e entre managers;
- preservacao do atributo local depois de trocar o personagem por outro respawn.

As assercoes de geometria devem validar invariantes, nao repetir valores de
tuning como destino exato ou margem exata. Valores de configuracao authored
podem ser usados para montar as fixtures.

### `DoorController`

Reativar `tests/client/doors/DoorController.spec.luau`, removendo o retorno
temporario que atualmente desabilita o spec. Substituir o fake de
`InteractDoor` por um fake do manager:

```lua
manager:isLocked(door)
manager:unlock(door)
manager:enter(door)
```

Manter a cobertura existente de dialogo, fallback, cancelamento, transicao,
eventos e warning de `DoorKey`. Acrescentar as garantias de que:

- o controller nao consulta `InventoryController`;
- nenhum remoto e chamado;
- unlock bem-sucedido nao inicia `enter` na mesma interacao;
- falhas nao provocam requests adicionais;
- eventos so aparecem apos os resultados locais correspondentes.

`InteractionController.spec.luau` e `TransitionController.spec.luau` continuam
como estao, salvo ajustes necessarios de fixtures decorrentes da remocao do
remote. Nao criar specs de UI nem specs de `StudioDoorScene`.

## Verificacao manual

A verificacao manual usara somente uma porta authored no mapa, nao uma cena
programatica:

- o initializer produz `access_card`, `Interactable`, `InteractionType = "Door"`
  e um `DoorKey` estavel;
- uma porta aberta e descoberta pelo `InteractionController` e atravessada com
  `F` usando fade;
- uma porta fechada sem item mostra o dialogo e publica `door_blocked` ao final;
- com `access_card` no inventario, a primeira interacao desbloqueia sem
  consumir o item;
- a segunda interacao atravessa para o lado oposto;
- o cliente observa `Locked = false` depois do unlock;
- o servidor nao recebe `InteractDoor` e conserva o atributo authored original;
- um respawn preserva o estado local aberto;
- uma nova sessao restaura o valor authored inicial;
- `ReplicatedStorage.Remotes` nao contem `InteractDoor` em uma sessao limpa;
- o bootstrap server-side inicia sem `DoorService`, `DoorUnlockBehavior` ou
  `StudioDoorScene`.

Se o mapa nao possuir um pickup authored de `access_card`, o fluxo sem item e o
unlock com inventario serao validados pelos specs; a ausencia desse pickup nao
deve levar a criar uma fixture server-side nesta migracao.

## Verificacao automatizada

Executar os comandos oficiais depois de atualizar o sourcemap:

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
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

O typecheck nao deve incluir `src/server/doors`, pois o diretorio de portas
server-side sera removido. O projeto de testes deve ser servido em uma sessao
Play limpa, com os runners TestEZ client e server, e ambos devem reportar
`failed == 0`. Depois de cada rodada, parar o Play e confirmar que fixtures,
conexoes e callbacks foram liberados.

## Ordem de implementacao

1. Criar `CharacterRoot` e `DoorManager` com as dependencias e validacoes
   definidas, junto do spec client-side do manager.
2. Executar o spec do manager e corrigir o contrato antes da integracao.
3. Alterar `DoorController` para receber o manager, remover remote/inventario
   direto e reativar seu spec.
4. Atualizar `init.client.luau` para construir e registrar o manager e o handler.
5. Corrigir `DoorModelInitializer` para `access_card`, contrato comum e
   preservacao de `DoorKey`.
6. Remover `DoorService` e `DoorUnlockBehavior` do bootstrap e da arvore de
   producao/testes.
7. Remover `InteractDoor` e atualizar `test.project.json` e `README.md`.
8. Executar lint, sourcemap, typecheck, builds e Play limpo no Roblox Studio.
9. Atualizar a documentacao antiga que ainda descreve autoridade server-side,
   `iron_key`, `InteractDoor` ou `StudioDoorScene`.

## Criterios de aceitacao

- Nenhuma interacao de porta usa `RemoteFunction`.
- `InteractDoor` nao e criado, ligado ou chamado.
- `DoorManager` e construido com `{ inventory = InventoryController }`.
- O manager usa `CharacterRoot.get()` diretamente para o personagem local.
- `Locked` e a fonte de verdade do runtime na copia client-side.
- Unlock nao consome nem altera o snapshot do inventario.
- Unlock local persiste depois de respawn e nao persiste depois de nova sessao.
- A travessia preserva o calculo atual baseado no eixo X do `Center`.
- Falhas nao deixam a tela preta, nao movem o personagem e nao alteram `Locked`.
- `DoorController` continua sendo apenas handler, dialogo, transicao e eventos.
- O servidor nao inicia nem executa `DoorService` ou `DoorUnlockBehavior`.
- `StudioDoorScene` nao existe como dependencia da solucao.
- O mapa continua authored por modelos, tags e atributos.
- Os specs client-side, lint, typecheck e builds passam.
