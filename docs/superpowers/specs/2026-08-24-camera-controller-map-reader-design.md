# Design: CameraController Com CameraMapReader

Data: 2026-08-24  
Status: Aprovado pelo usuario para especificacao  
Commit: nao criar

## Objetivo

Melhorar a arquitetura do sistema de camera tornando `CameraMapReader` uma
dependencia explicita de `CameraController`. O controller deve receber o reader
em vez de receber uma configuracao ja convertida:

```luau
local cameraController = CameraController.new(CameraMapReader)
```

Durante a construcao, o controller descobre `Workspace.CameraSystem`, le a
configuracao uma vez e cria seu resolver. `CameraVisibility` continua sendo um
utilitario externo para ocultar os parts de autoria do sistema de camera.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Dependencia do construtor | `CameraMapReader`, com metodo `read(rootName: string)` |
| Assinatura | `CameraController.new(CameraMapReader)` |
| Descoberta da pasta | Interna ao `CameraMapReader`, via `workspace:WaitForChild("CameraSystem")` |
| Preparacao da hierarquia | Reader aguarda `Shots` e `Zones`; aguarda tambem o shot padrao quando o atributo estiver disponivel |
| Leitura | Uma chamada a `cameraMapReader.read("CameraSystem")` durante `new` |
| Estado armazenado | `CameraConfig.Config` e `CameraResolver`; nenhuma pasta ou hot reload |
| Visibilidade | `CameraVisibility.hide(cameraSystem)` permanece no bootstrap |
| Compatibilidade | Remover a injecao direta de `CameraConfig`; nao criar segundo modo de construcao |
| Formato do mapa | Sem alteracoes em `CameraMapReader` ou `CameraConfig` |

## Arquitetura e fluxo

`CameraMapReader.luau` expoe o contrato `CameraMapReader.CameraMapReader` com o
metodo `read`, retornando `CameraConfig.Config`. O `CameraController` importa o
modulo compartilhado e usa esse tipo exportado na assinatura do construtor. O
modulo concreto continua sendo `ReplicatedStorage.Shared.camera.CameraMapReader`,
mas testes podem fornecer uma implementacao equivalente quando necessario.

O fluxo de carregamento sera:

1. `CameraController.new` chama `cameraMapReader.read("CameraSystem")`.
2. O reader aguarda `workspace:WaitForChild(rootName)`.
3. O reader aguarda as pastas filhas `Shots` e `Zones`.
4. O reader le e valida `DefaultShotId` e a existencia dos shots referenciados.
5. O reader converte e valida o mapa.
6. O controller guarda o config retornado e cria `CameraResolver.new(config)`.

O bootstrap continuara compondo os modulos e controlando a visibilidade:

```luau
local cameraSystem = workspace:WaitForChild("CameraSystem")
local cameraController = CameraController.new(CameraMapReader)

CameraVisibility.hide(cameraSystem)
cameraController:start()
```

O bootstrap nao interpretara mais `Shots`, `Zones`, `DefaultShotId` ou o
resultado de `read`. A leitura ocorrera antes de `start`, e a ocultacao ocorrera
fora do controller, sem alterar a responsabilidade de cada modulo.

O comportamento existente de `start`, `stop`, troca de shots por zonas,
retencao do ultimo shot, cinematics, `CameraType`, `Focus`, CFrame, FOV e
restauracao da camera sera preservado.

## Contratos e falhas

O modulo `CameraMapReader` exportara o proprio contrato:

```luau
export type CameraMapReader = {
    read: (rootName: string) -> CameraConfig.Config,
}

O `CameraController` importara o modulo e anotara a dependencia como
`CameraMapReader.CameraMapReader`. Nao havera uma declaracao duplicada do tipo no
controller.
```

O contrato usa o mesmo formato aceito pelo modulo atual. Nao havera suporte a
`CameraConfig` como argumento alternativo, para evitar dois caminhos de
inicializacao e manter a responsabilidade de leitura no controller.

