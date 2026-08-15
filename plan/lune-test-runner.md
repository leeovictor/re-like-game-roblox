# Plano: Runner de testes unitarios com Lune

## Objetivo

Adicionar o Lune como runtime e runner de testes unitarios deste projeto,
mantendo a execucao do jogo no Roblox Studio via Rojo. Nesta etapa sera criada
apenas uma suite pequena para validar o runner contra
`src/server/world/grid.luau`; os demais modulos de dominio ficarao sem testes
iniciais. A entrega deve deixar a infraestrutura pronta para que novos testes
possam ser adicionados posteriormente e executados com:

```bash
lune run test
```

## Estado atual

- O projeto e Luau/Roblox montado por [`default.project.json`](../default.project.json).
- As ferramentas atuais sao Rojo 7.7.0 em [`rokit.toml`](../rokit.toml) e
  [`aftman.toml`](../aftman.toml).
- Lune nao esta configurado nem instalado no ambiente atual.
- Nao existem diretorios `tests/`, `specs/`, scripts de teste ou CI.
- O projeto nao usa um framework de testes externo.
- Os modulos de producao usam imports baseados na arvore Roblox, por exemplo:

  ```luau
  require(script.Parent.types)
  require(script.Parent.Parent.world.grid)
  ```

- Os modulos de geracao usam tipos Roblox (`Vector3`, `Vector3int16`),
  `Random`, `math.noise` e, em partes de integracao, `workspace.Terrain`,
  `Region3`, `Enum` e `task`.
- A pasta [`src/server/cave-engine/`](../src/server/cave-engine/) possui um
  hifen no nome. Imports Roblox para essa pasta devem continuar usando
  `script["cave-engine"]`, nunca notacao de ponto.
- O worktree ja possui alteracoes nao relacionadas em
  [`src/server/init.server.luau`](../src/server/init.server.luau) e arquivos
  nao rastreados em [`docs/`](../docs/). A implementacao nao deve reverter nem
  modificar essas alteracoes.

## Escopo

### Incluido

1. Registrar uma versao fixa do Lune no toolchain do projeto.
2. Criar o comando `lune run test`.
3. Criar um harness minimo para descoberta e execucao de testes futuros.
4. Criar um loader compatível com os imports Roblox existentes.
5. Criar uma suite inicial somente para `src/server/world/grid.luau`.
6. Documentar instalacao e execucao do runner.
7. Verificar que o runner executa a suite de `Grid3D` corretamente.

### Fora de escopo

- Criar testes de `CaveEngine`, salas, tuneis ou qualquer outro modulo de
  dominio alem de `Grid3D` nesta etapa.
- Alterar os imports dos modulos em `src/` para imports relativos do Lune.
- Testar `workspace.Terrain:WriteVoxels`, `game:GetService` ou scripts de
  inicializacao fora do Roblox Studio.
- Adicionar framework externo de testes ou gerenciador de pacotes Luau.
- Adicionar workflow de CI. Isso pode ser feito em uma tarefa separada depois
  que os primeiros testes existirem.

## Decisoes de implementacao

### Toolchain

Adicionar Lune aos dois manifests existentes para que os fluxos que usam Rokit
ou Aftman permaneçam equivalentes:

```toml
lune = "lune-org/lune@0.10.4"
```

O projeto usa Rokit como caminho recomendado. A instalacao deve ser feita com:

```bash
rokit install
```

Se a versao estavel disponivel tiver mudado, confirmar a versao efetivamente
instalada e manter a mesma versao fixada nos dois manifests. Nao deixar uma
referencia sem versao.

### Estrutura do runner

Criar uma estrutura semelhante a esta:

```text
lune/
  test.luau
tests/
  support/
    harness.luau
    roblox-loader.luau
  server/
    world/
      grid.spec.luau
```

O unico arquivo de teste inicial deve ser
`tests/server/world/grid.spec.luau`, correspondente a
`src/server/world/grid.luau`. Nao criar suites para outros modulos.

