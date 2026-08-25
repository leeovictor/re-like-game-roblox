# Basic Enemy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar o primeiro sistema client-side de inimigos que spawna um clone por marker, detecta o player a ate 4 studs e o persegue com pathfinding sem salto.

**Architecture:** `EnemyController` le os markers, cria os clones e mantem uma unica conexao de `Heartbeat`. Cada clone e encapsulado por uma instancia `Enemy`, que possui seu estado `idle`/`chasing`, mede a distancia do player e recalcula seu `Path` a cada 0,1 segundo.

**Tech Stack:** Luau strict, Roblox Studio/DataModel, Rojo 7.7.0, TestEZ, `RunService.Heartbeat`, `PathfindingService`, `Humanoid:MoveTo`.

## Global Constraints

- O runtime sera client-side e nao criara remotes novos.
- A fonte dos spawns sera formada somente pelos filhos diretos `BasePart` de `Workspace.EnemiesMarkers`.
- O template sera `ReplicatedStorage.Models.Enemy` e os clones ficarao em `Workspace.Enemies`.
- Os estados permitidos serao somente `idle` e `chasing`.
- A distancia de deteccao e perda do alvo sera `4` studs.
- O path sera recalculado a cada `0,1` segundo enquanto o inimigo estiver perseguindo.
- O path sera criado com `PathfindingService:CreatePath({ AgentCanJump = false })`.
- O inimigo nao implementara ataque, dano, vida, line-of-sight, raycast, respawn ou spawn dinamico.
- Falhas de `ComputeAsync`, status sem path, waypoint inutil ou waypoint de salto farao o inimigo voltar para `idle` e emitirao `warn` no Output.
- Markers serao ocultados com `Transparency = 1` e `CanCollide = false` durante o runtime e restaurados em `stop()`.
- `start()` e `stop()` serao idempotentes e todo estado runtime pertendera a uma instancia.
- As specs serao strict, usarao fixtures isoladas em `beforeEach` e destruirao Instances e conexoes em `afterEach`.
- Nao serao criadas specs de UI.
- A spec e este plano nao receberao commit nem serao adicionados ao staging.
- O comando `luau-lsp analyze` devera ser executado ao final de cada task, antes de avancar para a proxima.

---

## File Map

- Create: `src/client/enemies/Enemy.luau` - instancia logica individual, estado, deteccao, pathfinding e movimentacao.
- Create: `src/client/enemies/EnemyController.luau` - leitura de markers, spawn, ocultacao e lifecycle da colecao de inimigos.
- Modify: `src/client/init.client.luau` - construir e iniciar `EnemyController` no composition root.
- Modify: `test.project.json` - mapear `src/client/enemies` para o client do place de testes.
- Create: `tests/client/enemies/Enemy.spec.luau` - testes do estado, deteccao e navegacao de uma instancia.
- Create: `tests/client/enemies/EnemyController.spec.luau` - testes de spawn, markers e lifecycle do controller.

O `default.project.json` nao precisa de uma entrada nova: seu mapeamento de
`src/client` ja inclui automaticamente o novo diretorio. O place principal ja
fornece `Workspace.EnemiesMarkers` e `ReplicatedStorage.Models.Enemy` como
assets do DataModel.

## Implementation Order

### Task 1: Implementar `Enemy` com sua spec

**Files:**
- Modify: `test.project.json:45-82`
- Create: `src/client/enemies/Enemy.luau`
- Create: `tests/client/enemies/Enemy.spec.luau`

**Interfaces:**
- Consumes: `CharacterRoot` via `script.Parent.Parent.player.CharacterRoot` e
  o servico Roblox `PathfindingService`.
- Produces: `Enemy.new(model): Enemy`, com `state`, `update(deltaTime)` e
  `destroy()` para uso pelo `EnemyController`.

- [ ] **Step 1: Adicionar o mapeamento do diretorio de inimigos no teste**

Dentro de `StarterPlayer.StarterPlayerScripts.Client` em `test.project.json`,
adicionar:

```json
"enemies": {
  "$path": "src/client/enemies"
},
```

O mapeamento deve ficar no place de testes e nao deve iniciar
`src/client/init.client.luau`.

- [ ] **Step 2: Criar a spec strict e os helpers da fixture**

Criar `tests/client/enemies/Enemy.spec.luau` com o formato TestEZ usado pelo
repositorio:

