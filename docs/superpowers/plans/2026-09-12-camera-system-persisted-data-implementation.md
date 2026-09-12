# Camera System: Parts Efemeras e Dados Serializados — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remover completamente `Shots` e `Zones` do Workspace enquanto o editor do plugin estiver desativado, persistindo a configuracao em `CameraSystem.Data` (StringValue JSON) e recriando as parts ao ativar; migrar o runtime para ler os dados serializados, com fallback para places antigos que ainda tem parts; e adicionar build versionado do plugin com rollback.

**Architecture:** O plugin passa a tratar `BasePart`s como artefatos exclusivos de edicao. Ao desativar: captura parts -> JSON -> grava `CameraSystem.Data` -> destroi as parts (pastas `Shots`/`Zones` permanecem). Ao ativar: le `Data` -> recria parts. Ao carregar o plugin, o estado inativo e normalizado (se houver parts legadas, serializa e remove). O runtime `CameraMapReader` prefere BaseParts quando existirem (edicao/legado) e cai para `Data` quando as pastas estiverem vazias; a validacao semantica e as mensagens existentes sao preservadas. O codec vive em `src/shared/camera/CameraSystemData.luau` e e compartilhado com o plugin via mapeamento do Rojo. O build do plugin passa por um script que arquiva versoes fora da pasta de plugins do Studio e permite rollback.

**Tech Stack:** Luau `--!strict`, Roblox Studio APIs (HttpService, ChangeHistoryService), Bash, Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0, StyLua 2.5.2.

## Global Constraints

- Sem commits: nenhuma etapa de `git commit` (AGENTS.md).
- Manter `--!strict`; proibido `--!nocheck`, ignores amplos ou `any` para silenciar diagnosticos.
- `Packages/` e gerado e nao deve ser editado.
- Nao usar `plugin:SetSetting` nem `HttpService` para requests HTTP (apenas `JSONEncode`/`JSONDecode`); a persistencia vai no proprio lugar, sob `Workspace.CameraSystem`.
- `CameraSystem.Data` (StringValue) e a fonte de verdade persistida; `BasePart`s sao efemeras.
- Precedencia do reader: se `Shots` ou `Zones` tiverem qualquer `BasePart`, le parts (legado/edicao); senao le `Data`. Sem hot reload.
- Preservar os atributos `DefaultShotId`, `FieldOfView`, `ShotId` e `Order` e as mensagens de erro atuais do `CameraMapReader` sempre que possivel.
- Manter a assinatura publica `CameraMapReader.read(rootName: string): CameraConfig.Config` e os tipos de `CameraConfig`.
- O codec nao pode depender de `Workspace`; `capture` recebe a pasta raiz.
- O fallback legado (parts) so sai quando nao houver mais places no formato antigo.
- Backups de build ficam FORA da pasta de plugins do Studio; o Studio carrega todo `.rbxmx`/`.rbxm` daquela pasta.
- Verificacao por tarefa: `selene` + `rojo sourcemap` + `luau-lsp analyze`; build final do jogo e do plugin versionado.

## Decisoes

| Decisao | Escolha |
|---------|---------|
| Onde persistir | `Workspace.CameraSystem.Data` (StringValue com JSON versionado) |
| Runtime com editor desligado | `CameraMapReader` le `Data`; fallback para BaseParts |
| Quando serializar | Ao desativar o editor, ao descarregar o plugin e na normalizacao de carga |
| Quando materializar | Ao ativar o editor, se `Shots`/`Zones` estiverem sem BaseParts e `Data` existir |
| Dados invalidos | `capture` e leniente com valores (nao perde o estado); falha estrutural mantem parts; runtime falha explicitamente como hoje |
| Rollback do plugin | Builds arquivados com timestamp + SHA em `PluginBackups/` (fora da pasta Plugins), rotacao de 5, rollback por script |

## Estrutura persistida

```text
Workspace
└── CameraSystem [Folder]              -- DefaultShotId [string]
    ├── Data [StringValue]              -- JSON versionado (fonte de verdade)
    ├── Shots [Folder]                  -- vazia fora do editor
    └── Zones [Folder]                  -- vazia fora do editor
```

Formato do JSON (`version = 1`):

```json
{
  "version": 1,
  "defaultShotId": "Center",
  "shots": [
    { "name": "Center", "cframe": [x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22], "fieldOfView": 55 }
  ],
  "zones": [
    { "name": "CenterZone", "cframe": [12 numeros], "size": [x,y,z], "shotId": "Center", "order": 1 }
  ]
}
```

