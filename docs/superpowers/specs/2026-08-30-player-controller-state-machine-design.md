# Design: PlayerController com Maquina de Estados

Data: 2026-08-30  
Status: Design consolidado; aguardando revisao do usuario; sem commit  
Escopo: fusao real de `TankController` e `CombatController`, mais efeito de ataque do player

## Objetivo

Substituir `TankController` e `CombatController` por uma unica
`PlayerController`, usando uma maquina de estados para definir o comportamento
do personagem durante o movimento e o combate.

O resultado devera:

- concentrar input, movimento, rotacao e dispatch de combate em uma unica
  controller;
- manter `CombatService` como servico de regras de combate;
- representar os modos `Free`, `Aiming` e `Reloading` como estados explicitos;
- centralizar o efeito de ataque recebido pelo player em `PlayerAttackController`;
- preservar o controle de contexto ja existente no `InputManager`;
- remover locks externos de combate e o uso de `acquireLock` pelo inventario;
- manter a escrita final do `HumanoidRootPart` sob autoridade do player;
- remover os dois controllers antigos, sem fachada ou compatibilidade temporaria;
- nao alterar nem executar testes unitarios;
- nao usar Roblox MCP nesta implementacao.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Arquitetura | Fusao real de `TankController` e `CombatController` |
| Controller resultante | `PlayerController` em `src/client/player/` |
| Estados | `Free`, `Aiming` e `Reloading` |
| Padrao | Um modulo separado por estado, seguindo `src/client/enemies/states/` |
| Efeito de ataque | `PlayerAttackController` escuta `playerAttackStarted` e `playerAttackEnded` |
| Estado `Free` | Movimento, rotacao e corrida normais |
| Estado `Aiming` | Sem movimento ou corrida; somente rotacao e disparo |
| Estado `Reloading` | Sem movimento, corrida, rotacao ou disparo |
| Contexto bloqueado | Continua sendo responsabilidade do `InputManager`, nao um estado do player |
| Transformacao durante ataque | `PlayerController` aplica um override com prioridade sobre os estados |
| Inventario | Remover o uso de `CombatService:acquireLock()` sem criar contexto novo |
| CombatService | Continua existindo, sem depender de controller de movimento |
| Rotacao de combate | Pertence ao estado `Aiming` da `PlayerController` |
| Lifecycle | `PlayerController` inicia e para o `CombatService` |
| Compatibilidade | Nenhuma API operacional antiga sera mantida |
| Testes unitarios | Fora do escopo; nao criar nem alterar specs |
| Roblox MCP | Fora do escopo; nao usar MCP |

## Arquitetura

```text
InputManager.PlayContext
  -> sinais Aim, Shoot e Reload
  -> valores Move, Rotate e Sprint

PlayerController
  -> maquina Free/Aiming/Reloading
  -> controle do Humanoid e HumanoidRootPart
  -> movimento e rotacao permitidos pelo estado
  -> encaminhamento das acoes ao CombatService
  -> uma conexao PreRender

CombatService
  -> inventario, municao, dano, sons e animacao
  -> aquisicao inicial de alvo
  -> cooldown e temporizacao de recarga
  -> nenhum movimento, rotacao ou lock externo

EnemyController
  -> expoe sinais tipados de inicio e fim de ataque

PlayerAttackController
  -> escuta os sinais de ataque
  -> controla a interpolacao do efeito no player
  -> desabilita o InputManager durante o efeito

DoorController
  -> usa o contrato de transformacao do PlayerController para teleporte pontual
```

A estrutura de arquivos sera:

```text
src/client/player/
  PlayerController.luau
  PlayerAttackController.luau
  types.luau
  states/
    Free.luau
    Aiming.luau
    Reloading.luau
```

Os estados terao a mesma forma geral dos estados de inimigo, com `onBegin`,
`update` e `onEnd`. O contrato de contexto, o nome dos estados e o contrato dos
objetos de estado ficarao em `src/client/player/types.luau`, evitando dependencia
circular entre `PlayerController` e os modulos de estado.

`PlayerController` sera a fonte de autoridade para o modo de controle do
personagem e para a escrita final do `HumanoidRootPart`. `CombatService`
continuara tendo um estado operacional interno para validar mira e recarga, mas
as transicoes de comportamento do player serao orquestradas pela controller e
mantidas sincronizadas com as operacoes aceitas pelo service.

`PlayerAttackController` sera uma controller de efeito, nao uma segunda fonte
de escrita no personagem. Ela recebera sinais de ataque confirmados, calculara
o `CFrame` desejado e atualizara um `TransformOverride` pertencente ao
`PlayerController`. O `PlayerController` aplicara esse override no seu proprio
`PreRender`, antes de executar o estado normal.

