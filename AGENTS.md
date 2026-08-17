# Instruções do Repositório

## Execução e Imports

- O projeto é Luau para Roblox montado pelo Rojo: `src/shared` -> `ReplicatedStorage.Shared`, `src/server` -> `ServerScriptService.Server` e `src/client` -> `StarterPlayer.StarterPlayerScripts.Client`. Confirme `default.project.json` antes de alterar um `require`.
- `src/` roda no Roblox Studio; `tests/` e `lune/` rodam no Lune. Os testes carregam módulos de `src/` pela árvore virtual de `tests/support/roblox-loader.luau`; mantenha os imports baseados em `script` próprios do Roblox.
- `src/server/cave-engine/` contém hífen. Use `script["cave-engine"].CaveEngine` ou `script["cave-engine"].TerrainWriter`, nunca notação de ponto nem renomeie a pasta.
- O cliente inicia em `src/client/init.client.luau` e usa React/ReactRoblox. O servidor e os módulos de domínio continuam dependentes das APIs Roblox e não devem ser testados como se fossem um jogo completo no Lune.

## Dependências e Ferramentas

- Versões fixadas em `rokit.toml` e `aftman.toml`: Rojo `7.7.0`, Lune `0.10.4`, Selene `0.29.0`, `luau-lsp 1.69.0` e Wally `0.3.2`. Prefira `rokit install`; `aftman install` é alternativa.
- Execute `wally install` após clonar ou alterar `wally.toml`. `Packages/` é gerado, ignorado pelo Git e mapeado para `ReplicatedStorage.Packages`; não edite esse diretório manualmente.

## Verificação

- Testes comportamentais: `lune run test`. O runner descobre recursivamente `tests/**/*.spec.luau`; não há comando de foco por teste integrado.
- Lint Roblox: `selene --config selene.roblox.toml src`. Lint Lune: `selene --config selene.lune.toml tests lune`. As bibliotecas padrão são separadas de propósito.
- Typecheck Roblox, nesta ordem:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

- Typecheck Lune separadamente, sem definições Roblox ou sourcemap:

```bash
luau-lsp analyze --platform standard \
  --base-luaurc typecheck/lune.luaurc --formatter gnu tests lune
```

- `typecheck/lune.luaurc` aponta `@lune/*` para `~/.lune/.typedefs/0.10.4/`; se precisar executar `lune setup`, faça-o em diretório descartável para não criar `.luaurc` na raiz. `sourcemap.json` é gerado e ignorado.
- A definição Roblox versionada corresponde ao `luau-lsp 1.69.0`; não troque por `latest` sem atualizar a ferramenta, a definição e o hash documentado no README.
- Verifique a árvore com `rojo build -o /tmp/dungeon-game-canve.rbxlx`. Use Roblox Studio/`rojo serve` para DataModel real, Terrain, `Terrain:WriteVoxels` e inicialização de scripts.

## Limites de Tipos

- Mantenha `--!strict` nos módulos Luau e não use `--!nocheck`, ignores amplos ou `typeErrors: false` para esconder diagnósticos.
- Não misture plataformas nas análises: globais Roblox como `workspace`, `game` e `Vector3` não pertencem a `tests/` ou `lune/`.
- `@lune/roblox` fornece datatypes em runtime que podem faltar nos typedefs gerados; preserve os contratos locais existentes no loader/testes em vez de adicionar definições Roblox ao typecheck Lune.