---

### Task 1: Codec compartilhado `CameraSystemData`

**Files:**
- Create: `src/shared/camera/CameraSystemData.luau`

**Interfaces:**
- Produces: `CameraSystemData.VERSION` (`number`), `CameraSystemData.DATA_NAME` (`string`), `CameraSystemData.capture(root: Folder): Config`, `CameraSystemData.encode(config: Config): string`, `CameraSystemData.decode(value: string): Config`.
- Produces tipos: `ShotData = { name: string, cframe: CFrame, fieldOfView: number }`, `ZoneData = { name: string, cframe: CFrame, size: Vector3, shotId: string, order: number }`, `Config = { defaultShotId: string, shots: { ShotData }, zones: { ZoneData } }`.

- [x] **Step 1: Criar o modulo com tipos e constantes**

Definir `VERSION = 1`, `DATA_NAME = "Data"` e os tipos `ShotData`, `ZoneData`, `Config` no padrao do repo (tabela de modulo com `--!strict`). Obter `HttpService` com `local HttpService = game:GetService("HttpService")` (`JSONEncode`/`JSONDecode` nao dependem de `HttpEnabled`).

- [x] **Step 2: Implementar `capture(root: Folder): Config`**

- Exigir `Shots` e `Zones` como `Folder`; erro claro caso contrario.
- Erro se houver filho direto de `Shots`/`Zones` que nao seja `BasePart` (preservar a semantica de validacao atual). Nao inspecionar outros filhos da raiz (ex.: o proprio `Data`).
- Shots: array ordenado por nome; `cframe = part.CFrame`; `fieldOfView` = atributo se for numero finito, senao `0`.
- Zones: array ordenado por `Order` (numeros validos primeiro, depois nome; mesma regra de `listZones`); `size = part.Size`; `shotId` = atributo se for string, senao `""`; `order` = atributo se for numero finito, senao `0`.
- `defaultShotId` = atributo `DefaultShotId` se for string, senao `""`.
- Nao incluir nenhum outro filho da raiz (ex.: `Data`) no config.

- [x] **Step 3: Implementar `encode(config): string`**

- Converter `CFrame` com `GetComponents()` (12 numeros) e `Vector3` como 3 numeros.
- Serializar com `HttpService:JSONEncode`; erro se algum numero for nao finito (`NaN`/`inf`).
- Ordem estavel: shots por nome, zones por `order`/nome.

- [x] **Step 4: Implementar `decode(value: string): Config`**

- `JSONDecode` em `pcall`; erro com mensagem clara em caso de JSON invalido.
- Exigir `version == VERSION`; erro caso contrario.
- Validacao estrutural: `defaultShotId` string; `shots`/`zones` arrays de tabelas; `name` string nao vazia e unica; `cframe` com 12 numeros finitos; `fieldOfView`/`order` numeros finitos; `size` com 3 numeros finitos; `shotId` string.
- Retornar `Config` tipado com casts explicitos; nao validar faixas semanticas (FOV 1-120, `Size > 0`, `Order` inteiro, referencias) — isso fica no `CameraMapReader` e no `validate()` do plugin.

- [x] **Step 5: Verificar estaticamente**

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu \
  src