```luau
--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local Enemy = require(client.enemies.Enemy)

return function()
    describe("Enemy", function()
        -- beforeEach, afterEach e os testes entram aqui.
    end)
end
```

Implementar os helpers dentro da mesma spec, nao em uma task separada:

- `makeCharacter(position)`: cria `Model`, `Part` chamado
  `HumanoidRootPart`, `Humanoid`, parenta no `workspace` e atribui a
  `Players.LocalPlayer.Character`;
- `makeEnemy(position)`: cria um `Model` com `HumanoidRootPart`, `Humanoid` e
  uma peca visual adicional;
- `makeFloor(position, size)`: cria uma `Part` ancorada para a fixture de
  navegacao;
- `track(instance)`: adiciona cada Instance criada a uma tabela local da
  fixture.

No `beforeEach`, salvar `Players.LocalPlayer.Character` e seu parent. No
`afterEach`, destruir todas as Instances rastreadas, restaurar o personagem e
seu parent e limpar a tabela. A spec nao deve compartilhar modelos,
personagens, paths ou superficies entre testes.

- [ ] **Step 3: Escrever os testes de comportamento do `Enemy` antes da implementacao**

Na mesma spec, adicionar somente estes cinco comportamentos de `Enemy`:

1. `inicia no estado idle`: criar model e verificar
   `Enemy.new(model).state == "idle"`.
2. `permanece idle sem player root`: criar o inimigo, definir
   `Players.LocalPlayer.Character = nil`, chamar `enemy:update(0.1)` e verificar
   `enemy.state == "idle"`.
3. `volta para idle fora do raio`: colocar player em
   `Vector3.new(20, 3, 0)` e inimigo em `Vector3.new(0, 3, 0)`, chamar
   `update(0.1)` e verificar `idle`.
4. `entra em chasing e envia waypoint em superficie navegavel`: criar uma
   plataforma ancorada `Vector3.new(20, 1, 20)` em `Vector3.new(0, 20, 0)`,
   colocar inimigo e player na mesma superficie com roots a no maximo 4 studs,
   aguardar `task.wait(0.5)` e chamar `update(0.1)`. Verificar
   `enemy.state == "chasing"` e `Humanoid.WalkToPoint ~= Vector3.zero`.
5. `volta para idle quando ComputeAsync falha`: criar duas plataformas
   ancoradas `Vector3.new(1, 1, 12)` nas posicoes
   `Vector3.new(-2, 20, 0)` e `Vector3.new(2, 20, 0)`, colocar cada root sobre
   uma plataforma, mantendo distancia de 4 studs e sem superficie conectando
   as duas, aguardar `task.wait(0.5)`, chamar `update(0.1)` e verificar
   `enemy.state == "idle"`.

O caso navegavel usa o `PathfindingService` real e demonstra o calculo por meio
do estado `chasing` e do `WalkToPoint` alterado. O caso sem path aceita o status
`NoPath` como a falha observavel. Capturar `LogService.MessageOut` somente se
for necessario limpar a conexao ou validar que o `warn` foi emitido; o estado
deve ser a assercao principal.

- [ ] **Step 4: Rodar a spec para confirmar o ciclo vermelho**

Sincronizar `test.project.json`, parar o Play atual, iniciar um Play limpo e
executar somente a spec de `Enemy`:

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local spec = player.PlayerScripts.TestEZTests.Client.enemies["Enemy.spec"]
return require(ReplicatedStorage.TestEZRunnerShared).run({ spec })
```

Esperado: a spec falha porque `src/client/enemies/Enemy.luau` ainda nao existe.
Nao considerar essa falha inicial como validacao final.

- [ ] **Step 5: Criar o modulo `Enemy` strict e seu contrato**

Criar `src/client/enemies/Enemy.luau` com:

```luau
--!strict

local PathfindingService = game:GetService("PathfindingService")
local CharacterRoot = require(script.Parent.Parent.player.CharacterRoot)

local DETECTION_RADIUS = 4
local PATH_RECOMPUTE_INTERVAL = 0.1