`DoorManager:enter()` tambem nao escrevera diretamente no personagem. Ele
calculara o destino e o retornara em `destinationCFrame`. `DoorController`
entregara esse valor ao metodo `PlayerController:setCFrame`, mantendo a mesma
regra de uma unica fonte de escrita.

## Maquina de estados

### Estado `Free`

Ao entrar em `Free`, a mira ativa sera encerrada quando necessario. Durante a
atualizacao:

- `Move` sera convertido em movimento tank;
- `Rotate` sera convertido em rotacao tank;
- `Sprint` definira `Humanoid.WalkSpeed` entre a velocidade de caminhada e a de
  corrida;
- `Move` e `Rotate` com valores padrao, produzidos por um contexto desabilitado,
  resultarao em personagem parado;
- `Aim=true` chamara `CombatService:beginAim()`;
- a transicao para `Aiming` so ocorrera se a mira for aceita pelo service;
- se o service fornecer uma direcao de aquisicao inicial, a controller a
  aplicara por `setLookVector`.

### Estado `Aiming`

Durante a atualizacao:

- o movimento sera sempre `Vector3.zero`;
- a corrida sera ignorada;
- `Rotate` aplicara somente a rotacao manual em torno do eixo Y;
- a velocidade configurada nao sera usada para gerar deslocamento;
- `Shoot=true` chamara `CombatService:shoot()`;
- se o disparo iniciar uma recarga por falta de municao, a controller mudara
  para `Reloading`;
- `Reload=true` chamara `CombatService:requestReload()`;
- a transicao para `Reloading` so ocorrera quando a recarga for aceita;
- `Aim=false` chamara `CombatService:endAim()` e levara a controller para
  `Free`.

### Estado `Reloading`

Durante a atualizacao:

- o movimento sera sempre `Vector3.zero`;
- a rotacao sera sempre zero;
- `Move`, `Rotate`, `Sprint`, `Aim`, `Shoot` e `Reload` nao terao efeito;
- `CombatService:update(deltaTime)` continuara sendo executado para concluir a
  recarga;
- quando o service voltar a `neutral`, a controller consultara o valor atual de
  `PlayContext.GetActionState("Aim")`;
- com `Aim=true`, a controller iniciara uma nova mira e ira para `Aiming`;
- com `Aim=false`, ira para `Free`.

As transicoes principais serao:

```text
Free --Aim aceito--> Aiming
Aiming --Aim liberado--> Free
Aiming --Reload aceito--> Reloading
Aiming --Shoot esvazia e inicia recarga--> Reloading
Reloading --recarga concluida e Aim pressionado--> Aiming
Reloading --recarga concluida e Aim liberado--> Free
```

Se uma operacao do `CombatService` for rejeitada, a controller permanecera no
estado atual e nao alterara o personagem parcialmente. Isso cobre ausencia de
 arma, municao invalida, pente cheio, falta de reserva e cooldown de disparo.

## Efeito de ataque recebido

O `EnemyController` nao recebera uma referencia do `PlayerController` e nao
escrevera diretamente no `HumanoidRootPart`. Ele criara sinais por instancia:

- `playerAttackStarted`, emitido quando a colisao e a chance do ataque forem
  confirmadas;
- `playerAttackEnded`, emitido quando o efeito terminar ou for cancelado.

O evento de inicio carregara `enemy`, `attackId`, `startCFrame`, `targetCFrame`,
`turnDuration` e `duration`. O evento de fim carregara `enemy`, `attackId` e
`cancelled`. O par `enemy`/`attackId` impedira que um encerramento antigo
libere o efeito de um ataque posterior com o mesmo contador local.

`PlayerAttackController` recebera somente esses sinais e a instancia do
`PlayerController`:

```luau
local playerAttackController = PlayerAttackController.new({
    player = playerController,
    attackStarted = enemyController.playerAttackStarted,
    attackEnded = enemyController.playerAttackEnded,
})
```

Ao receber `playerAttackStarted`, ele desabilitara o `InputManager`, iniciara um
`TransformOverride` no player e interpolara o `CFrame` durante a duracao do
ataque. Ele nao escrevera diretamente no root. O `PlayerController` aplicara o
override no seu `PreRender` e suspendera a atualizacao de `Free`, `Aiming` ou
`Reloading` enquanto o override estiver ativo.

O override sera liberado quando o `playerAttackEnded` correspondente chegar.
O controller tambem usara a duracao como fallback para nao deixar o player
preso caso o evento de fim seja perdido. Ao liberar, ele reativara o
`InputManager` somente se tiver sido o dono da desativacao.