```

Expected: zero diagnosticos.

---

### Task 2: Migrar `CameraMapReader` para os dados serializados

**Files:**
- Modify: `src/shared/camera/CameraMapReader.luau`

**Interfaces:**
- Consumes: `CameraSystemData.capture`, `CameraSystemData.decode`, `CameraSystemData.DATA_NAME`.
- Produces: mesma assinatura `CameraMapReader.read(rootName: string): CameraConfig.Config`; le `Data` quando `Shots`/`Zones` estiverem sem BaseParts.

- [x] **Step 1: Extrair a validacao semantica e o mapeamento**

Criar uma funcao local `toRuntimeConfig(raw: CameraSystemData.Config, rootFolder: Folder): CameraConfig.Config` que:
- Valida `FieldOfView` entre 1 e 120 com a mensagem atual `Shot "%s" deve ter FieldOfView entre 1 e 120`.
- Valida `DefaultShotId` nao vazio e existente com a mensagem atual `DefaultShotId "%s" nao existe em Shots`.
- Valida `ShotId` com a mensagem atual de string nao vazia e referencia existente.
- Valida `Order` inteiro com a mensagem atual.
- Valida `Size` positivo com a mensagem atual.
- Ordena as zonas por `order` e depois `name` (mesma regra atual) e devolve `CameraConfig.Config`.

- [x] **Step 2: Adicionar a leitura de `Data` com precedencia para parts**

No inicio de `read`:
- Apos obter `rootFolder`, `shotsFolder` e `zonesFolder`, detectar se existe `BasePart` direto em `Shots` ou `Zones` (mesmo criterio do `hasParts` do plugin).
- Se existir: `raw = CameraSystemData.capture(rootFolder)` (fluxo legado/edicao).
- Senao: `local data = rootFolder:WaitForChild(CameraSystemData.DATA_NAME)` (evita corrida de replicacao no servidor ao vivo; a espera e indefinida, como `Shots`/`Zones` hoje); se for `StringValue`, `raw = CameraSystemData.decode(data.Value)`.
- Se `Data` existir com tipo errado, falhar (`CameraSystem.Data deve ser um StringValue`).
- Encaminhar `raw` para `toRuntimeConfig` e remover a iteracao direta de parts e as validacoes duplicadas.

- [x] **Step 3: Verificar estaticamente e compilar o jogo**

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu \
  src
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
```

Expected: zero diagnosticos e build concluido.

---

### Task 3: Adaptar o modelo e o widget do plugin

**Files:**
- Modify: `plugin.project.json`
- Modify: `plugin/camera/CameraSystemModel.luau`
- Modify: `plugin/camera/CameraSystemWidget.luau`

**Interfaces:**
- Consumes: `CameraSystemData` mapeado no build do plugin.
- Produces em `CameraSystemModel`: `captureConfig(self): CameraSystemData.Config`, `readData(self): CameraSystemData.Config?`, `writeData(self, config: CameraSystemData.Config): ()`, `materialize(self, config: CameraSystemData.Config): ()`, `destroyParts(self): ()`, `showParts(self): ()`, `hasParts(self): boolean`.
- Produces em `CameraSystemWidget`: `clearSelection(self): ()`.

- [x] **Step 1: Mapear o codec no projeto do plugin**

Alterar `plugin.project.json` para incluir o modulo compartilhado como filho do script raiz:

```json
{
  "name": "camera-system-plugin",
  "tree": {
    "$path": "plugin",
    "CameraSystemData": {
      "$path": "src/shared/camera/CameraSystemData.luau"
    }
  }
}
```

Com esse mapeamento, `CameraSystemData` e irmao da Folder `camera` (nao filho dela). Portanto: `init.plugin.luau` (raiz) usa `require(script.CameraSystemData)`; `CameraSystemModel.luau` (dentro de `camera/`) usa `require(script.Parent.Parent.CameraSystemData)`.

Conferir a inclusao com o sourcemap, que prova a arvore (build terminando sem erro nao prova):

```bash
rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/camera-system-plugin-sourcemap.json
rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: `CameraSystemData` aparece como `ModuleScript` filho da raiz do plugin, ao lado da Folder `camera`, e o build conclui.

- [x] **Step 2: Substituir `setPartsVisible` por `showParts`**

Remover `setPartsVisible` e adicionar `showParts` que deixa as parts em aparencia de edicao: shots `Transparency = 0`, zones `Transparency = 0.75`, `Locked = false`. Manter os waypoints begin/end.

- [x] **Step 3: Ajustar `createShot` e `createZone`**

Criar shots com `Transparency = 0` e zones com `Transparency = 0.75` (aparência de edicao), `Locked = false`. Nao gravar mais a transparencia de "persistido oculto" — fora do editor a part nao existe.

- [x] **Step 4: Adicionar operacoes de dados e materializacao ao modelo**

- `hasParts`: `#listShots() > 0 or #listZones() > 0`.
- `captureConfig`: `CameraSystemData.capture(self:ensureHierarchy().root)`.
- `readData`: `FindFirstChild(CameraSystemData.DATA_NAME)`; `nil` se ausente; exigir `StringValue`; `CameraSystemData.decode(value)`. E edit-time, sem corrida de replicacao.
- `writeData`: criar/reutilizar `StringValue` chamado `CameraSystemData.DATA_NAME` na raiz e atribuir `CameraSystemData.encode(config)`; waypoints begin/end; erro se o filho existente nao for `StringValue`.
- `materialize(config)`: definir `DefaultShotId` na raiz e recriar as parts na ordem shots -> zones, com nome, `CFrame`, `Size`, atributos `FieldOfView`/`ShotId`/`Order`, `Anchored = true`, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`, `Locked = false` e transparencia de edicao; waypoints begin/end.
- `destroyParts`: destruir somente `BasePart`s diretos de `Shots`/`Zones`; waypoints begin/end.
- Nota: como as demais mutacoes, `materialize`/`destroyParts` entram no historico do `ChangeHistoryService`; um undo pos-desativacao pode restaurar parts enquanto `Data` existe, e a proxima normalizacao (carga ou desativacao) resolve o estado. Registrar essa decisao na spec (Task 5).

- [x] **Step 5: Limpar a selecao no widget**

Adicionar `CameraSystemWidget.clearSelection` que zera `shotSelection`/`zoneSelection`, limpa `fovInput`/`shotIdInput` e chama `updateSelectionVisuals`.

- [x] **Step 6: Verificar estaticamente e buildar o plugin**

O README ja documenta o typecheck do plugin com sourcemap proprio (o sourcemap do jogo nao cobre `plugin/`); usa-lo aqui:

```bash
selene --config selene.roblox.toml plugin
rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/camera-system-plugin-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap /tmp/camera-system-plugin-sourcemap.json \
  --formatter gnu \
  plugin
rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: zero diagnosticos e build concluido.

---

### Task 4: Reorganizar o ciclo de vida em `plugin/init.plugin.luau`

**Files:**
- Modify: `plugin/init.plugin.luau`

**Interfaces:**
- Consumes: novos metodos do modelo e `CameraSystemWidget.clearSelection`.
- Produces: `activateEditor` materializa; `deactivateEditor` serializa e destroi; carga do plugin normaliza o estado inativo.

- [x] **Step 1: Remover o controle de transparencia de persistidos**

Remover `setPersistedPartsTransparency` e a chamada final; a ocultacao deixa de existir porque as parts sao removidas.

- [x] **Step 2: Criar helpers de persistencia e remocao**

- `persistParts(): boolean`: `pcall` capturando config do modelo e gravando em `Data`; em falha, `warn` com o label `Camera System: persist parts failed` e retorna `false`.
- `removeParts(): boolean`: `pcall` chamando `destroyParts`; em falha, `warn` e retorna `false`.

- [x] **Step 3: Normalizar o estado inativo na carga do plugin**

Se `Workspace.CameraSystem` existir e for `Folder`: criar `model` se necessario, `ensureHierarchy`, e se `hasParts()` entao `persistParts()` e, somente em caso de sucesso, `removeParts()`. Se a raiz nao existir, nao criar nada.

- [x] **Step 4: Atualizar `activateEditor`**

- Garantir `model` via helper `ensureModel()` (cria somente se `nil`; o bloco `if widget == nil` nao pode recriar o model).
- `ensureHierarchy`.
- Se `not hasParts()`: `local config = readData()`; se nao for `nil`, `materialize(config)`.
- Chamar `showParts()` para padronizar parts adotadas (legado salvo com editor ativo).
- Manter `preview` e `widget` sendo criados no bloco `if widget == nil` (o `preview` precisa existir antes do primeiro `refresh`), os listeners, o `refresh` e `gui.Enabled = true`; remover `setPartsVisible(true)`.

- [x] **Step 5: Atualizar `deactivateEditor`**

Ordem: `disconnectAll` -> `preview:clear()` -> `persistParts()` -> se `true`, `removeParts()` -> `widget:clearSelection()` -> `gui.Enabled = false` -> `editorActive = false`. Se `persistParts` falhar, manter as parts e avisar (fail-safe para nao perder dados invalidos).

- [x] **Step 6: Revisar `destroyEditor`, `BindToClose` e `Unloading`**

`destroyEditor` continua chamando `deactivateEditor` antes de destruir o widget; `BindToClose` do dock e `plugin.Unloading` continuam persistindo/destruindo via `deactivateEditor`, com `model = nil` apenas no `destroyEditor`.

- [x] **Step 7: Verificar estaticamente e buildar**

Repetir o typecheck do plugin do Task 3 Step 6 (sourcemap proprio) e rodar:

```bash
selene --config selene.roblox.toml plugin
rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: zero diagnosticos e build concluido.

---

### Task 5: Documentacao

**Files:**
- Create: `docs/superpowers/specs/2026-09-12-camera-system-persistence-design.md`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-17-camera-system-plugin-design.md`

