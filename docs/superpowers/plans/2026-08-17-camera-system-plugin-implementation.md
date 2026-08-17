# Camera System Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir a configuracao estatica de camera por shots e zonas persistidos no `Workspace`, oferecendo um plugin leve para autoria no Roblox Studio.

**Architecture:** O runtime tera um `CameraMapReader` que converte `Workspace.CameraSystem` em uma configuracao pura para o `CameraResolver`; a leitura ocorrera uma vez antes de iniciar o controller. O plugin ficara em uma arvore Rojo separada, com um modelo de dados focado em criar, editar, validar e ordenar `Part`s e um `DockWidget` que delega transformacoes espaciais para as ferramentas nativas do Studio.

**Tech Stack:** Luau strict, Roblox Studio APIs, Rojo 7.7.0, Lune 0.10.4, Selene 0.29.0, luau-lsp 1.69.0, testes comportamentais em Lune.

## Global Constraints

- Manter `--!strict` nos modulos Luau e nao usar `--!nocheck`, ignores amplos ou `typeErrors: false`.
- O runtime Roblox sera verificado com `selene --config selene.roblox.toml src`.
- Os testes Lune serao verificados com `selene --config selene.lune.toml tests lune`.
- Testes comportamentais serao executados com `lune run test`.
- Typecheck Roblox usara `rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json` seguido do comando `luau-lsp` documentado em `AGENTS.md`.
- Typecheck Lune continuara separado, sem definicoes Roblox ou sourcemap.
- O plugin nao sera incluido na arvore do jogo em `default.project.json`.
- A ordem de resolucao das zonas sera persistida no atributo numerico `Order`; nao adicionar um conceito separado de prioridade nesta entrega.
- O runtime lera a arvore de camera uma unica vez no inicio do cliente e falhara com erro contextual se a configuracao for invalida.

---

## File Map

### Runtime e tipos

- Modify: `src/shared/camera/CameraConfig.luau` - manter somente os tipos exportados e remover a tabela de configuracao estatica usada como fonte de runtime.
- Create: `src/shared/camera/CameraMapReader.luau` - ler e validar `CameraSystem`, `Shots` e `Zones`, retornando `CameraConfig.Config`.
- Modify: `src/client/init.client.luau` - ler `Workspace.CameraSystem` antes de criar o controller e o debugger.
- Modify: `tests/shared/camera/CameraResolver.spec.luau` - remover a dependencia da configuracao estatica e manter fixtures locais para o resolver.
- Create: `tests/shared/camera/CameraMapReader.spec.luau` - testar conversao, ordenacao e falhas do leitor usando instancias falsas.

### Plugin

- Create: `plugin.project.json` - arvore Rojo separada para empacotar o plugin sem o inserir no jogo.
- Create: `plugin/init.plugin.luau` - ponto de entrada do plugin, toolbar, `DockWidgetPluginGui` e ciclo de vida.
- Create: `plugin/camera/CameraSystemModel.luau` - criar/localizar a hierarquia persistida e executar operacoes de dados.
- Create: `plugin/camera/CameraSystemPreview.luau` - criar e limpar markers temporarios de shots e zonas.
- Create: `plugin/camera/CameraSystemWidget.luau` - construir o painel, listas, controles e sincronizacao com `Selection`.

### Verificacao

- No change expected: `default.project.json` - continuar mapeando somente o jogo; o plugin sera construido com `plugin.project.json`.
- No change expected: `src/shared/camera/CameraResolver.luau` - continuar recebendo configuracao pura e resolvendo a primeira zona correspondente.
- No change expected: `src/client/camera/CameraController.luau` - continuar recebendo `CameraConfig.Config` e controlando a camera.
- No change expected: `src/client/camera/CameraDebugger.luau` - continuar visualizando a configuracao pura carregada durante o playtest.

---

### Task 1: Implementar o leitor testavel da arvore de camera

**Files:**
- Create: `tests/shared/camera/CameraMapReader.spec.luau`
- Modify: `src/shared/camera/CameraConfig.luau:28-134`
- Create: `src/shared/camera/CameraMapReader.luau`

