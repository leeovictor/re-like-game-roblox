# Plano: Linter para codigo Luau em Roblox e Lune

## Objetivo

Adicionar um linter versionado ao toolchain do projeto para verificar o codigo
Luau escrito em `src/`, `tests/` e `lune/`, respeitando a diferenca entre os
ambientes de execucao Roblox e Lune.

A ferramenta escolhida e o [Selene](https://kampfkarren.github.io/selene/),
configurado para entender a sintaxe Luau. O linter deve ser executavel a partir
da raiz do projeto, produzir um baseline inicial sem avisos e ser documentado
junto dos comandos existentes de instalacao e testes.

## Estado atual

- O projeto e um jogo Roblox em Luau montado por
  [`default.project.json`](../default.project.json).
- O codigo de producao esta em `src/` e e carregado pelo Roblox Studio via
  Rojo.
- Os testes unitarios em `tests/` e o runner em `lune/` sao executados pelo
  Lune, nao pelo runtime Roblox.
- O projeto usa Rokit como gerenciador recomendado e mantem
  [`aftman.toml`](../aftman.toml) para fluxos alternativos.
- Rojo 7.7.0 e Lune 0.10.4 ja estao fixados em
  [`rokit.toml`](../rokit.toml) e [`aftman.toml`](../aftman.toml).
- Selene 0.29.0 esta disponivel localmente e foi usado para validar a
  compatibilidade da configuracao proposta.
- Ainda nao existe `selene.toml`, configuracao equivalente ou comando de lint
  documentado no repositorio.
- O worktree possui alteracoes preexistentes em
  [`README.md`](../README.md), [`aftman.toml`](../aftman.toml),
  [`rokit.toml`](../rokit.toml), [`src/server/init.server.luau`](../src/server/init.server.luau)
  e arquivos nao rastreados em `docs/`, `lune/`, `plan/` e `tests/`. A
  implementacao nao deve reverter nem apagar essas alteracoes.

## Diagnostico da configuracao

Selene precisa receber uma biblioteca padrao que inclua a sintaxe Luau. Sem
isso, tipos como `Vector3`, `number?` e declaracoes `export type` podem ser
interpretados como sintaxe Lua invalida.

O codigo Roblox e o codigo Lune tambem precisam de bibliotecas padrao
distintas:

| Area | Runtime | Globais/APIs relevantes |
| --- | --- | --- |
| `src/` | Roblox Studio | `game`, `script`, `workspace`, `Instance`, `Vector3`, `Vector3int16`, `Region3`, `Enum`, `Random`, `task`, `warn` |
| `tests/` | Lune | `warn` e modulos locais carregados por `@lune/*` |
| `lune/` | Lune | `warn` e modulos locais carregados por `@lune/*` |

Os modulos `@lune/fs`, `@lune/luau`, `@lune/process` e `@lune/roblox` sao
atribuidos a variaveis locais via `require`, portanto nao exigem declarar toda
a API do Lune como globais do Selene.

As verificacoes exploratorias produziram os seguintes resultados:

- `std = "luau+roblox"` em `src/`, `tests/` e `lune/`: nenhum erro de parsing,
  mas tres avisos de variavel nao usada no codigo de producao.
- `std = "luau"` em `src/`: falsos positivos para as APIs Roblox, incluindo
  `game`, `script`, `workspace`, `Vector3`, `Enum` e `Random`.
- `std = "luau"` em `tests/` e `lune/`: dois erros para o global `warn`.

Por isso, a implementacao deve usar uma configuracao para Roblox e outra para
Lune. A diferenca de biblioteca padrao declara os simbolos validos sem
misturar globais Roblox nos testes; os lints gerais permanecem os mesmos.

## Escopo

### Incluido

1. Registrar Selene 0.29.0 em Rokit e Aftman.
2. Criar a configuracao do Selene para o codigo Roblox.
3. Criar a configuracao do Selene para o codigo executado no Lune.
4. Criar uma biblioteca padrao minima para o global `warn` do Lune.
5. Corrigir os tres avisos atuais de `unused_variable` sem desativar esse lint
   globalmente.
6. Documentar a instalacao e os dois comandos de lint no README.
7. Verificar lint, testes unitarios, build Rojo e integridade do diff.

### Fora de escopo

- Adicionar `luau-lsp analyze` ou uma etapa de type checking semantico.
- Adicionar formatador. Selene verifica lint; formatacao pode ser tratada por
  StyLua em uma tarefa separada.
- Adicionar workflow de CI nesta tarefa.
- Alterar a arquitetura de imports Roblox para funcionar diretamente no Lune.
- Adicionar testes para modulos que nao fazem parte da suite atual.
- Desativar `undefined_variable`, `unused_variable` ou todos os avisos apenas
  para obter uma execucao verde.

## Decisoes de implementacao

### Toolchain

Adicionar a mesma versao fixa aos dois manifests:

```toml
selene = "Kampfkarren/selene@0.29.0"
```

As entradas devem ser adicionadas dentro da tabela `[tools]`, sem remover Rojo
ou Lune. Rokit continua sendo o fluxo recomendado:

```bash
rokit install
```

O fluxo equivalente com Aftman deve continuar funcionando:

```bash
aftman install
```

Se a fonte escolhida pelo gerenciador nao aceitar a versao fixada, nao deixar
uma versao aberta ou diferente entre os manifests. Confirmar a versao real
instalada, atualizar os dois arquivos para a mesma versao validada e registrar
essa decisao no resultado da verificacao.

### Configuracao Roblox

Criar `selene.roblox.toml` na raiz:

```toml
std = "luau+roblox"
```

Essa biblioteca fornece as declaracoes Roblox necessarias para o codigo em
`src/` e tambem ativa o reconhecimento de arquivos `.luau`.

### Configuracao Lune

Criar `selene.lune.toml` na raiz:

```toml
std = "luau+selene-lune"
```

Criar `selene-lune.yml` na raiz:

```yaml
---
base: luau
globals:
  warn:
    any: true
```

O arquivo customizado deve declarar somente o que o runner realmente fornece
como global. As APIs de `@lune/*` continuam sendo resolvidas como valores
locais retornados por `require`, e globais Roblox nao devem ser adicionados a
essa biblioteca.

Caso o Selene exija o caminho explicito para uma biblioteca customizada na
versao instalada, ajustar apenas o valor de `std` para apontar para
`selene-lune.yml`, mantendo a mesma base Luau e a mesma declaracao de `warn`.

### Baseline sem avisos

O comando inicial com `std = "luau+roblox"` encontrou estes avisos:

```text
src/shared/remotes.luau: ensureRemote is defined, but never used
src/client/init.client.luau: ReplicatedStorage is assigned a value, but never used
src/server/world/tunnels.luau: rooms is defined, but never used
```

Corrigir de forma localizada:

1. Em [`src/client/init.client.luau`](../src/client/init.client.luau), remover
   a aquisicao de `ReplicatedStorage`, que atualmente nao tem efeito e nao e
   usada por nenhum codigo.
2. Em [`src/shared/remotes.luau`](../src/shared/remotes.luau), preservar o
   comportamento atual do modulo, que retorna uma tabela vazia, e renomear a
   funcao de infraestrutura nao utilizada para `_ensureRemote`, sinalizando a
   intencao ao linter sem desativar `unused_variable` no projeto.
3. Em [`src/server/world/tunnels.luau`](../src/server/world/tunnels.luau),
   remover o parametro `rooms` de `buildTunnelGraph` e do unico ponto de
   chamada, pois a funcao usa `connected` para construir o grafo e nao acessa
   `rooms`.

Nao transformar os avisos em sucesso usando `--allow-warnings` como comando
   padrao e nao configurar `unused_variable = "allow"` para o projeto inteiro.

### Comandos de lint

O codigo Roblox e o codigo Lune devem ser verificados separadamente:

```bash
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

Os comandos devem falhar com codigo diferente de zero quando houver erros,
avisos ou erros de parsing. Nao usar `--allow-warnings` no comando documentado,
porque o objetivo desta tarefa e obter um baseline sem avisos e detectar novas
regressoes.

### Documentacao

Atualizar [`README.md`](../README.md) com uma secao `Luau Linting` contendo:

- requisito de instalar as ferramentas com Rokit;
- alternativa de instalacao com Aftman;
- `selene --version`;
- comando para verificar `src/` com a configuracao Roblox;
- comando para verificar `tests/` e `lune/` com a configuracao Lune;
- explicacao breve de que as duas areas usam bibliotecas padrao diferentes;
- diferenca entre lint e os testes executados por `lune run test`.

## Sequencia de implementacao

1. Confirmar o estado do worktree e nao modificar arquivos fora do escopo do
   linter, exceto os tres ajustes de baseline descritos acima.
2. Adicionar Selene 0.29.0 em [`rokit.toml`](../rokit.toml) e
   [`aftman.toml`](../aftman.toml).
3. Criar `selene.roblox.toml`, `selene.lune.toml` e `selene-lune.yml` na raiz.
4. Aplicar os tres ajustes de `unused_variable` em `src/`.
5. Executar o Selene com as duas configuracoes e ajustar somente configuracoes
   ou nomes diretamente relacionados aos diagnosticos encontrados.
6. Atualizar [`README.md`](../README.md) sem remover a documentacao atual de
   Rojo ou Lune.
7. Instalar as ferramentas e executar toda a verificacao definida abaixo.
8. Revisar o diff final para garantir que nao houve alteracao acidental em
   `docs/`, nos testes existentes ou no arquivo de projeto Rojo.

## Verificacao da implementacao

Executar todos os comandos a partir da raiz do projeto:

```bash
rokit install
selene --version
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
lune run test
rojo build -o /tmp/dungeon-game-canve.rbxlx
git diff --check
git status --short
```

Se o fluxo Aftman tambem precisar ser validado, executar adicionalmente:

```bash
aftman install
selene --version
selene --config selene.roblox.toml src
selene --config selene.lune.toml tests lune
```

### Resultados esperados

- `rokit install` instala Selene, Rojo 7.7.0 e Lune 0.10.4 sem remover
  ferramentas existentes.
- `selene --version` corresponde a versao fixada nos manifests.
- O lint de `src/` termina com codigo zero, sem erros, avisos ou erros de
  parsing.
- O lint de `tests/` e `lune/` termina com codigo zero usando apenas a
  biblioteca padrao Luau mais o global Lune `warn`.
- O codigo com tipos Luau, incluindo `export type` e tipos opcionais, nao gera
  erros de parsing.
- Os diagnosticos para `game`, `script`, `workspace`, `Vector3`, `Enum` e
  demais APIs Roblox aparecem como resolvidos em `src/`.
- Um uso acidental de um global Roblox em `tests/` ou `lune/` nao e aceito pela
  biblioteca padrao Lune.
- `lune run test` continua terminando com codigo zero e executa a suite atual.
- `rojo build` continua funcionando e nao inclui `tests/`, `lune/` ou os
  arquivos de configuracao do Selene na arvore Roblox, conforme
  [`default.project.json`](../default.project.json).
- `git diff --check` nao aponta whitespace invalido.
- Nenhuma alteracao preexistente em `src/server/init.server.luau`, `docs/`,
  `tests/` ou `lune/` e removida ou sobrescrita sem relacao direta com o lint.

### Teste negativo recomendado

Durante a verificacao, criar temporariamente uma copia nao versionada de um
arquivo `.luau` com um erro simples, executar o comando correspondente e
confirmar que o Selene retorna codigo diferente de zero. Remover a copia antes
da revisao final do worktree.

Exemplos de comportamentos que devem continuar sendo detectados:

- variavel local nao utilizada sem prefixo `_`;
- global inexistente em `tests/` ou `lune/`;
- sintaxe Luau invalida;
- global ou API Roblox inexistente em `src/`.

## Riscos e observacoes

- Selene e um linter; ele nao substitui o type checker do Luau nem garante que
  `require(script.Parent...)` resolva corretamente na arvore Roblox.
- O Selene usa bibliotecas padrao para reconhecer simbolos, nao executa o
  codigo. A configuracao Lune nao transforma os testes em um ambiente Roblox.
- O global `warn` foi declarado manualmente apenas porque o runtime Lune atual
  o fornece e a biblioteca Luau basica do Selene nao o declara.
- Se novos modulos Lune passarem a usar outros globais, adicionar somente os
  simbolos reais em `selene-lune.yml`, evitando copiar a biblioteca Roblox.
- Se o codigo de producao passar a usar novas APIs Roblox, a biblioteca
  `luau+roblox` deve ser atualizada ou validada antes de adicionar excecoes
  locais.
- A pasta `src/server/cave-engine/` contem hifen. Qualquer verificacao manual
  de imports relacionada a ela deve manter `script["cave-engine"]`, conforme
  [`AGENTS.md`](../AGENTS.md).
- A adicao de CI pode ser feita depois que o baseline estiver verde, usando os
  mesmos dois comandos de lint e `lune run test`.

## Referencias

- [Selene: documentacao geral](https://kampfkarren.github.io/selene/)
- [Selene: configuracao](https://kampfkarren.github.io/selene/usage/configuration.html)
- [Selene: formato de bibliotecas padrao](https://kampfkarren.github.io/selene/usage/std.html)
- [Selene: lint `unused_variable`](https://kampfkarren.github.io/selene/lints/unused_variable.html)
- [Selene: filtragem de lints](https://kampfkarren.github.io/selene/usage/filtering.html)
- [Rokit](https://github.com/rojo-rbx/rokit)
- [Aftman](https://github.com/LPGhatguy/aftman)
- [Luau Language Server: modo standalone](https://github.com/JohnnyMorganz/luau-lsp#standalone)
