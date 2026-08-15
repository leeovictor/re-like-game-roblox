# Instruções do Repositório

## Estrutura e Imports

- O projeto é Luau para Roblox, montado pelo Rojo. `src/shared` vai para `ReplicatedStorage.Shared`, `src/server` para `ServerScriptService.Server` e `src/client` para `StarterPlayer.StarterPlayerScripts.Client`; confirme a árvore em `default.project.json` antes de alterar um `require`.
- `src/` roda no Roblox Studio. `tests/` e `lune/` rodam no Lune com o loader virtual `tests/support/roblox-loader.luau`; não altere imports baseados em `script` para fazê-los funcionar diretamente no Lune.
- `src/server/cave-engine/` contém hífen. Use `script["cave-engine"].CaveEngine` ou `script["cave-engine"].TerrainWriter`; nunca use notação de ponto nem renomeie a pasta para contornar isso.

## Toolchain

- Versões fixadas em `rokit.toml` e `aftman.toml`: Rojo `7.7.0`, Lune `0.10.4`, Selene `0.29.0` e `luau-lsp 1.69.0`.
- Fluxo recomendado: `rokit install`. Alternativa: `aftman install`. Confirme ferramentas com `luau-lsp --version`, `lune --version`, `selene --version` e `rojo --version`.

## Verificação

- Gere `sourcemap.json` antes do typecheck Roblox; ele é artefato ignorado e não deve ser commitado:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

- O typecheck Lune é separado, sem definições Roblox e sem sourcemap. `typecheck/lune.luaurc` resolve `@lune/*` por `~/.lune/.typedefs/0.10.4/`; se necessário, execute `lune setup` em um diretório descartável, nunca para criar um `.luaurc` compartilhado na raiz:

```bash
luau-lsp analyze --platform standard \
  --base-luaurc typecheck/lune.luaurc --formatter gnu tests lune
```

- A definição Roblox versionada em `typecheck/globalTypes.None.d.luau` corresponde à tag `luau-lsp 1.69.0`; não substitua por `latest` sem atualizar a versão e verificar o hash documentado no README.
- Selene é separado do typecheck: `selene --config selene.roblox.toml src` e `selene --config selene.lune.toml tests lune`.
- O fluxo comportamental é `lune run test`; os testes usam arquivos `tests/**/*.spec.luau` e atualmente cobrem lógica/test harness, não um jogo Roblox completo.
- Verifique a árvore Rojo com `rojo build -o /tmp/dungeon-game-canve.rbxlx`. Use Roblox Studio/`rojo serve` para DataModel real, Terrain, `Terrain:WriteVoxels` e inicialização de scripts.

## Tipos e Limites

- Os arquivos Luau não vazios existentes usam `--!strict`; mantenha a adoção explícita e gradual para novos módulos. Não use `--!nocheck`, ignores amplos ou `typeErrors: false` para esconder diagnósticos.
- Não misture plataformas nas análises: globais Roblox como `workspace`, `game` e `Vector3` pertencem à execução Roblox; `tests/` e `lune/` devem continuar sem essas definições globais.
- `@lune/roblox` fornece datatypes em runtime que não aparecem completamente nos typedefs gerados; o loader e o teste de `Grid3D` mantêm contratos locais para essa fronteira dinâmica. Não resolva isso adicionando definições Roblox ao typecheck Lune.
- Preserve a distinção entre Selene, `luau-lsp`, testes Lune, build Rojo e validação no Studio. Não adicione CI nesta etapa sem solicitação explícita.