export type State = "idle" | "chasing"
export type Enemy = {
    model: Model,
    state: State,
    update: (self: Enemy, deltaTime: number) -> (),
    destroy: (self: Enemy) -> (),
}
```

O modulo deve exportar uma tabela `Enemy` com `Enemy.new(model)`. Nao importar
`EnemyController`, `RunService` ou `Players`, nem manter estado mutavel no
escopo do modulo.

- [ ] **Step 6: Implementar o estado por instancia e o construtor**

Em `Enemy.new(model)`, validar que o argumento e `Model`, que existe um
`HumanoidRootPart` `BasePart` e que existe um `Humanoid`. Guardar, em tabelas
novas por instancia:

```luau
local self = setmetatable({
    model = model,
    state = "idle",
    humanoid = humanoid,
    root = root,
    path = PathfindingService:CreatePath({
        AgentCanJump = false,
    }),
    pathElapsed = PATH_RECOMPUTE_INTERVAL,
}, Enemy)
```

O `pathElapsed` inicial permite o primeiro calculo imediatamente quando o
player entrar no raio. O path e os campos `humanoid`, `root`, `state` e
`pathElapsed` nao podem ser compartilhados entre duas instancias.

- [ ] **Step 7: Implementar `update()` com deteccao e estados**

`update(deltaTime)` deve executar nesta ordem:

1. Somar `deltaTime` em `pathElapsed`.
2. Obter o player root por `CharacterRoot.get()`.
3. Se o player root nao existir, limpar os waypoints e o destino do path,
   definir `idle` e permitir tentativa imediata quando um novo alvo existir.
4. Se o root do inimigo nao estiver disponivel ou a distancia for maior que 4,
   executar a mesma transicao para `idle`.
5. Se estiver `idle` com player valido dentro do raio, mudar para `chasing`.
6. Se `pathElapsed < PATH_RECOMPUTE_INTERVAL`, retornar sem calcular.
7. Zerar `pathElapsed` e executar o calculo do path.

Criar um helper de transicao que aceite se a proxima tentativa pode ser
imediata:

```luau
local function enterIdle(self: Enemy, allowImmediateNextAttempt: boolean)
    self.state = "idle"
    self.pathElapsed = if allowImmediateNextAttempt
        then PATH_RECOMPUTE_INTERVAL
        else 0
end
```

Quando a distancia ultrapassar o limite ou o player desaparecer, usar
`allowImmediateNextAttempt = true`. Quando o path falhar, usar `false` para
impedir que a mesma falha seja tentada e registrada a cada frame. Depois da
falha, o inimigo fica `idle`; se o player continuar no raio, uma nova tentativa
so ocorre respeitando o intervalo de 0,1 segundo.

Em `idle`, nao chamar `MoveTo` nem `ComputeAsync`. Ao sair do raio, limpar os
waypoints e o destino atuais, mantendo o objeto `Path` isolado da instancia
para que o proximo `chasing` possa reutiliza-lo sem waypoints antigos.

- [ ] **Step 8: Implementar `ComputeAsync`, waypoints e logs**

Usar as posicoes atuais e proteger `ComputeAsync` com `pcall`:

```luau
local ok, errorMessage = pcall(function()
    self.path:ComputeAsync(self.root.Position, playerRoot.Position)
end)
if not ok then
    warn(("[Enemy:%s] ComputeAsync failed: %s"):format(
        self.model.Name,
        tostring(errorMessage)
    ))
    enterIdle(self, false)
    return
end
```

Se `self.path.Status ~= Enum.PathStatus.Success`, registrar:

```luau
warn(("[Enemy:%s] Pathfinding failed with status: %s"):format(
    self.model.Name,
    self.path.Status.Name
))
enterIdle(self, false)
return
```

Depois de `GetWaypoints()`, exigir um waypoint posterior ao inicial. Se nao
existir, registrar `warn` com o nome do inimigo e o motivo `no usable waypoint`
e voltar para `idle`.

Percorrer todos os waypoints antes de movimentar. Se qualquer waypoint tiver
`Action == Enum.PathWaypointAction.Jump`, registrar `warn` com o motivo
`jump waypoint is unsupported`, descartar o path e voltar para `idle`.

Enviar apenas o primeiro waypoint posterior ao ponto inicial:

```luau
local waypoint = waypoints[2]
self.humanoid:MoveTo(waypoint.Position)
```

Nao usar `MoveToFinished:Wait()`, nao conectar callbacks por inimigo, nao criar
coroutines e nunca definir `Humanoid.Jump = true`.

- [ ] **Step 9: Implementar `destroy()` e validar a spec de `Enemy`**

Implementar `destroy()` de modo idempotente: destruir o model uma vez, limpar
as referencias internas e nao criar novos paths. Rodar novamente a spec
isolada com o runner da Step 4, agora esperando todos os cinco comportamentos
passarem.

- [ ] **Step 10: Rodar o LSP desta task**

Gerar o sourcemap do place de testes e executar o typecheck antes de iniciar a
Task 2:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups \
  src/client/player src/client/enemies src/client/ui \
  tests
```

