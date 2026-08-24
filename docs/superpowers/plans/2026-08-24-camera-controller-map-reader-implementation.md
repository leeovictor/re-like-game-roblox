# CameraController Com CameraMapReader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refatorar `CameraController` para receber `CameraMapReader`, descobrir e ler `Workspace.CameraSystem` durante `new`, mantendo `CameraVisibility` externo.

**Architecture:** `CameraController.new(cameraMapReader)` chama `cameraMapReader.read("CameraSystem")` uma vez e cria o `CameraResolver` com o config retornado. O `CameraMapReader` aguarda e valida toda a hierarquia do mapa. O bootstrap continua obtendo a pasta para `CameraVisibility.hide`, mas deixa de interpretar ou ler o mapa diretamente.

**Tech Stack:** Luau strict, Roblox Studio, TestEZ, Rojo 7.7.0, Selene 0.29.0 e luau-lsp 1.69.0.

## Global Constraints

- Preservar `--!strict` nos arquivos Luau alterados.
- Manter `CameraMapReader.read` e o formato de `CameraConfig` inalterados.
- Fazer uma única leitura do mapa durante `CameraController.new`; toda espera e validação da hierarquia pertence ao reader.
- Manter `CameraVisibility.hide(cameraSystem)` externo ao controller.
- Preservar os comportamentos atuais de shots, cinematics, `Focus`, FOV, ciclo de vida e restauração da câmera.
- Isolar e destruir fixtures de Instances e restaurar estado de câmera/personagem nas specs.
- Não fazer commits nem executar revisão automatizada, conforme solicitação do usuário.

---

### Task 1: Atualizar o contrato do CameraController

**Files:**
- Modify: `src/client/camera/CameraController.luau:7-105`
- Test: `tests/client/camera/CameraController.spec.luau:9-70`

**Interfaces:**
- Consumes: `CameraMapReader.CameraMapReader`, tipo exportado por `CameraMapReader.luau`, com `read(rootName: string) -> CameraConfig.Config`; o reader descobre o mapa no Workspace pelo nome.
- Produces: `CameraController.new(cameraMapReader)` que carrega o mapa antes de retornar.

- [ ] **Step 1: Criar a fixture de CameraSystem na spec**

Adicionar helpers que criem `Folder` e `Part` em `workspace`, registrando a raiz para destruição no `afterEach`:

```luau
local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)

local createdCameraSystem: Folder?

local function newCameraSystem(): Folder
    local root = Instance.new("Folder")
    root.Name = "CameraSystem"
    root.Parent = workspace

    local shots = Instance.new("Folder")
    shots.Name = "Shots"
    shots.Parent = root

    local zones = Instance.new("Folder")
    zones.Name = "Zones"
    zones.Parent = root

    root:SetAttribute("DefaultShotId", "Default")

    local defaultShot = Instance.new("Part")
    defaultShot.Name = "Default"
    defaultShot.CFrame = CFrame.new(0, 10, -20)
    defaultShot:SetAttribute("FieldOfView", 55)
    defaultShot.Parent = shots

    local firstShot = Instance.new("Part")
    firstShot.Name = "First"
    firstShot.CFrame = CFrame.new(0, 10, 20)
    firstShot:SetAttribute("FieldOfView", 65)
    firstShot.Parent = shots

    local zone = Instance.new("Part")
    zone.Name = "FirstZone"
    zone.Size = Vector3.new(10, 10, 10)
    zone:SetAttribute("ShotId", "First")
    zone:SetAttribute("Order", 1)
    zone.Parent = zones

    createdCameraSystem = root
    return root
end
```

Use `ReplicatedStorage` in the spec to require o reader real e mantenha os helpers existentes de espera do personagem e restauração da câmera.

- [ ] **Step 2: Adaptar a fixture de cada teste para criar o mapa antes do controller**

No `beforeEach`, crie `newCameraSystem()` antes de construir o controller. Remova `newConfig()` e troque:

```luau
controller = CameraController.new(newConfig())
```

por:

```luau
controller = CameraController.new(CameraMapReader)
```

No `afterEach`, destrua `createdCameraSystem` depois de parar o controller e zere a referência. Preserve a posição inicial do personagem, `Anchored`, `CameraType`, `CFrame`, `CameraSubject` e FOV.

- [ ] **Step 3: Exportar o contrato e implementar a função de carregamento no controller**

Adicionar o contrato no modulo compartilhado:

```luau
export type CameraMapReader = {
    read: (root: Instance?) -> CameraConfig.Config,
}
```

Importar `CameraMapReader` no controller e referenciar o tipo como
`CameraMapReader.CameraMapReader`. O reader deve concentrar a espera/leitura:

```luau
function CameraMapReader.read(root: Instance?): CameraConfig.Config
    local cameraSystem = workspace:WaitForChild(rootName)
    local shotsFolder = cameraSystem:WaitForChild("Shots")
    cameraSystem:WaitForChild("Zones")
    local defaultShotId = cameraSystem:GetAttribute("DefaultShotId")
    -- Validacao e conversao existentes permanecem neste modulo.
end
```

Alterar `CameraController.new` para receber `cameraMapReader: CameraMapReader.CameraMapReader`, chamar `cameraMapReader.read("CameraSystem")` antes de montar o estado e usar o config retornado em `CameraResolver.new(config)`. Não guardar a pasta nem o reader no objeto.

- [ ] **Step 4: Verificar que os métodos públicos não mudaram**

Conferir que `start`, `stop`, `getCurrentShotId`, `hasShot`, `setCinematicShot` e `clearCinematicShot` continuam com as mesmas assinaturas e que nenhuma chamada adicional a `read` aparece fora do construtor.

### Task 2: Simplificar o bootstrap e validar a integração

**Files:**
- Modify: `src/client/init.client.luau:32-42`
- Verify: `src/client/camera/CameraVisibility.luau`
- Verify: `tests/client/camera/CameraVisibility.spec.luau`

**Interfaces:**
- Consumes: `CameraController.new(CameraMapReader)` e `CameraVisibility.hide(cameraSystem)`.
- Produces: bootstrap sem leitura manual do mapa e sem mudança na utilidade de visibilidade.

- [ ] **Step 1: Remover a leitura manual do mapa**

Substituir o bloco atual de espera de folders, atributo, `CameraMapReader.read` e `cameraConfig` por:

```luau
local cameraSystem = workspace:WaitForChild("CameraSystem")
local cameraController = CameraController.new(CameraMapReader)
CameraVisibility.hide(cameraSystem)
cameraController:start()
```

Manter o `require` de `CameraMapReader` porque ele será passado ao controller. Não mover `CameraVisibility` para `CameraController`.

- [ ] **Step 2: Confirmar a responsabilidade de CameraVisibility**

Verificar que `CameraVisibility.hide` continua operando apenas sobre filhos diretos de `Shots` e `Zones`, sem alteração de código ou contrato. A spec correspondente deve permanecer inalterada.

- [ ] **Step 3: Executar lint e builds**

Rodar:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Esperar zero diagnósticos e builds concluídos. Não criar commit.

- [ ] **Step 4: Executar typecheck e TestEZ no Studio**

Gerar o sourcemap e executar o comando de typecheck documentado em `AGENTS.md`. Depois de sincronizar as alterações, reiniciar o Play no Studio e confirmar `failed == 0` nos runners server e client. Não executar review automatizada.
