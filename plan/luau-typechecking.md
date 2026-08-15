# Plano: Typechecking Luau separado para Roblox e Lune

## Status

Este documento e um plano de execucao. A etapa de planejamento foi concluida,
mas a implementacao ainda nao foi iniciada.

O executor deve ler este arquivo junto com:

- [`AGENTS.md`](../AGENTS.md)
- [`README.md`](../README.md)
- [`rokit.toml`](../rokit.toml)
- [`aftman.toml`](../aftman.toml)
- [`default.project.json`](../default.project.json)
- [`selene.roblox.toml`](../selene.roblox.toml)
- [`selene.lune.toml`](../selene.lune.toml)
- [`selene-lune.yml`](../selene-lune.yml)
- [`plan/luau-linter.md`](./luau-linter.md)
- [`plan/lune-test-runner.md`](./lune-test-runner.md)

Nao executar a implementacao sem revisar as decisoes e os pontos de confirmacao
descritos neste plano.

## Contexto do repositorio

O projeto e um jogo Roblox em Luau montado por Rojo.

- O codigo de producao esta em `src/`.
- `src/` e executado no Roblox Studio por meio do Rojo.
- `tests/` e `lune/` sao executados pelo Lune.
- Os testes usam `tests/support/roblox-loader.luau` para carregar modulos de
  `src/` em uma arvore virtual de objetos Roblox.
- O projeto usa Rokit como gerenciador recomendado.
- Aftman permanece como alternativa de instalacao.
- Selene ja esta configurado separadamente para Roblox e Lune.
- Nao existe ainda uma etapa de typechecking versionada no repositorio.

O mapeamento Rojo em `default.project.json` e:

| Caminho local | Destino Roblox |
| --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |

A pasta `src/server/cave-engine/` contem um hifen. Os imports devem continuar
usando colchetes:

```luau
local CaveEngine = require(script["cave-engine"].CaveEngine)
```

Nao substituir por `script.cave-engine`, `script.cave_engine` ou outro caminho.

## Estado preexistente a preservar

Antes de qualquer mudanca, conferir:

```bash
git status --short
```

No momento da criacao deste plano, o worktree ja possuia alteracoes em:

- `README.md`
- `aftman.toml`
- `rokit.toml`
- `src/client/init.client.luau`
- `src/server/init.server.luau`
- `src/server/world/tunnels.luau`
- `src/shared/remotes.luau`

Tambem havia arquivos nao rastreados em:

- `docs/`
- `lune/`
- `plan/`
- `tests/`
- `selene-lune.yml`
- `selene.lune.toml`
- `selene.roblox.toml`

Essas alteracoes nao foram criadas por esta tarefa e nao podem ser revertidas,
apagadas ou sobrescritas sem relacao direta com a implementacao aprovada.

O arquivo `sourcemap.json` e um artefato gerado e ja esta ignorado por
`.gitignore`. Ele pode ser recriado durante a verificacao, mas nao deve ser
adicionado ao commit.

## Estado de verificacao conhecido

As verificacoes exploratorias feitas durante o planejamento produziram:

- `lune --version`: `lune 0.10.4`.
- `selene --version`: `selene 0.29.0`.
- `rojo --version`: ferramenta gerenciada pelo Rokit, configurada como `7.7.0`.
- `rokit --version`: `1.2.0`.
- `aftman --version`: `0.3.0`.
- `luau-lsp` no cache do Aftman: `1.68.1`, mas ainda nao listado nos manifests
  deste projeto.
- `lune run test`: uma suite, cinco testes aprovados.
- `selene --config selene.roblox.toml src`: zero erros e zero avisos.
- `selene --config selene.lune.toml tests lune`: zero erros e zero avisos.
- `rojo build`: concluido com sucesso.

O `luau-lsp analyze` executado sem configuracao Lune produziu diagnosticos de
ambiente, nao um baseline valido:

