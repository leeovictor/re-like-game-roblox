# TankController Maintenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduzir a duplicacao interna do `TankController`, eliminar contratos duplicados com `TankControlMath`, desacoplar specs de tuning, enxugar o contrato publico e documentar decisoes implicitas (escada de prioridade de input e orientacao congelada durante lock).

**Architecture:** O mapeamento tecla→acao→campo passa a vir de uma unica tabela `KEY_BINDINGS` consumida por binding, unbinding e sincronizacao de input. `TankControlMath` torna-se dono de `horizontalUnit` e do tipo `InputState`; o controller compoe o proprio tipo a partir do export. Velocidades passam a ser configuracao opcional de `new`. Prioridades de `ContextActionService` sao centralizadas em `src/shared/input/ActionPriorities.luau`. Nenhum comportamento observavel muda, exceto onde novas specs travam comportamentos existentes.

**Tech Stack:** Luau `--!strict`, Roblox Studio, Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0, TestEZ no Roblox Studio.

## Global Constraints

- Mantenha `--!strict`; proibido `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Nao redeclare tipos ja exportados por um modulo dono (`TankControlMath.InputState`); componha a partir do export.
- Siga `docs/controller-service-pattern.md`: metodos com `:` e `self`, closures preservam o receptor, estado por instancia, `start`/`stop` idempotentes.
- Nao adicione specs de UI e nao inicie entrypoints de producao nos testes.
- Specs nao devem acoplar valores de tuning; injete a configuracao na fixture.
- `src/shared` e mapeado integralmente por `test.project.json` e pelo comando de typecheck: novos modulos em `src/shared/` nao exigem mudanca de projeto.
- Os diretorios `src/client/dialogue` e `src/client/interactions` nao entram no `luau-lsp analyze`; mudancas neles sao verificadas por Selene, builds Rojo e TestEZ.
- Nao commitar este plano sem confirmacao explicita do usuario.

## Ciclo de Verificacao (usado por toda tarefa)

1. Lint:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

2. Sourcemap e typecheck (sempre nessa ordem):

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
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

3. Builds dos dois projetos:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

4. TestEZ via Studio/MCP (pre-requisito: `rojo serve test.project.json` ativo com a sessao Studio `RE Like Test` conectada): pare a sessao Play (se ativa), inicie o Play novamente e confirme `failed == 0` nos resultados de `TestEZAutoServer` e `TestEZAutoClient`. Use o Output apenas para detalhes.

## File Map

- Create `src/shared/input/ActionPriorities.luau`: escada de prioridade de input compartilhada (Task 5).
- Modify `src/shared/player/TankControlMath.luau`: exporta `horizontalUnit` com fallback explicito (Task 1).
- Modify `src/client/player/TankController.luau`: compoe `InputState`, tabela `KEY_BINDINGS`, remove `handleInput` publico, config de velocidades, `resolveCharacter` (Tasks 1-4, 6-7).
- Modify `src/client/dialogue/DialogueController.luau`: prioridade via `ActionPriorities` (Task 5).
- Modify `src/client/interactions/InteractionController.luau`: prioridade via `ActionPriorities` (Task 5).
- Modify `tests/client/player/TankControlMath.spec.luau`: specs de `horizontalUnit` (Task 1).
- Modify `tests/client/player/TankController.spec.luau`: helpers via bound callback, config injetada, specs de caracterizacao (Tasks 3, 4, 7).
- Modify `tests/client/dialogue/DialogueController.spec.luau`: helper via bound callback e prioridade referenciada (Tasks 3, 5).
- Modify `tests/client/interactions/InteractionController.spec.luau`: prioridades referenciadas e trava da escada (Task 5).

## Fora de Escopo

- Seam de `setSpeedMultiplier` para `WalkSpeed`: nenhum consumidor atual; reintroduzir quando um recurso real de velocidade existir (YAGNI).
- Bindings de gamepad/touch: `KEY_BINDINGS` habilita a extensao, mas nao adiciona entradas.
- Spec de `syncInput`/`IsKeyDown`: `UserInputService` nao permite simulacao programatica dos seus sinais/estado.
- Stylua no pipeline: ferramenta nao versionada em `rokit.toml`; apenas corrigir o whitespace manualmente (Task 6).

---

### Task 1: Deduplicar `horizontalUnit` e compor `InputState`

**Files:**
- Modify: `tests/client/player/TankControlMath.spec.luau`
- Modify: `src/shared/player/TankControlMath.luau`
- Modify: `src/client/player/TankController.luau:26-32,58-64,177,187`

**Interfaces:**
- Consumes: `TankControlMath.calculate(lookVector: Vector3, input: TankControlMath.InputState, deltaTime: number): TankControlMath.Motion` (existente).
- Produces: `TankControlMath.horizontalUnit(vector: Vector3, fallback: Vector3): Vector3`.
- Produces: `TankController.InputState = TankControlMath.InputState & { running: boolean }` (exportado pelo controller, composto do modulo dono).

- [ ] **Step 1: Escrever as specs falhadoras de horizontalUnit**

Em `tests/client/player/TankControlMath.spec.luau`, dentro do `describe("TankControlMath", ...)`, acrescente apos o ultimo `it`:

```luau
		it("usa o fallback quando a projecao horizontal e nula", function()
			local direction = TankControlMath.horizontalUnit(Vector3.new(0, 5, 0), Vector3.new(0, 0, -1))

			assertVectorNear(direction, Vector3.new(0, 0, -1))
		end)

		it("descarta o componente vertical antes de normalizar", function()
			local direction = TankControlMath.horizontalUnit(Vector3.new(3, 10, -4), Vector3.zero)

			assertVectorNear(direction, Vector3.new(3, 0, -4).Unit)
		end)
