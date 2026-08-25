# Design: Sistema Generico de Interacoes

> **Atualização histórica:** as seções que descrevem `PickupController`,
> `PickupService` e remotes refletem o design anterior. O fluxo atual usa
> `PickupInteraction` e `PickupManager` client-side; referências posteriores
> aos nomes antigos devem ser lidas como histórico.

Data: 2026-08-22  
Status: Aprovado pelo usuario para especificacao

## Objetivo

Substituir os caminhos separados de interacao por um detector client-side
comum. O jogador usara a tecla `F` para interagir com portas, pickups e novos
pontos interagiveis que sejam adicionados no futuro.

O detector usara a mesma busca volumetrica existente com
`Workspace:GetPartBoundsInRadius`, mas com uma esfera maior e reposicionada:

- raio: `3` studs;
- centro: `HumanoidRootPart.Position + LookVector * 2.5`;
- altura: a mesma altura do `HumanoidRootPart`;
- exclusao: o personagem do jogador;
- busca: somente quando `F` for pressionado, sem polling por `Heartbeat`.

Nao havera indicador visual de alvo. A esfera de debug continuara opcional e a
alteracao local que a mantem desabilitada sera preservada.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Tecla | Um unico binding de `F` no `InteractionController` |
| Deteccao | `GetPartBoundsInRadius` em um ponto a frente do jogador |
| Volume | Raio `3`, centro `2.5` studs a frente |
| Marcacao | Tag `Interactable` e atributo `InteractionType` |
| Tipos iniciais | `Door` e `Pickup` |
| Indicador | Nenhum indicador visual de gameplay |
| Bloqueio | `setEnabled(false/true)` no controller generico |
| Arquitetura client-side | Detector generico e handlers por dominio |
| Arquitetura server-side | Pickups mantem sua autoridade; portas sao locais no cliente |
| Porta | `DoorManager` e `DoorController` client-side |
| Pickup | Usa novo `CollectPickup`; `ProximityPrompt` deixa de ser caminho de interacao |
| Pickups authored | `Part` ou `Model` com `ItemId` obrigatorio e `Quantity` opcional |
| Autoridade | O servidor cria itens, valida pedidos e aplica mutacoes |
| Cena de teste | Nenhuma cena de teste server-side e criada |
| Testes | Uma unica sessao Play limpa, com `failed == 0` no servidor e cliente |

## Arquitetura

```text
src/shared/interactions/interactionTypes.luau
  constantes da tag e do atributo comuns

src/shared/remotes.luau
  mantem somente os remotes de inventario e pickups

src/client/interactions/InteractionController.luau
  captura F, busca o alvo e encaminha para handlers registrados

src/client/doors/DoorController.luau
  handler client-side das regras de porta, dialogo e transicao

src/client/pickups/PickupController.luau
  handler client-side que solicita a coleta

src/client/doors/DoorManager.luau
  valida, desbloqueia e move localmente

src/server/pickups/PickupService.luau
  registra pickups, valida CollectPickup e adiciona itens ao inventario

src/client/init.client.luau
  registra handlers e inicia InteractionController

src/server/init.server.luau
  compoe e inicia PickupService junto dos services existentes
```

Nao sera criado um `InteractionService` server-side. O detector e o contrato
comum serao genericos no cliente. Pickups continuam com autoridade server-side;
portas usam `DoorManager` e `DoorController` localmente, sem `InteractDoor`.

## Contrato dos alvos

O objeto raiz de cada ponto interagivel tera:

```text
tag: Interactable
atributo: InteractionType = "Door" ou "Pickup"
```

O detector subira a hierarquia a partir da peca atingida ate encontrar essa
raiz. A raiz pode ser um `Model` ou uma `BasePart`.

### Porta

As portas continuarao com sua estrutura e configuracao especificas:

```text
DoorModel [tag: Interactable]
|-- InteractionType = "Door"
|-- Locked = true/false
|-- RequiredItemId = "iron_key"
|-- Doorway [BasePart]
|   |-- Center [Attachment]
|-- LockedDialogue [Folder, opcional]
```

O antigo tag `Door` podera permanecer para ferramentas existentes, mas nao
sera requisito da deteccao nem da validacao de runtime. O initializer de portas
devera aplicar o contrato comum aos modelos novos ou reconfigurados.

