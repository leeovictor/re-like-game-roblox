# PlayerController State Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fundir `TankController` e `CombatController` em `PlayerController`, adicionar os estados `Free`, `Aiming` e `Reloading`, e centralizar o efeito de ataque recebido pelo player.

**Architecture:** `PlayerController` sera a unica controller de movimento, input, rotacao e estado de controle. `CombatService` continuara cuidando das regras de combate, sem depender de movimento. `EnemyController` emitira sinais tipados `playerAttackStarted` e `playerAttackEnded`; `PlayerAttackController` escutara esses sinais, desabilitara o `InputManager` e atualizara um override que `PlayerController` aplicara como unico escritor do `HumanoidRootPart`.

**Tech Stack:** Luau strict, Roblox `RunService.PreRender`, `InputManager`, `Signal`, `Humanoid`, `CFrame`, React/ReactRoblox, Rojo 7.7.0, Selene 0.29.0 e luau-lsp 1.69.0.

## Global Constraints

- O runtime continua client-side, sem remotes novos.
- `PlayerController` e a unica controller de movimento, input e combate do player.
- Os estados de controle sao exatamente `Free`, `Aiming` e `Reloading`.
- `Free` permite movimento, rotacao e corrida.
- `Aiming` bloqueia movimento e corrida, mas permite rotacao e disparo.
- `Reloading` bloqueia movimento, corrida, rotacao e disparo.
- O contexto bloqueado continua sendo responsabilidade do `InputManager`, nao um estado `Locked`.
- `CombatService` nao depende de controller de movimento.
- `CombatService` nao possui `setTurnInput()` nem `acquireLock()` depois da migracao.
- O inventario nao chama mais `combatService:acquireLock()` e nao ganha um contexto novo.
- `PlayerController` e o unico escritor final do `HumanoidRootPart`.
- `Enemy` nao escreve o `CFrame` do player; ele emite sinais de inicio e fim de ataque.
- `PlayerAttackController` nao escreve diretamente no `HumanoidRootPart`.
- `DoorManager` calcula o destino da porta, mas `PlayerController` aplica o `CFrame` final.
- `playerAttackStarted` carrega `attackId`, `startCFrame`, `targetCFrame`, `turnDuration` e `duration`.
- `playerAttackEnded` carrega `attackId` e `cancelled`.
- Um encerramento com `attackId` antigo nao libera um override atual.
- `PlayerAttackController` chama `InputManager.disable()` somente durante um ataque ativo e restaura o input ao liberar seu proprio bloqueio.
- Nao criar nem alterar specs unitarias e nao executar TestEZ.
- Nao usar Roblox MCP.
- Manter `--!strict`; nao usar `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Usar imports absolutos por `StarterPlayer.StarterPlayerScripts.Client` nos modulos client-side, conforme `AGENTS.md`.
- Nao editar `Packages/` nem `DevPackages/`.
- Nao reverter alteracoes existentes no worktree que nao facam parte desta tarefa.
- Nao fazer commit da spec, deste plano ou da implementacao, conforme `AGENTS.md`.

## Checkpoint Estatico

Executar ao final de cada task. O sourcemap deve ser regenerado antes do LSP.

```bash
rojo sourcemap --include-non-scripts default.project.json --output /tmp/dungeon-game-canve-player-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap /tmp/dungeon-game-canve-player-sourcemap.json --formatter gnu \
  src/shared \
  src/server/player \
  src/client/camera \
  src/client/cinematics \
  src/client/combat \
  src/client/dialogue \
  src/client/doors \
  src/client/enemies \
  src/client/events \
  src/client/interactions \
  src/client/inventory \
  src/client/objectives \
  src/client/pickups \
  src/client/player \
  src/client/ui