- `@lune/fs`, `@lune/luau`, `@lune/process` e `@lune/roblox` nao foram
  resolvidos.
- `warn` foi reportado como global desconhecido.
- `tests/support/roblox-loader.luau:88` apresentou um diagnostico real sobre o
  uso de `maximum: number?` apos o fallback.

Esses diagnosticos devem ser tratados por configuracao e por correcoes locais,
nao por desativacao global do typechecker.

## Objetivo

Adicionar uma etapa de analise semantica de tipos Luau que complemente o Selene
e mantenha os ambientes separados:

- `src/` sera analisado com definicoes Roblox e sourcemap Rojo.
- `tests/` e `lune/` serao analisados com plataforma Luau padrao e definicoes do
  Lune.
- O typechecker nao deve tratar APIs Roblox como disponiveis nos modulos Lune.
- O typechecker deve resolver imports baseados em `script`, inclusive
  `script["cave-engine"]`.
- O Roblox Studio continuara sendo a verificacao de integracao com o DataModel
  real.
- `lune run test` continuara sendo a verificacao de comportamento em runtime.

## Fora de escopo

- Nao adicionar CI nesta etapa.
- Nao converter todos os arquivos para `--!strict` de uma vez.
- Nao usar `--!nocheck`.
- Nao ignorar todos os diagnosticos para obter uma execucao verde.
- Nao misturar definicoes Roblox e Lune em uma unica execucao.
- Nao alterar os imports de `src/` para que o Lune consiga executa-los sem o
  loader virtual.
- Nao substituir o Selene.
- Nao usar Lune para simular um jogo Roblox completo.
- Nao adicionar testes de Terrain ou de inicializacao do Studio ao Lune.

## Ferramenta recomendada

A ferramenta recomendada e o `luau-lsp` no modo standalone:

```bash
luau-lsp analyze
```

Motivos:

- Usa o analisador semantico de Luau.
- Verifica tipos, retornos, argumentos, narrowing e require paths.
- Suporta definicoes globais customizadas.
- Suporta definicoes Roblox.
- Suporta sourcemap no formato Rojo.
- Pode ser usado localmente sem depender do editor.
- Produz codigo de saida diferente de zero para erros de tipo quando usado com
  o formatter padrao ou `gnu`.

O `luau-lsp` tambem executa alguns lints internos de Luau. O Selene continuara
sendo o linter oficial do projeto. As duas ferramentas tem responsabilidades
diferentes e devem continuar com comandos separados.

Nao usar `--formatter plain` como gate. A implementacao atual da CLI retorna
codigo zero nesse modo, mesmo quando ha falhas, para manter compatibilidade com
luacheck.

## Versoes a fixar

A versao recomendada para esta implementacao e `luau-lsp 1.69.0`, publicada em
julho de 2026 e sincronizada com Luau `0.729`.

Adicionar a mesma entrada nos dois manifests:

```toml
luau-lsp = "JohnnyMorganz/luau-lsp@1.69.0"
```

Manter as versoes existentes:

```toml
rojo = "rojo-rbx/rojo@7.7.0"
lune = "lune-org/lune@0.10.4"
selene = "Kampfkarren/selene@0.29.0"
luau-lsp = "JohnnyMorganz/luau-lsp@1.69.0"
```

Arquivos previstos para alteracao:

- `rokit.toml`
- `aftman.toml`

O Rokit continua como caminho recomendado:

```bash
rokit add JohnnyMorganz/luau-lsp@1.69.0
rokit install
```

O Aftman deve ser validado como alternativa:

```bash
aftman add JohnnyMorganz/luau-lsp@1.69.0
aftman install
```

O repositorio do Aftman foi arquivado e nao e mais mantido. Se a resolucao do
artefato `1.69.0` falhar no Aftman, nao deixar uma versao aberta nem usar uma
versao diferente sem registrar a decisao. Nesse caso, confirmar se ambos os
manifests devem usar outra versao explicitamente validada.

## Arquivos de configuracao previstos