Esperado: `luau-lsp` termina sem erros para a implementacao e a spec de
`Enemy`. Se o ambiente ainda nao tiver os diretorios server listados pelo
comando oficial, manter os caminhos do `AGENTS.md` e corrigir somente
diagnosticos introduzidos pelos arquivos desta task.

### Task 2: Implementar `EnemyController` com sua spec e conectar o bootstrap

**Files:**
- Create: `src/client/enemies/EnemyController.luau`
- Create: `tests/client/enemies/EnemyController.spec.luau`
- Modify: `src/client/init.client.luau:21-43`

**Interfaces:**
- Consumes: `Enemy.new(model): Enemy`, `Workspace.EnemiesMarkers`,
  `ReplicatedStorage.Models.Enemy` e `RunService.Heartbeat`.
- Produces: `EnemyController.new(): EnemyController`, com `start()` e `stop()`;
  os campos `enemies`, `started` e `heartbeatConnection` para as specs.

- [ ] **Step 1: Criar a spec strict e as fixtures do controller**

Criar `tests/client/enemies/EnemyController.spec.luau` importando os modulos
reais pelo DataModel:

```luau
--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local EnemyController = require(client.enemies.EnemyController)

return function()
    describe("EnemyController", function()
        -- beforeEach, afterEach e os testes entram aqui.
    end)
end
```

Na mesma spec, criar no `beforeEach` uma `Folder` `Workspace.EnemiesMarkers`,
um `Part` marker direto, uma `Folder` `ReplicatedStorage.Models` e um
`Model` `ReplicatedStorage.Models.Enemy` com `HumanoidRootPart` e `Humanoid`.
Criar tambem `EnemyController.new()`.

Salvar e restaurar qualquer `EnemiesMarkers`, `Models` ou `Enemies` que ja
existam no DataModel. Rastrear e destruir todas as fixtures e desconectar todas
as conexoes no `afterEach`. A spec deve evitar iniciar o bootstrap normal.

- [ ] **Step 2: Escrever os testes do controller antes da implementacao**

Adicionar somente estes quatro comportamentos:

```luau
it("cria um inimigo por marker BasePart direto", function()
    controller:start()

    expect(#controller.enemies).to.equal(1)
    local clone = workspace.Enemies:GetChildren()[1]
    expect(clone:IsA("Model")).to.equal(true)
    expect((clone :: Model).HumanoidRootPart.Position).to.be.near(marker.Position, 0.001)
end)

it("oculta markers durante o runtime", function()
    controller:start()

    expect(marker.Transparency).to.equal(1)
    expect(marker.CanCollide).to.equal(false)
end)

it("restaura markers e destroi clones em stop", function()
    local originalTransparency = marker.Transparency
    local originalCanCollide = marker.CanCollide
    controller:start()
    controller:stop()

    expect(marker.Transparency).to.equal(originalTransparency)
    expect(marker.CanCollide).to.equal(originalCanCollide)
    expect(#workspace.Enemies:GetChildren()).to.equal(0)
end)

it("mantem start e stop idempotentes", function()
    local originalTransparency = marker.Transparency
    controller:start()
    controller:start()
    expect(#controller.enemies).to.equal(1)
    expect(controller.heartbeatConnection).to.be.ok()

    controller:stop()
    controller:stop()

    expect(#workspace.Enemies:GetChildren()).to.equal(0)
    expect(marker.Transparency).to.equal(originalTransparency)
    expect(controller.heartbeatConnection).to.equal(nil)
end)
```

Os helpers da fixture devem atribuir `marker.CFrame` e o root do template a
posicoes conhecidas, permitindo verificar o alinhamento sem depender da
rotacao ou do `PrimaryPart` `Head` do asset real.

- [ ] **Step 3: Rodar a spec para confirmar a falha inicial do controller**

Executar somente a spec do controller com o runner temporario:

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local spec = player.PlayerScripts.TestEZTests.Client.enemies["EnemyController.spec"]
return require(ReplicatedStorage.TestEZRunnerShared).run({ spec })
```

Esperado: a spec falha porque `src/client/enemies/EnemyController.luau` ainda
nao existe. A implementacao da Task 1 deve continuar carregavel no mesmo
DataModel.

- [ ] **Step 4: Criar o contrato strict do controller**

Criar `src/client/enemies/EnemyController.luau` com imports diretos dos servicos
Roblox e do tipo exportado pelo modulo `Enemy`:

```luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EnemyModule = require(script.Parent.Enemy)

