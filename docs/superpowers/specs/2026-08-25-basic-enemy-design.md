# Design: Inimigo Basico Client-Side

Data: 2026-08-25  
Status: Aprovado em conversa; spec e plano sem commit

## Objetivo

Criar a primeira versao do sistema de inimigos do jogo com a menor arquitetura
necessaria para validar o ciclo basico de spawn, deteccao e perseguicao.

O sistema devera:

- ler os marcadores em `Workspace.EnemiesMarkers`;
- clonar `ReplicatedStorage.Models.Enemy` uma vez para cada marcador;
- criar uma instancia logica independente para cada inimigo;
- colocar os clones em `Workspace.Enemies`;
- ocultar e desabilitar a colisao dos marcadores durante o runtime;
- detectar o player por distancia;
- perseguir o player usando a API de pathfinding;
- alternar somente entre os estados `idle` e `chasing`;
- nao implementar ataque, dano, vida ou qualquer outra interacao de combate.

O runtime sera client-side. Cada cliente criara e controlara sua propria copia
visual e logica dos inimigos. Esta decisao e adequada para a versao single-player
atual e nao representa uma fronteira de seguranca para multiplayer competitivo.

## Contexto do projeto

O projeto usa Rojo e mapeia `src/client` inteiro para
`StarterPlayer.StarterPlayerScripts.Client` no `default.project.json`. O
composition root atual e `src/client/init.client.luau`.

Os assets necessarios ja existem no place principal:

```text
Workspace
|- EnemiesMarkers
|  `- [BasePart markers]

ReplicatedStorage
`- Models
   `- Enemy
```

O marker atual e um `BasePart` e o modelo `Enemy` e um rig R6 com
`HumanoidRootPart` e `Humanoid`. O modelo tem `Head` como `PrimaryPart`, por
isso o posicionamento nao deve depender de `PrimaryPart`; o
`HumanoidRootPart` sera usado explicitamente.

O place `RE Like Test` e reservado para os testes TestEZ. O projeto de testes
nao inicia os entrypoints normais e devera mapear o novo diretorio client-side
para que as specs possam importar os modulos de inimigos.

## Decisoes

| Tema | Decisao |
|---|---|
| Arquitetura | `Enemy` por spawn coordenado por `EnemyController` |
| Autoridade | Client-side, sem remotes novos |
| Fonte dos spawns | Filhos diretos `BasePart` de `Workspace.EnemiesMarkers` |
| Template | `ReplicatedStorage.Models.Enemy` |
| Pasta dos clones | `Workspace.Enemies` |
| Estados | `idle` e `chasing` |
| Raio de deteccao | `4` studs |
| Perda do alvo | Distancia maior que `4` studs |
| Recalculo de path | `0,1` segundo enquanto estiver perseguindo |
| Pathfinding | `PathfindingService:CreatePath({ AgentCanJump = false })` |
| Salto | Sem suporte; nunca definir `Humanoid.Jump` para seguir path |
| Falha de path | Voltar para `idle` |
| Diagnostico | `warn` no Output para falhas de `ComputeAsync` e status sem path |
| Combate | Fora de escopo |
| Spawn dinamico | Fora de escopo; ler markers somente no `start()` |

## Arquitetura

### `Enemy`

Criar `src/client/enemies/Enemy.luau` como uma instancia logica por clone.

O modulo exportara os contratos:

```luau
export type State = "idle" | "chasing"