### Pickup

Um pickup authored tera a seguinte configuracao:

```text
PickupPart ou PickupModel [tag: Interactable]
|-- InteractionType = "Pickup"
|-- ItemId = "iron_key"
|-- Quantity = 1 [opcional]
```

`ItemId` precisa ser uma string valida do catalogo. `Quantity`, quando presente,
sera validada pela `ItemInstanceFactory`; itens nao stackable ou quantidades
invalidas nao serao registrados.

## InteractionController

`InteractionController` sera o unico dono da entrada de interacao. Sua API
publica tera, no minimo:

```text
start()
stop()
register(interactionType, handler)
setEnabled(enabled)
isEnabled()
getTarget()
```

O construtor aceitara uma configuracao opcional do probe:

```text
ProbeConfig = {
  radius: number,
  forwardOffset: number,
}
```

A instancia de producao usara `radius = 3` e `forwardOffset = 2.5`. Essa
configuracao sera injetavel para que os testes validem o algoritmo com valores
proprios, sem duplicar os numeros de tuning do jogo nas expectativas.

O handler tera uma operacao equivalente a:

```text
interact(target: Instance)
```

### Ciclo de entrada

1. `start()` registra o binding de `F` uma unica vez.
2. Se o controller estiver desabilitado, o binding nao existira e `F` ficara
   disponivel para outros sistemas.
3. Ao receber `UserInputState.Begin`, o controller procura o personagem e seu
   `HumanoidRootPart`.
4. Calcula o centro da esfera usando o `LookVector` do root.
5. Executa `GetPartBoundsInRadius` com `OverlapParams` que exclui o personagem.
6. Para cada peca encontrada, sobe ate a raiz interagivel.
7. Remove duplicatas quando varias pecas pertencem ao mesmo alvo.
8. Seleciona o alvo mais proximo dentro da esfera.
9. Le `InteractionType` da raiz e procura o handler registrado.
10. Chama o handler com a raiz selecionada.

O alvo sera limpo quando nao houver personagem, root, alvo valido ou quando o
controller for parado/desabilitado. Nenhuma busca continua sera feita enquanto
o jogador nao pressionar `F`.

### Prioridade do F e habilitacao

O `InteractionController` usara `ContextActionService:BindActionAtPriority`
para registrar sua acao em `F` com a prioridade normal de interacao.
`DialogueController` continuara registrando sua acao de confirmacao em `F`
somente enquanto houver dialogo ativo, usando a prioridade maior que ja existe
no projeto (`Enum.ContextActionPriority.High.Value + 1`).

Assim, quando um dialogo estiver ativo, o bind do dialogo recebe `F` antes do
bind de interacao, sem que um controller conheca ou consulte o outro. O
`InteractionController` nao tera dependencia do `DialogueController`, e o
handler de porta tambem nao precisara consultar estado de dialogo.

O estado inicial sera habilitado. `setEnabled(false)` desassociara `F`, limpara
o alvo e impedira novos despachos. `setEnabled(true)` reassociara `F` se o
controller estiver iniciado. A troca pode ocorrer antes ou depois de `start()`.
Nenhuma operacao ja iniciada sera cancelada por essa troca.

`start()` e `stop()` serao idempotentes. O controller generico nao conhecera
`Locked`, `ItemId`, `unlock` ou `collect`.

### Warnings de configuracao

Warnings serao claros e identificarao o caminho completo do alvo:

- uma raiz com `Interactable` sem `InteractionType` valido gera warning;
- uma raiz com `InteractionType` sem a tag `Interactable` gera warning;
- uma raiz com `ItemId` sem a tag `Interactable` gera warning;
- um `InteractionType` valido sem handler registrado gera warning com o tipo;
- a mesma configuracao invalida nao sera reportada repetidamente a cada `F`.

Geometria comum sem metadados de interacao nao sera considerada alvo invalido,
pois paredes e pisos dentro da esfera nao devem gerar spam. `InteractionType`,
`ItemId` e a tag antiga `Door` serao considerados indicacoes de candidato para
que objetos parcialmente configurados ou portas ainda nao migradas produzam um
warning util.

## Handlers client-side

### DoorController

`DoorController` deixara de possuir input, busca esferica e alvo proprio. Ele
continuara responsavel por:

- confirmar que o alvo recebido e um `Model`;
- ler `Locked` e `RequiredItemId` replicados;
- consultar o inventario local para decidir entre `unlock` e `enter`;
- exibir `LockedDialogue` e a mensagem de desbloqueio;
- coordenar `TransitionController` antes de `enter`;
- chamar `InteractDoor` com o pedido especifico da porta.

O fluxo permanece:

```text
Locked + possui chave -> InteractDoor(unlock) -> "Porta destrancada"
Locked + sem chave    -> LockedDialogue
Unlocked              -> TransitionController -> InteractDoor(enter)
```

Os atributos lidos no cliente continuam sendo apenas uma decisao de fluxo e
feedback. O servidor revalida o pedido e permanece como autoridade.

### PickupController

`PickupController` recebera a raiz `Part` ou `Model` e chamara:

```text
CollectPickup({ pickup = target })
```

Ele nao determinara `ItemId`, `Quantity` ou `uid`, nao acessara o inventario
diretamente e nao criara `ProximityPrompt`. A notificacao existente continuara
sendo recebida por `PickupNotificationController` depois que o servidor
confirmar a coleta.

## Servidor e remotos

### Remotes

`InteractDoor` continuara sendo um `RemoteFunction` para pedidos de porta.
`ReplicatedStorage.Shared.remotes` adicionara `CollectPickup` como outro
`RemoteFunction`.

O cliente enviara somente a referencia do alvo e, no caso da porta, a acao
especifica ja existente. Nenhum valor de item sera aceito como autoridade.

### DoorService

`DoorService` continuara atendendo `InteractDoor` e passara a validar o
contrato comum:

- alvo descendente de `Workspace`;
- tag `Interactable`;
- `InteractionType == "Door"`;
- estrutura `Model/Doorway/Center`;
- atributos `Locked` e `RequiredItemId` validos;
- distancia, lado e concorrencia;
- item compativel quando a acao for `unlock`.

Sua logica de desbloqueio, teleporte, estado e uso da chave nao sera movida
para o controller generico.

### PickupService

`PickupService` tera uma tabela server-side que associa cada alvo a uma
`ItemInstance` criada pela `ItemInstanceFactory`. A tabela sera a fonte de
autoridade do pickup.

No `start()` o servico:

1. Procura alvos ja marcados com `Interactable`.
2. Registra os que possuem `InteractionType == "Pickup"`.
3. Escuta novos alvos marcados para registrar pickups adicionados em runtime.
4. Le `ItemId` e `Quantity` do alvo.
5. Cria um `uid` com `HttpService:GenerateGUID(false)` e uma `ItemInstance`
   server-side pela factory.
6. Ignora configuracoes invalidas com warning, sem criar estado parcial.
7. Desabilita `ProximityPrompt`s descendentes de pickups reconhecidos.

Pickups gerados por definicoes existentes do servico tambem usarao o mesmo
registro server-side. Cada pickup, authored ou gerado, tera uma instancia
independente e um `uid` independente.

`CollectPickup` validara:

- formato do pedido e tipo da referencia;
- existencia do alvo na tabela do servico;
- permanencia do alvo no `Workspace`;
- tag, `InteractionType` e configuracao esperada;
- personagem e root do jogador;
- distancia de aproximadamente `6` studs, suficiente para a esfera client-side;
- lock por pickup para impedir duas coletas concorrentes.

Nao sera adicionada exigencia de linha de visao, preservando o comportamento
anterior de `RequiresLineOfSight = false`.

Em uma coleta valida, o servico adicionara a instancia ao inventario. Somente
apos `InventoryService:addInstance` retornar sucesso ele removera o registro,
destruira o alvo e disparara `PickupCollected` para aquele jogador. Em caso de
falha, o alvo permanecera no mapa e o lock sera liberado.

## Fluxos

### Porta

```text
F
-> InteractionController encontra raiz Door
-> DoorController le Locked/inventario local
-> InteractDoor(unlock ou enter)
-> DoorService revalida e executa
-> DoorController mostra dialogo ou conclui a transicao
```

### Pickup

```text
F
-> InteractionController encontra raiz Pickup
-> PickupController envia CollectPickup
-> PickupService valida o alvo registrado
-> InventoryService:addInstance
-> alvo destruido e PickupCollected enviado
-> PickupNotificationController publica a notificacao
```