```

Resultado esperado: nenhum diagnostico nos modulos de producao. Nao incluir a
arvore `tests` e nao executar TestEZ.

---

## File Map

### Novos arquivos

- `src/client/player/PlayerController.luau` - controller unica de input, estados, movimento, rotacao e aplicacao de transformacoes.
- `src/client/player/PlayerAttackController.luau` - coordenacao do efeito de ataque recebido, input disable e interpolacao.
- `src/client/player/types.luau` - contratos do player e dos objetos de estado sem dependencia circular.
- `src/client/player/states/Free.luau` - comportamento normal de movimento, rotacao e corrida.
- `src/client/player/states/Aiming.luau` - comportamento sem movimento, com rotacao e disparo.
- `src/client/player/states/Reloading.luau` - comportamento totalmente parado durante recarga.

### Arquivos de producao alterados

- `src/client/combat/CombatService.luau` - remover movimento, rotacao manual e locks externos; expor resultado de mira e tuning de rotacao.
- `src/client/enemies/types.luau` - contratos dos sinais de ataque e remoção da dependencia de movimento do player.
- `src/client/enemies/EnemyController.luau` - criar e expor `playerAttackStarted` e `playerAttackEnded`.
- `src/client/enemies/Enemy.luau` - armazenar sinais, emitir lifecycle do ataque e remover `movementController`.
- `src/client/enemies/states/tryAttack.luau` - emitir o inicio de ataque confirmado.
- `src/client/enemies/states/attacking.luau` - remover transformacao do player e emitir fim normal.
- `src/client/doors/DoorController.luau` - apontar a dependencia de transformacao para `PlayerController`.
- `src/client/doors/DoorManager.luau` - retornar o `destinationCFrame` sem escrever no root.
- `src/shared/doors/doorTypes.luau` - adicionar `destinationCFrame` opcional ao resultado de entrada.
- `src/client/init.client.luau` - construir `PlayerController` e `PlayerAttackController` na ordem correta.
- `src/client/ui/App.luau` - remover o efeito que chamava `acquireLock()`.

### Arquivos removidos

- `src/client/player/TankController.luau`.
- `src/client/combat/CombatController.luau`.

Nao alterar arquivos em `tests/`, `test.project.json`, codigo server ou `TankControlMath`.

---

### Task 1: Desacoplar o CombatService de movimento e locks

**Files:**
- Modify: `src/client/combat/CombatService.luau`

**Interfaces:**
- Consumes: `InventoryController.InventoryController`, `EnemyController.EnemyController`, `CombatConfig` e `CharacterRoot`.
- Produces: `CombatService.Dependencies` somente com `inventory` e `enemies`; `beginAim() -> (boolean, Vector3?)`; `getAimTurnSpeed() -> number?`; `endAim()`; `shoot() -> boolean`; `requestReload() -> boolean`; `update(deltaTime)`.

- [ ] **Step 1: Remover a dependencia de movimento e os campos de lock**

Remover o require de `TankController`, o campo `movement` de `Dependencies`, e
os campos `turnLeft`, `turnRight`, `externalLockCount`,
`externalLockGeneration` e `aimHeld` do contrato e do estado criado em `new()`.
O contrato inicial deve ficar conceitualmente assim:

```luau
export type Dependencies = {
    inventory: InventoryControllerModule.InventoryController,
    enemies: EnemyControllerModule.EnemyController,
}
```

Apagar as guardas baseadas em `externalLockCount` e toda a logica de release de
lock. Nao alterar as validacoes de inventario, cooldown, dano ou recarga que nao
dependam desses campos.

- [ ] **Step 2: Fazer a aquisicao de alvo retornar uma direcao**

Alterar `acquireInitialTarget` para retornar `Vector3?`. Manter a ordenacao por
distancia, o raio e o raycast. No primeiro inimigo visivel, retornar `offset` em
vez de chamar `movement:setLookVector(offset)`:

```luau
if result ~= nil and result.Instance:IsDescendantOf(enemy.model) then
    return offset
end
```

Quando nenhum alvo for adquirido, retornar `nil`.

- [ ] **Step 3: Atualizar o contrato de mira**

Alterar `beginAim` para retornar `(boolean, Vector3?)`. Retornar `false, nil`
quando o service nao estiver iniciado, nao houver arma valida ou a municao
carregada for invalida. Em sucesso, definir o estado interno como `aiming`,
iniciar a animacao, obter a direcao retornada por `acquireInitialTarget` e
retornar `true, targetDirection`:

```luau
local targetDirection = acquireInitialTarget(self, config)
return true, targetDirection
```

Remover `self.aimHeld = true`. `endAim` deve continuar encerrando a acao ativa,
mas sem armazenar estado de tecla.

- [ ] **Step 4: Mover a rotacao manual para o futuro PlayerController**

Remover de `CombatService.update` o bloco que consulta `turnLeft`/`turnRight`
e chama `movement:setLookVector`. `update(deltaTime)` deve continuar
incrementando `reloadElapsed` e chamando `finishReload` quando a duracao for
atingida.

Adicionar a consulta:

```luau
function CombatService.getAimTurnSpeed(self: CombatService): number?
    if self.state ~= "aiming" then
        return nil
    end
    local _, config = getWeapon(self)
    return if config ~= nil then config.aimTurnSpeed else nil
