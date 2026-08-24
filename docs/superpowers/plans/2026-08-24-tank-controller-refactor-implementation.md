# TankController Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar `TankController` e seus consumidores para controllers instanciaveis com dependencias explicitas e padronizar a construcao do `CameraController`.

**Architecture:** `TankController.new()` criara estado isolado por instancia. `DialogueController` recebera a instancia de movimento por `new(dependencies)`, enquanto `CinematicController`, handlers de interacao e UI receberao referencias explicitas compostas em `init.client.luau`. O comportamento de movimento, camera e dialogo sera preservado; somente a propriedade do estado e a forma de composicao mudarao.

**Tech Stack:** Luau `--!strict`, Roblox Studio, Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0, TestEZ no Roblox Studio, React/ReactRoblox.

## Global Constraints

- Controllers/services com estado runtime devem ser instancias criadas por `new`.
- Controllers/services usam `new(dependencies)` com tabela nomeada; usam `new()` quando nao possuem dependencias externas.
- Metodos de instancia usam `:` e declaram `self`.
- `TankControlMath` continua sendo importado diretamente como modulo puro interno.
- O composition root, atualmente `src/client/init.client.luau`, cria e conecta as instancias.
- Consumidores nao importam outro controller/service concreto somente para obter seu singleton.
- Mantenha `--!strict` e nao use `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Nao injete `Players`, `RunService` ou `ContextActionService` nesta migracao.
- Nao adicione specs de UI.
- A verificacao deve usar os comandos oficiais do `AGENTS.md`, builds Rojo e Play limpo no Roblox Studio.
- O resultado TestEZ deve ter `failed == 0` no client e no server.
- Nao fazer commit deste spec nem deste plano de implementacao.

## File Map

- Modify `src/client/player/TankController.luau`: transformar estado e operacoes em uma instancia criada por `new()`.
- Modify `tests/client/player/TankController.spec.luau`: criar uma instancia por fixture e testar isolamento.
- Modify `src/client/dialogue/DialogueController.luau`: receber movimento por dependencia e tornar estado/signal por instancia.
- Modify `tests/client/dialogue/DialogueController.spec.luau`: construir TankController e DialogueController por fixture.
- Modify `src/client/camera/CameraController.luau`: aceitar `{ cameraMapReader = CameraMapReader }`.
- Modify `tests/client/camera/CameraController.spec.luau`: atualizar a construcao nomeada.
- Modify `src/client/cinematics/CinematicController.luau`: chamar a dependencia de movimento como metodo de instancia.
- Modify cinematic specs que usam fakes de movimento: declarar e chamar metodos com `self`.
- Modify `src/client/doors/DoorController.luau`: remover default controller e import operacional de dialogo.
- Modify `src/client/dialogue/DialogueInteractionController.luau`: remover default controller e import operacional de dialogo.
- Modify `src/client/dialogue/useDialogue.luau`: observar a instancia recebida como argumento.
- Modify `src/client/ui/App.luau`: receber `dialogueController` por props.
- Modify `src/client/init.client.luau`: construir todas as instancias e callbacks explicitos.
- Add `docs/controller-service-pattern.md`: instrucoes prescritivas para controllers/services e dependencias.
- Modify `AGENTS.md`: referenciar `docs/controller-service-pattern.md`.

### Task 1: Migrar TankController para instancia

**Files:**
- Modify: `tests/client/player/TankController.spec.luau`
- Modify: `src/client/player/TankController.luau`

**Interfaces:**
- Produces `TankController.new(): TankController`.
- Produces `TankController:start(): ()`.
- Produces `TankController:stop(): ()`.
- Produces `TankController:acquireMovementLock(): () -> ()`.
- Produces `TankController:handleInput(actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult`.

- [ ] **Step 1: Atualizar a fixture da spec para construir uma instancia**

Em `tests/client/player/TankController.spec.luau`, substitua as chamadas no
modulo por uma variavel `controller` criada em cada teste:

```luau
local TankController = require(client.player.TankController)

return function()
	describe("TankController", function()
		local controller

		beforeEach(function()
			controller = TankController.new()
		end)

		afterEach(function()
			controller:stop()
		end)
	end)
end
```

Atualize `invokeForward` e `invokeRun` para receber `controller` e chamar
`controller:handleInput(...)`. Troque cada `TankController.start()`,
`TankController.stop()` e `TankController.acquireMovementLock()` por chamadas
na instancia.

- [ ] **Step 2: Adicionar um teste de isolamento de locks**

Acrescente uma spec que mantenha um lock em uma instancia sem bloquear outra:

```luau
it("mantem locks isolados entre instancias", function()
	local lockedController = TankController.new()
	local activeController = TankController.new()
	local release = lockedController:acquireMovementLock()
	local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	activeController:start()
	activeController:handleInput("DungeonTankForward", Enum.UserInputState.Begin)
	RunService.PreRender:Wait()

	expect(humanoid.MoveDirection.Magnitude > 0).to.equal(true)
	release()
	activeController:stop()
end)
```

Garanta que `lockedController:stop()` tambem seja chamado no cleanup local ou
que a fixture registre ambas as instancias, para nao deixar geracoes ou estado
mutavel entre testes.

- [ ] **Step 3: Mover o estado global para os campos da instancia**

Em `src/client/player/TankController.luau`, crie `TankController` com
`__index = TankController` e mova para o objeto retornado por `new()` os campos
que hoje estao no escopo do modulo:

```luau
export type TankController = {
	input: InputState,
	started: boolean,
	movementLockCount: number,
	movementLockGeneration: number,
	renderConnection: RBXScriptConnection?,
	inputEndedConnection: RBXScriptConnection?,
	activeHumanoid: Humanoid?,
	originalAutoRotate: boolean?,
	originalWalkSpeed: number?,
	controlledLookVector: Vector3?,
	start: (self: TankController) -> (),
	stop: (self: TankController) -> (),
	acquireMovementLock: (self: TankController) -> (() -> ()),
	handleInput: (self: TankController, actionName: string, inputState: Enum.UserInputState) -> Enum.ContextActionResult,
}
```

Mantenha `ACTION_*`, velocidades, `ACTIONS`, `TankControlMath` e os servicos
Roblox como valores/colaboradores de modulo. Altere helpers que leem ou
escrevem estado para receber `self`, incluindo `resetInput`,
`releaseHumanoid`, `acquireHumanoid`, `update`, `bindActions`, `stop` e
`acquireMovementLock`. O calculo em `TankControlMath.calculate(...)` nao muda.

- [ ] **Step 4: Encaminhar callbacks do ContextActionService para a instancia**

Em `start`, registre bindings com closures que capturem `self`, em vez de
passar diretamente um metodo que exige receptor:

```luau
ContextActionService:BindActionAtPriority(
	ACTION_FORWARD,
	function(actionName, inputState)
		return self:handleInput(actionName, inputState)
	end,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.W
)
```

Aplique o mesmo encaminhamento aos cinco actions. `inputEndedConnection` e
`renderConnection` devem ser armazenados em `self` e desconectados apenas pela
instancia que os criou.

- [ ] **Step 5: Implementar `new()` e converter todos os metodos publicos**

Implemente:

```luau
function TankController.new(): TankController
	local self = setmetatable({
		input = {
			forward = false,
			backward = false,
			left = false,
			right = false,
			running = false,
		},
		started = false,
		movementLockCount = 0,
		movementLockGeneration = 0,
		renderConnection = nil,
		inputEndedConnection = nil,
		activeHumanoid = nil,
		originalAutoRotate = nil,
		originalWalkSpeed = nil,
		controlledLookVector = nil,
	}, TankController)
	return (self :: any) :: TankController
end
```

Converta `start`, `stop`, `acquireMovementLock` e `handleInput` para
`function TankController.start(self: TankController)` e equivalentes. Preserve
as garantias atuais de idempotencia, resync de input e invalidacao de locks.

- [ ] **Step 6: Rodar a spec do controller no Studio**

Sincronize o projeto de testes, reinicie o Play para recarregar os scripts e
confirme que `TankController.spec` nao gera falhas. Se o teste de isolamento
interferir nos bindings globais do `ContextActionService`, mantenha somente a
segunda instancia iniciada e verifique a independencia usando o comportamento
observavel dessa instancia; nunca compartilhe ou reutilize uma instancia entre
testes.

### Task 2: Converter DialogueController e seus testes

**Files:**
- Modify: `src/client/dialogue/DialogueController.luau`
- Modify: `tests/client/dialogue/DialogueController.spec.luau`

**Interfaces:**
- Consumes `{ movement = TankController }`.
- Produces `DialogueController.new(dependencies): DialogueController`.
- Produces `DialogueController.changed` por instancia.
- Produces `:start()`, `:stop()`, `:getState()`, `:show()` e `:ask()`.

- [ ] **Step 1: Alterar o setup da spec para duas instancias explicitas**

No `beforeEach`, crie e inicie o TankController antes do dialogo:

```luau
local tankController
local dialogueController

beforeEach(function()
	tankController = TankController.new()
	dialogueController = DialogueController.new({
		movement = tankController,
	})
	tankController:start()
	dialogueController:start()
end)

afterEach(function()
	dialogueController:stop()
	tankController:stop()
	for _, connection in signalConnections do
		connection:Disconnect()
	end
	signalConnections = {}
end)
```

Atualize todos os usos da tabela do modulo para `dialogueController:` e passe o
controller correto a `invokeForward`. Mantenha os testes de callback,
substituicao, input e locks com os mesmos comportamentos esperados.

- [ ] **Step 2: Adicionar o teste de isolamento de state e Signal**

Crie duas instancias com o mesmo fake ou dois TankControllers e confirme que
publicar em uma nao altera o estado da outra:

```luau
it("isola estado e signal entre instancias", function()
	local first = DialogueController.new({ movement = tankController })
	local second = DialogueController.new({ movement = tankController })
	local observed = false

	first:start()
	second:start()
	second.changed:Connect(function()
		observed = true
	end)
	first:show("Somente o primeiro")

	expect(first:getState().text).to.equal("Somente o primeiro")
	expect(second:getState()).to.equal(nil)
	expect(observed).to.equal(false)
	first:stop()
	second:stop()
end)
```

Registre e desconecte a conexao em `signalConnections` ou destrua-a
explicitamente no proprio teste.

- [ ] **Step 3: Definir dependencies e campos por instancia**

Remova o `require` operacional de `TankController` usado para acessar um
singleton. Declare uma interface estrutural para a dependencia de movimento e
uma tabela de dependencias nomeada:

```luau
type MovementController = {
	acquireMovementLock: (self: MovementController) -> (() -> ()),
}

export type Dependencies = {
	movement: MovementController,
}
```

Transforme os valores globais `changed`, `state`, `activeCallback`,
`movementRelease`, `started` e `generation` em campos do tipo de instancia:

```luau
type Controller = {
	dependencies: Dependencies,
	changed: ChangedSignal,
	state: DialogState?,
	activeCallback: ActiveCallback?,
	movementRelease: (() -> ())?,
	started: boolean,
	generation: number,
	start: (self: Controller) -> (),
	stop: (self: Controller) -> (),
	getState: (self: Controller) -> DialogState?,
	show: (self: Controller, text: string, callback: ShowCallback?) -> (),
	ask: (self: Controller, text: string, options: { DialogOption }, callback: AskCallback?) -> (),
}
```

Crie `changed = Signal.new()` dentro de `new(dependencies)` e faca helpers
como `publish`, `closeCurrent`, `reveal`, `startTyping`, `handleAction` e
`bindActions` receberem `self`. `startTyping` deve capturar a instancia para
que a geracao consultada seja a do dialogo correto.

- [ ] **Step 4: Implementar a factory e chamadas de movimento com `:`**

Implemente:

```luau
function DialogueController.new(dependencies: Dependencies): DialogueController
	local self = setmetatable({
		dependencies = dependencies,
		changed = (Signal.new() :: any) :: ChangedSignal,
		state = nil,
		activeCallback = nil,
		movementRelease = nil,
		started = false,
		generation = 0,
	}, ControllerMethods)
	return (self :: any) :: DialogueController
end
```

Em `show` e `ask`, adquira o lock com
`self.dependencies.movement:acquireMovementLock()`. Preserve a ordem atual de
fechamento: liberar o lock proprio, invalidar a geracao, desregistrar actions,
publicar `nil` e executar o callback.

- [ ] **Step 5: Converter os metodos publicos e remover o singleton**

Exporte somente a factory e os tipos necessarios. Nao deixe `controller`,
`changed`, `state` ou qualquer default operacional no escopo do modulo. Os
metodos devem usar `ControllerMethods.__index = ControllerMethods` ou a mesma
forma de metatable usada pelos outros controllers instanciaveis.

- [ ] **Step 6: Rodar a spec de DialogueController**

Reinicie o Play do TestEZ e confirme os testes de dialogo, incluindo o caso em
que um lock externo continua ativo depois que o dialogo fecha.

### Task 3: Padronizar CameraController e chamadas de CinematicController

**Files:**
- Modify: `src/client/camera/CameraController.luau`
- Modify: `tests/client/camera/CameraController.spec.luau`
- Modify: `src/client/cinematics/CinematicController.luau`
- Modify: `tests/client/cinematics/CinematicController.spec.luau` e demais specs cinematic existentes

**Interfaces:**
- `CameraController.new({ cameraMapReader = CameraMapReader }): CameraController`.
- `CinematicController` continua recebendo `dependencies.movement`, mas chama sua API como metodo de instancia.

- [ ] **Step 1: Atualizar a chamada da spec de camera**

Troque a construcao existente por:

```luau
controller = CameraController.new({
	cameraMapReader = CameraMapReader,
})
```

Nao altere as fixtures de shots, zonas ou assercoes de comportamento.

- [ ] **Step 2: Alterar o contrato do construtor de camera**

Declare:

```luau
export type Dependencies = {
	cameraMapReader: CameraMapReader.CameraMapReader,
}
```

Altere `CameraController.new(dependencies)` para carregar a configuracao com
`dependencies.cameraMapReader.read("CameraSystem")`. Mantenha o resolver,
shots, overrides, conexao `PreRender` e cleanup sem mudancas comportamentais.

- [ ] **Step 3: Remover a dependencia operacional concreta de TankController em cinematic**

Como `CinematicController` so precisa de `acquireMovementLock`, substitua o
tipo concreto importado por uma interface estrutural local:

```luau
type MovementController = {
	acquireMovementLock: (self: MovementController) -> (() -> ()),
}

export type Dependencies = {
	camera: CameraController.CameraController,
	movement: MovementController,
	sound: CinematicSoundPlayer.CinematicSoundPlayer,
}
```

Remova o `require` runtime de `TankController` usado somente para tipo e altere
o lock da linha de execucao para:

```luau
return self.dependencies.movement:acquireMovementLock()
```

- [ ] **Step 4: Atualizar fakes cinematic para metodos com `self`**

Nos fakes de movimento, declare o metodo como funcao de tabela e invoque-o com
dois pontos:

```luau
local movement = {
	lockCount = 0,
}

function movement:acquireMovementLock()
	self.lockCount += 1
	local released = false
	return function()
		if released then
			return
		end
		released = true
		self.lockCount -= 1
	end
end
```

Preserve os testes de preload, concorrencia, stop, cleanup, efeitos e geracao.

- [ ] **Step 5: Rodar as specs de camera e cinematic**

Reinicie o Play e confirme que camera e cinematics continuam passando sem
alteracao de comportamento, especialmente restauracao de shot e liberacao de
movimento.

### Task 4: Compor DialogueController e handlers no bootstrap

**Files:**
- Modify: `src/client/doors/DoorController.luau`
- Modify: `src/client/dialogue/DialogueInteractionController.luau`
- Modify: `src/client/dialogue/useDialogue.luau`
- Modify: `src/client/ui/App.luau`
- Modify: `src/client/init.client.luau`
- Modify: `tests/client/interactions/InteractionController.spec.luau`

**Interfaces:**
- `DoorController.new(dependencies): InteractionHandler` continua sendo a API de construcao.
- `DialogueInteractionController.new({ show = callback }): InteractionHandler` continua sendo a API de construcao.
- `useDialogue(controller: DialogueController.DialogueController)` observa somente a instancia fornecida.

- [ ] **Step 1: Remover defaults ocultos dos handlers**

Em `DoorController.luau`, remova o import de `DialogueController`,
`defaultDependencies`, `defaultController` e o campo exportado `interact` que
aponta para o default. Retorne a tabela com `new = createController`.

Em `DialogueInteractionController.luau`, remova o import de
`DialogueController`, o default dependencies/controller e retorne somente
`new = createController`.

As funcoes internas devem continuar usando `dependencies.dialogue.show` e
`dependencies.show`, sem saber de onde veio a instancia.

- [ ] **Step 2: Atualizar o hook e o componente App**

Altere o hook para receber a instancia:

```luau
local function useDialogue(controller: DialogueController.DialogueController)
	local dialogue, setDialogue = React.useState(controller:getState())

	React.useEffect(function()
		local connection = controller.changed:Connect(function(nextDialogue)
			setDialogue(nextDialogue)
		end)
		return function()
			connection:Disconnect()
		end
	end, { controller })

	return dialogue
end
```

Defina props tipadas em `App` com `dialogueController` e chame
`useDialogue(props.dialogueController)`. Nao adicione spec de UI.

- [ ] **Step 3: Criar as instancias no init.client.luau**

Altere o bootstrap para manter referencias locais nomeadas:

```luau
local cameraController = CameraController.new({
	cameraMapReader = CameraMapReader,
})
local tankController = TankController.new()
cameraController:start()
tankController:start()

local dialogueController = DialogueController.new({
	movement = tankController,
})
dialogueController:start()

local cinematicController = CinematicController.new({
	camera = cameraController,
	movement = tankController,
	sound = cinematicSoundPlayer,
})
```

Mantenha a inicializacao de `CinematicSoundPlayer` antes de construir o
cinematic controller. A ordem deve garantir que os controllers usados pelos
handlers ja estejam criados antes do registro de interacoes.

- [ ] **Step 4: Montar callbacks de dialogo sem perder `self`**

Crie uma funcao local de adaptacao ou closures equivalentes:

```luau
local function showDialogue(text, callback)
	dialogueController:show(text, callback)
end
```

Use-a na dependencia `dialogue = { show = showDialogue }` de
`DoorController.new` e em `{ show = showDialogue }` de
`DialogueInteractionController.new`.

Mova para o composition root as dependencias concretas que estavam no
`defaultDependencies` de `DoorController`: `InventoryController.getState`,
`GameplayEvents.emit`, a funcao que valida e invoca `remotes.InteractDoor`, e
`TransitionController`. Preserve exatamente o contrato de
`DoorController.Dependencies`.

- [ ] **Step 5: Registrar os handlers criados e passar props para App**

Substitua os registros que usavam tabelas default por:

```luau
local doorController = DoorController.new(doorDependencies)
local dialogueInteractionController = DialogueInteractionController.new({
	show = showDialogue,
})

InteractionController.register("Door", doorController)
InteractionController.register("Pickup", PickupController)
InteractionController.register("Dialogue", dialogueInteractionController)
```

Renderize a UI com a instancia:

```luau
root:render(React.createElement(App, {
	dialogueController = dialogueController,
}))
```

Atualize `CinematicController.new` para usar `movement = tankController` e
remova qualquer `TankController.start()` ou
`TankController.acquireMovementLock()` restante do bootstrap.

- [ ] **Step 6: Atualizar a spec de InteractionController que importava o default**

Em `tests/client/interactions/InteractionController.spec.luau`, substitua o
require e as chamadas diretas ao singleton no teste de prioridade por um
TankController e um DialogueController criados na fixture do teste:

```luau
local TankController = require(client.player.TankController)
local DialogueController = require(client.dialogue.DialogueController)

local tankController = TankController.new()
local dialogueController = DialogueController.new({
	movement = tankController,
})
tankController:start()
dialogueController:start()
dialogueController:show("Blocking")

-- assertions sobre as prioridades

dialogueController:stop()
tankController:stop()
```

Registre o cleanup em `afterEach` da fixture existente para evitar conexoes e
bindings entre testes. Mantenha `DoorController.spec.luau` sem alteracao
estrutural, pois ela ja constroi `DoorController.new` com dependencies falsas.
Mantenha fakes de dialogo como callbacks sem `self` quando forem apenas
interfaces funcionais fornecidas a um handler.

- [ ] **Step 7: Fazer busca de chamadas singleton restantes**

Execute:

```bash
rg "TankController\.(start|stop|acquireMovementLock|handleInput)|DialogueController\.(start|stop|show|ask|getState)|CameraController\.new\(CameraMapReader" src tests
```

O resultado nao pode conter chamadas operacionais singleton. Referencias de
tipo e nomes dentro de mensagens de erro sao permitidos somente quando nao
representarem uma chamada.

### Task 5: Criar o guia de controllers/services e referencia-lo no AGENTS

**Files:**
- Add: `docs/controller-service-pattern.md`
- Modify: `AGENTS.md`

**Interfaces:**
- O guia e a referencia normativa para alteracoes futuras do OpenCode.
- `AGENTS.md` deve apontar para o caminho exato do guia.

- [ ] **Step 1: Escrever o guia com regras e exemplos reais**

Crie `docs/controller-service-pattern.md` com estas secoes:

1. Escopo e diferenca entre modulo puro e controller/service runtime.
2. Construcao: `new()` sem dependencias e `new(dependencies)` com tabela nomeada.
3. Campos de instancia e proibicao de estado mutavel global.
4. Metodos com `:` e callbacks por closure.
5. `start`/`stop` idempotentes e liberacao de conexoes/tarefas.
6. Composition root e fluxo de dependencias explicitas.
7. Testes com fixtures isoladas e cleanup em `afterEach`.
8. Anti-padroes: singleton oculto, default controller, lookup dinamico e injecao
   desnecessaria de servicos Roblox.

Inclua exemplos consistentes com o codigo:

```luau
local tankController = TankController.new()
local dialogueController = DialogueController.new({
	movement = tankController,
})

local showDialogue = function(text, callback)
	dialogueController:show(text, callback)
end
```

Registre que modulos puros internos, como `TankControlMath`, podem ser
importados diretamente e que controllers existentes fora do escopo so devem
ser padronizados quando forem alterados.

- [ ] **Step 2: Adicionar referencia curta ao AGENTS.md**

Inclua em `AGENTS.md`, na secao de execucao/imports ou limites de tipos, uma
regra como:

```markdown
- O padrao de construcao, dependencias e lifecycle de controllers/services esta em `docs/controller-service-pattern.md`; consulte-o antes de criar ou alterar esses modulos.
```

Nao duplique o documento inteiro no `AGENTS.md`.

- [ ] **Step 3: Revisar o guia contra o codigo migrado**

Confirme que cada exemplo usa chamadas com `:`, que a regra de tabela nomeada
nao contradiz `TankController.new()`, e que o texto nao promete migracao de
controllers fora deste escopo.

### Task 6: Executar validacao completa

**Files:**
- Verify: todos os arquivos alterados nas tasks anteriores

- [ ] **Step 1: Rodar lint de producao e testes**

Execute:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

Corrija somente diagnosticos introduzidos pela migracao, mantendo `--!strict`.

- [ ] **Step 2: Gerar sourcemap e rodar typecheck Roblox**

Execute a sequencia exigida pelo repositorio:

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
  src/client/camera src/client/dialogue src/client/cinematics \
  src/client/doors src/client/player src/client/ui tests
```

O sourcemap deve ser gerado antes do analyze. Inclua os diretorios client
alterados, mesmo que o comando historico do `AGENTS.md` ainda nao os liste.

- [ ] **Step 3: Construir os dois projetos Rojo**

Execute:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Confirme que os dois builds terminam sem erro e que nenhum arquivo gerado e
adicionado ao worktree.

- [ ] **Step 4: Executar Play limpo no Roblox Studio**

Sirva ou sincronize `test.project.json` na sessao `RE Like Test`. Pare e inicie
o Play depois das alteracoes para recarregar todos os ModuleScripts. Confirme
no Output que `TestEZAutoServer` e `TestEZAutoClient` terminaram com
`failed == 0`.

Verifique tambem manualmente:

- bindings de tanque aparecem uma vez e desaparecem depois de `:stop()`;
- velocidade e rotacao do humanoid sao restauradas;
- dialogo bloqueia somente o movimento que adquiriu seu lock;
- cinematic continua adquirindo e liberando a mesma instancia de movimento;
- camera continua aplicando e restaurando shots;
- portas e alvos de dialogo chamam a instancia criada no bootstrap.

- [ ] **Step 5: Inspecionar o diff final sem commit**

Execute:

```bash
git diff --check
git status --short
git diff -- src/client/player/TankController.luau src/client/dialogue/DialogueController.luau src/client/camera/CameraController.luau src/client/cinematics/CinematicController.luau src/client/doors/DoorController.luau src/client/dialogue/DialogueInteractionController.luau src/client/dialogue/useDialogue.luau src/client/ui/App.luau src/client/init.client.luau AGENTS.md docs/controller-service-pattern.md
```

Confirme que somente os arquivos planejados foram alterados pela implementacao
e nao faca commit do spec ou do plano.