- [x] **Step 1: Registrar o design**

Criar a spec com: fonte de verdade (`Data`), formato JSON versionado, ciclo de vida do plugin (normalizar na carga, serializar/destruir ao desativar, materializar ao ativar), precedencia do reader (BaseParts > `Data`), fail-safe (erro semantico persiste e remove; falha estrutural mantem parts) e a decisao sobre waypoints/undo do ciclo de vida (`materialize`/`destroyParts` no historico; undo pode restaurar parts com `Data` presente).

- [x] **Step 2: Atualizar o README**

Na secao `Camera System Plugin`: documentar que desativar o editor remove as parts do Workspace, que `Data` guarda a configuracao, que ativar recria as parts e que o runtime le `Data` com fallback para parts antigas. Trocar o build manual pelo script (Task 6) e documentar o rollback.

- [x] **Step 3: Apontar a spec antiga para a nova**

Na spec `2026-08-17-camera-system-plugin-design.md`, ajustar a frase de fonte de verdade e adicionar um link para a spec nova, sem reescrever o restante do documento.

---

### Task 6: Build versionado e rollback do plugin

**Files:**
- Create: `scripts/plugin-build.sh`
- Create: `scripts/plugin-rollback.sh`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- `scripts/plugin-build.sh [--no-install]`: builda via `rojo build plugin.project.json`, arquiva com timestamp + SHA, rotaciona e instala no Studio.
- `scripts/plugin-rollback.sh list | previous | <arquivo>`: lista ou restaura uma versao arquivada.

**Localizacao dos backups:** `PLUGIN_BACKUP_DIR`, default `$(dirname "$ROBLOX_PLUGINS_DIR")/PluginBackups` (ex.: `/mnt/c/Users/leona/AppData/Local/Roblox/PluginBackups`). Fora da pasta `Plugins` de proposito: o Studio carrega todo `.rbxmx`/`.rbxm` daquela pasta, entao backups ali fariam duas versoes do plugin carregarem juntas.

- [x] **Step 1: Criar o script de build versionado**

`scripts/plugin-build.sh` com `set -euo pipefail`:
- Raiz do repo via `git rev-parse --show-toplevel`; `SHA=$(git rev-parse --short HEAD)`; sufixo `-dirty` se `git status --porcelain` nao vazio.
- `ROBLOX_PLUGINS_DIR` default `/mnt/c/Users/leona/AppData/Local/Roblox/Plugins` (mesmo caminho do README/AGENTS), sobrescrivivel por env.
- `PLUGIN_BACKUP_DIR` default `$(dirname "$ROBLOX_PLUGINS_DIR")/PluginBackups`, sobrescrivivel por env.
- Na primeira execucao, se o backup dir estiver vazio e o plugin instalado existir, arquiva-lo como `camera-system-plugin-installed-<timestamp>.rbxmx` antes de instalar (preserva a versao atual para rollback).
- Build para arquivo temporario; ao suceder, copia para `$PLUGIN_BACKUP_DIR/camera-system-plugin-<YYYYmmdd-HHMMSS>-<sha>[-dirty].rbxmx`.
- Rotaciona mantendo as 5 mais recentes (`ls -1t ... | tail -n +6 | xargs -r rm -f`).
- Instala com `mv` em `$ROBLOX_PLUGINS_DIR/camera-system-plugin.rbxmx`, a menos que `--no-install`; falha com mensagem clara se o diretorio nao existir.
- Imprime o caminho arquivado e o lembrete de reiniciar o Studio.

- [x] **Step 2: Criar o script de rollback**

`scripts/plugin-rollback.sh`:
- `list`: lista `$PLUGIN_BACKUP_DIR/*.rbxmx` mais recentes primeiro (nome + data), marcando o que difere do instalado.
- `<arquivo>`: valida que o caminho esta dentro de `$PLUGIN_BACKUP_DIR` e copia sobre `$ROBLOX_PLUGINS_DIR/camera-system-plugin.rbxmx`.
- `previous` (default): restaura o arquivo arquivado mais recente que difere do instalado (`cmp -s`); se nao houver, avisa.
- Imprime lembrete de reiniciar o Studio.

- [x] **Step 3: Documentar o fluxo e o caveat de dados**