end
```

- [ ] **Step 5: Remover o reingresso automatico em mira**

Em `finishReload`, manter a limpeza de `reloadWeaponUid`, `reloadElapsed` e
`reloadGeneration`, mas remover a chamada `self:beginAim()`. A controller do
player decidira a proxima transicao lendo
`PlayContext.GetActionState("Aim")`.

Em `requestReload`, remover a guarda de `aimHeld` e de lock. O service ainda
deve exigir `started`, estado `aiming`, arma valida, pente incompleto e reserva
disponivel.

- [ ] **Step 6: Remover API morta e verificar referencias internas**

Apagar `setTurnInput` e `acquireLock` inteiros, incluindo os campos associados.
Usar busca de producao para confirmar que o arquivo nao contem:

```text
TankController
setTurnInput
acquireLock
movement
externalLock
turnLeft
turnRight
aimHeld
```

Preservar `CombatService.start()` observando `InventoryController.changed` e
`CombatService.stop()` limpando animacao, recarga e conexao.

- [ ] **Step 7: Rodar o checkpoint estatico**

Executar o `Checkpoint Estatico` deste plano. O resultado esperado e nenhum
diagnostico nos modulos de producao, mesmo que referencias antigas de outros
arquivos ainda sejam removidas nas tasks seguintes.

---

### Task 2: Criar contratos e estados do PlayerController

**Files:**
- Create: `src/client/player/types.luau`
- Create: `src/client/player/states/Free.luau`
- Create: `src/client/player/states/Aiming.luau`
- Create: `src/client/player/states/Reloading.luau`

**Interfaces:**
- Consumes: `CombatService.CombatService` e `TankControlMath.InputState`.
- Produces: `PlayerTypes.PlayerState`, `PlayerTypes.StateObject`, `PlayerTypes.StateContext`, `FreeState`, `AimingState` e `ReloadingState`.

- [ ] **Step 1: Definir os contratos sem importar PlayerController**

Criar `types.luau` com `--!strict`, importando `CombatService` e
`TankControlMath`. Usar estes contratos como base:

```luau
export type PlayerState = "Free" | "Aiming" | "Reloading"

export type InputState = TankControlMath.InputState & {
    running: boolean,
    aiming: boolean,
}

export type StateContext = {
    input: InputState,
    combat: CombatServiceModule.CombatService,
    transition: (nextState: PlayerState) -> (),
    beginAim: () -> (boolean, Vector3?),
    endAim: () -> (),
    shoot: () -> boolean,
    requestReload: () -> boolean,
    updateFreeMovement: (deltaTime: number) -> (),
    updateAimRotation: (deltaTime: number) -> (),
    stopMovement: () -> (),
    setLookVector: (lookVector: Vector3) -> (),
}

export type StateObject = {
    onBegin: ((context: StateContext) -> ())?,
    onEnd: ((context: StateContext) -> ())?,
    update: (context: StateContext, deltaTime: number) -> (),
    onAimChanged: ((context: StateContext, aiming: boolean) -> ())?,
    onShoot: ((context: StateContext) -> ())?,
    onReload: ((context: StateContext) -> ())?,
}
```

Adicionar tambem os contratos `MovementController`, `TransformOverride` e
`PlayerController` exportados pelo modulo para serem alias usados em
`PlayerController.luau`:

```luau
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

- [ ] **Step 2: Implementar o estado Free**

Criar um `StateObject` que chame `context.updateFreeMovement(deltaTime)` em
`update`. No callback `onAimChanged`, ignorar `false`; para `true`, chamar
`context.beginAim()`, aplicar a direcao retornada quando nao for `nil`, e
transicionar para `Aiming` somente quando o retorno for aceito:

```luau
onAimChanged = function(context, aiming)
    if not aiming then
        return
    end
    local accepted, targetDirection = context.beginAim()
    if not accepted then
        return
    end
    if targetDirection ~= nil then
        context.setLookVector(targetDirection)
    end
    context.transition("Aiming")
end
```

Deixar `onShoot` e `onReload` ausentes ou sem efeito no estado `Free`.

- [ ] **Step 3: Implementar o estado Aiming**

O `update` deve chamar `context.stopMovement()` e
`context.updateAimRotation(deltaTime)`. O callback `onAimChanged(false)` deve
chamar `context.endAim()` e transicionar para `Free`.