export type Enemy = {
    model: Model,
    state: State,
    update: (self: Enemy, deltaTime: number) -> (),
    destroy: (self: Enemy) -> (),
}
```

`Enemy.new(model)` recebera um clone ja colocado no mundo e iniciara seu estado
como `idle`. O objeto sera responsavel por:

- localizar e guardar o `HumanoidRootPart` e o `Humanoid` do proprio modelo;
- consultar `CharacterRoot.get()` para obter o root atual do player;
- medir a distancia entre os roots;
- manter seu estado e path atual;
- controlar o intervalo minimo de `0,1` segundo entre tentativas de path;
- calcular e seguir o path enquanto estiver em `chasing`;
- voltar para `idle` quando perder o player ou o path falhar;
- destruir seu modelo em `destroy()`.

O modulo usara diretamente `CharacterRoot` e `PathfindingService`. Nao havera
injecao artificial de `Players`, `RunService` ou outros servicos Roblox. O
controller sera o responsavel por chamar `update()`.

### `EnemyController`

Criar `src/client/enemies/EnemyController.luau` como controller de runtime.

O modulo exportara uma instancia criada com `EnemyController.new()`. Como as
dependencias sao servicos e objetos do DataModel acessiveis diretamente, o
construtor nao recebera tabela de dependencias.

O controller sera responsavel por:

- localizar `Workspace.EnemiesMarkers` no `start()`;
- ocultar os markers e desabilitar sua colisao;
- localizar o template `ReplicatedStorage.Models.Enemy`;
- criar ou reutilizar `Workspace.Enemies`;
- clonar e posicionar cada inimigo;
- criar uma instancia `Enemy` para cada clone valido;
- conectar um unico `RunService.Heartbeat`;
- chamar `enemy:update(deltaTime)` para todos os inimigos;
- limpar todos os recursos criados no `stop()`.

Todo estado mutavel do controller sera criado em `new()` e ficara na instancia:

- flag `started`;
- tabela de inimigos criados;
- conexao de `Heartbeat`;
- tabela dos valores originais de `Transparency` e `CanCollide` dos markers.

Nao havera estado operacional mutavel no escopo do modulo e nao havera
singleton oculto.

## Fluxo de inicializacao

`EnemyController:start()` sera idempotente. Se ja estiver iniciado, retornara
sem criar conexoes, clones ou inimigos adicionais.

Quando iniciado pela primeira vez:

1. Localizar `Workspace.EnemiesMarkers`.
2. Percorrer somente seus filhos diretos que sejam `BasePart`.
3. Salvar `Transparency` e `CanCollide` de cada marker.
4. Aplicar `Transparency = 1` e `CanCollide = false`.
5. Localizar `ReplicatedStorage.Models.Enemy` e validar que e um `Model`.
6. Localizar `Workspace.Enemies` ou criar uma `Folder` com esse nome.
7. Clonar o template para cada marker.
8. Validar que cada clone possui `HumanoidRootPart` como `BasePart` e um
   `Humanoid`.
9. Mover o clone para `marker.Position` usando o root como referencia,
   preservando a rotacao authored do clone.
10. Criar `Enemy.new(clone)` e adicionar a instancia a lista do controller.
11. Conectar o `Heartbeat`.

O sistema nao observara `ChildAdded`, `ChildRemoved` ou novos markers depois do
`start()`. Spawns dinamicos nao fazem parte desta versao.

Se um clone nao possuir os componentes obrigatorios, o clone sera destruido e
nao sera criada uma instancia logica para ele. O controller nao devera deixar
um modelo parcialmente configurado no mundo.

## Posicionamento dos clones

O modelo `Enemy` atual possui `Head` como `PrimaryPart`, portanto
`SetPrimaryPartCFrame` ou qualquer logica que presuma o `PrimaryPart` nao sera
usada.

O posicionamento devera deslocar o modelo inteiro para que o
`HumanoidRootPart.Position` coincida com `marker.Position`. A rotacao atual do
root do clone sera preservada. A rotacao do marker nao sera aplicada, porque o
marker e um objeto de autoria espacial e pode possuir uma orientacao que nao
representa a direcao inicial do inimigo.

O marker nao sera destruido, movido, ancorado ou alterado alem de:

- `Transparency = 1` durante o runtime;
- `CanCollide = false` durante o runtime.

## Maquina de estados

### `idle`

O inimigo inicia em `idle` e permanece parado quando nao existe player root
valido ou quando a distancia ate o player e maior que `4` studs.

Enquanto estiver em `idle`:

- nenhum path sera calculado;
- o path e os waypoints logicos anteriores serao descartados;
- nenhuma nova ordem de `MoveTo` sera emitida;
- a proxima entrada em `chasing` devera permitir um calculo imediato.

### `chasing`

Quando `CharacterRoot.get()` retornar um root valido e a distancia entre o
inimigo e o player for menor ou igual a `4` studs, o inimigo entrara em
`chasing`.

Enquanto estiver em `chasing`:

- o path sera calculado imediatamente na primeira entrada do estado ou depois
  de perder o alvo;
- novos paths serao calculados a cada `0,1` segundo;
- a origem sera a posicao atual do root do inimigo;
- o destino sera a posicao atual do root do player;
- os waypoints serao enviados ao `Humanoid` com `MoveTo`;
- o inimigo nao atacara nem alterara a vida de nenhuma entidade.

Se a distancia ficar maior que `4` studs, o inimigo voltara para `idle` e
parara de seguir o path. O mesmo limite sera usado para detectar e perder o
player; nao havera histerese.

Se o player perder o personagem ou o `HumanoidRootPart`, o inimigo tambem
voltara para `idle`.

Depois de uma falha de pathfinding, o inimigo permanecera em `idle` ate a
proxima atualizacao. Se o player ainda estiver dentro do raio, ele podera
voltar para `chasing`, mas a nova tentativa respeitara o intervalo minimo de
`0,1` segundo desde a tentativa anterior. Isso evita chamadas e logs a cada
frame quando a mesma falha e persistente.

## Pathfinding

Cada `Enemy` criara um objeto `Path` com:

```luau
PathfindingService:CreatePath({
    AgentCanJump = false,
})
```

O sistema usara `ComputeAsync(enemyRoot.Position, playerRoot.Position)` e
validara `path.Status == Enum.PathStatus.Success` antes de ler
`path:GetWaypoints()`.

O primeiro waypoint depois do ponto inicial que representar o proximo ponto
navegavel sera enviado com `Humanoid:MoveTo`. Se nao houver waypoint posterior
ao ponto inicial, o path sera considerado inutil para esta V1. O sistema nao
aguardara `MoveToFinished:Wait()` dentro do loop principal e nao criara uma
coroutine por inimigo. O recalculo frequente de `0,1` segundo atualizara a
direcao e o proximo waypoint sem bloquear o controller.

O sistema nao executara `PathWaypointAction.Jump` e nunca definira
`Humanoid.Jump = true`. Se qualquer waypoint exigir `Jump`, o path sera
considerado inutil para esta V1 e tratado como falha de pathfinding.

Uma excecao durante `ComputeAsync`, status diferente de `Success`, uma lista
sem waypoint utilizavel ou um waypoint de salto sera tratado como falha de
pathfinding. O inimigo
devera:

1. registrar um `warn` no Output;
2. descartar o path atual;
3. voltar para `idle`;
4. permanecer sem atacar ou manipular vida.

Os logs de diagnostico deverao incluir pelo menos o nome do inimigo e o motivo
da falha. Para uma excecao, incluir o erro retornado. Para um status sem path,
incluir o nome do status, como `NoPath`.

Exemplos de formato aceitavel:

```text
[Enemy:Enemy_FacilityEntrance] ComputeAsync failed: <error>
[Enemy:Enemy_FacilityEntrance] Pathfinding failed with status: NoPath
```

Cada falha de calculo podera gerar seu proprio log. Nao havera supressao ou
rate limit na V1, pois o objetivo e tornar visivel a frequencia do problema
durante o teste manual.

## Lifecycle

`start()` e `stop()` seguirao o padrao do projeto e serao idempotentes.

`stop()` devera:

1. marcar o controller como parado;
2. desconectar o `Heartbeat` se existir;
3. chamar `destroy()` em cada `Enemy` criado;
4. destruir os clones dos inimigos;
5. limpar a lista de inimigos;
6. restaurar `Transparency` e `CanCollide` dos markers ainda existentes;
7. limpar a tabela de propriedades originais.

O controller nao destruira a pasta `Workspace.Enemies` se ela ja existia ou se
estiver vazia apos o cleanup, para nao remover uma instancia authored do mapa.
Ele destruira somente os clones que criou.

Depois de `stop()`, uma nova chamada a `start()` devera ocultar novamente os
markers atuais e criar um novo conjunto de clones.

## Composicao do bootstrap

`src/client/init.client.luau` continuara sendo o composition root. O bootstrap
devera importar e iniciar o controller:

```luau
local EnemyController = require(script.enemies.EnemyController)