`CameraMapReader.read` mantera todas as validacoes e mensagens existentes e
passara a concentrar tambem a espera da hierarquia. Uma falha de dados invalidos
sera propagada durante `CameraController.new`; o controller nao usara
configuracao parcial nem aplicara fallback silencioso.

Se a pasta indicada por `rootName` ainda nao existir, o reader aguardara
indefinidamente com `WaitForChild`. Se a pasta existir mas seus dados forem
invalidos, a chamada ao reader falhara explicitamente.

O controller nao guardara a pasta para observar mudancas. O mapa sera um
snapshot carregado uma unica vez durante a construcao.

## Alteracoes por arquivo

### `src/client/camera/CameraController.luau`

- Adicionar o tipo estrutural do reader.
- Alterar `new` para receber o reader.
- Remover do controller a espera/interpretação da hierarquia.
- Chamar `cameraMapReader.read("CameraSystem")` no construtor.
- Manter o config lido no campo usado pelo resolver e pelos metodos atuais.
- Preservar todos os demais comportamentos publicos.

### `src/client/init.client.luau`

- Manter o `require` de `CameraMapReader` para injeta-lo no controller.
- Manter `workspace:WaitForChild("CameraSystem")` para `CameraVisibility`.
- Remover a espera/interpretação manual de `Shots`, `Zones` e `DefaultShotId`.
- Remover `CameraMapReader.read` e a variavel `cameraConfig` do bootstrap.
- Criar o controller com `CameraController.new(CameraMapReader)`.
- Manter `CameraVisibility.hide(cameraSystem)` externo ao controller.

### `tests/client/camera/CameraController.spec.luau`

- Criar uma fixture isolada `Workspace.CameraSystem` com as pastas, shots,
  zonas e atributos necessarios.
- Passar o `CameraMapReader` real ao construtor.
- Manter os testes comportamentais atuais de inicializacao, troca de zona,
  cinematics, limpeza e restauracao.
- Verificar que o controller carrega a configuracao a partir da fixture no
  construtor.
- Destruir a fixture e restaurar personagem e camera no teardown.

### Arquivos sem alteracao funcional

- `src/shared/camera/CameraMapReader.luau`: parser, validacoes e espera da
  hierarquia ficam centralizados no reader.
- `src/client/camera/CameraVisibility.luau`: utilitario externo permanece.
- `tests/client/camera/CameraVisibility.spec.luau`: comportamento de ocultacao
  permanece coberto.

## Testes e verificacao

Os testes client-side devem demonstrar que:

- O construtor aceita o reader e carrega a configuracao da pasta do Workspace.
- O controller inicia usando o shot padrao definido na fixture.
- Entrar em uma zona continua trocando para o shot configurado.
- Sair da zona continua mantendo o ultimo shot, conforme o comportamento atual.
- Override cinematic e limpeza continuam funcionando.
- A fixture, conexoes, camera e personagem sao restaurados no teardown.

A verificacao final deve executar:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

O TestEZ deve ser executado em Play limpo no Roblox Studio, com `failed == 0`
nos resultados server e client. Depois de alterar scripts ou specs, a sessao
Play deve ser reiniciada antes da execucao dos testes.

## Fora de escopo

- Alterar o formato ou as validacoes de `CameraMapReader`.
- Alterar `CameraResolver` ou a regra de selecao de shots.
- Mover `CameraVisibility` para dentro do controller.
- Adicionar hot reload ou observar alteracoes no Workspace.
- Manter compatibilidade com `CameraController.new(config)`.
- Refatorar outras dependencias do sistema de camera.
- Criar commits durante esta especificacao ou sua implementacao, salvo pedido
  explicito posterior do usuario.

## Criterios de aceitacao

- `CameraController.new(CameraMapReader)` e a unica forma de construcao.
- `CameraMapReader.read("CameraSystem")` e executado internamente durante `new`.
- A pasta e descoberta internamente pelo reader com `WaitForChild`.
- O bootstrap nao le mais o mapa, mas continua chamando `CameraVisibility.hide`.
- O comportamento atual do controller permanece preservado.
- O reader continua sendo a barreira de validacao do mapa.
- Testes, lint, typecheck e builds concluem sem falhas.