export type EnemyController = {
    started: boolean,
    enemies: { EnemyModule.Enemy },
    heartbeatConnection: RBXScriptConnection?,
    start: (self: EnemyController) -> (),
    stop: (self: EnemyController) -> (),
}
```

O modulo deve exportar uma tabela `EnemyController` com `new()`. Todo estado
mutavel deve ser criado pelo construtor; nao criar singleton ou tabelas mutaveis
reutilizadas no escopo do modulo.

- [ ] **Step 5: Implementar `new()` e a ocultacao dos markers**

Inicializar campos novos por controller:

```luau
local self = setmetatable({
    started = false,
    enemies = {},
    heartbeatConnection = nil,
    markerProperties = {},
}, EnemyController)
```

Em `start()`, retornar se `started` ja for `true`. Localizar
`Workspace.EnemiesMarkers`, percorrer `GetChildren()` e aceitar somente
`BasePart`. Para cada marker, salvar e aplicar:

```luau
self.markerProperties[marker] = {
    transparency = marker.Transparency,
    canCollide = marker.CanCollide,
}
marker.Transparency = 1
marker.CanCollide = false
```

Nao alterar `Anchored`, `CFrame`, tamanho ou outras propriedades do marker.
Markers sem os componentes necessarios do template nao devem deixar clones
parciais no mundo.

- [ ] **Step 6: Implementar spawn, posicionamento e validacao do template**

Localizar `ReplicatedStorage.Models.Enemy` e validar `Model`. Localizar
`Workspace.Enemies` ou criar uma `Folder`. Se existir uma instancia com esse
nome que nao seja `Folder`, emitir `warn`, nao criar clones e manter o
controller seguro para `stop()`.

Para cada marker, clonar o template, validar `HumanoidRootPart` como
`BasePart` e `Humanoid`, e destruir o clone se a validacao falhar.

Alinhar o root do clone a `marker.Position`, preservando a rotacao authored do
root e sem usar `PrimaryPart` `Head`:

```luau
local currentRoot = root.CFrame
local rootRotation = currentRoot - currentRoot.Position
local targetRoot = CFrame.new(marker.Position) * rootRotation
local delta = targetRoot * currentRoot:Inverse()
clone:PivotTo(delta * clone:GetPivot())
clone.Name = "Enemy_" .. marker.Name
clone.Parent = enemiesFolder
```

Criar `EnemyModule.new(clone)` somente depois da validacao e parentar o clone
na pasta `Workspace.Enemies`. Adicionar a instancia retornada a
`self.enemies`. O controller deve destruir somente os clones que criou e deve
preservar qualquer outro objeto que ja estivesse na pasta.

- [ ] **Step 7: Conectar o loop central de Heartbeat**

Depois do spawn, criar uma unica conexao que capture o controller:

```luau
self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
    for _, enemy in self.enemies do
        enemy:update(deltaTime)
    end
end)
```

Nao criar uma conexao por inimigo e nao passar `Enemy.update` diretamente como
callback sem o receptor correto.

- [ ] **Step 8: Implementar `stop()` e o cleanup completo**

Quando `started` for `false`, retornar sem alterar recursos. Quando ativo:

1. Definir `started = false`.
2. Desconectar e zerar `heartbeatConnection`.
3. Chamar `enemy:destroy()` em cada instancia criada.
4. Limpar `self.enemies`.
5. Restaurar `Transparency` e `CanCollide` dos markers ainda existentes.
6. Limpar `self.markerProperties`.

`Enemy:destroy()` e o unico ponto que chama `Destroy()` nos clones. O
controller nao deve destruir a pasta `Workspace.Enemies` em `stop()`, porque
ela pode ser authored ou reutilizada. Uma nova chamada a `start()` deve criar
um conjunto novo e salvar os valores atuais dos markers.

- [ ] **Step 9: Registrar o controller no bootstrap**

Adicionar ao topo de `src/client/init.client.luau`:

```luau
local EnemyController = require(script.enemies.EnemyController)
```

Depois da criacao e inicio do `TankController`, adicionar:

```luau
local enemyController = EnemyController.new()
enemyController:start()
```

Nao alterar o `TankController`, nao registrar inputs e nao criar logica
server-side. O controller deve ser uma instancia criada pelo composition root.

- [ ] **Step 10: Rodar as specs da task e a suite client**

Sincronizar `test.project.json`, parar o Play e iniciar um Play limpo. Rodar a
spec isolada do controller com o runner da Step 3 e depois a suite completa:

```luau
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Esperado: os cinco testes de `Enemy` e os quatro testes de `EnemyController`
passam, cobrindo os oito comportamentos aprovados; o resultado client informa
`failed == 0`. O resultado server tambem deve ser executado para confirmar
`failed == 0`.