```

- [ ] **Step 2: Rodar o TestEZ e confirmar que falham**

Pare e inicie o Play (ciclo de verificacao, item 4). Esperado: as duas novas specs falham com erro de chamada a valor nil (`TankControlMath.horizontalUnit` nao existe).

- [ ] **Step 3: Exportar horizontalUnit com fallback explicito**

Em `src/shared/player/TankControlMath.luau`, substitua a funcao local `horizontalUnit` por um metodo exportado e use-o em `calculate`:

```luau
-- Projeta o vetor no plano horizontal e normaliza; usa o fallback quando a
-- projecao e nula (vetor puramente vertical).
function TankControlMath.horizontalUnit(vector: Vector3, fallback: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude == 0 then
		return fallback
	end
	return horizontal.Unit
end

function TankControlMath.calculate(lookVector: Vector3, input: InputState, deltaTime: number): Motion
	local moveAmount = (if input.forward then 1 else 0) - (if input.backward then 1 else 0)
	local rotationAmount = (if input.left then 1 else 0) - (if input.right then 1 else 0)

	return {
		moveDirection = TankControlMath.horizontalUnit(lookVector, Vector3.zero) * moveAmount,
		rotationRadians = ROTATION_RADIANS_PER_SECOND * rotationAmount * deltaTime,
	}
end
```

O comportamento de `calculate` e inalterado: o fallback `Vector3.zero` reproduz o retorno anterior para vetores verticais.

- [ ] **Step 4: Consumir o export no TankController**

Em `src/client/player/TankController.luau`:

1. Remova a funcao local `horizontalUnit` (linhas 58-64).
2. Substitua a declaracao local de `InputState` (linhas 26-32) por uma composicao do contrato do modulo dono:

```luau
export type InputState = TankControlMath.InputState & { running: boolean }
```

3. Junto as constantes no topo do modulo (logo apos `RUN_SPEED`), acrescente o fallback do controller com a razao documentada:

```luau
-- CFrame.lookAt exige uma direcao valida; o fallback e o olhar padrao do Roblox.
local DEFAULT_LOOK_VECTOR = Vector3.new(0, 0, -1)
```

4. Na funcao `update`, troque as duas chamadas:

```luau
	local lookVector = self.controlledLookVector
		or TankControlMath.horizontalUnit(rootPart.CFrame.LookVector, DEFAULT_LOOK_VECTOR)
```

```luau
	if motion.rotationRadians ~= 0 then
		lookVector = TankControlMath.horizontalUnit(
			CFrame.Angles(0, motion.rotationRadians, 0):VectorToWorldSpace(lookVector),
			DEFAULT_LOOK_VECTOR
		)
	end
```

- [ ] **Step 5: Rodar o ciclo completo de verificacao**

Esperado: lint, typecheck e builds limpos; TestEZ com `failed == 0` no client e no server.

- [ ] **Step 6: Commit**

```bash
git add src/shared/player/TankControlMath.luau src/client/player/TankController.luau tests/client/player/TankControlMath.spec.luau
git commit -m "refactor(player): compartilhar horizontalUnit e compor InputState a partir de TankControlMath"
```

---

### Task 2: Tabela unica de bindings tecla→acao→campo

**Files:**
- Modify: `src/client/player/TankController.luau:11-24,78-84,113-135,137-149,195-247`

**Interfaces:**
- Consumes: `TankController.InputState` (Task 1).
- Produces: nenhuma mudanca de contrato publico; tabela interna `KEY_BINDINGS` e tipo interno `KeyBinding`.

- [ ] **Step 1: Substituir ACTIONS e constantes pela tabela de bindings**

Em `src/client/player/TankController.luau`, substitua o bloco de constantes (linhas 11-24) por:

```luau
local ACTION_FORWARD = "DungeonTankForward"
local ACTION_BACKWARD = "DungeonTankBackward"
local ACTION_LEFT = "DungeonTankLeft"
local ACTION_RIGHT = "DungeonTankRight"
local ACTION_RUN = "DungeonTankRun"
local WALK_SPEED = 5
local RUN_SPEED = 10
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value

type InputField = "forward" | "backward" | "left" | "right" | "running"

type KeyBinding = {
	actionName: string,
	keyCode: Enum.KeyCode,
	field: InputField,
}

-- Fonte unica do mapeamento tecla -> acao -> campo de InputState; binding,
-- unbinding e sincronizacao de entrada derivam daqui.
local KEY_BINDINGS: { KeyBinding } = {
	{ actionName = ACTION_FORWARD, keyCode = Enum.KeyCode.W, field = "forward" },
	{ actionName = ACTION_BACKWARD, keyCode = Enum.KeyCode.S, field = "backward" },
	{ actionName = ACTION_LEFT, keyCode = Enum.KeyCode.A, field = "left" },
	{ actionName = ACTION_RIGHT, keyCode = Enum.KeyCode.D, field = "right" },
	{ actionName = ACTION_RUN, keyCode = Enum.KeyCode.LeftShift, field = "running" },
}
```

A tabela `ACTIONS` deixa de existir.

- [ ] **Step 2: Reescrever as quatro funcoes duplicadas**

Substitua `syncInput` (linhas 78-84), `updateInput` (linhas 113-135), `handleInputEnded` (linhas 137-149), `bindActions` (linhas 195-241) e `unbindActions` (linhas 243-247) por:

```luau
local function syncInput(self: TankController): ()
	for _, binding in KEY_BINDINGS do
		self.input[binding.field] = UserInputService:IsKeyDown(binding.keyCode)
	end
end
```

```luau
local function updateInput(self: TankController, actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	local isPressed = if inputState == Enum.UserInputState.Begin then true elseif inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel then false
		else nil

	if isPressed == nil then
		return Enum.ContextActionResult.Sink
	end

	for _, binding in KEY_BINDINGS do
		if binding.actionName == actionName then
			self.input[binding.field] = isPressed
		end
	end

	return Enum.ContextActionResult.Sink
end
```

```luau
local function handleInputEnded(self: TankController, inputObject: InputObject): ()
	for _, binding in KEY_BINDINGS do
		if inputObject.KeyCode == binding.keyCode then
			self.input[binding.field] = false
		end
	end
end
```

```luau
local function bindActions(self: TankController): ()
	for _, binding in KEY_BINDINGS do
		ContextActionService:BindActionAtPriority(
			binding.actionName,
			function(actionName, inputState)
				return self:handleInput(actionName, inputState)
			end,
			false,
			ACTION_PRIORITY,
			binding.keyCode
		)
	end
end
```

```luau
local function unbindActions(): ()
	for _, binding in KEY_BINDINGS do
		ContextActionService:UnbindAction(binding.actionName)
	end
end
```

- [ ] **Step 3: Rodar o ciclo completo de verificacao**

Refatorio preserva comportamento; as specs existentes de binding/unbinding/speed (TankController.spec, DialogueController.spec, InteractionController.spec) devem continuar verdes sem edicao. Esperado: `failed == 0` em client e server.

- [ ] **Step 4: Commit**

```bash
git add src/client/player/TankController.luau
git commit -m "refactor(player): unificar mapeamento tecla-acao do TankController em KEY_BINDINGS"
```

---

### Task 3: Remover `handleInput` do contrato publico

**Files:**
- Modify: `tests/client/player/TankController.spec.luau:10-20,117,122,140`
- Modify: `tests/client/dialogue/DialogueController.spec.luau:16-20,140`
- Modify: `src/client/player/TankController.luau:48,199,337-343`

**Interfaces:**
- Produces: contrato publico do `TankController` reduzido a `{ input, start, stop, acquireMovementLock }` (+ campos de estado); `MovementController` inalterado.
- Produces: helper de spec `invokeBoundAction(actionName: string, inputState: Enum.UserInputState)` que invoca o callback registrado no `ContextActionService`.

- [ ] **Step 1: Trocar os helpers das specs para invocar o callback registrado**

Em `tests/client/player/TankController.spec.luau`, substitua `invokeForward` e `invokeRun` (linhas 10-20) por:

```luau
local function invokeBoundAction(actionName: string, inputState: Enum.UserInputState)
	local info = (ContextActionService:GetAllBoundActionInfo() :: any)[actionName]
	expect(info).to.be.ok()
	local callback = (info :: any)["function"]
	expect(callback).to.be.ok()
	return (callback :: any)(actionName, inputState)
end

local function invokeForward(inputState: Enum.UserInputState)
	return invokeBoundAction("DungeonTankForward", inputState)
end

local function invokeRun(inputState: Enum.UserInputState)
	return invokeBoundAction("DungeonTankRun", inputState)
end
```

Atualize as chamadas: `invokeRun(controller, Enum.UserInputState.Begin)` vira `invokeRun(Enum.UserInputState.Begin)` (linhas 72 e 85); `invokeForward(controller, Enum.UserInputState.Begin)` vira `invokeForward(Enum.UserInputState.Begin)` (linhas 117 e 122); `activeController:handleInput("DungeonTankForward", Enum.UserInputState.Begin)` (linha 140) vira `invokeForward(Enum.UserInputState.Begin)`.

Em `tests/client/dialogue/DialogueController.spec.luau`, substitua o helper (linhas 16-20) por `invokeForward` sem parametro de controller usando o mesmo corpo de `invokeBoundAction` acima, e a chamada `invokeForward(tankController, Enum.UserInputState.Begin)` (linha 140) vira `invokeForward(Enum.UserInputState.Begin)`.

Rode o TestEZ: as specs devem continuar verdes com o metodo ainda presente (as specs agora nao dependem mais dele).

- [ ] **Step 2: Remover o metodo publico**

Em `src/client/player/TankController.luau`:

1. Na closure de `bindActions` (Task 2), troque `return self:handleInput(actionName, inputState)` por `return updateInput(self, actionName, inputState)`.
2. Remova a entrada `handleInput: (self: TankController, actionName: string, inputState: Enum.UserInputState) -> Enum.ContextActionResult,` do `export type TankController` (linha 48).
3. Remova o metodo `TankController.handleInput` (linhas 337-343).

- [ ] **Step 3: Rodar o ciclo completo de verificacao**

Se alguma spec ainda chamasse `handleInput`, ela falha aqui — e esse e o objetivo do passo. Esperado: `failed == 0` em client e server.

- [ ] **Step 4: Commit**

```bash
git add src/client/player/TankController.luau tests/client/player/TankController.spec.luau tests/client/dialogue/DialogueController.spec.luau
git commit -m "refactor(player): remover handleInput do contrato publico do TankController"
```

---

### Task 4: Injetar configuracao de velocidades (desacoplar specs de tuning)

**Files:**
- Modify: `tests/client/player/TankController.spec.luau:67-77`
- Modify: `src/client/player/TankController.luau:34-49,175,249-269`

**Interfaces:**
- Produces: `TankControllerConfig = { walkSpeed: number?, runSpeed: number? }` (exportado).
- Produces: `TankController.new(config: TankControllerConfig?): TankController` — `new()` continua valido (defaults `WALK_SPEED`/`RUN_SPEED`).
- Produces: campos de instancia `walkSpeed: number` e `runSpeed: number`.

- [ ] **Step 1: Reescrever a spec de velocidade com config injetada**

Em `tests/client/player/TankController.spec.luau`, substitua o teste `it("uses the run speed while the run action is active", ...)` (linhas 67-77) por dois testes com valores injetados:

```luau
		it("usa a velocidade de corrida configurada enquanto a acao de corrida esta ativa", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid

			controller = TankController.new({ walkSpeed = 4, runSpeed = 8 })
			controller:start()
			invokeRun(Enum.UserInputState.Begin)
			RunService.PreRender:Wait()
			task.wait()

			expect(humanoid.WalkSpeed).to.equal(8)
		end)

		it("usa a velocidade de caminhada configurada quando nao esta correndo", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid

			controller = TankController.new({ walkSpeed = 4, runSpeed = 8 })
			controller:start()
			RunService.PreRender:Wait()
			task.wait()

			expect(humanoid.WalkSpeed).to.equal(4)
		end)
```

A reatribuicao de `controller` faz o `afterEach` parar a instancia nova; a instancia do `beforeEach` nunca foi iniciada e nao segura recursos.

- [ ] **Step 2: Rodar o TestEZ e confirmar que falham**

Esperado: `humanoid.WalkSpeed` resulta `10` (default atual) e as duas specs falham com `expected 8, got 10` / `expected 4, got 10`.

- [ ] **Step 3: Implementar a configuracao**

Em `src/client/player/TankController.luau`:

1. Acrescente o tipo exportado acima do `export type TankController`:

```luau
export type TankControllerConfig = {
	walkSpeed: number?,
	runSpeed: number?,
}
```

2. Acrescente ao `export type TankController` os campos `walkSpeed: number,` e `runSpeed: number,`.

3. Substitua `TankController.new` por:

```luau
function TankController.new(config: TankControllerConfig?): TankController
	local walkSpeed = WALK_SPEED
	local runSpeed = RUN_SPEED
	if config ~= nil then
		if config.walkSpeed ~= nil then
			walkSpeed = config.walkSpeed
		end
		if config.runSpeed ~= nil then
			runSpeed = config.runSpeed
		end
	end

	local self = setmetatable({
		input = {
			forward = false,
			backward = false,
			left = false,
			right = false,
			running = false,
		},
		walkSpeed = walkSpeed,
		runSpeed = runSpeed,
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

4. Em `update`, troque a linha de `WalkSpeed` por:

```luau
	humanoid.WalkSpeed = if self.input.running then self.runSpeed else self.walkSpeed
```

`init.client.luau`, `DialogueController.spec.luau` e `InteractionController.spec.luau` continuam chamando `TankController.new()` sem argumentos — nenhuma mudanca necessaria.

- [ ] **Step 4: Rodar o ciclo completo de verificacao**

Esperado: `failed == 0` em client e server.

- [ ] **Step 5: Commit**

```bash
git add src/client/player/TankController.luau tests/client/player/TankController.spec.luau
git commit -m "refactor(player): injetar velocidades de caminhada e corrida no TankController"
```

---

### Task 5: Centralizar a escada de prioridade de input

**Files:**
- Create: `src/shared/input/ActionPriorities.luau`
- Modify: `src/client/player/TankController.luau` (constante `ACTION_PRIORITY`)
- Modify: `src/client/dialogue/DialogueController.luau:3-7,43`
- Modify: `src/client/interactions/InteractionController.luau:9-13`
- Modify: `tests/client/dialogue/DialogueController.spec.luau:92`
- Modify: `tests/client/interactions/InteractionController.spec.luau:397-398`

**Interfaces:**
- Produces: `ReplicatedStorage.Shared.input.ActionPriorities` com `MOVEMENT: number`, `INTERACTION: number` e `DIALOGUE: number` (module table, sem `new` — modulo puro de constantes).
- Consumes: nada de tarefas anteriores.

- [ ] **Step 1: Criar o modulo de prioridades**

Crie `src/shared/input/ActionPriorities.luau`:

```luau
--!strict

-- Escada de prioridade de input do cliente: dialogo precisa sobrepor
-- movimento e interacao para roubar WASD enquanto um dialogo esta ativo.
local ActionPriorities = {
	MOVEMENT = Enum.ContextActionPriority.High.Value,
	INTERACTION = Enum.ContextActionPriority.High.Value,
	DIALOGUE = Enum.ContextActionPriority.High.Value + 1,
}

return ActionPriorities
```

`src/shared` ja e mapeado integralmente por `test.project.json` e pelo typecheck; nenhuma mudanca de projeto e necessaria.

- [ ] **Step 2: Consumir o modulo nos tres controllers**

Em `src/client/player/TankController.luau`, troque `local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value` (Task 2) por:

```luau
local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
```

declarado junto aos requires, e `local ACTION_PRIORITY = ActionPriorities.MOVEMENT` no lugar da constante antiga.

Em `src/client/dialogue/DialogueController.luau`, acrescente o require junto ao de `Signal` e troque a constante (linha 43):

```luau
local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
```

```luau
local ACTION_PRIORITY = ActionPriorities.DIALOGUE
```

Em `src/client/interactions/InteractionController.luau`, acrescente o require junto ao de `interactionTypes` (o servico `ReplicatedStorage` ja esta resolvido na linha 9) e troque a constante (linha 13):

```luau
local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
```

```luau
local ACTION_PRIORITY = ActionPriorities.INTERACTION
```

- [ ] **Step 3: Referenciar as constantes nas specs e travar a escada**

Em `tests/client/dialogue/DialogueController.spec.luau`, acrescente o require no topo e troque a assercao de prioridade (linha 92):

```luau
local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
```

```luau
			expect(actionInfo.priorityLevel).to.equal(ActionPriorities.DIALOGUE)
```

Em `tests/client/interactions/InteractionController.spec.luau`, acrescente o mesmo require no topo e troque as assercoes (linhas 397-398), mantendo a trava explicita da relacao entre os degraus:

```luau
			expect(actions.DungeonDialogueConfirm.priorityLevel).to.equal(ActionPriorities.DIALOGUE)
			expect(actions[ACTION_NAME].priorityLevel).to.equal(ActionPriorities.INTERACTION)
			expect(ActionPriorities.DIALOGUE).to.equal(ActionPriorities.MOVEMENT + 1)
```

A ultima assercao falha propositadamente se alguem mudar a escada sem consciencia do contrato de precedencia.

- [ ] **Step 4: Rodar o ciclo completo de verificacao**

`DialogueController.luau` e `InteractionController.luau` nao entram no `luau-lsp analyze`; a cobertura deles e Selene + builds + TestEZ. Esperado: `failed == 0` em client e server.

- [ ] **Step 5: Commit**

```bash
git add src/shared/input/ActionPriorities.luau src/client/player/TankController.luau src/client/dialogue/DialogueController.luau src/client/interactions/InteractionController.luau tests/client/dialogue/DialogueController.spec.luau tests/client/interactions/InteractionController.spec.luau
git commit -m "refactor(input): centralizar prioridades de acao em ActionPriorities"
```

---

### Task 6: Extrair `resolveCharacter` do `update`

**Files:**
- Modify: `src/client/player/TankController.luau` (funcao `update`, linhas 151-193; whitespace residual na linha 176)

**Interfaces:**
- Produces: funcao interna `resolveCharacter(self: TankController): ResolvedCharacter?` com `ResolvedCharacter = { humanoid: Humanoid, rootPart: BasePart }`. Nenhuma mudanca de contrato publico.

- [ ] **Step 1: Extrair a resolucao de personagem**

Em `src/client/player/TankController.luau`, acrescente acima de `update`:

```luau
type ResolvedCharacter = {
	humanoid: Humanoid,
	rootPart: BasePart,
}

local function resolveCharacter(self: TankController): ResolvedCharacter?
	local player = Players.LocalPlayer
	local character = player.Character
	if character == nil then
		releaseHumanoid(self)
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		releaseHumanoid(self)
		return nil
	end
	acquireHumanoid(self, humanoid)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return nil
	end

	return { humanoid = humanoid, rootPart = rootPart }
end
```

E reescreva o inicio de `update` (removendo tambem o whitespace residual da linha 176):

```luau
local function update(self: TankController, deltaTime: number): ()
	if not self.started then
		return
	end

	local character = resolveCharacter(self)
	if character == nil then
		return
	end

	local humanoid = character.humanoid
	local rootPart = character.rootPart

	humanoid.WalkSpeed = if self.input.running then self.runSpeed else self.walkSpeed

	local lookVector = self.controlledLookVector
		or TankControlMath.horizontalUnit(rootPart.CFrame.LookVector, DEFAULT_LOOK_VECTOR)
	if not canMove(self) then
		self.controlledLookVector = lookVector
		rootPart.AssemblyAngularVelocity = Vector3.zero
		humanoid:Move(Vector3.zero, false)
		return
	end

	local motion = TankControlMath.calculate(lookVector, self.input, deltaTime)
	if motion.rotationRadians ~= 0 then
		lookVector = TankControlMath.horizontalUnit(
			CFrame.Angles(0, motion.rotationRadians, 0):VectorToWorldSpace(lookVector),
			DEFAULT_LOOK_VECTOR
		)
	end
	self.controlledLookVector = lookVector
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookVector)
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid:Move(motion.moveDirection, false)
end
```

- [ ] **Step 2: Rodar o ciclo completo de verificacao**

Refatorio preserva comportamento. Esperado: `failed == 0` em client e server.

- [ ] **Step 3: Commit**

```bash
git add src/client/player/TankController.luau
git commit -m "refactor(player): extrair resolveCharacter do update do TankController"
```

---

### Task 7: Specs de caracterizacao para guardas de lock e orientacao congelada

**Files:**
- Modify: `tests/client/player/TankController.spec.luau` (novos `it` dentro do `describe`)
- Modify: `src/client/player/TankController.luau` (comentario no ramo de lock de `update`)

**Interfaces:**
- Consumes: `invokeForward` (Task 3), estado `movementLockCount` (ja inspecionado pela spec existente de isolamento).
- Produces: nenhuma mudanca de producao, exceto comentario documental.

- [ ] **Step 1: Escrever as specs de caracterizacao**

Em `tests/client/player/TankController.spec.luau`, acrescente apos o teste `it("mantem locks isolados entre instancias", ...)`:

```luau
		it("ignora releases duplicados do mesmo lock", function()
			controller:start()
			local release = controller:acquireMovementLock()

			release()
			release()

			expect(controller.movementLockCount).to.equal(0)
		end)

		it("invalida releases de locks criados antes de stop", function()
			controller:start()
			local staleRelease = controller:acquireMovementLock()
			controller:stop()
			controller:start()
			local keepRelease = controller:acquireMovementLock()
			expect(controller.movementLockCount).to.equal(1)

			staleRelease()
			expect(controller.movementLockCount).to.equal(1)

			keepRelease()
			expect(controller.movementLockCount).to.equal(0)
		end)

		it("retorna a orientacao anterior ao lock apos liberar o movimento", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

			controller:start()
			RunService.PreRender:Wait()

			local expectedLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
			local release = controller:acquireMovementLock()
			rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(90), 0)
			RunService.PreRender:Wait()
			task.wait()

			release()
			RunService.PreRender:Wait()
			task.wait()

			local actualLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
			expect(actualLook.X).to.be.near(expectedLook.X, 0.001)
			expect(actualLook.Z).to.be.near(expectedLook.Z, 0.001)
		end)
```

- [ ] **Step 2: Rodar o TestEZ e confirmar que passam**

Estas specs travam comportamento existente (guarda `released`, guarda de geracao, look vector congelado). Esperado: todas passam. Se alguma falhar, PARE e investigue com systematic-debugging antes de prosseguir — nao ajuste a spec para casar com o codigo sem entender a divergencia.

- [ ] **Step 3: Documentar a decisao no ramo de lock**

Em `src/client/player/TankController.luau`, no ramo `if not canMove(self) then` dentro de `update`:

```luau
	if not canMove(self) then
		-- O look vector fica congelado enquanto o movimento esta bloqueado;
		-- ao liberar o lock, o personagem retorna a orientacao anterior.
		self.controlledLookVector = lookVector
		rootPart.AssemblyAngularVelocity = Vector3.zero
		humanoid:Move(Vector3.zero, false)
		return
	end
```

- [ ] **Step 4: Rodar o ciclo completo de verificacao**

Esperado: `failed == 0` em client e server.

- [ ] **Step 5: Commit**

```bash
git add tests/client/player/TankController.spec.luau src/client/player/TankController.luau
git commit -m "test(player): travar guardas de lock e orientacao congelada do TankController"
```