O estado `attacking` do inimigo continuara interpolando o proprio root e
aplicando o dano ao terminar. A interpolacao do player sera removida de
`src/client/enemies/states/attacking.luau`. `Enemy.destroy()` emitira o fim
cancelado quando destruir um ataque ativo.

## Contratos e API

`PlayerController.new()` recebera dependencias nomeadas:

```luau
local playerController = PlayerController.new({
    combat = combatService,
})
```

O contrato publico incluira:

```luau
export type PlayerState = "Free" | "Aiming" | "Reloading"

export type MovementController = {
    setLookVector: (self: MovementController, lookVector: Vector3) -> (),
    setCFrame: (self: MovementController, cframe: CFrame) -> (),
}

export type TransformOverride = {
    setCFrame: (self: TransformOverride, cframe: CFrame) -> boolean,
    release: (self: TransformOverride) -> (),
}

export type PlayerController = MovementController & {
    state: PlayerState,
    started: boolean,
    beginTransformOverride: (
        self: PlayerController,
        attackId: number
    ) -> TransformOverride?,
    start: (self: PlayerController) -> (),
    stop: (self: PlayerController) -> (),
}
```

O `CombatService` deixara de importar `TankController` e tera somente as
dependencias de inventario e inimigos. A API sera ajustada para que:

- `beginAim()` retorne se a mira foi aceita e, quando aplicavel, a direcao do
  alvo adquirido;
- `getAimTurnSpeed()` retorne o `aimTurnSpeed` da arma equipada enquanto a mira
  puder ser executada, permitindo que o estado `Aiming` aplique a rotacao;
- `endAim()` encerre a mira;
- `shoot()` execute um disparo ou rejeite a operacao;
- `requestReload()` inicie uma recarga aceita;
- `update(deltaTime)` cuide da temporizacao interna da recarga;
- nao exista `setTurnInput()`;
- nao exista `acquireLock()`.

O contrato de transformacao utilizado por `DoorController` apontara para
`PlayerController.MovementController`. `EnemyController` e `Enemy` nao terao
essa dependencia; eles emitirao os sinais de ataque. `DoorActionResult` tera um
`destinationCFrame` opcional, preenchido somente por uma entrada bem-sucedida.

## Input e lifecycle

No `start()` da `PlayerController`:

1. iniciar `CombatService`;
2. inicializar o estado em `Free`;
3. conectar `Aim`, `Shoot` e `Reload` por `BindActionStateChanged`;
4. armazenar todas as conexoes de input na instancia;
5. criar uma unica conexao `RunService.PreRender`;
6. executar uma atualizacao inicial.

Os callbacks de input serao closures da instancia. Eles apenas encaminharao
eventos para o estado atual e verificarao `started` antes de operar.

No `stop()`:

1. marcar a controller como parada;
2. desconectar os sinais de input;
3. desconectar `PreRender`;
4. parar o `CombatService`;
5. restaurar `Humanoid.AutoRotate` e `Humanoid.WalkSpeed` originais;
6. limpar input, estado temporario e referencia do humanoid ativo;
7. voltar para `Free` sem deixar callbacks antigos ativos.

`start()` e `stop()` serao idempotentes. O `PlayerController` sera o unico dono
da escrita do root e do loop de movimento; `PlayerAttackController` tera apenas
o loop do seu efeito e nunca escrevera diretamente no personagem.

`beginTransformOverride(attackId)` so aceitara um override por vez. O handle
retornado atualizara o `CFrame` desejado na instancia, e `release()` sera
idempotente e ignorara handles de ataques antigos. No `PreRender`, o
`PlayerController` aplicara o override quando presente e retornara antes de
executar o estado normal.

Quando `InputManager` trocar para `DialogueContext` ou desabilitar o contexto
atual, os valores do `PlayContext` serao restaurados para seus defaults. A
liberacao de `Aim` encerrara a mira, e os valores zerados farao a controller
parar. Nao sera criado um estado `Locked`.

O inventario nao chamara mais `combatService:acquireLock()`. Nenhum contexto
novo sera adicionado para o inventario nesta mudanca.

`PlayerAttackController.start()` conectara os dois sinais de ataque e criara
uma conexao `PreRender` para atualizar a interpolacao. `stop()` desconectara os
sinais, liberara qualquer override ativo e restaurara o input quando a
desativacao tiver sido iniciada por ele.

## Composicao

`src/client/init.client.luau` continuara sendo o composition root. A ordem
relevante sera:

1. criar e iniciar `InventoryController`;
2. criar `EnemyController` sem dependencia do player e sem inicia-lo ainda;
3. criar `CombatService` com inventario e inimigos;
4. criar `PlayerController` com `combat = combatService`;
5. criar `PlayerAttackController` com os sinais do `EnemyController` e o player;
6. iniciar `PlayerAttackController` antes do `EnemyController` para nao perder
   sinais de ataques iniciais;
7. iniciar `PlayerController`, que iniciara o service;
8. iniciar `EnemyController`;
9. criar `DoorController` com o contrato de transformacao do player;
10. passar `combatService` para a UI para leitura de estado e municao.

Os comandos diretos `tankController:start()` e `combatController:start()` serao
substituidos por `playerController:start()`. A UI continuara recebendo
`combatService`, mas nao podera adquirir locks externos.

## Arquivos envolvidos

### Criados

- `src/client/player/PlayerController.luau`;
- `src/client/player/PlayerAttackController.luau`;
- `src/client/player/types.luau`;
- `src/client/player/states/Free.luau`;
- `src/client/player/states/Aiming.luau`;
- `src/client/player/states/Reloading.luau`.

### Removidos

- `src/client/player/TankController.luau`;
- `src/client/combat/CombatController.luau`.

### Alterados

- `src/client/combat/CombatService.luau`: remover dependencia de movimento,
  rotacao manual, locks externos e API correspondente;
- `src/client/enemies/EnemyController.luau`: expor os sinais tipados
  `playerAttackStarted` e `playerAttackEnded`;
- `src/client/enemies/Enemy.luau`: receber os sinais de ataque, emitir o inicio
  e o fim da sequencia e remover a dependencia de movimento do player;
- `src/client/enemies/types.luau`: adicionar contratos dos eventos e dos sinais;
- `src/client/enemies/states/tryAttack.luau`: emitir o evento de inicio com os
  `CFrame`s da animacao confirmada;
- `src/client/enemies/states/attacking.luau`: remover a escrita do `CFrame` do
  player e emitir o evento de fim;
- `src/client/doors/DoorController.luau`: manter somente a dependencia de
  transformacao pontual do `PlayerController`;
- `src/client/doors/DoorManager.luau`: retornar `destinationCFrame` em vez de
  escrever diretamente no `HumanoidRootPart`;
- `src/shared/doors/doorTypes.luau`: adicionar `destinationCFrame` opcional ao
  resultado de acao;
- `src/client/init.client.luau`: compor e iniciar apenas `PlayerController`;
- `src/client/ui/App.luau`: remover o efeito que chamava `acquireLock()`;
- demais referencias de producao a `TankController` e `CombatController`.

Nao serao alterados testes unitarios, codigo server, remotes, tuning de
`TankControlMath`, layouts da UI ou novos contextos do `InputManager`.

## Criterios de sucesso

- Nao existem imports ou chamadas de `TankController` e `CombatController` na
  producao.
- Existe somente uma conexao `PreRender` para movimento e combate do player.
- `Free` permite movimento, rotacao e corrida.
- `Aiming` impede movimento e corrida, mas permite rotacao e disparo.
- `Reloading` impede movimento, corrida, rotacao e disparo.
- Mira rejeitada nao muda o estado para `Aiming`.
- Recarga rejeitada nao muda o estado para `Reloading`.
- Recarga concluida retorna para `Aiming` somente quando `Aim` continua ativo.
- Troca de contexto encerra a mira por meio do `InputManager`.
- `CombatService` nao possui `acquireLock`, `setTurnInput` ou dependencia de
  movimento.
- O inventario nao chama mais `acquireLock`.
- `start()` e `stop()` permanecem idempotentes e liberam todos os recursos.
- `PlayerAttackController` aplica o efeito recebido sem escrever diretamente no
  `HumanoidRootPart`.
- `EnemyController` e `Enemy` nao dependem de `PlayerController`.
- `DoorController` usa o contrato de transformacao pontual do player.

A verificacao da implementacao usara somente lint, typecheck e builds Rojo
definidos em `AGENTS.md`. Specs unitarias e Roblox MCP nao serao usados.

## Fora de escopo

- adicionar um contexto de input para inventario;
- criar um estado `Locked` na `PlayerController`;
- redesenhar a UI de combate ou inventario;
- alterar regras server-side ou adicionar remotes;
- adicionar novos tipos de arma;
- modificar `TankControlMath` alem de ajustes estritamente necessarios de
  integracao;
- criar ou alterar testes unitarios;
- executar Roblox MCP;
- manter aliases ou fachada para as controllers removidas.