Criar:

```text
typecheck/
  roblox.luaurc
  lune.luaurc
  luau-lsp.roblox.json
  globalTypes.None.d.luau
```

O `README.md` tambem devera receber uma secao de typechecking. O arquivo
`default.project.json` nao precisa ser alterado para esta etapa.

### `typecheck/roblox.luaurc`

```json
{
  "languageMode": "nonstrict",
  "typeErrors": true,
  "lintErrors": false
}
```

Essa e a configuracao base do typechecking Roblox. Ela nao deve declarar
aliases ou globals do Lune.

### `typecheck/lune.luaurc`

```json
{
  "languageMode": "nonstrict",
  "typeErrors": true,
  "lintErrors": false,
  "globals": [
    "warn"
  ],
  "aliases": {
    "lune": "~/.lune/.typedefs/0.10.4/"
  }
}
```

O alias `lune` deve resolver imports como:

```luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
```

O comando oficial do Lune para gerar essas definicoes e:

```bash
lune setup
```

Ele cria os arquivos em `~/.lune/.typedefs/0.10.4/` e tambem cria ou altera
`.luaurc` no diretorio atual. Para evitar uma configuracao raiz acidentalmente
compartilhada entre Roblox e Lune, executar `lune setup` em um diretorio
descartavel ou revisar e incorporar manualmente apenas o alias necessario em
`typecheck/lune.luaurc`.

Nao e necessario adicionar as definicoes Lune ao Rojo.

### `typecheck/luau-lsp.roblox.json`

```json
{
  "luau-lsp.diagnostics.strictDatamodelTypes": true
}
```

O Language Server trata tipos do DataModel como `any` nos diagnosticos por
padrao para reduzir falsos positivos. Esta opcao deve ser habilitada para que
os imports por `script` e os membros do DataModel tenham valor semantico. Se
ela produzir falsos positivos, investigar cada caso e nao desativar o
typechecker inteiro.

## Definicoes Roblox

O modo standalone nao baixa automaticamente as definicoes Roblox. Versionar a
definicao correspondente a versao fixada do `luau-lsp`:

```text
typecheck/globalTypes.None.d.luau
```

Baixar da tag imutavel correspondente:

```bash
curl --fail --location \
  https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.69.0/scripts/globalTypes.None.d.luau \
  --output typecheck/globalTypes.None.d.luau
```

Registrar a origem e verificar o conteudo:

```bash
sha256sum typecheck/globalTypes.None.d.luau
```

A definicao `None` deve ser a escolha inicial porque cobre as APIs de runtime
necessarias sem incluir APIs de seguranca de plugin desnecessarias. Se o codigo
passar a usar APIs com outro nivel de seguranca, essa decisao precisa ser
revisada explicitamente.

Nao usar uma URL dinamica de `latest` no comando de verificacao. Se o
`luau-lsp` for atualizado, atualizar a definicao e os manifests no mesmo ciclo.

## Sourcemap Rojo

Gerar o sourcemap antes da analise Roblox:

```bash
rojo sourcemap \
  --include-non-scripts \
  default.project.json \
  --output sourcemap.json
```

`--include-non-scripts` e obrigatorio para incluir pastas como
`cave-engine` e `world`, que fazem parte da resolucao de `script.Parent`.

O arquivo deve continuar ignorado pelo Git. Nao adicionar `sourcemap.json` ao
commit.

O sourcemap nao muda os imports do codigo. Em particular, este import deve
continuar valido:

```luau
local TerrainWriter = require(script["cave-engine"].TerrainWriter)
```

## Comando de typechecking Roblox

Executar a partir da raiz:

```bash
luau-lsp analyze \
  --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json \
  --formatter gnu \
  src
```

Esse comando deve analisar todos os arquivos Luau em `src/` com:

- APIs Roblox.
- Tipos `Vector3`, `Vector3int16`, `Region3`, `Enum`, `Random` e `Instance`.
- `game`, `workspace` e `script`.
- A arvore de instancias do `default.project.json`.
- Os modulos locais resolvidos pelo sourcemap.

