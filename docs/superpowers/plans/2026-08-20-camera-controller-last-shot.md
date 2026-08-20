# Camera Controller Last Shot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manter o ultimo shot ativo quando o jogador estiver fora de todas as zonas, usando o shot padrao apenas quando ainda nao houver shot ativo.

**Architecture:** O `CameraResolver` continuara stateless e retornara o shot da zona ou `nil`. O `CameraController` resolvera o shot efetivo com `zoneShotId or currentShotId or defaultShotId`, mantendo o estado temporal no campo `currentShotId` existente.

**Tech Stack:** Luau strict, Roblox Studio, TestEZ, Rojo, Selene e luau-lsp.

## Global Constraints

- Mantenha `--!strict` nos modulos Luau e specs.
- Preserve imports baseados em `script` e os mapeamentos de `default.project.json` e `test.project.json`.
- Nao altere `src/client/init.client.luau`; os entrypoints normais nao sao executados pelo projeto de testes.
- Specs que criam estado, conexoes ou alteram Instances devem limpar tudo em `afterEach`.
- Execute as analises na plataforma Roblox conforme `AGENTS.md`.
- Nao crie novos atributos, zonas especiais, persistencia ou blending de camera.

---

### Task 1: Preservar o ultimo shot fora das zonas

**Files:**
- Modify: `src/shared/camera/CameraResolver.luau:8-10,53-68`
- Modify: `src/client/camera/CameraController.luau:51-62`
- Modify: `tests/shared/camera/CameraResolver.spec.luau:44-75`
- Create: `tests/client/camera/CameraController.spec.luau`

**Interfaces:**
- Consumes: `CameraConfig.Config`, `CameraResolver.resolve(position: Vector3)` e `CameraController.currentShotId` existentes.
- Produces: `CameraResolver.resolve(position: Vector3): CameraConfig.ShotId?`; dentro de uma zona retorna seu `shotId`, fora de todas retorna `nil`.

- [ ] **Step 1: Atualizar os testes do resolver para o novo contrato**

Em `tests/shared/camera/CameraResolver.spec.luau`, altere as expectativas de
posicoes fora de zonas para `nil`:

```lua
it("rejeita pontos fora em cada eixo", function()
    local resolver = CameraResolver.new(newConfig())
    expect(resolver:resolve(Vector3.new(5.01, 0, 0))).to.equal("Second")
    expect(resolver:resolve(Vector3.new(0, 5.01, 0))).to.equal(nil)
    expect(resolver:resolve(Vector3.new(0, 0, 5.01))).to.equal(nil)
end)

it("retorna nil fora de todas as zonas", function()
    local resolver = CameraResolver.new(newConfig())
    expect(resolver:resolve(Vector3.new(0, 20, 0))).to.equal(nil)
end)
```

Mantenha inalterados os testes de zonas internas, fronteira compartilhada,
rotacao, validacao e imutabilidade da configuracao.

- [ ] **Step 2: Adicionar o teste client-side sequencial**

Crie `tests/client/camera/CameraController.spec.luau` com uma fixture usando o
personagem local real, mantendo o `HumanoidRootPart` ancorado durante o teste e
restaurando CFrame, Anchored e camera no `afterEach`:

