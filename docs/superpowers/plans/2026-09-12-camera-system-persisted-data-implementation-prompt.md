# Prompt de Implementacao — Camera System: Parts Efemeras e Dados Serializados

> **Como usar:** aponte o agente para este arquivo (ou copie o conteudo abaixo)
> junto com o plano `docs/superpowers/plans/2026-09-12-camera-system-persisted-data-implementation.md`.
> O plano e a fonte de detalhes; este prompt define como executar.

---

Voce vai implementar o plano **`docs/superpowers/plans/2026-09-12-camera-system-persisted-data-implementation.md`** neste repositorio. Leia o plano inteiro e o `AGENTS.md` da raiz antes de tocar em qualquer arquivo. O `AGENTS.md` prevalece sobre este prompt em caso de conflito.

## Contexto

- Projeto Luau para Roblox montado pelo Rojo 7.7.0: `src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService.Server`, `src/client` → `StarterPlayer.StarterPlayerScripts.Client`. O plugin e um build separado (`plugin.project.json`), nunca mapeado no jogo.
- A mudanca central: parar de manter shots/zones como `BasePart`s visiveis no `Workspace` quando o editor esta desativado, persistindo a configuracao em `Workspace.CameraSystem.Data` (StringValue com JSON versionado) e recriando as parts ao ativar.

## Regras inegociaveis

1. **Nao faca commits.** Nenhum `git commit`/`git add`, nem ao final. O usuario commita quando quiser.
2. Mantenha `--!strict` em todos os modulos. Proibido `--!nocheck`, ignores amplos ou `any` para silenciar diagnosticos.
3. Nao edite `Packages/` (gerado pelo Wally).
4. Nao use `plugin:SetSetting` nem `HttpService` para requests HTTP. `HttpService:JSONEncode`/`JSONDecode` sao permitidos e sao o codec.
5. Nao reabra decisoes ja tomadas no plano; se algo parecer errado, **pare e reporte** antes de improvisar:
   - `CameraSystem.Data` (StringValue, JSON `version = 1`) e a fonte de verdade persistida; `BasePart`s sao efemeras.
   - Precedencia do reader: se houver `BasePart` em `Shots` **ou** `Zones`, le parts; senao, le `Data`.
   - Serializa ao desativar, ao descarregar o plugin e na normalizacao de carga; materializa ao ativar.
   - `capture` e leniente com valores (grava `0`/`""`), estrita com estrutura (filho nao-`BasePart`, numero nao finito). Falha estrutural mantem as parts.
   - Validacao estrutural no codec; semantica no reader e no `validate()` do plugin.
   - Fallback legado de BaseParts permanece no reader.
6. Nao altere contratos publicos: `CameraMapReader.read(rootName: string): CameraConfig.Config` e os tipos de `CameraConfig` continuam iguais.

## Fatos criticos para nao errar

- **Codec compartilhado:** crie `src/shared/camera/CameraSystemData.luau` (`VERSION`, `DATA_NAME`, `capture`, `encode`, `decode`) e mapeie no `plugin.project.json` como filho do script raiz do plugin. O `CameraSystemData` fica **irmao** da Folder `camera`, entao: `init.plugin.luau` usa `require(script.CameraSystemData)`; `CameraSystemModel.luau` usa `require(script.Parent.Parent.CameraSystemData)`.
- **Reader:** ao ler `Data`, use `rootFolder:WaitForChild(CameraSystemData.DATA_NAME)` (corrida de replicacao). No plugin, `readData` pode usar `FindFirstChild` (edit-time).
- **`createShot`/`createZone`:** passam a nascer com aparencia de edicao (shots `Transparency = 0`, zones `0.75`, `Locked = false`); remova `setPartsVisible` e introduza `showParts`.
- **Typecheck do plugin:** o sourcemap do jogo nao cobre `plugin/`. Use o sourcemap proprio (`rojo sourcemap --include-non-scripts plugin.project.json`) no `luau-lsp analyze` dos Tasks 3, 4 e 7, como o README documenta.
- **Backups/rollback:** scripts arquivam em `PluginBackups/` (derivado do dir de plugins, **fora** da pasta de plugins do Studio) e mantem 5 versoes. O Studio carrega todo `.rbxmx` da pasta de plugins — nunca deixe backups la.

## Como executar

1. Siga as Tasks **1 → 7 na ordem**. Nao pule steps nem antecipe tasks.
2. Em cada task: implemente step a step e rode a verificacao listada nos Steps de verificacao (selene, sourcemap, luau-lsp analyze, rojo build). Se algo falhar, conserte antes de avancar; nao deixe o repositorio em estado quebrado.
3. Atualize os checkboxes (`- [x]`) do arquivo do plano conforme concluir cada step, se o seu fluxo permitir editar o plano.
4. Verificacao por task e obrigatoria; nao acumule para o final.
5. Antes de mudar um `require`, confirme o caminho pelo `plugin.project.json`/`default.project.json` e, se necessario, gere o sourcemap correspondente.
6. Se encontrar divergencia entre o plano e o codigo real (metodo renomeado, pasta diferente, contrato mudado), pare e reporte a divergencia com arquivo e linha antes de decidir.
7. A Task 7 Step 4 e validacao manual no Roblox Studio — **nao tente executa-la**; entregue o checklist para o usuario e pare.

## Proibicoes de escopo

- Nao remova o fallback legado de BaseParts.
- Nao materialize parts automaticamente ao iniciar o Play.
- Nao crie hot reload de configuracao.
- Nao migre `CameraConfig.luau` estatico.
- Nao adicione marker de versao embutido no plugin.
- Nao implemente politica de migracao para `version` diferente de 1 (o `decode` rejeita).

## Entrega final

Ao terminar as Tasks 1–7 (exceto o checklist manual), reporte de forma concisa:

- Arquivos criados e modificados (caminhos completos).
- Saida/resultado das verificacoes executadas (selene, typechecks, builds, `bash -n` dos scripts, sourcemap do plugin com `CameraSystemData`).
- Qualquer `warn`/limitacao conhecida que tenha restado.
- O checklist manual do Task 7 Step 4, pronto para o usuario rodar no Studio.
- O diff resumido (`git diff --stat`) **sem commitar**.

Se qualquer decisao do plano se mostrar inviavel na pratica, pare, explique a inviabilidade com evidencia e proponha a alternativa minima antes de continuar.