Nao fornecer definicoes `@lune/*` nesta execucao.

## Comando de typechecking Lune

Executar separadamente:

```bash
luau-lsp analyze \
  --platform standard \
  --base-luaurc typecheck/lune.luaurc \
  --formatter gnu \
  tests lune
```

Esse comando deve:

- Resolver os modulos `@lune/*` usando as definicoes geradas pelo Lune `0.10.4`.
- Reconhecer `warn`.
- Nao carregar definicoes globais Roblox.
- Nao usar `sourcemap.json`.
- Nao analisar `src/` como se fosse codigo Lune.

O loader virtual em `tests/support/roblox-loader.luau` executa `src/` em runtime
Lune, mas o typechecker nao deve tentar inferir esse grafo dinamico. A funcao
`Loader.load` atualmente retorna `any`, portanto os testes verificam o harness e
o uso das APIs Lune, enquanto `src/` e analisado pela configuracao Roblox.

`@lune/roblox` tambem nao representa o runtime completo do Studio. Ele fornece
datatypes e APIs limitadas. Terrain, servicos reais e inicializacao do Studio
continuam sendo responsabilidade da integracao Roblox.

## Estrategia para `--!strict`

Comecar em `nonstrict`. Isso permite verificar anotacoes existentes, incluindo:

- `export type`.
- tipos opcionais.
- unions literais.
- tipos de retorno.
- assinaturas de metodos.
- incompatibilidades explicitas.

Adotar `--!strict` por modulos, nesta ordem inicial sugerida:

1. `src/server/world/types.luau`
2. `src/server/world/grid.luau`
3. `src/server/world/stats.luau`
4. `src/server/world/config.luau`
5. `src/server/world/terrainWriter.luau`
6. `src/server/world/rockVolume.luau`
7. `src/server/world/rooms.luau`
8. `src/server/world/tunnels.luau`
9. `src/server/world/WorldGenerator.luau`
10. `src/server/cave-engine/CaveEngine.luau`
11. `src/server/cave-engine/TerrainWriter.luau`
12. entradas Roblox e scripts Lune

Cada arquivo strict deve iniciar com:

```luau
--!strict
```

Nao adicionar `--!strict` a todos os arquivos de uma vez. Modulos com dados
dinamicos, `pcall`, `setmetatable`, `any` ou contratos externos devem ser
avaliados individualmente.

Nao usar `--!nocheck` para encobrir problemas. Um `any` local pode ser usado
somente em uma fronteira dinamica justificada, com narrowing ou contrato
explicito quando possivel.

## Baseline e tratamento de diagnosticos

O baseline de typechecking aceito deve ter:

- zero `TypeError` em `src/`.
- zero `SyntaxError` em `src/`.
- zero imports Roblox nao resolvidos.
- zero `TypeError` em `tests/` e `lune/`.
- zero imports `@lune/*` nao resolvidos.
- nenhum global Roblox aceito na analise Lune.

O baseline do Selene ja esta verde e deve permanecer separado.

Tratar diagnosticos na seguinte ordem:

1. Corrigir configuracao, definicoes ou sourcemap quando for falso positivo.
2. Corrigir codigo quando representar erro real.
3. Adicionar narrowing para valores opcionais.
4. Corrigir contratos de `FindFirstChild`, `setmetatable`, tabelas e retornos.
5. Documentar qualquer fronteira dinamica que realmente precise de `any`.

Nao usar `--ignore` amplo, `--!nocheck`, `typeErrors: false` ou uma lista de
excecoes global para obter sucesso.

O diagnostico confirmado durante a investigacao foi em
`tests/support/roblox-loader.luau:88`, onde o parametro opcional `maximum` e
usado apos uma atribuicao que o analisador ainda considera opcional. A correcao
esperada e localizada, por exemplo:

```luau
local upper = maximum or minimum
return minimum + (upper - minimum) * value
```

Confirmar a mensagem na versao `1.69.0` antes de editar.

Outros possiveis diagnosticos em `FindFirstChild`, `worldToCell`,
`setmetatable`, `RemoteEvent` e `Terrain:WriteVoxels` devem ser confirmados
pela ferramenta. Nao aplicar alteracoes especulativas antes da primeira
execucao configurada.

## Verificacoes negativas

Os testes negativos podem usar arquivos temporarios fora das pastas analisadas.
Nao deixar codigo deliberadamente invalido em `src/`, `tests/` ou `lune/`.

Fixture de erro de tipo:

```luau
local value: number = "not a number"
print(value)
```

Executar com a configuracao Lune:

```bash
luau-lsp analyze \
  --platform standard \
  --base-luaurc typecheck/lune.luaurc \
  /tmp/luau-type-error.luau
```

Esperar codigo diferente de zero e uma mensagem contendo `TypeError`.

Fixture de separacao de ambientes:

```luau
print(workspace)
```

Analisar com `typecheck/lune.luaurc` e esperar global desconhecido e codigo
diferente de zero. Isso confirma que APIs Roblox nao foram misturadas ao
ambiente Lune.

Fixture Roblox positiva:

```luau
local position: Vector3 = Vector3.new(0, 0, 0)
print(position)
```

Analisar com a definicao Roblox e esperar sucesso.

Tambem confirmar que uma alteracao temporaria de tipo em um modulo de `src/`
faz o comando Roblox falhar. Remover a fixture ou restaurar o arquivo antes da
revisao final.

## Selene, testes e build

Manter os comandos atuais do linter:

```bash
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Manter o runner de testes:

```bash
lune run test
```

Manter a verificacao Rojo:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx
```

Interpretacao:

- Selene valida lint e regras de codigo.
- `luau-lsp analyze` valida tipos e resolucao semantica.
- `lune run test` valida comportamento em runtime Lune.
- `rojo build` valida a arvore de projeto Roblox.
- Roblox Studio valida integracao com DataModel e Terrain.

## Roblox Studio