No callback `onShoot`, chamar `context.shoot()`. Se a chamada fizer o
`CombatService` entrar em `reloading`, transicionar para `Reloading`.

No callback `onReload`, chamar `context.requestReload()` e transicionar para
`Reloading` somente quando retornar `true`.

- [ ] **Step 4: Implementar o estado Reloading**

O `update` deve chamar `context.stopMovement()` em todos os frames. O
`PlayerController` chamara `CombatService:update(deltaTime)` antes do update do
estado; portanto o estado deve apenas verificar a conclusao:

```luau
if context.combat.state ~= "neutral" then
    return
end

if context.input.aiming then
    local accepted, targetDirection = context.beginAim()
    if accepted then
        if targetDirection ~= nil then
            context.setLookVector(targetDirection)
        end
        context.transition("Aiming")
        return
    end
end

context.transition("Free")
```

Os callbacks `onAimChanged`, `onShoot` e `onReload` nao devem iniciar outra
acao enquanto o estado for `Reloading`.

- [ ] **Step 5: Rodar o checkpoint estatico**

Executar o `Checkpoint Estatico` deste plano. Corrigir apenas erros nos novos
contratos e estados; nao tocar na arvore de testes.

---

### Task 3: Implementar o PlayerController e o TransformOverride

**Files:**
- Create: `src/client/player/PlayerController.luau`

**Interfaces:**
- Consumes: `InputManager.Contexts.PlayContext`, `TankControlMath`, `CombatService.CombatService` e estados da Task 2.
- Produces: `PlayerController.new(dependencies, config?)`, `start`, `stop`, `setLookVector`, `setCFrame` e `beginTransformOverride`.

- [ ] **Step 1: Definir a API e o estado por instancia**

Criar `PlayerController.luau` com imports absolutos e estes tipos:

```luau
export type Dependencies = {
    combat: CombatServiceModule.CombatService,
}

export type PlayerControllerConfig = {
    walkSpeed: number?,
    runSpeed: number?,
}

export type MovementController = PlayerTypes.MovementController
export type TransformOverride = PlayerTypes.TransformOverride

export type PlayerController = PlayerTypes.MovementController & {
    state: PlayerTypes.PlayerState,
    started: boolean,
    beginTransformOverride: (
        self: PlayerController,
        attackId: number
    ) -> PlayerTypes.TransformOverride?,
    start: (self: PlayerController) -> (),
    stop: (self: PlayerController) -> (),
}
```

Criar em `new()` uma tabela de input, os speeds configurados, `started = false`,
`state = "Free"`, `currentState`, `inputConnections`, `renderConnection`,
`activeHumanoid`, `originalAutoRotate`, `originalWalkSpeed`,
`controlledLookVector`, `transformOverride` e uma geracao do override. Nenhum
recurso deve ser criado fora da instancia.

- [ ] **Step 2: Migrar a resolucao do personagem e a escrita de orientacao**

Migrar `resolveCharacter`, `acquireHumanoid` e `releaseHumanoid` do
`TankController`. `acquireHumanoid` deve salvar e desabilitar
`Humanoid.AutoRotate`; `releaseHumanoid` deve restaurar `AutoRotate` e
`WalkSpeed`.

Manter `setLookVector` e `setCFrame` como metodos da instancia. Ambos devem
normalizar a direcao horizontal quando aplicavel, atualizar
`controlledLookVector` e alterar o root somente se houver um `HumanoidRootPart`
valido. `setCFrame` deve preservar o comportamento de sincronizar a direcao
controlada depois de um teleporte da porta.

- [ ] **Step 3: Implementar as operacoes usadas pelos estados**

Implementar closures ou helpers da instancia para:

- `updateFreeMovement(deltaTime)`: ler `controlledLookVector` ou o look atual,
  resolver velocidade por `TankControlMath.resolveSpeed`, calcular o movimento
  com `TankControlMath.calculate`, aplicar rotacao e chamar `Humanoid:Move`;
- `updateAimRotation(deltaTime)`: ignorar movimento, consultar
  `combat:getAimTurnSpeed()`, usar `input.left`/`input.right`, aplicar somente
  rotacao no eixo Y e zerar `AssemblyAngularVelocity`;
- `stopMovement()`: chamar `Humanoid:Move(Vector3.zero, false)` e zerar a
  velocidade angular quando houver humanoid ativo;
- `readInput()`: obter `Move`, `Rotate`, `Sprint` e `Aim` do `PlayContext` e
  atualizar a tabela de input.

