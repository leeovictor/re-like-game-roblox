# Camera System Runtime And Plugin Lifecycle Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tornar o carregamento do mapa de camera tolerante a replicacao, permitir reabrir o dock indefinidamente e ocultar shots/zones fora do editor e durante o runtime.

**Architecture:** O cliente aguardara a hierarquia persistida com `WaitForChild` e fara um unico snapshot depois que `CameraSystem`, `Shots` e `Zones` existirem. O plugin separara estado ativo do estado persistido: uma GUI reutilizada alternara listeners, preview e transparencia sem destruir o dock a cada fechamento.

**Tech Stack:** Luau strict, Roblox Studio APIs, Rojo 7.7.0, Lune 0.10.4, Selene 0.29.0, luau-lsp 1.69.0.

## Global Constraints

- Manter `--!strict` e nao usar `--!nocheck`, ignores amplos ou typecheck desabilitado.
- O runtime deve ler a configuracao uma unica vez depois da hierarquia existir; nao adicionar hot reload.
- A espera por `Workspace.CameraSystem`, `Shots` e `Zones` e indefinida, sem timeout.
- O plugin deve reutilizar a mesma `DockWidgetPluginGui` ao ocultar e reabrir.
- Shots e zones persistidos usam `Transparency = 1` fora do editor e `Transparency = 0` enquanto o editor estiver ativo.
- O runtime deve esconder os mesmos parts com `LocalTransparencyModifier = 1`, sem alterar `Transparency` persistido.
- Markers temporarios devem existir somente enquanto o editor estiver ativo.

---

### Task 1: Aguardar a hierarquia no cliente e ocultar dados no runtime

**Files:**
- Modify: `src/client/init.client.luau`
- Create: `src/client/camera/CameraVisibility.luau`
- Create: `tests/shared/camera/CameraVisibility.spec.luau`

**Interfaces:**
- Consumes: `Workspace.CameraSystem`, `Shots`, `Zones` e listas de `BasePart`s diretas.
- Produces: `CameraVisibility.hide(root: Instance): ()` e inicializacao do controller apos `WaitForChild`.

- [ ] **Step 1: Escrever o teste comportamental de visibilidade**

Criar fixtures falsas com `BasePart` direto em `Shots` e `Zones`, alem de uma parte aninhada e uma parte fora da arvore. Verificar que `hide` define `LocalTransparencyModifier = 1` somente nos filhos diretos de `Shots` e `Zones`.

- [ ] **Step 2: Executar os testes para confirmar RED**

Run: `lune run test`

Expected: a nova suite falha porque `CameraVisibility` ainda nao existe.

- [ ] **Step 3: Implementar o helper de visibilidade**

Implementar `CameraVisibility.hide(root)` com `FindFirstChild`/`GetChildren`, exigindo as pastas `Shots` e `Zones` e atribuindo `LocalTransparencyModifier = 1` apenas aos `BasePart`s diretos.

- [ ] **Step 4: Aguardar a hierarquia antes do snapshot**

Em `src/client/init.client.luau`, substituir `FindFirstChild` por:

```lua
local cameraSystem = workspace:WaitForChild("CameraSystem")
cameraSystem:WaitForChild("Shots")
cameraSystem:WaitForChild("Zones")
local cameraConfig = CameraMapReader.read(cameraSystem)
CameraVisibility.hide(cameraSystem)
```

Manter a ordem: leitura, ocultacao e somente entao criacao/inicio do controller e debugger; nao conectar eventos de alteracao.

- [ ] **Step 5: Executar testes e checks**

Run: `lune run test`

Expected: todas as suites passam.

Run: `selene --config selene.roblox.toml src` e `selene --config selene.lune.toml tests lune`

Expected: zero diagnosticos novos.

- [ ] **Step 6: Commitar**

```bash
git add src/client/init.client.luau src/client/camera/CameraVisibility.luau tests/shared/camera/CameraVisibility.spec.luau
git commit -m "feat: wait for and hide camera map at runtime"
```