Depois do typechecking e do build:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx
rojo serve
```

Abrir o place no Roblox Studio e revisar Script Analysis.

O Studio e a autoridade para:

- tipos da versao real do Roblox.
- DataModel efetivamente carregado.
- `workspace.Terrain`.
- `Terrain:WriteVoxels`.
- scripts de inicializacao.

O Studio pode usar uma versao de Luau diferente da CLI. Essa diferenca e
aceitavel: a CLI fornece verificacao reproduzivel e o Studio fornece validacao
do runtime real.

Nao alterar `default.project.json` para habilitar o typechecker. A propriedade
global `Workspace.LuauTypeCheckMode` somente deve ser considerada depois da
adocao gradual de `--!strict`.

## VS Code

Instalar a extensao:

- [JohnnyMorganz.luau-lsp no Marketplace](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp)

Workspace Roblox sugerido:

```json
{
  "luau-lsp.platform.type": "roblox",
  "luau-lsp.sourcemap.enabled": true,
  "luau-lsp.sourcemap.autogenerate": true,
  "luau-lsp.sourcemap.rojoProjectFile": "default.project.json",
  "luau-lsp.sourcemap.includeNonScripts": true,
  "luau-lsp.sourcemap.sourcemapFile": "sourcemap.json",
  "luau-lsp.diagnostics.strictDatamodelTypes": true,
  "luau-lsp.server.baseLuaurc": "${workspaceFolder}/typecheck/roblox.luaurc"
}
```

Workspace Lune sugerido:

```json
{
  "luau-lsp.platform.type": "standard",
  "luau-lsp.sourcemap.enabled": false,
  "luau-lsp.diagnostics.workspace": true,
  "luau-lsp.server.baseLuaurc": "${workspaceFolder}/typecheck/lune.luaurc"
}
```

Usar workspaces separados para Roblox e Lune. Nao abrir os dois ambientes com
configuracoes conflitantes no mesmo workspace do Language Server.

A extensao pode embutir uma versao diferente do servidor. Se for necessario
usar exatamente o binario gerenciado pelo projeto, configurar
`luau-lsp.server.path` em settings locais do desenvolvedor, nunca com caminho
absoluto versionado no repositorio:

```json
{
  "luau-lsp.server.path": "/caminho/local/.rokit/bin/luau-lsp"
}
```

O comando standalone versionado continua sendo a fonte de verdade para a
verificacao reproduzivel.

## Sequencia de implementacao

1. Conferir `git status --short` e preservar todas as alteracoes preexistentes.
2. Adicionar `luau-lsp@1.69.0` a `rokit.toml` e `aftman.toml`.
3. Executar `rokit install` e confirmar `luau-lsp --version`.
4. Executar `aftman install` em uma verificacao separada e confirmar a mesma
   versao, se o artefato for suportado.
5. Obter `globalTypes.None.d.luau` da tag `1.69.0`.
6. Criar `typecheck/roblox.luaurc`.
7. Criar `typecheck/lune.luaurc`.
8. Criar `typecheck/luau-lsp.roblox.json`.
9. Gerar as definicoes Lune usando Lune `0.10.4`.
10. Gerar `sourcemap.json` com `--include-non-scripts`.
11. Executar o typechecking Roblox em `nonstrict`.
12. Executar o typechecking Lune em `nonstrict`.
13. Corrigir primeiro diagnosticos de configuracao.
14. Corrigir diagnosticos reais de codigo, incluindo o narrowing confirmado do
    loader, sem alterar imports por conveniencia.
15. Reexecutar as duas analises ate o baseline nao possuir erros semanticos.
16. Adotar `--!strict` por grupos pequenos e repetir o baseline a cada grupo.
17. Atualizar o `README.md` com instalacao e comandos.
18. Adicionar a configuracao VS Code somente depois de validar os comandos CLI.
19. Executar verificacoes positivas e negativas.
20. Executar Selene, testes, build e `git diff --check`.
21. Revisar o diff e confirmar que `docs/`, `tests/`, `lune/` e mudancas
    preexistentes nao foram removidos.
22. Nao adicionar CI nesta etapa.

## Checklist completo

- [ ] `rokit.toml` fixa `luau-lsp@1.69.0`.
- [ ] `aftman.toml` fixa `luau-lsp@1.69.0`.
- [ ] Rokit instala o binario esperado.
- [ ] Aftman instala ou executa a mesma versao.
- [ ] `luau-lsp --version` corresponde ao manifesto.
- [ ] `globalTypes.None.d.luau` corresponde a tag `1.69.0`.
- [ ] Definicoes Lune correspondem ao Lune `0.10.4`.
- [ ] `typecheck/roblox.luaurc` nao declara APIs Lune.
- [ ] `typecheck/lune.luaurc` nao declara APIs Roblox.
- [ ] `@lune/fs` e resolvido.
- [ ] `@lune/luau` e resolvido.
- [ ] `@lune/process` e resolvido.
- [ ] `@lune/roblox` e resolvido.
- [ ] `warn` e reconhecido no ambiente Lune.
- [ ] `workspace` nao e reconhecido como global em `tests/` e `lune/`.
- [ ] `sourcemap.json` e gerado com `--include-non-scripts`.
- [ ] `script.Parent.types` e resolvido.
- [ ] `script["cave-engine"].CaveEngine` e resolvido.
- [ ] Nenhum import Roblox foi alterado para contornar o hifen.
- [ ] Typechecking de `src/` termina sem `TypeError` ou `SyntaxError`.
- [ ] Typechecking de `tests/` e `lune/` termina sem `TypeError` ou `SyntaxError`.
- [ ] Selene Roblox termina sem erros e avisos.
- [ ] Selene Lune termina sem erros e avisos.
- [ ] `lune run test` termina com codigo zero.
- [ ] `rojo build` termina com codigo zero.
- [ ] Fixture com erro de tipo termina com codigo diferente de zero.
- [ ] Fixture com global Roblox no ambiente Lune termina com codigo diferente de zero.
- [ ] Nenhum diagnostico foi ignorado globalmente.
- [ ] Nenhum arquivo foi convertido globalmente para strict sem avaliacao.
- [ ] Nenhuma configuracao de CI foi adicionada.
- [ ] Alteracoes preexistentes foram preservadas.
- [ ] `git diff --check` termina sem erros.

## Criterios objetivos de aceitacao

Considerar a implementacao concluida somente quando:

1. Os dois manifests fixarem a mesma versao de `luau-lsp`.
2. O binario instalado corresponder a versao documentada.
3. O comando Roblox resolver APIs Roblox e imports via sourcemap.
4. O import `script["cave-engine"]` for resolvido sem alterar a grafia.
5. O comando Lune resolver todos os `@lune/*` usados atualmente.
6. O comando Lune rejeitar um uso deliberado de `workspace` ou outro global
   Roblox.
7. Os comandos nao compartilharem definicoes globais de Roblox e Lune.
8. O baseline nao possuir `TypeError`, `SyntaxError` ou require desconhecido.
9. Um erro de tipo deliberado provocar codigo de saida diferente de zero.
10. Selene, `lune run test` e `rojo build` continuarem passando.
11. O Studio continuar carregando o place e exibindo analise compativel apos
    `rojo serve`.
12. A adocao de `--!strict` permanecer gradual.
13. Nenhuma alteracao preexistente for perdida.
14. Nenhuma etapa de CI for adicionada nesta tarefa.

## Decisoes que precisam de confirmacao

- Confirmar se `luau-lsp 1.69.0` deve ser fixado mesmo que o Aftman exija uma
  versao anterior para algum sistema operacional.
- Confirmar se `globalTypes.None.d.luau` sera versionado no repositorio ou
  regenerado durante a instalacao.
- Confirmar se a dependencia das definicoes Lune em `~/.lune/.typedefs/0.10.4/`
  e aceitavel ou se todos os arquivos de definicao devem ser versionados em
  `typecheck/`.
- Confirmar se o VS Code sera configurado por dois workspaces versionados ou por
  settings locais dos desenvolvedores.
- Confirmar quais modulos serao os primeiros candidatos a `--!strict` depois
  do baseline `nonstrict`.
- Confirmar se a validacao Aftman continua obrigatoria enquanto ele estiver
  arquivado.

## Referencias

- [Luau Language Server](https://github.com/JohnnyMorganz/luau-lsp)
- [Luau LSP standalone](https://github.com/JohnnyMorganz/luau-lsp#standalone)
- [Luau LSP language server clients](https://github.com/JohnnyMorganz/luau-lsp/blob/main/editors/README.md)
- [Luau LSP release 1.69.0](https://github.com/JohnnyMorganz/luau-lsp/releases/tag/1.69.0)
- [Roblox type checking](https://create.roblox.com/docs/luau/type-checking)
- [Luau types](https://luau.org/types)
- [Luau `.luaurc` RFC](https://rfcs.luau.org/config-luaurc.html)
- [Lune installation](https://lune-org.github.io/docs/getting-started/1-installation/)
- [Lune editor setup](https://lune-org.github.io/docs/getting-started/3-editor-setup/)
- [Lune modules and aliases](https://lune-org.github.io/docs/the-book/7-modules/)
- [Lune Roblox API status](https://lune-org.github.io/docs/roblox/4-api-status/)
- [Lune setup implementation](https://github.com/lune-org/lune/blob/main/crates/lune/src/cli/setup.rs)
- [Rokit](https://github.com/rojo-rbx/rokit)
- [Aftman](https://github.com/LPGhatguy/aftman)
