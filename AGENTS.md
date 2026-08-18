# Instrucoes do Repositorio

## Execucao e Imports

- O projeto e Luau para Roblox montado pelo Rojo: `src/shared` -> `ReplicatedStorage.Shared`, `src/server` -> `ServerScriptService.Server` e `src/client` -> `StarterPlayer.StarterPlayerScripts.Client`. Confirme `default.project.json` antes de alterar um `require`.
- `src/` roda no Roblox Studio. `tests/` e uma arvore TestEZ dentro de `test.project.json`, com roots separados em `ReplicatedStorage.TestEZTests.Shared`, `ServerScriptService.TestEZTests.Server` e `StarterPlayer.StarterPlayerScripts.TestEZTests.Client`. `CameraVisibility` pertence ao root client.
- `test.project.json` mapeia apenas os subdiretorios de producao necessarios e omite `src/server/init.server.luau` e `src/client/init.client.luau`; os entrypoints normais continuam exclusivos de `default.project.json`.
- Specs sao ModuleScripts `--!strict` que retornam uma funcao TestEZ e registram `describe`, `it`, `expect`, `beforeEach` e `afterEach`. Imports usam o DataModel real, sem indirection virtual ou filesystem. O escopo nao inclui specs de UI.
- Specs que criam Instances, conexoes ou estado mutavel devem criar fixtures isoladas em `beforeEach` e destruir ou desconectar tudo em `afterEach`.
- `src/server/cave-engine/` contem hifen. Use `script["cave-engine"].CaveEngine` ou `script["cave-engine"].TerrainWriter`, nunca notacao de ponto nem renomeie a pasta.
- O cliente inicia em `src/client/init.client.luau` e usa React/ReactRoblox. Os runners de teste nao iniciam esses entrypoints: chame-os explicitamente pelo MCP no DataModel `Server` e no DataModel `Client`.

## Dependencias e Ferramentas

- Versoes fixadas em `rokit.toml` e `aftman.toml`: Rojo `7.7.0`, Selene `0.29.0`, `luau-lsp 1.69.0` e Wally `0.3.2`. Prefira `rokit install`; `aftman install` e alternativa.
- Execute `wally install` apos clonar ou alterar `wally.toml`. `Packages/` e `DevPackages/` sao gerados, ignorados pelo Git e mapeados para `ReplicatedStorage.Packages` e `ReplicatedStorage.DevPackages`; TestEZ e carregado como `ReplicatedStorage.DevPackages.TestEZ`. Nao edite esses diretorios manualmente.
- Sirva o place de teste com `rojo serve test.project.json` e conecte a sessao Studio `RE Like Test`; `rojo sync test.project.json` pode ser usado para uma sincronizacao pontual.

## Verificacao

- Execute Play limpo pelo MCP. No DataModel `Server`, rode `require(game.ServerScriptService.TestEZRunner).run()`. No DataModel `Client`, rode `require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()`. O criterio de sucesso e `failed == 0`; use Output apenas para detalhes. Pare Play e limpe fixtures entre rodadas, repetindo o fluxo completo duas vezes.
- Lint Roblox:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

- Gere o sourcemap do place de teste e rode o typecheck Roblox:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu src tests
```

- A ordem do typecheck e `rojo sourcemap` antes de `luau-lsp analyze`; use somente a plataforma Roblox para `src` e `tests`.
- Verifique os dois projetos com builds Rojo:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

- A definicao Roblox versionada corresponde ao `luau-lsp 1.69.0`; nao troque por `latest` sem atualizar a ferramenta, a definicao e o hash documentado no README.
- Use Roblox Studio/MCP para o DataModel real, Terrain, `Terrain:WriteVoxels` e inicializacao de scripts. `default.project.json` continua sendo o projeto do jogo.

## Limites de Tipos

- Mantenha `--!strict` nos modulos Luau e nao use `--!nocheck`, ignores amplos ou `typeErrors: false` para esconder diagnosticos.
- Nao misture plataformas nas analises: `src` e `tests` usam globais Roblox, `script`, `Instance`, `Vector3` e `CFrame` fornecidos pelo DataModel e pelas definicoes Roblox versionadas.
- Preserve imports baseados em `script` e os contratos dos modulos de producao; qualquer incompatibilidade deve ser corrigida no mapeamento do projeto de teste ou nas declaracoes TestEZ, nao com `--!nocheck` ou tipos globais amplos.