O estado `Aiming` nunca deve chamar `TankControlMath.calculate` para deslocar o
personagem. O estado `Reloading` tambem nao deve alterar orientacao.

- [ ] **Step 4: Implementar transicoes e contexto dos estados**

Criar o mapa:

```luau
local states: { [PlayerTypes.PlayerState]: PlayerTypes.StateObject } = {
    Free = FreeState,
    Aiming = AimingState,
    Reloading = ReloadingState,
}
```

Criar um `StateContext` estavel com closures para `transition`, `beginAim`,
`endAim`, `shoot`, `requestReload`, movimento, rotacao, parada e orientacao.
`transition` deve chamar `onEnd` do estado anterior, atualizar `state` e
`currentState`, e chamar `onBegin` do novo estado. Ignorar transicao para o
mesmo estado.

- [ ] **Step 5: Implementar o override de transformacao**

`beginTransformOverride(attackId)` deve retornar `nil` se a controller nao
estiver iniciada ou se outro override estiver ativo. Em sucesso, criar um
handle com a geracao atual:

```luau
local override = playerController:beginTransformOverride(attackId)
if override ~= nil then
    override:setCFrame(nextCFrame)
end
```

`handle:setCFrame(cframe)` deve apenas armazenar o `CFrame` desejado e retornar
`true` enquanto o handle for o override ativo. `handle:release()` deve ser
idempotente, limpar o override somente se a geracao ainda for a mesma e
ignorar handles antigos.

No loop de `PreRender`, depois de `combat:update(deltaTime)`, aplicar o override
quando presente e retornar sem chamar o estado normal:

```luau
local override = self.transformOverride
if override ~= nil then
    applyOverrideCFrame(self, override.cframe)
    return
end

self.currentState.update(self.stateContext, deltaTime)
```

Isso garante que `PlayerController` nao sobrescreva a interpolacao de ataque.

- [ ] **Step 6: Implementar input bindings e lifecycle**

Em `start()`:

1. retornar sem efeito se `started` ja for `true`;
2. marcar `started = true`;
3. chamar `combat:start()`;
4. conectar `Aim`, `Shoot` e `Reload` do `PlayContext` por closures;
5. armazenar cada retorno em `inputConnections`;
6. sincronizar input atual;
7. processar `Aim=true` inicial pelo estado `Free`;
8. conectar uma unica funcao a `RunService.PreRender`.

O callback de `Aim` deve atualizar `input.aiming` e delegar ao
`currentState.onAimChanged`. Os callbacks `Shoot` e `Reload` so devem delegar
quando o valor recebido for `true`.

Em `stop()`:

1. retornar sem efeito se ja estiver parado;
2. marcar `started = false`;
3. desconectar e limpar `inputConnections`;
4. desconectar `renderConnection`;
5. limpar e invalidar qualquer `transformOverride`;
6. chamar `combat:stop()`;
7. limpar input e restaurar o humanoid;
8. definir `state = "Free"`.

- [ ] **Step 7: Rodar o checkpoint estatico**

Executar o `Checkpoint Estatico` deste plano. O resultado esperado e nenhum
diagnostico nos modulos de producao.

---

### Task 4: Publicar o lifecycle de ataques do EnemyController

**Files:**
- Modify: `src/client/enemies/types.luau`
- Modify: `src/client/enemies/EnemyController.luau`
- Modify: `src/client/enemies/Enemy.luau`
- Modify: `src/client/enemies/states/tryAttack.luau`
- Modify: `src/client/enemies/states/attacking.luau`

**Interfaces:**
- Consumes: dados atuais de colisao, orientacoes do ataque e `Enemy` state machine.
- Produces: sinais por instancia `playerAttackStarted` e `playerAttackEnded`; `Enemy` sem `movementController`.

- [ ] **Step 1: Definir eventos e sinais tipados**

Em `enemies/types.luau`, adicionar contratos sem importar
`PlayerController`:

```luau
export type SignalConnection = {
    Disconnect: (self: SignalConnection) -> (),
}

export type PlayerAttackStartedEvent = {
    enemy: Enemy,
    attackId: number,
    startCFrame: CFrame,
    targetCFrame: CFrame,
    turnDuration: number,
    duration: number,
}

export type PlayerAttackEndedEvent = {
    enemy: Enemy,
    attackId: number,
    cancelled: boolean,
}

export type PlayerAttackStartedSignal = {
    Fire: (self: PlayerAttackStartedSignal, event: PlayerAttackStartedEvent) -> (),
    Connect: (
        self: PlayerAttackStartedSignal,
        callback: (event: PlayerAttackStartedEvent) -> ()
    ) -> SignalConnection,
}

export type PlayerAttackEndedSignal = {
    Fire: (self: PlayerAttackEndedSignal, event: PlayerAttackEndedEvent) -> (),
    Connect: (
        self: PlayerAttackEndedSignal,
        callback: (event: PlayerAttackEndedEvent) -> ()
    ) -> SignalConnection,
}

export type PlayerAttackSignals = {
    playerAttackStarted: PlayerAttackStartedSignal,
    playerAttackEnded: PlayerAttackEndedSignal,
}
```