O script `lune/test.luau` deve:

- ser descoberto automaticamente pelo comando `lune run test`;
- procurar recursivamente por arquivos futuros com uma convencao definida,
  preferencialmente `tests/**/*.spec.luau`;
- carregar cada modulo de teste e executar os casos registrados pelo harness;
- imprimir uma linha resumida com quantidade de suites/casos aprovados,
  falhos e tempo total;
- retornar codigo de processo diferente de zero quando houver falha;
- retornar codigo zero quando a suite de `Grid3D` passar;
- continuar informando explicitamente quando nenhum arquivo de teste futuro for
  encontrado, sem tratar isso como falha.

O `tests/support/harness.luau` deve ser pequeno e sem dependencia externa. A
API deve permitir que futuros testes registrem suites e casos, por exemplo com
uma forma equivalente a `describe`/`it` e assercoes basicas. O harness deve
capturar erros por caso para que uma falha produza diagnostico e nao interrompa
silenciosamente toda a descoberta.

### Compatibilidade com os modulos Roblox

O Lune resolve `require` por caminhos de arquivo e nao fornece a arvore
`script.Parent` do Roblox. Para nao quebrar a execucao no Studio, nao alterar os
imports de `src/` apenas para acomodar o runner.

O `tests/support/roblox-loader.luau` deve:

1. Ler os arquivos Luau de `src/` usando `@lune/fs`.
2. Executa-los usando `@lune/luau.load` com um ambiente customizado.
3. Construir uma arvore virtual de nos para que expressões como
   `script.Parent.types` e `script["cave-engine"].CaveEngine` continuem
   resolvendo o modulo correto.
4. Fornecer `require` customizado para os nos virtuais e cachear modulos
   carregados.
5. Expor no ambiente de teste os tipos do `@lune/roblox` que o codigo usa:

   ```luau
   Vector3 = roblox.Vector3
   Vector3int16 = roblox.Vector3int16
   Region3 = roblox.Region3
   Enum = roblox.Enum
   ```

6. Fornecer um `Random` deterministico com a interface usada pelo projeto:
   `Random.new`, `NextInteger`, `NextNumber` e `Shuffle`.
7. Evitar executar caminhos que dependem de `workspace`, `Terrain` ou APIs do
   Studio. Esses caminhos devem continuar sendo responsabilidade de testes de
   integracao executados dentro do Roblox.

O loader deve respeitar maiusculas/minusculas dos nomes reais em `src/` e usar
strings de caminho para lidar com a pasta `cave-engine`.

Para a suite inicial, o loader precisa necessariamente disponibilizar
`Vector3` e `Vector3int16`, pois sao usados por `Grid3D`. O suporte a
`Random`, `Region3`, `Enum`, `workspace` e `Terrain` deve permanecer isolado
dos testes atuais e so ser exercitado quando outros modulos forem incluidos em
uma etapa futura.

## Suite inicial de Grid3D

Criar `tests/server/world/grid.spec.luau` com uma unica suite e cinco casos,
usando um grid pequeno para manter o teste rapido e deterministico. A suite
deve carregar o modulo de producao atraves do loader, e nao por uma copia ou
reimplementacao do algoritmo.

Usar, por exemplo, `resolution = 4`, `worldMin = Vector3.new(-4, -8, -12)` e
`sizeStuds = Vector3.new(8, 12, 16)`, produzindo um grid de `2x3x4` com 24
celulas. Os casos devem verificar:

1. `Grid3D.new` cria os metadados esperados (`resolution`, `size`, `worldMin`,
   `worldMax`, `center`) e inicializa todas as celulas como `"Rock"`.
2. `worldToCell` e `cellToWorld` convertem corretamente pontos nos limites e
   no centro das celulas, incluindo o comportamento fora dos limites.
3. `inBounds`, `setCell` e `getCell` respeitam limites, alteram uma celula
   valida e retornam `"Outside"` para uma celula invalida sem causar erro.