## Integracao e migracao

### Cliente

`src/client/init.client.luau` continuara iniciando dialogo, inventario e
transicao na ordem existente. Depois registrara os handlers de `Door` e
`Pickup` e iniciara o `InteractionController`. A chamada direta a
`DoorController.start()` sera removida.

### Servidor

`src/server/init.server.luau` continuara compondo inventario, uso de itens e
portas. Tambem criara a `ItemInstanceFactory` com um gerador server-side de
`uid`, criara o `PickupService` e o iniciara depois de `InventoryService`.

`DoorModelInitializer` sera ajustado para marcar portas com o contrato comum.
`StudioDoorScene.luau` nao sera alterado, integrado, testado nem usado como
fixture desta funcionalidade; sua remocao futura fica fora deste trabalho.

Modelos authored do mapa precisarao receber a tag e o atributo comuns. Pickups
que ainda tenham prompt serao migrados para o fluxo por `F` e seus prompts
ficarao desabilitados quando o servico reconhecer o alvo.

### Projeto de testes

`test.project.json` mapeara `src/client/interactions` e
`src/shared/interactions` quando esses diretorios forem criados. O mapeamento
existente de portas e pickups continuara disponivel. Os entrypoints normais nao
serao incluidos no projeto de testes.

## Testes

Os specs continuarao sendo ModuleScripts TestEZ strict e usarao fixtures
isoladas com limpeza em `afterEach`.

### Client

`InteractionController.spec.luau` cobrira:

- deteccao de alvos dentro e fora da esfera usando uma `ProbeConfig` de teste;
- calculo do centro a partir do `forwardOffset` configurado;
- rejeicao de alvos alem do `radius` configurado;
- exclusao do personagem;
- deteccao de `Part` e `Model` pela raiz;
- deduplicacao e escolha do alvo mais proximo;
- alvo sem configuracao valida e warnings correspondentes;
- handler ausente e warning com tipo/caminho;
- registro de handlers;
- prioridade do bind de dialogo sobre o bind de interacao em `F`;
- `setEnabled(false/true)` antes e depois de `start()`;
- idempotencia de `start()` e `stop()`.

Os testes de `DoorController` serao adaptados para chamar o handler diretamente
e continuarao cobrindo unlock, enter, dialogo, inventario e transicao.

Um spec do `PickupController` verificara que o alvo correto e enviado a
`CollectPickup`, sem simular entrega de remotes entre DataModels.

### Server

`DoorService.spec.luau` atualizara as fixtures para o contrato comum e mantera
a cobertura de validacao, unlock, enter e concorrencia.

`PickupService.spec.luau` cobrira:

- descoberta de pickups authored existentes;
- registro de novos pickups;
- rejeicao de item desconhecido e quantidade invalida;
- criacao server-side de `ItemInstance` e `uid`;
- coleta dentro da distancia;
- rejeicao de alvo nao registrado, removido ou distante;
- preservacao do pickup quando o inventario falhar;
- lock contra duas coletas concorrentes;
- destruicao e notificacao somente apos sucesso;
- desabilitacao de `ProximityPrompt`.

Nao serao criados specs de UI nem para `StudioDoorScene`.

## Verificacao

Executar:

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
  src/server/inventory src/server/items src/server/pickups src/server/doors src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

No Roblox Studio, iniciar uma unica sessao Play limpa do projeto de testes.
`TestEZAutoServer` e `TestEZAutoClient` devem reportar `failed == 0`. Confirmar
manualmente que portas e pickups respondem a `F`, que prompts nao coletam mais
pickups, que pickups authored funcionam, e que desabilitar/reabilitar o
controller bloqueia e restaura ambos os dominios.

Parar o Play ao final e confirmar que fixtures e conexoes temporarias foram
limpas.

## Fora de escopo

- `InteractionService` server-side ou remoto totalmente generico;
- indicador visual de alvo ou redesign de UI;
- cancelamento de transicoes, dialogos ou pedidos ja iniciados ao desabilitar;
- atributos customizados de item alem de `ItemId` e `Quantity`;
- persistencia de pickups;
- alteracao, integracao ou teste de `StudioDoorScene`;
- novos tipos concretos alem de `Door` e `Pickup`;
- geracao de loot ou reposicionamento automatico no mapa.