Adicionar `PlayerAttackSignals` para passar os sinais ao `Enemy` sem passar o
controller concreto. Remover o import e o campo de `TankController` do contrato
do inimigo.

- [ ] **Step 2: Criar sinais no EnemyController e remover sua dependencia de movimento**

Alterar `EnemyController.Dependencies` para uma tabela vazia ou remover o
parametro de `new()`. Em `new()`, criar dois `Signal.new()` por instancia e
armazenar `playerAttackStarted` e `playerAttackEnded` no controller.

Ao criar cada `Enemy`, passar `PlayerAttackSignals` e nao um
`movementController`. Expor os dois sinais no tipo publico de
`EnemyController`.

`EnemyController.start()` continuara criando os inimigos e atualizando-os no
`Heartbeat`; a mudanca nao deve criar outro loop para o player.

- [ ] **Step 3: Armazenar lifecycle de ataque no Enemy**

Alterar `Enemy.new(model, signals)` para guardar `playerAttackStarted`,
`playerAttackEnded`, um contador `playerAttackGeneration` e
`activePlayerAttackId`. Remover
`movementController`, `attackingPlayerStartCFrame` e
`attackingPlayerTargetCFrame` do objeto quando eles nao forem mais necessarios
fora do evento.

Ao destruir um inimigo com ataque ativo, emitir:

```luau
self.playerAttackEnded:Fire({
    enemy = self,
    attackId = self.activePlayerAttackId,
    cancelled = true,
})
```

Limpar o id antes de finalizar o objeto para evitar emissao duplicada.

- [ ] **Step 4: Emitir `playerAttackStarted` em `tryAttack`**

No trecho em que a colisao e a chance do ataque ja foram confirmadas:

1. obter `attackingEnemyTargetCFrame` e `attackingPlayerTargetCFrame` como hoje;
2. incrementar `playerAttackGeneration`;
3. salvar `activePlayerAttackId`;
4. definir `playerAttackOwner = true` e `state.playerAttackInProgress = true`;
5. emitir o evento com os CFrames e os tempos de `config`;
6. retornar `"attacking"`.

Usar `turnDuration = config.ATTACKING_TURN_TIME` e
`duration = config.ATTACKING_TIME`, preservando a diferenca entre o tempo de
orientacao e o tempo total do golpe. Remover a chamada
`enemy.movementController:setLookVector(...)`.

- [ ] **Step 5: Remover transformacao do player e emitir fim normal**

Em `attacking.luau`, manter somente a interpolacao do proprio
`enemyRoot`. Remover a interpolacao e a chamada `setCFrame` do player.

No `onEnd`, aplicar o dano como atualmente e emitir o fim correspondente:

```luau
local attackId = enemy.activePlayerAttackId
if attackId ~= nil then
    enemy.playerAttackEnded:Fire({
        enemy = enemy,
        attackId = attackId,
        cancelled = false,
    })
    enemy.activePlayerAttackId = nil
end
```

Garantir que o fim seja emitido uma unica vez antes de limpar o estado do
ataque.

- [ ] **Step 6: Rodar o checkpoint estatico**

Executar o `Checkpoint Estatico`. Confirmar que `EnemyController` e `Enemy` nao
importam `TankController` nem `PlayerController`.

---

### Task 5: Implementar o PlayerAttackController

**Files:**
- Create: `src/client/player/PlayerAttackController.luau`

**Interfaces:**
- Consumes: `PlayerController.PlayerController`, `PlayerAttackStartedSignal` e `PlayerAttackEndedSignal`.
- Produces: `PlayerAttackController.new(dependencies)`, `start()` e `stop()`.

- [ ] **Step 1: Definir dependencia e estado por instancia**

Criar os tipos:

```luau
export type Dependencies = {
    player: PlayerControllerModule.PlayerController,
    attackStarted: EnemyTypes.PlayerAttackStartedSignal,
    attackEnded: EnemyTypes.PlayerAttackEndedSignal,
}

export type PlayerAttackController = {
    started: boolean,
    start: (self: PlayerAttackController) -> (),
    stop: (self: PlayerAttackController) -> (),
}
```

O estado deve conter `started`, `inputConnections`, `renderConnection`,
`activeAttack`, `inputDisabledBySelf` e nenhum estado em escopo de modulo.
`activeAttack` deve armazenar `enemy`, `attackId`, o evento, o override e o
tempo decorrido.

- [ ] **Step 2: Iniciar o efeito ao receber `playerAttackStarted`**

No callback do sinal:

1. ignorar o evento se o controller estiver parado ou ja houver ataque ativo;
2. chamar `player:beginTransformOverride(event.attackId)`;
3. ignorar o evento se o player nao aceitar o override;
4. chamar `InputManager.disable()`;
5. marcar `inputDisabledBySelf = true`;
6. armazenar o evento, o handle e `elapsed = 0`;
7. definir o CFrame inicial no handle.

O controller recebe o signal como dependencia, nao busca `EnemyController` por
`Locator` e nao importa um singleton operacional.

- [ ] **Step 3: Interpolar no loop proprio sem escrever no root**

Conectar `RunService.PreRender` em `start()`. Enquanto houver ataque ativo:

```luau
active.elapsed += deltaTime
local progress = math.clamp(
    active.elapsed / active.event.turnDuration,
    0,
    1
)
local cframe = active.event.startCFrame:Lerp(active.event.targetCFrame, progress)
active.override:setCFrame(cframe)
```

Depois de `turnDuration`, manter o `targetCFrame` no override ate o fim normal
ou o fallback de `duration`. O controller nunca deve alterar o root diretamente.

- [ ] **Step 4: Encerrar por signal, fallback ou cancelamento**

No callback de `playerAttackEnded`, comparar `enemy` e `attackId` com o ataque
ativo. Se qualquer um nao corresponder, ignorar. Se corresponder:

1. aplicar uma ultima vez `targetCFrame` quando o ataque nao for cancelado;
2. chamar `override:release()`;
3. limpar `activeAttack`;
4. chamar `InputManager.enable()` somente quando `inputDisabledBySelf` for `true`;
5. limpar `inputDisabledBySelf`.

No `PreRender`, se `elapsed >= event.duration` e ainda nao houver evento de fim,
executar a mesma rotina de release como fallback. Um evento de fim posterior
deve ser ignorado pelo `attackId`/ausencia de ataque ativo.

- [ ] **Step 5: Implementar lifecycle idempotente**

`start()` deve ignorar chamada repetida, conectar os dois sinais, criar o loop
de `PreRender` e nao iniciar um ataque por conta propria.

`stop()` deve ignorar chamada repetida, desconectar sinais e render loop,
liberar override ativo e restaurar o input se o bloqueio tiver sido iniciado por
esta instancia.

- [ ] **Step 6: Rodar o checkpoint estatico**

Executar o `Checkpoint Estatico`. Confirmar que o unico modulo que escreve no
`HumanoidRootPart` durante o efeito e `PlayerController`.

---

### Task 6: Migrar composition root, porta e UI; remover controllers antigos

**Files:**
- Modify: `src/client/init.client.luau`
- Modify: `src/client/doors/DoorController.luau`
- Modify: `src/client/doors/DoorManager.luau`
- Modify: `src/shared/doors/doorTypes.luau`
- Modify: `src/client/ui/App.luau`
- Delete: `src/client/player/TankController.luau`
- Delete: `src/client/combat/CombatController.luau`

**Interfaces:**
- Consumes: APIs produzidas nas Tasks 1, 3, 4 e 5.
- Produces: composition root sem `TankController`/`CombatController`, `DoorController` usando `PlayerController.MovementController`, `DoorManager` sem escrita direta no root e UI sem `acquireLock()`.

- [ ] **Step 1: Atualizar imports e tipos do DoorController**

Trocar o import de `TankController` por `PlayerController` e atualizar:

```luau
movement: PlayerController.MovementController,
```

Remover o import de `CharacterRoot`, pois o manager retornara o destino. Apos
uma entrada bem-sucedida, aplicar somente o CFrame retornado:

```luau
if result.success and result.action == "enter" and result.destinationCFrame ~= nil then
    dependencies.movement:setCFrame(result.destinationCFrame)
end
```