- [ ] **Step 11: Rodar o LSP desta task**

Gerar o sourcemap atualizado e executar novamente o comando completo antes de
iniciar a Task 3:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups \
  src/client/player src/client/enemies src/client/ui \
  tests
```

Esperado: `luau-lsp` termina sem erros para os modulos, bootstrap mapeado e
specs. Nao usar `--!nocheck`, ignores amplos ou configuracoes para esconder
diagnosticos.

### Task 3: Validar lint, LSP, builds e runtime manual

**Files:**
- Verify: `src/client/enemies/Enemy.luau`
- Verify: `src/client/enemies/EnemyController.luau`
- Verify: `src/client/init.client.luau`
- Verify: `test.project.json`
- Verify: `tests/client/enemies/Enemy.spec.luau`
- Verify: `tests/client/enemies/EnemyController.spec.luau`

**Interfaces:**
- Consumes: os dois modulos implementados, os dois projetos Rojo e as sessoes
  `RE Like Test` e `RE Like`.
- Produces: lint limpo, LSP limpo, builds validos, suite TestEZ client e server
  sem falhas e confirmacao manual do spawn e da perseguicao.

- [ ] **Step 1: Rodar lint de producao e testes**

Executar da raiz:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Esperado: ambos terminam sem diagnosticos. Nao editar `Packages/` ou
`DevPackages/`.

- [ ] **Step 2: Rodar o LSP mais uma vez nesta task**

Executar na ordem oficial:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups \
  src/client/player src/client/enemies src/client/ui \
  tests
```

Esperado: `luau-lsp` termina sem erros. Confirmar que os entrypoints normais
nao foram incluidos no typecheck do place de testes.

- [ ] **Step 3: Construir os dois projetos Rojo**

Executar:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Esperado: ambos terminam com sucesso. O novo controller deve estar no build
normal e os modulos e specs devem estar no build de testes sem iniciar os
entrypoints normais.

- [ ] **Step 4: Executar a suite TestEZ em dois Plays limpos**

Servir ou sincronizar `test.project.json` na sessao `RE Like Test`. Repetir duas
vezes:

1. Parar o Play anterior.
2. Iniciar um Play novo pelo MCP do Roblox Studio.
3. Aguardar `TestEZAutoServer` e `TestEZAutoClient`.
4. Confirmar `failed == 0` no resultado server e client.
5. Conferir o Output para warnings inesperados.
6. Parar o Play e confirmar que fixtures e conexoes nao permanecem.

Depois de qualquer alteracao de script, parar e iniciar novamente o Play antes
de executar os testes para recarregar os modulos no DataModel.

- [ ] **Step 5: Validar manualmente o place principal**

Na sessao `RE Like`, iniciar o Play e confirmar:

- `Workspace.EnemiesMarkers.FacilityEntrance` fica invisivel;
- o marker nao possui colisao;
- `Workspace.Enemies` contem um clone por marker;
- o `HumanoidRootPart` do clone coincide com a posicao do marker;
- o inimigo permanece `idle` fora de 4 studs;
- ao aproximar o player para ate 4 studs, o inimigo entra em `chasing` e
  segue o caminho do mapa;
- ao afastar o player para mais de 4 studs, o inimigo para e retorna a `idle`;
- falhas de path aparecem no Output com nome do inimigo e erro ou status.

Nao validar ataque, dano, vida ou salto, pois esses comportamentos nao fazem
parte desta V1.

- [ ] **Step 6: Fazer a verificacao final da arvore de trabalho sem commit**

Executar:

```bash
git status --short
git diff --check
```

Confirmar que as alteracoes de implementacao estao limitadas aos arquivos do
File Map e que os dois documentos desta especificacao (`docs/superpowers/specs`
e `docs/superpowers/plans`) permanecem sem commit conforme solicitado. Nao
executar `git add`, `git commit`, amend, push ou outra operacao de staging. Nao
remover nem reverter alteracoes preexistentes de outro trabalho.