4. `forEachCell` visita exatamente as 24 celulas na ordem `x -> y -> z`, com a
   primeira celula `(1, 1, 1)` e a ultima `(2, 3, 4)`.
5. `toDebugString` gera o resumo correto depois de alterar uma celula para
   `"Air"` e outra para `"Outside"`, incluindo as contagens de cada material.

As assercoes devem verificar componentes numericos individualmente ou usar
uma tolerancia explicita para valores `Vector3`; nao depender de comparacoes
de identidade entre instancias de datatype.

## Sequencia de implementacao

1. Adicionar a entrada fixada do Lune em [`rokit.toml`](../rokit.toml) e
   [`aftman.toml`](../aftman.toml), sem remover a configuracao existente do
   Rojo.
2. Criar o harness em `tests/support/harness.luau` com registro de suites,
   casos, assercoes, captura de erros e resumo.
3. Criar o loader em `tests/support/roblox-loader.luau`, mantendo o codigo de
   producao inalterado.
4. Criar `lune/test.luau` para descoberta dos testes futuros e integracao com o
   harness.
5. Atualizar [`README.md`](../README.md) com:
   - requisito de Rokit/Aftman;
   - `rokit install`;
   - `lune --version`;
   - `lune run test`;
   - convencao de nomes/localizacao para testes futuros;
   - limite entre testes unitarios Lune e integracao no Studio.
6. Criar `tests/server/world/grid.spec.luau` com somente os cinco casos da
   suite inicial descrita acima.
7. Nao adicionar testes para outros modulos de dominio nesta tarefa.

## Verificacao da implementacao

Executar a partir da raiz do projeto:

```bash
rokit install
lune --version
lune list
lune run test
rojo build -o /tmp/dungeon-game-canve.rbxlx
git diff --check
git status --short
```

Resultados esperados:

- `rokit install` instala o Lune e preserva Rojo 7.7.0.
- `lune --version` corresponde a versao fixada no manifest.
- `lune list` mostra o script `test`.
- `lune run test` termina com codigo zero, descobre uma suite e cinco casos de
  `Grid3D`, e nao produz erro de import ou de runtime.
- A saida identifica os cinco casos como aprovados e nao registra falhas.
- `rojo build` continua funcionando, demonstrando que a infraestrutura em
  `lune/` e `tests/` nao entrou no modelo Rojo definido em
  [`default.project.json`](../default.project.json).
- `git diff --check` nao aponta whitespace invalido.
- Nenhuma alteracao preexistente em `src/server/init.server.luau` ou `docs/`
  e removida.

## Riscos e observacoes

- Lune nao executa um jogo Roblox completo. A biblioteca `@lune/roblox` fornece
  datatypes e algumas APIs de manipulacao de arquivos/place, mas nao substitui
  `workspace.Terrain` em runtime de jogo.
- O `Random` do loader deve ser deterministico, mas nao deve ser usado para
  afirmar que a sequencia numerica e identica ao `Random` do Roblox. Testes
  futuros devem validar invariantes e determinismo, nao valores acidentais da
  implementacao do shim.
- O loader customizado e infraestrutura de teste; ele nao deve ser importado
  por scripts executados no Roblox Studio.
- Se a API real do Lune 0.10.4 diferir da documentacao consultada, ajustar o
  loader ao runtime instalado e manter a versao efetivamente validada fixa no
  manifest.

## Referencias

- [Lune: instalacao](https://lune-org.github.io/docs/getting-started/1-installation/)
- [Lune: uso da linha de comando](https://lune-org.github.io/docs/getting-started/2-command-line-usage/)
- [Lune: modulos e resolucao de paths](https://lune-org.github.io/docs/the-book/7-modules/)
- [Lune: API Luau `load`](https://lune-org.github.io/docs/api-reference/luau/)
- [Lune: API Roblox disponivel](https://lune-org.github.io/docs/roblox/4-api-status/)
- [Rokit](https://github.com/rojo-rbx/rokit)