Essa e uma transformacao pontual que sincroniza `controlledLookVector` e passa
pelo unico escritor do root, `PlayerController`.

- [ ] **Step 2: Fazer DoorManager retornar o destino sem escrever no root**

Adicionar `destinationCFrame: CFrame?` a `doorTypes.DoorActionResult`. Em
`DoorManager.enter`, manter as validacoes de distancia, lado, porta trancada e
selada. Calcular o destino como hoje, mas substituir:

```luau
root.CFrame = CFrame.lookAt(destination, destination + direction)
result = { success = true, action = "enter" }
```

por:

```luau
result = {
    success = true,
    action = "enter",
    destinationCFrame = CFrame.lookAt(destination, destination + direction),
}
```

Manter `CharacterRoot.get()` para validar a posicao atual e calcular a altura;
somente a escrita do CFrame sera removida.

- [ ] **Step 3: Remover o lock da UI**

Em `src/client/ui/App.luau`, remover completamente o effect que depende de
`inventoryVisible` e chama:

```luau
props.combatService:acquireLock()
```

Nao substituir por `InputManager.disable()`, contexto novo ou outro lock. Manter
as props e leituras de `combatService` usadas para HUD de arma e municao.

- [ ] **Step 4: Reorganizar a composicao no init.client.luau**

Remover os requires de `TankController` e `CombatController`; adicionar
`PlayerController` e `PlayerAttackController`.

Usar esta ordem, preservando as instancias compartilhadas:

```luau
local inventoryController = InventoryController.new()
inventoryController:start()

local enemyController = EnemyController.new()

local combatService = CombatService.new({
    inventory = inventoryController,
    enemies = enemyController,
})

local playerController = PlayerController.new({
    combat = combatService,
})

local playerAttackController = PlayerAttackController.new({
    player = playerController,
    attackStarted = enemyController.playerAttackStarted,
    attackEnded = enemyController.playerAttackEnded,
})

playerAttackController:start()
playerController:start()
enemyController:start()
```

Criar `DoorController` depois de `playerController` e passar `movement =
playerController`. Remover `combatService:start()` e os dois starts antigos; o
`PlayerController:start()` inicia o service.

Manter `combatService` nas props do `App` e manter `enemyController` sendo
passado ao `CombatService` por referencia nomeada. Nao registrar essas
instancias no `Locator` para resolver dependencias.

- [ ] **Step 5: Remover arquivos antigos e referencias de producao**

Apagar `TankController.luau` e `CombatController.luau` com `apply_patch`. Fazer
busca somente em `src/` e confirmar que nao restam:

```text
require(...TankController)
require(...CombatController)
TankController
CombatController
acquireLock
setTurnInput
```

Nao corrigir referencias nas specs unitarias, conforme solicitado; elas ficam
fora da implementacao e fora do typecheck deste plano.

- [ ] **Step 6: Rodar o checkpoint estatico**

Executar o `Checkpoint Estatico`. Corrigir imports absolutos, contratos e ordem
de lifecycle ate nao haver diagnosticos de producao.

---

### Task 7: Verificacao final de producao

**Files:**
- Verify: todos os arquivos de producao alterados nas Tasks 1-6
- Do not modify: `tests/`

- [ ] **Step 1: Executar lint de producao**

Executar:

```bash
selene --config selene.roblox.toml src
```

Esperado: nenhum diagnostico. Nao executar o lint da arvore `tests`.

- [ ] **Step 2: Executar o checkpoint final de LSP**

Executar integralmente o `Checkpoint Estatico` depois do lint. Esperado: nenhum
diagnostico nos diretorios de producao analisados.

- [ ] **Step 3: Construir os dois projetos Rojo**

Executar:

```bash
rojo build -o /tmp/dungeon-game-canve-player.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-player-test.rbxlx test.project.json
```

Esses builds verificam o mapeamento dos projetos; nao iniciar Play nem executar
TestEZ.

- [ ] **Step 4: Fazer busca final de contratos antigos**

Confirmar em `src/` que nao existem imports ou chamadas operacionais de
`TankController`, `CombatController`, `setTurnInput` ou `acquireLock`. Confirmar
que `PlayerAttackController` nao contem escrita direta em
`HumanoidRootPart.CFrame` e que `Enemy` nao contem `movementController`.

- [ ] **Step 5: Revisar o diff sem commit**

Executar `git status --short` e `git diff --check`. Verificar que somente a
especificacao, este plano e os arquivos de producao previstos foram alterados,
sem reverter modificacoes preexistentes e sem criar commit.