**Interfaces:**
- Consumes: uma instancia raiz com filhos `Shots` e `Zones`; cada filho deve expor `Name`, `CFrame`, `Size`, `GetAttribute`, `GetChildren` e `IsA`.
- Produces: `CameraMapReader.read(root: Instance?): CameraConfig.Config`.

- [ ] **Step 1: Escrever fixtures falsas para a arvore de instancias**

No inicio de `CameraMapReader.spec.luau`, carregar `harness`, `roblox-loader`,
`@lune/roblox`, `CameraMapReader` e criar helpers locais. O helper de part deve
retornar uma tabela com estes membros: `Name`, `ClassName`, `CFrame`, `Size`,
`attributes`, `GetAttribute`, `SetAttribute`, `GetChildren` e `IsA`. O helper de
folder deve retornar `Name`, `ClassName`, `children`, `GetChildren`,
`FindFirstChild` e `IsA`.

O fixture valido deve representar:

```lua
CameraSystem [Folder]
  DefaultShotId = "Center"
  Shots [Folder]
    Center [Part] FieldOfView = 55
    North [Part] FieldOfView = 60
  Zones [Folder]
    First [Part] ShotId = "Center", Order = 2
    Second [Part] ShotId = "North", Order = 1
```

Os helpers precisam imitar `GetChildren()` retornando uma copia da lista, para
que o leitor nao possa alterar a arvore falsa durante a ordenacao.

- [ ] **Step 2: Escrever os testes comportamentais que devem falhar**

Adicionar uma suite `CameraMapReader` com estes casos:

```lua
harness.it("converte shots e zonas para CameraConfig", function()
    local config = CameraMapReader.read(newCameraSystem())
    harness.assert.equal(config.defaultShotId, "Center")
    harness.assert.equal(config.shots.North.fieldOfView, 60)
    harness.assert.equal(config.zones[1].id, "Second")
    harness.assert.equal(config.zones[2].id, "First")
    harness.assert.equal(config.zones[1].shotId, "North")
end)

harness.it("preserva CFrame e Size das instancias", function()
    local root = newCameraSystem()
    local config = CameraMapReader.read(root)
    harness.assert.equal(config.shots.Center.cframe, root.Shots.Center.CFrame)
    harness.assert.equal(config.zones[1].volume.size, root.Zones.Second.Size)
end)

harness.it("rejeita ShotId inexistente", function()
    local root = newCameraSystem()
    root.Zones.First.attributes.ShotId = "Missing"
    assertReadFails(root, "First")
end)

harness.it("rejeita DefaultShotId inexistente", function()
    local root = newCameraSystem()
    root.attributes.DefaultShotId = "Missing"
    assertReadFails(root, "DefaultShotId")
end)

harness.it("rejeita FOV invalido e tamanho nao positivo", function()
    local root = newCameraSystem()
    root.Shots.Center.attributes.FieldOfView = 0
    assertReadFails(root, "Center")

    root = newCameraSystem()
    root.Zones.First.Size = Vector3.new(0, 10, 10)
    assertReadFails(root, "First")
end)

harness.it("rejeita Order ausente ou invalido", function()
    local root = newCameraSystem()
    root.Zones.First.attributes.Order = nil
    assertReadFails(root, "First")
end)
```

O helper `assertReadFails` deve usar `pcall` e verificar que a mensagem contem
o identificador passado. Nao testar apenas que qualquer erro ocorreu, porque o
contrato exige contexto de instancia.

- [ ] **Step 3: Executar somente a suite nova para confirmar o RED**

Run: `lune run test`

Expected: a suite nova falha porque `CameraMapReader.luau` ainda nao existe ou
nao implementa `read`; as suites preexistentes continuam sendo executadas pelo
runner.

- [ ] **Step 4: Remover a configuracao estatica de `CameraConfig`**

Em `src/shared/camera/CameraConfig.luau`, manter os tipos exportados:

```lua
export type ShotId = string
export type ZoneId = string
export type Shot = { cframe: CFrame, fieldOfView: number }
export type Volume = { cframe: CFrame, size: Vector3 }
export type Zone = { id: ZoneId, volume: Volume, shotId: ShotId }
export type Config = {
    defaultShotId: ShotId,
    shots: { [ShotId]: Shot },
    zones: { Zone },
}
```

Retornar uma tabela vazia tipada ou um modulo equivalente sem shots e zonas
hardcoded. Atualizar qualquer consumidor que leia valores da tabela; os
consumidores de tipos podem continuar usando `CameraConfig.Config`.

- [ ] **Step 5: Implementar `CameraMapReader.read`**

Implementar o modulo com `--!strict` e estas regras, nesta ordem:

1. Confirmar que `root` e `Folder` e localizar `Shots` e `Zones` como folders.
2. Ler `DefaultShotId` como string nao vazia.
3. Para cada filho direto de `Shots`, exigir `BasePart`, ler `FieldOfView` como
   number e montar `shots[shot.Name]` com `CFrame` e FOV.
4. Confirmar que `DefaultShotId` existe em `shots`.
5. Para cada filho direto de `Zones`, exigir `BasePart`, ler `ShotId` como string,
   ler `Order` como number inteiro, validar `Size.X/Y/Z > 0` e armazenar uma
   entrada temporaria com o valor de order.
6. Ordenar as entradas por `Order`; em empate, ordenar por `Name` para que o
   resultado seja deterministico.
7. Confirmar que cada `ShotId` de zona existe em `shots`.
8. Retornar a configuracao sem expor o campo interno `Order` ao resolver.

Usar mensagens no formato `CameraSystem: <tipo> "<nome>" <problema>`. Nao
delegar a leitura para `CameraResolver`, pois o leitor precisa apontar a
instancia persistida que causou o erro. O `CameraResolver.new` continuara
validando a configuracao pura como segunda barreira.

- [ ] **Step 6: Executar a suite para confirmar o GREEN**

Run: `lune run test`

Expected: todos os casos de `CameraMapReader` e as suites existentes passam.

- [ ] **Step 7: Rodar lint e typecheck dos modulos alterados**

Run: `selene --config selene.roblox.toml src`

Expected: nenhum diagnostico em `src/shared/camera`.

Run: `selene --config selene.lune.toml tests lune`

Expected: nenhum diagnostico nos testes.

- [ ] **Step 8: Commitar a unidade do leitor**

```bash
git add src/shared/camera/CameraConfig.luau src/shared/camera/CameraMapReader.luau tests/shared/camera/CameraMapReader.spec.luau
git commit -m "feat: read camera configuration from workspace instances"
```

---

### Task 2: Conectar o leitor ao cliente e atualizar as fixtures do resolver

**Files:**
- Modify: `src/client/init.client.luau:1-27`
- Modify: `tests/shared/camera/CameraResolver.spec.luau:25-77`

**Interfaces:**
- Consumes: `CameraMapReader.read(workspace.CameraSystem)` e `CameraConfig.Config`.
- Produces: `CameraController` e `CameraDebugger` inicializados com a mesma configuracao lida do mapa.

- [ ] **Step 1: Remover a dependencia de dados estaticos no teste do resolver**

Em `CameraResolver.spec.luau`, remover a assercao que consulta
`CameraConfig.shots`, `CameraConfig.zones` e os testes que usam a configuracao
hardcoded. Manter `newConfig()` como fixture local e cobrir nela todos os
comportamentos do resolver: zonas adjacentes, zona rotacionada, fronteira,
shot default, referencias invalidas, FOV, tamanho e imutabilidade.

O teste deve carregar somente `CameraResolver` e os datatypes de
`@lune/roblox`; nao deve depender de valores de mapa.

- [ ] **Step 2: Atualizar a inicializacao do cliente**

Em `src/client/init.client.luau`, trocar:

```lua
local CameraConfig = require(ReplicatedStorage.Shared.camera.CameraConfig)
local CameraController = require(script.camera.CameraController)
local CameraDebugger = require(script.camera.CameraDebugger)

local controller = CameraController.new(CameraConfig)
```

