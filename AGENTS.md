# Instrucoes do Repositorio

## Execucao e Imports

- O projeto e Luau para Roblox montado pelo Rojo: `src/shared` -> `ReplicatedStorage.Shared`, `src/server` -> `ServerScriptService.Server` e `src/client` -> `StarterPlayer.StarterPlayerScripts.Client`. Confirme `default.project.json` antes de alterar um `require`.
- Nos modulos de `src/client`, requires de outros modulos client-side devem usar `StarterPlayer.StarterPlayerScripts.Client`; declare `local StarterPlayer = game:GetService("StarterPlayer")` e use caminhos absolutos. Mantenha imports de `ReplicatedStorage` para modulos shared e pacotes.
- Tipos compartilhados entre controllers/services devem ser exportados pelo modulo dono e importados pelos consumidores; nao redeclare localmente contratos ja existentes.
- Os padroes de arquitetura para novos controllers, managers e services estao em `docs/luau-architecture-patterns.md`; consulte-o antes de criar ou alterar esses modulos.
- `src/server/cave-engine/` contem hifen. Use `script["cave-engine"].CaveEngine` ou `script["cave-engine"].TerrainWriter`, nunca notacao de ponto nem renomeie a pasta.
- O cliente inicia em `src/client/init.client.luau` e usa React/ReactRoblox.
- Hooks que recebem callbacks e nao devem reexecutar efeitos guardam o callback em `useRef`, como em `useInventoryHotkey`; `DocumentReaderOverlay` e `CinematicLetterbox` ja seguem esse padrao.

## UI, Tema e Componentes

- Cores de UI vem exclusivamente de `src/client/ui/theme.luau`; `Color3.fromRGB` e `Color3.new` aparecem apenas no proprio `theme.luau`.
- `src/client/ui/App.luau` e a raiz de composicao e orquestracao; arvores de UI devem virar componentes em `src/client/ui/*.luau`.
- Componentes de UI recebem props e retornam `nil` quando ocultos, como `DropdownMenu`, `ConfirmationModal`, `PickupToast`, `DialogueOverlay` e `ObjectivesPanel`.
- Componentes que precisam preservar estado local ao ocultar (por exemplo, aba e selecao do `InventoryPanel`) ficam montados com prop `visible`, em vez de criacao condicional.
- Estado local de UI (aba, selecao, animacao) pertence ao componente dono; `App` guarda apenas estado de orquestracao, como visibilidade global, modal de confirmacao e cinematic.
- Overlays fullscreen (`ConfirmationModal`, `DocumentReaderOverlay`) permanecem filhos diretos da ScreenGui raiz; nao aninhe em frames com tamanho limitado.
- Efeitos visuais globais, como `BlurEffect`, pertencem ao ciclo de vida do componente que os exibe, nao ao `App`.
- Logica pura de apresentacao e derivacao (por exemplo, `inventoryPresentation`, `inventoryActions`, `combatHudState`) fica em modulos sem React.
- Use PascalCase para arquivos de componentes (`InventoryPanel.luau`) e camelCase para hooks e modulos puros (`useInventoryHotkey.luau`, `theme.luau`).

## Dependencias e Ferramentas

- Versoes fixadas em `rokit.toml` e `aftman.toml`: Rojo `7.7.0`, Selene `0.29.0`, `luau-lsp 1.69.0`, Wally `0.3.2` e StyLua `2.5.2`. Prefira `rokit install`; `aftman install` e alternativa.
- Execute `wally install` apos clonar ou alterar `wally.toml`. `Packages/` e gerado, ignorado pelo Git e mapeado para `ReplicatedStorage.Packages`. Nao edite esse diretorio manualmente.
- Ao alterar qualquer codigo em `plugin/`, use o script de build versionado, que arquiva a versao anterior em `PluginBackups/` e instala o pacote atualizado na pasta de plugins do Roblox Studio:

```bash
scripts/plugin-build.sh
```

- Para listar ou restaurar builds arquivadas, use `scripts/plugin-rollback.sh list`, `scripts/plugin-rollback.sh previous` ou `scripts/plugin-rollback.sh <arquivo>.rbxmx`.

## Git e Commits

- Nao faca commits ao escrever uma spec ou um plano de implementacao.
- Nao faca commits ao implementar qualquer plano.
- So faca commit quando o usuario solicitar explicitamente.

## Verificacao

- Lint Roblox:

```bash
selene --config selene.roblox.toml src
```

- Gere o sourcemap do jogo e rode o typecheck Roblox:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu \
  src
```

- A ordem do typecheck e `rojo sourcemap` antes de `luau-lsp analyze`; use somente a plataforma Roblox para `src`.
- Verifique o projeto com build Rojo:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
```

- A definicao Roblox versionada corresponde ao `luau-lsp 1.69.0`; nao troque por `latest` sem atualizar a ferramenta, a definicao e o hash documentado no README.
- Use Roblox Studio/MCP para o DataModel real, Terrain, `Terrain:WriteVoxels` e inicializacao de scripts. `default.project.json` e o projeto do jogo.
- Apos alterar UI, `rg -n "Color3\.(fromRGB|new)" src/client/ui` deve retornar ocorrencias apenas em `src/client/ui/theme.luau`.
- Apos extrair ou mover componentes de UI, valide no Play: inventario, dropdown, modal de dialogo, leitor de documentos, objetivos, HUD de combate e toasts.

## Limites de Tipos

- Mantenha `--!strict` nos modulos Luau e nao use `--!nocheck`, ignores amplos ou `typeErrors: false` para esconder diagnosticos.
- O typecheck usa a plataforma Roblox: `src` usa globais `script`, `Instance`, `Vector3` e `CFrame` fornecidos pelo DataModel e pelas definicoes Roblox versionadas.
- Preserve os contratos dos modulos de producao e siga o padrao de imports client-side definido acima; qualquer incompatibilidade deve ser corrigida nos mapeamentos do Rojo ou nas definicoes, nao com `--!nocheck` ou tipos globais amplos.
