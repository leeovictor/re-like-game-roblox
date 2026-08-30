# Design: PlayerController com Maquina de Estados

Data: 2026-08-30  
Status: Design consolidado; aguardando revisao do usuario; sem commit  
Escopo: fusao real de `TankController` e `CombatController` em `PlayerController`

## Objetivo

Substituir `TankController` e `CombatController` por uma unica
`PlayerController`, usando uma maquina de estados para definir o comportamento
do personagem durante o movimento e o combate.

O resultado devera:

- concentrar input, movimento, rotacao e dispatch de combate em uma unica
  controller;
- manter `CombatService` como servico de regras de combate;
- representar os modos `Free`, `Aiming` e `Reloading` como estados explicitos;
- preservar o controle de contexto ja existente no `InputManager`;
- remover locks externos de combate e o uso de `acquireLock` pelo inventario;
- manter o contrato de movimento usado por inimigos e portas;
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
| Estado `Free` | Movimento, rotacao e corrida normais |
| Estado `Aiming` | Sem movimento ou corrida; somente rotacao e disparo |
| Estado `Reloading` | Sem movimento, corrida, rotacao ou disparo |
| Contexto bloqueado | Continua sendo responsabilidade do `InputManager`, nao um estado do player |
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

EnemyController, Enemy e DoorController
  -> dependem do contrato MovementController de PlayerController
```

A estrutura de arquivos sera:

```text
src/client/player/
  PlayerController.luau
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
personagem. `CombatService` continuara tendo um estado operacional interno para
validar mira e recarga, mas as transicoes de comportamento do player serao
orquestradas pela controller e mantidas sincronizadas com as operacoes aceitas
pelo service.

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
arma, munição invalida, pente cheio, falta de reserva e cooldown de disparo.

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

export type PlayerController = MovementController & {
    state: PlayerState,
    started: boolean,
    start: (self: PlayerController) -> (),
    stop: (self: PlayerController) -> (),
}
```

O `CombatService` deixara de importar `TankController` e tera somente as
dependencias de inventario e inimigos. A API sera ajustada para que:

- `beginAim()` retorne se a mira foi aceita e, quando aplicavel, a direcao do
  alvo adquirido;
- `endAim()` encerre a mira;
- `shoot()` execute um disparo ou rejeite a operacao;
- `requestReload()` inicie uma recarga aceita;
- `update(deltaTime)` cuide da temporizacao interna da recarga;
- nao exista `setTurnInput()`;
- nao exista `acquireLock()`.

O contrato de movimento utilizado por `EnemyController`, `Enemy`,
`enemies/types` e `DoorController` sera atualizado para apontar para
`PlayerController.MovementController`.

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
do loop do player; nao existira um segundo loop de movimento ou combate.

Quando `InputManager` trocar para `DialogueContext` ou desabilitar o contexto
atual, os valores do `PlayContext` serao restaurados para seus defaults. A
liberacao de `Aim` encerrara a mira, e os valores zerados farao a controller
parar. Nao sera criado um estado `Locked`.

O inventario nao chamara mais `combatService:acquireLock()`. Nenhum contexto
novo sera adicionado para o inventario nesta mudanca.

## Composicao

`src/client/init.client.luau` continuara sendo o composition root. A ordem
relevante sera:

1. criar e iniciar `InventoryController`;
2. criar e iniciar `EnemyController` com o contrato de movimento do player;
3. criar `CombatService` com inventario e inimigos;
4. criar `PlayerController` com `combat = combatService`;
5. iniciar `PlayerController`, que iniciara o service;
6. passar `combatService` para a UI para leitura de estado e municao.

Os comandos diretos `tankController:start()` e `combatController:start()` serao
substituidos por `playerController:start()`. A UI continuara recebendo
`combatService`, mas nao podera adquirir locks externos.

## Arquivos envolvidos

### Criados

- `src/client/player/PlayerController.luau`;
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
- `src/client/init.client.luau`: compor e iniciar apenas `PlayerController`;
- `src/client/enemies/EnemyController.luau`: atualizar o tipo da dependencia de
  movimento;
- `src/client/enemies/Enemy.luau`: atualizar o tipo do movimento recebido;
- `src/client/enemies/types.luau`: atualizar o contrato importado;
- `src/client/doors/DoorController.luau`: atualizar o tipo da dependencia;
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
- Os consumidores de movimento funcionam com `PlayerController`.

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