```lua
--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local CameraController = require(client.camera.CameraController)

local function newConfig(): any
    return {
        defaultShotId = "Default",
        shots = {
            Default = { cframe = CFrame.new(0, 10, -20), fieldOfView = 55 },
            First = { cframe = CFrame.new(0, 10, 20), fieldOfView = 65 },
        },
        zones = {
            {
                id = "FirstZone",
                volume = { cframe = CFrame.new(), size = Vector3.new(10, 10, 10) },
                shotId = "First",
            },
        },
    }
end

local function waitFor(predicate: () -> boolean): boolean
    local deadline = os.clock() + 3
    while os.clock() < deadline do
        if predicate() then
            return true
        end
        task.wait()
    end
    return predicate()
end

return function()
    describe("CameraController", function()
        local controller: any
        local rootPart: BasePart
        local camera: Camera
        local previousRootCFrame: CFrame
        local previousAnchored: boolean
        local previousCameraType: Enum.CameraType
        local previousCameraCFrame: CFrame
        local previousFieldOfView: number

        beforeEach(function()
            local character = Players.LocalPlayer.Character
            if character == nil then
                character = Players.LocalPlayer.CharacterAdded:Wait()
            end
            rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

            local currentCamera = workspace.CurrentCamera
            if currentCamera == nil then
                error("CameraController spec exige workspace.CurrentCamera")
            end
            camera = currentCamera

            previousRootCFrame = rootPart.CFrame
            previousAnchored = rootPart.Anchored
            previousCameraType = camera.CameraType
            previousCameraCFrame = camera.CFrame
            previousFieldOfView = camera.FieldOfView

            rootPart.Anchored = true
            rootPart.CFrame = CFrame.new(0, 0, 20)
            controller = CameraController.new(newConfig())
            controller:start()
        end)

        afterEach(function()
            if controller ~= nil then
                controller:stop()
            end
            rootPart.CFrame = previousRootCFrame
            rootPart.Anchored = previousAnchored
            camera.CameraType = previousCameraType
            camera.CFrame = previousCameraCFrame
            camera.FieldOfView = previousFieldOfView
        end)

        it("mantem o ultimo shot ao sair de uma zona", function()
            expect(waitFor(function()
                return controller:getCurrentShotId() == "Default"
            end)).to.equal(true)

            rootPart.CFrame = CFrame.new()
            expect(waitFor(function()
                return controller:getCurrentShotId() == "First"
            end)).to.equal(true)

            rootPart.CFrame = CFrame.new(0, 0, 20)
            expect(waitFor(function()
                return controller:getCurrentShotId() == "First"
            end)).to.equal(true)
        end)
    end)
end
```

- [ ] **Step 3: Executar os testes antes da implementacao**

Sirva o projeto de testes com `rojo serve test.project.json`, conecte a sessao
Studio `RE Like Test`, inicie o Play e execute os runners relevantes. O estado
esperado antes da implementacao e falha: o resolver ainda retorna `Default` fora
das zonas e o teste do controller falha ao esperar que `First` seja mantido.

- [ ] **Step 4: Alterar o contrato e o retorno do resolver**

Em `src/shared/camera/CameraResolver.luau`, altere a assinatura exportada e o
retorno final:

```lua
resolve: (self: CameraResolver, position: Vector3) -> CameraConfig.ShotId?,
```

```lua
return nil
```

O retorno de zona e todas as validacoes devem permanecer iguais.

- [ ] **Step 5: Aplicar o fallback temporal no controller**

Em `src/client/camera/CameraController.luau`, substitua a resolucao atual por:

```lua
local zoneShotId = self.resolver:resolve(position)
local desiredShotId = zoneShotId or self.currentShotId or self.config.defaultShotId
if desiredShotId ~= self.currentShotId then
    local shot = self.config.shots[desiredShotId]
    if shot == nil then
        return
    end

    self.currentShotId = desiredShotId
    camera.CFrame = shot.cframe
    camera.FieldOfView = shot.fieldOfView
end
```

Nao altere a atualizacao de `camera.Focus` nem o ciclo de vida da conexao.

- [ ] **Step 6: Executar novamente o teste focal**

Rode o Play limpo no Studio. Os testes do resolver e do controller devem passar,
com `failed == 0` nos resultados server e client. Pare o Play, limpe as fixtures
e repita o fluxo completo uma segunda vez.

- [ ] **Step 7: Executar as verificacoes do repositorio**

Rode:

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
  src/server/inventory src/server/items src/server/pickups \
  src/client/camera src/client/inventory src/client/pickups \
  src/client/player src/client/ui tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

O resultado esperado e nenhuma falha de lint, typecheck ou build. Nao fazer
commit sem solicitacao explicita do usuario.