por uma sequencia que carregue o leitor e leia a pasta antes de criar qualquer
controller:

```lua
local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)
local CameraController = require(script.camera.CameraController)
local CameraDebugger = require(script.camera.CameraDebugger)

local cameraSystem = workspace:FindFirstChild("CameraSystem")
local cameraConfig = CameraMapReader.read(cameraSystem)
local controller = CameraController.new(cameraConfig)
```

Criar o debugger com `cameraConfig` tambem. Nao capturar eventos de alteracao de
instancias depois desta leitura; o playtest deve usar um snapshot.

- [ ] **Step 3: Rodar os testes comportamentais**

Run: `lune run test`

Expected: todas as suites passam, incluindo os testes do resolver sem
configuracao estatica.

- [ ] **Step 4: Verificar o build do jogo**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx`

Expected: o build termina sem erro e continua contendo `ReplicatedStorage.Shared`
e os scripts de cliente existentes; nenhum arquivo de plugin aparece no
DataModel porque ele esta fora de `default.project.json`.

- [ ] **Step 5: Commitar a integracao do cliente**

```bash
git add src/client/init.client.luau tests/shared/camera/CameraResolver.spec.luau
git commit -m "feat: initialize camera from workspace configuration"
```

---

### Task 3: Criar o modelo e o projeto Rojo do plugin

**Files:**
- Create: `plugin.project.json`
- Create: `plugin/camera/CameraSystemModel.luau`

**Interfaces:**
- Consumes: `Workspace`, `Instance`, `Selection` e `ChangeHistoryService` fornecidos pelo ponto de entrada do plugin.
- Produces: modelo com metodos `ensureHierarchy`, `listShots`, `listZones`, `createShot`, `createZone`, `captureCamera`, `applyShot`, `setFieldOfView`, `assignShot`, `setDefaultShot`, `reorderZone` e `validate`.

- [ ] **Step 1: Criar o projeto separado do plugin**

Adicionar `plugin.project.json` com uma arvore propria que aponte para
`plugin/init.plugin.luau`, sem alterar `default.project.json`. O projeto deve
ser construido separadamente por:

```bash
rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx
```

O conteudo minimo do projeto deve ser:

```json
{
  "name": "camera-system-plugin",
  "tree": {
    "$path": "plugin"
  }
}
```

Usar a convencao de script `.plugin.luau` para que o arquivo carregue no
Studio no contexto de plugin, onde o global `plugin` e disponibilizado.

- [ ] **Step 2: Definir as constantes e helpers do modelo**

Em `CameraSystemModel.luau`, definir constantes para `CameraSystem`, `Shots`,
`Zones`, `DefaultShotId`, `FieldOfView`, `ShotId` e `Order`. Implementar helpers
privados para localizar folders, exigir nomes nao vazios e registrar uma
operacao no `ChangeHistoryService`.

O modelo deve aceitar os servicos no construtor para permanecer independente
de globais:

```lua
CameraSystemModel.new(workspace, selection, changeHistoryService): Model
```

- [ ] **Step 3: Implementar `ensureHierarchy` e listagem**

`ensureHierarchy()` deve criar ou reutilizar:

```text
Workspace.CameraSystem [Folder]
Workspace.CameraSystem.Shots [Folder]
Workspace.CameraSystem.Zones [Folder]
```

Sem sobrescrever shots, zonas ou atributos ja existentes. `listShots()` deve
retornar somente `BasePart`s filhos diretos de `Shots`, ordenados por `Name`.
`listZones()` deve retornar somente `BasePart`s filhos diretos de `Zones`,
ordenados por `Order` e depois por `Name`.

- [ ] **Step 4: Implementar criacao e edicao de shots**

Implementar estas operacoes com `ChangeHistoryService:SetWaypoint` antes e
depois da mutacao:

```lua
createShot(name: string, camera: Camera): Part
captureCamera(shot: Part, camera: Camera): ()
applyShot(shot: Part, camera: Camera): ()
setFieldOfView(shot: Part, fieldOfView: number): ()
setDefaultShot(shot: Part): ()
```

`createShot` deve criar um `Part` ancorado, sem colisao/toque/query, com o
`CFrame` e `FieldOfView` da camera, e falhar se o nome ja existir. `captureCamera`
deve atualizar ambos os valores. `applyShot` deve fazer o inverso. `setDefaultShot`
deve validar que o shot pertence a `Shots` e escrever `DefaultShotId` no root.
`setFieldOfView` deve aceitar somente numeros entre 1 e 120 e atualizar o
atributo `FieldOfView` do shot.

- [ ] **Step 5: Implementar criacao, associacao e ordenacao de zonas**

Implementar:

```lua
createZone(name: string, cframe: CFrame, size: Vector3): Part
assignShot(zone: Part, shot: Part): ()
reorderZone(zone: Part, delta: number): ()
```

`createZone` deve criar o `Part` ancorado com `CanCollide`, `CanTouch` e
`CanQuery` falsos, definir `ShotId` para o shot default atual quando ele
existir, e atribuir o proximo `Order` inteiro. Se nao houver shot default,
criar a zona sem esconder o estado invalido; o painel mostrara o erro e o
runtime falhara ate a configuracao ser corrigida.

`assignShot` deve exigir que ambos os objetos estejam na hierarquia correta.
`reorderZone` deve trocar os valores `Order` da zona com a vizinha na direcao
de `delta` (`-1` sobe, `1` desce), sem permitir valores duplicados ou negativos.

- [ ] **Step 6: Implementar `validate` para feedback do editor**

`validate()` deve retornar uma lista de strings, sem lancar erro, usando as
mesmas regras do runtime: folders existentes, default valido, FOV entre 1 e
120, filhos diretos que sejam `BasePart`, `ShotId` resolvivel, `Order` numerico
inteiro e `Size` positivo. As mensagens devem incluir o nome do shot ou zona.
O runtime continuara usando o `CameraMapReader` como autoridade final.

- [ ] **Step 7: Fazer lint do plugin e construir o pacote**

Run: `selene --config selene.roblox.toml plugin`

Expected: nenhum diagnostico nos modulos do plugin.

Run:

```bash
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --formatter gnu plugin
```

Expected: nenhum erro de tipo nos modulos do plugin. Esse typecheck e separado
do typecheck de `src` porque o plugin nao participa do sourcemap do jogo.

Run: `rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx`

Expected: pacote do plugin gerado sem erro.

- [ ] **Step 8: Commitar o modelo do plugin**

```bash
git add plugin.project.json plugin/camera/CameraSystemModel.luau
git commit -m "feat: add camera system plugin data model"
```

---

### Task 4: Implementar preview, painel e fluxo do plugin

**Files:**
- Create: `plugin/camera/CameraSystemPreview.luau`
- Create: `plugin/camera/CameraSystemWidget.luau`
- Create: `plugin/init.plugin.luau`

**Interfaces:**
- Consumes: `CameraSystemModel`, `Selection`, `Workspace.CurrentCamera`, `ChangeHistoryService` e APIs de `DockWidgetPluginGui`.
- Produces: toolbar `Camera System`, dock widget com listas e comandos de autoria, markers temporarios e sincronizacao de selecao.

- [ ] **Step 1: Implementar o preview temporario**

Em `CameraSystemPreview.luau`, criar uma pasta `__CameraSystemPreview` em
`Workspace`, marcar `Archivable = false` e limpar qualquer instancia antiga
com esse nome ao inicializar.

Implementar:

```lua
CameraSystemPreview.new(workspace): Preview
preview:refresh(shots: { Part }, zones: { Part }): ()
preview:clear(): ()
```

`refresh` deve destruir os markers anteriores e criar:

- Uma seta de tres segmentos para cada shot, usando seu `CFrame.LookVector`.
- Uma copia semitransparente de cada zona, com cor derivada do indice na lista.

Todos os markers devem ser ancorados, sem colisao/toque/query, sem sombras e
parentados apenas na pasta de preview. O runtime lera somente filhos diretos
de `CameraSystem.Shots` e `CameraSystem.Zones`, portanto esses markers nunca
serao confundidos com dados persistidos.

- [ ] **Step 2: Criar o widget e seus controles basicos**

Em `CameraSystemWidget.luau`, construir o `DockWidgetPluginGui` com:

- Botao `New Shot`.
- Botoes `Capture Camera`, `Apply To Camera` e `Set Default`.
- Botao `New Zone`.
- Campo/lista de `ShotId` e botao `Assign Shot`.
- Listas de shots e zonas.
- Botoes `Move Up` e `Move Down` para zonas.
- Campo numerico de FOV para shot selecionado.
- Area de status com erros de `model:validate()`.

O widget deve expor callbacks em vez de mutar o modelo diretamente:

```lua
CameraSystemWidget.new(widgetInfo, callbacks): Widget
widget:refresh(shots, zones, defaultShotId, errors): ()
widget:destroy(): ()
```

Cada linha da lista deve guardar a instancia associada e chamar
`Selection:Set({ instance })` ao ser clicada. O widget deve desabilitar
acoes que exigem shot/zona quando a selecao correspondente nao existir.

- [ ] **Step 3: Sincronizar selecao e alteracoes de dados**

No ponto de entrada, conectar `Selection.SelectionChanged` e as mudancas de
descendentes/atributos relevantes para chamar uma funcao de refresh do painel e
do preview. Nao conectar o runtime a esses eventos; eles existem apenas no
plugin.

Ao selecionar um `Part` no viewport:

- Se for filho de `Shots`, selecionar o shot na lista.
- Se for filho de `Zones`, selecionar a zona na lista.
- Se for marker de preview ou outro objeto, limpar a selecao logica do painel.

- [ ] **Step 4: Implementar o ponto de entrada do plugin**

Em `plugin/init.plugin.luau`:

1. Obter `Selection`, `ChangeHistoryService` e `Workspace`.
2. Criar `plugin:CreateToolbar("Camera System")`.
3. Criar um botao `Edit Camera System`.
4. Criar um `DockWidgetPluginGuiInfo` com `InitialDockState = Left`, tamanho
   inicial de 320x520 e `OverrideEnabled = true`.
5. Instanciar `CameraSystemModel`, `CameraSystemPreview` e
   `CameraSystemWidget` apenas quando o widget for ativado.
6. Chamar `ensureHierarchy()` antes de renderizar as listas.
7. Conectar callbacks do widget ao modelo:
   - `New Shot` usa `Workspace.CurrentCamera`.
   - `Capture Camera` e `Apply To Camera` usam o shot selecionado.
   - O campo FOV chama `setFieldOfView` com o valor numerico informado.
   - `New Zone` usa `Workspace.CurrentCamera.Focus.Position` como centro e
     `Vector3.new(10, 10, 10)` como tamanho inicial.
   - `Assign Shot` usa os objetos selecionados nas listas.
   - `Set Default` escreve `DefaultShotId`.
   - `Move Up` e `Move Down` chamam `reorderZone` com `-1` ou `1`.
8. Depois de cada callback, atualizar model, preview, validacao e listas.
9. Desconectar eventos e chamar `preview:clear()` ao fechar/desativar o widget.

- [ ] **Step 5: Verificar manualmente o workflow no Studio**

Construir o pacote:

```bash
rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx
```

Instalar o pacote como plugin local no Roblox Studio e confirmar:

1. O botao cria e abre o `Camera System` dock widget.
2. A primeira abertura cria `Workspace.CameraSystem`, `Shots` e `Zones`.
3. `New Shot` usa a posicao e FOV atuais da camera.
4. Mover/girar o Part do shot altera a transformacao persistida.
5. `Capture Camera` e `Apply To Camera` funcionam nos dois sentidos.
6. `New Zone` cria uma caixa transformavel.
7. Escalar e girar a zona no Studio preserva `CFrame` e `Size`.
8. `Assign Shot` grava `ShotId` e `Set Default` grava `DefaultShotId`.
9. Mover zonas para cima/baixo altera `Order` e a lista do painel.
10. Undo/Redo desfaz e refaz cada operacao do plugin.
11. O preview mostra direcao dos shots e volumes das zonas sem criar filhos em
    `Shots` ou `Zones`.
12. Fechar e reabrir o widget reutiliza os dados persistidos.

- [ ] **Step 6: Validar um playtest com configuracao valida e invalida**

No Studio, iniciar um playtest com pelo menos dois shots, um default e duas
zonas. Confirmar que o cliente troca de shot ao atravessar as zonas e que,
quando duas zonas se sobrepoem, a primeira conforme `Order` vence.

Depois, quebrar deliberadamente o atributo `ShotId` de uma zona e iniciar outro
playtest. Confirmar que o output apresenta erro contendo o nome da zona e o
shot inexistente, e que o controller nao inicia com configuracao parcial.

- [ ] **Step 7: Commitar o plugin completo**

```bash
git add plugin/init.plugin.luau plugin/camera/CameraSystemModel.luau plugin/camera/CameraSystemPreview.luau plugin/camera/CameraSystemWidget.luau
git commit -m "feat: add camera system studio plugin"
```

---

### Task 5: Executar a verificacao completa e revisar a entrega

**Files:**
- Verify: `docs/superpowers/specs/2026-08-17-camera-system-plugin-design.md`
- Verify: `docs/superpowers/plans/2026-08-17-camera-system-plugin-implementation.md`
- Verify: todos os arquivos listados nas tarefas anteriores.

**Interfaces:**
- Consumes: runtime, testes e pacote do plugin implementados nas tarefas anteriores.
- Produces: evidencia final de testes, lint, typecheck e build.

- [ ] **Step 1: Executar os testes comportamentais**

Run: `lune run test`

Expected: todas as suites descobertas passam, incluindo `CameraResolver` e
`CameraMapReader`.

- [ ] **Step 2: Executar os lints separados**

Run: `selene --config selene.roblox.toml src`

Expected: nenhum diagnostico nos scripts Roblox do jogo.

Run: `selene --config selene.lune.toml tests lune`

Expected: nenhum diagnostico nos testes e scripts Lune.

Run: `selene --config selene.roblox.toml plugin`

Expected: nenhum diagnostico nos scripts Roblox do plugin.

- [ ] **Step 3: Executar os typechecks conforme o repositorio**

Run:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

Expected: nenhum erro de tipo em `src`.

Run:

```bash
luau-lsp analyze --platform standard \
  --base-luaurc typecheck/lune.luaurc --formatter gnu tests lune