local enemyController = EnemyController.new()
enemyController:start()
```

O controller de inimigos nao dependera do `TankController`,
`InteractionController`, `DoorManager`, `PickupManager` ou de qualquer sistema
de combate. A ordem de inicializacao devera manter o bootstrap existente
funcional e nao devera registrar novos inputs.

## Arquivos envolvidos

### Novos arquivos de producao

- `src/client/enemies/Enemy.luau`;
- `src/client/enemies/EnemyController.luau`.

### Arquivos de producao alterados

- `src/client/init.client.luau`: construir e iniciar `EnemyController`.

### Arquivos de teste alterados

- `test.project.json`: mapear `src/client/enemies` dentro do client de testes;
- `tests/client/enemies/Enemy.spec.luau`;
- `tests/client/enemies/EnemyController.spec.luau`.

O comando de typecheck devera incluir `src/client/enemies`. Nenhuma spec de UI
sera criada ou alterada.

## Testes

As specs serao `ModuleScript` strict no formato TestEZ do repositorio. Cada
fixture que criar Instances, conexoes ou estado mutavel devera ser criada em
`beforeEach` e destruida ou desconectada em `afterEach`.

Os testes ficam limitados aos seguintes comportamentos:

- criar um inimigo por marker `BasePart` direto;
- ocultar markers com `Transparency = 1` e `CanCollide = false`;
- restaurar markers e destruir clones em `stop()`;
- manter `start()` e `stop()` idempotentes;
- iniciar cada inimigo no estado `idle`;
- retornar para `idle` sem player root ou fora do raio;
- transicionar para `chasing` e chamar pathfinding em fixture navegavel;
- retornar para `idle` em falha de pathfinding.

Nao serao adicionados testes separados para filhos nao-`BasePart`, isolamento
entre duas instancias ou detalhes internos que nao sejam observaveis por esses
comportamentos.

Os cenarios de pathfinding usarao fixtures reais do DataModel do place de
testes: uma superficie navegavel para o caminho de sucesso e uma configuracao
sem caminho para o caso de falha. A spec devera capturar e limpar a referencia
de `Players.LocalPlayer.Character` quando usar um personagem fixture.

## Validacao manual

Depois da implementacao, a validacao no place principal devera confirmar:

1. Ao iniciar o cliente, os markers deixam de ser visiveis e nao colidem.
2. Existe um clone em `Workspace.Enemies` para cada marker.
3. O clone aparece com o `HumanoidRootPart` na posicao do marker.
4. Ao aproximar o player para ate `4` studs, o inimigo muda para `chasing` e
   segue o player pelo mapa.
5. Ao afastar o player para mais de `4` studs, o inimigo para e volta para
   `idle`.
6. Erros ou status sem path aparecem no Output com o nome do inimigo e o
   motivo.

## Fora de escopo

- ataque ou cooldown de ataque;
- dano ao player;
- vida, morte ou dano ao inimigo;
- autoridade server-side ou remotes;
- respawn de inimigos;
- spawn dinamico depois do `start()`;
- perseguicao de mais de um player;
- line-of-sight ou raycast;
- audios, efeitos visuais ou animacoes novas;
- salto ou tratamento de waypoints de salto;
- sistema generico de factions, aggro ou prioridade de alvos;
- configuracao de tuning por atributos do mapa;
- alterar o modelo authored em `ReplicatedStorage.Models.Enemy`;
- criar uma cena de teste permanente no place principal;
- commits da spec ou do plano de implementacao.