- README: substituir o build manual pelo script e documentar `plugin-rollback.sh`. Registrar o caveat: rollback do plugin nao reverte o lugar; reverter para uma versao anterior a `Data` so funciona em place com parts materializadas — antes de downgradar, abrir o place com a versao atual, ativar o editor e salvar com as parts presentes.
- AGENTS.md: trocar o bloco de build do plugin por `scripts/plugin-build.sh` e citar `scripts/plugin-rollback.sh`.

- [x] **Step 4: Verificar os scripts**

```bash
chmod +x scripts/plugin-build.sh scripts/plugin-rollback.sh
bash -n scripts/plugin-build.sh scripts/plugin-rollback.sh
scripts/plugin-build.sh --no-install
scripts/plugin-rollback.sh list
```

Expected: sintaxe ok, build concluido, arquivo arquivado com timestamp/SHA e `list` mostrando os backups. Nao restaurar durante a verificacao.

---

### Task 7: Verificacao integrada

**Files:**
- Verify: `src/shared/camera/CameraSystemData.luau`
- Verify: `src/shared/camera/CameraMapReader.luau`
- Verify: `plugin/init.plugin.luau`
- Verify: `plugin/camera/CameraSystemModel.luau`
- Verify: `plugin/camera/CameraSystemWidget.luau`
- Verify: `plugin.project.json`
- Verify: `scripts/plugin-build.sh`
- Verify: `scripts/plugin-rollback.sh`

- [x] **Step 1: Rodar lint e typechecks completos**

Jogo:

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu \
  src
```

Plugin (sourcemap proprio, conforme o README):

```bash
selene --config selene.roblox.toml plugin
rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/camera-system-plugin-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap /tmp/camera-system-plugin-sourcemap.json \
  --formatter gnu \
  plugin
```

- [x] **Step 2: Buildar o jogo e instalar o plugin versionado**

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
scripts/plugin-build.sh
```

Expected: jogo buildado, plugin arquivado com timestamp + SHA e instalado na pasta de plugins do Studio.

- [x] **Step 3: Ensaiar o rollback**

```bash
scripts/plugin-rollback.sh list
scripts/plugin-rollback.sh previous
scripts/plugin-rollback.sh <arquivo-mais-recente>
```

Expected: `list` mostra as versoes; `previous` restaura a anterior; o comando com o arquivo mais recente reinstala a versao atual. Reiniciar o Studio antes de validar manualmente.

- [ ] **Step 4: Validar manualmente no Studio**

1. Place com parts legadas: abrir o Studio -> `CameraSystem.Shots`/`Zones` ficam sem `BasePart`, `CameraSystem.Data` existe e as listas do plugin continuam corretas ao ativar.
2. Desativar o editor -> pastas permanecem, parts somem, `Data` atualizado.
3. Fechar e reabrir o Studio -> parts continuam ausentes e `Data` intacto.
4. Ativar o editor -> parts recriadas com `CFrame`, `Size`, `FieldOfView`, `ShotId`, `Order` e `DefaultShotId` originais.
5. Editar shot (mover/girar) e zona (mover/escalar/atribuir shot) -> desativar -> ativar -> edicoes preservadas.
6. Play com o editor desativado -> camera resolve pelo caminho `Data`.
7. Play com o editor ativo -> camera resolve pelo caminho de parts e `CameraVisibility` esconde as parts.
8. Estado semanticamente invalido (ex.: zona sem `ShotId`): desativar persiste mesmo assim e remove as parts; reativar recria e o widget mostra o erro.
9. Falha estrutural (ex.: `Model` dentro de `Shots`): desativar mantem as parts e avisa no Output; corrigir e desativar remove normalmente.
10. Undo/Redo no Studio continua funcionando para as operacoes de edicao; undo do ciclo de vida pode restaurar parts com `Data` presente e a proxima normalizacao resolve.

- [x] **Step 5: Revisar o diff final**

```bash
git diff --stat
git diff -- src/shared/camera plugin scripts
```

## Fora de escopo

- Persistencia via `plugin:SetSetting` (dados sao por lugar).
- Materializar parts automaticamente ao iniciar o Play.
- Remover o fallback legado de BaseParts no reader.
- Hot reload da configuracao durante o playtest.
- Migrar automaticamente configuracao de `CameraConfig.luau` estatico.
- Marker de versao embutido no proprio plugin (a versao e identificada pelo nome do arquivo arquivado).
- Politica de migracao quando `version` mudar: o `decode` rejeita versao desconhecida e a migracao fica para um plano futuro.