### Task 2: Reutilizar o dock e controlar visibilidade no editor

**Files:**
- Modify: `plugin/init.plugin.luau`
- Modify: `plugin/camera/CameraSystemPreview.luau`
- Modify: `plugin/camera/CameraSystemModel.luau`

**Interfaces:**
- Consumes: `CameraSystemModel`, `CameraSystemPreview`, `CameraSystemWidget`, `DockWidgetPluginGui.Enabled` e `BindToClose`.
- Produces: ativacao/desativacao idempotente do editor, com parts persistidos visiveis somente durante a edicao.

- [ ] **Step 1: Adicionar operacoes de visibilidade ao modelo**

Adicionar `setPartsVisible(visible: boolean): ()` ao modelo. A operacao deve localizar a hierarquia atual e definir `Transparency` nos `BasePart`s diretos de `Shots` e `Zones` para `0` quando `visible` for verdadeiro e `1` caso contrario. Registrar waypoints antes e depois, como nas mutacoes existentes.

- [ ] **Step 2: Separar abrir, ativar, desativar e destruir**

Refatorar `plugin/init.plugin.luau` para manter `widget`, `preview` e `model` depois de ocultar o dock. Criar funcoes:

```lua
activateEditor(): ()
deactivateEditor(): ()
destroyEditor(): ()
```

`activateEditor` deve garantir a hierarquia, definir parts visiveis, conectar listeners uma vez, atualizar listas/validacao e criar/atualizar preview. `deactivateEditor` deve desconectar listeners, limpar preview, ocultar parts e definir `gui.Enabled = false`. `destroyEditor` deve chamar a desativacao, destruir a GUI e zerar referencias.

- [ ] **Step 3: Corrigir os caminhos do toolbar e do fechamento do dock**

O clique do toolbar deve chamar `activateEditor` quando o widget ainda nao existir; caso exista, alternar entre `activateEditor` e `deactivateEditor`. O callback de `BindToClose` deve somente desativar, nunca destruir a GUI. O callback de unload/plugin desativado deve destruir o editor se a API estiver disponivel.

- [ ] **Step 4: Manter markers somente durante ativacao**

Garantir que `preview:clear()` seja chamado em toda desativacao e que `preview:refresh()` ocorra em toda ativacao. Nao criar preview durante a inicializacao do plugin se o dock estiver fechado.

- [ ] **Step 5: Verificar o fluxo estatico e os builds**

Run: `selene --config selene.roblox.toml plugin`

Run: `rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx`

Run: `lune run test`

Expected: zero diagnosticos, build concluido e todas as suites passando.

- [ ] **Step 6: Commitar**

```bash
git add plugin/init.plugin.luau plugin/camera/CameraSystemPreview.luau plugin/camera/CameraSystemModel.luau
git commit -m "feat: reuse camera editor and toggle authored visibility"
```

### Task 3: Verificacao integrada

**Files:**
- Verify: `src/client/init.client.luau`
- Verify: `src/client/camera/CameraVisibility.luau`
- Verify: `plugin/init.plugin.luau`
- Verify: `plugin/camera/CameraSystemModel.luau`
- Verify: `plugin/camera/CameraSystemPreview.luau`

- [ ] **Step 1: Executar testes e lints separados**

```bash
lune run test
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
selene --config selene.roblox.toml plugin
```

- [ ] **Step 2: Executar typechecks e builds**

Executar os dois typechecks documentados em `AGENTS.md`, gerar o sourcemap separado do plugin quando necessario, e construir:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx
rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx
```

- [ ] **Step 3: Validar manualmente no Studio**

Confirmar: cliente aguarda a hierarquia replicada; parts ficam invisiveis no playtest; toolbar abre, fecha e reabre o mesmo dock; fechar pelo X tambem permite reabrir; parts aparecem somente com editor ativo; preview e removido ao fechar; transformacoes persistem.

- [ ] **Step 4: Revisar diff**

```bash
```