```

Expected: nenhum erro de tipo em testes e scripts Lune.

O plugin sera validado pela analise Roblox apenas se o ambiente do projeto
aceitar a arvore `plugin`; caso contrario, usar a verificacao manual de lint e
o build do pacote como barreiras e registrar o diagnostico exato antes de
ajustar a configuracao.

- [ ] **Step 4: Construir jogo e plugin**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx`

Expected: build do jogo concluido sem plugin na arvore principal.

Run: `rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx`

Expected: pacote do plugin concluido sem erro.

- [ ] **Step 5: Revisar o diff e o status**

Run: `git diff --check && git status --short`

Expected: nenhum whitespace invalido; somente arquivos da especificacao,
plano e implementacao desta feature aparecem como alterados ou nao rastreados.

- [ ] **Step 6: Fazer uma revisao final contra a especificacao**

Confirmar explicitamente que a entrega cobre:

- shots editaveis por `Part` e capturaveis pela camera do Studio;
- zonas 3D completamente transformaveis;
- associacao zona-shot por `ShotId`;
- `DefaultShotId` persistido no root;
- ordem persistida por `Order`;
- leitura unica no inicio;
- erro explicito em referencia invalida;
- ausencia de hot reload, deteccao de overlap e prioridade independente nesta entrega.
