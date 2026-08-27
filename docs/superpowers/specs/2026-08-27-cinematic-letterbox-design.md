# Design: Letterboxing do Sistema de Cinematics

Data: 2026-08-27
Status: Design aprovado pelo usuario; sem commit

## Objetivo

Exibir barras pretas superior e inferior durante qualquer cinematic client-side.
As barras devem entrar no inicio da execucao, sair depois que a cinematic
terminar e usar transicoes suaves. Durante esse periodo, a UI principal do jogo
deve ficar oculta.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Arquitetura | Controller visual separado injetado no `CinematicController` |
| Proporcao | Area visivel alvo de `2.39:1`, calculada pela viewport atual |
| Barras | Duas `Frame` pretas em uma `ScreenGui` dedicada |
| Camada | `ScreenGui` com `DisplayOrder` alto e `IgnoreGuiInset = true` |
| UI existente | `DungeonGui` fica desabilitado durante a cinematic |
| Entrada | Barras expandem simultaneamente a partir das bordas |
| Saida | Barras retraem simultaneamente para tamanho zero |
| Duracao | `0.35s`, com easing `Quad` e direcao `Out` |
| Concorrencia | Uma nova transicao invalida callbacks de transicoes antigas |
| Falhas | Erros visuais geram aviso, sem impedir a limpeza da cinematic |
| Testes | Nao ler nem alterar testes unitarios |

## Arquitetura

Adicionar `src/client/cinematics/CinematicLetterbox.luau`. A instancia criada
por `new()` sera responsavel por:

- criar e manter a `ScreenGui` e as duas barras;
- calcular a altura das barras a partir de `workspace.CurrentCamera.ViewportSize`;
- animar entrada, resize e saida usando `TweenService`;
- preservar e restaurar o valor original de `DungeonGui.Enabled`;
- invalidar callbacks de tweens antigos quando uma nova transicao comecar.

O modulo exportara um contrato com `show()` e `hide()`. O
`CinematicController` recebera esse contrato como dependencia opcional, para
que callers existentes sem UI continuem funcionando. O composition root em
`src/client/init.client.luau` criara a instancia real usando o `PlayerGui` e a
passara ao controller.

## Fluxo de execucao

Depois do preload e da aquisicao do bloqueio de movimento, o
`CinematicController` muda para `playing` e chama `letterbox:show()` antes de
executar o primeiro efeito da timeline. A animacao roda em paralelo com a
timeline e nao adiciona espera ao scheduler da cinematic.

As rotinas de conclusao normal, interrupcao, falha e `stop()` chamarao
`letterbox:hide()` junto da limpeza existente. O `hide()` so desabilitara a
`ScreenGui` dedicada e restaurara o `DungeonGui` quando o tween de saida
terminar. Se outro `show()` ocorrer antes desse callback, o callback antigo nao
podera reativar a UI prematuramente.

Se a cinematic falhar durante o preload, nenhuma barra sera exibida. Um
`hide()` seguro nesses caminhos nao deve alterar uma UI que nao foi ativada.

## Proporcao responsiva

Considere `viewportAspect = largura / altura` e `cinematicAspect = 2.39`.
Quando a viewport for mais estreita que a proporcao cinematografica, a area
visivel tera fracao `viewportAspect / cinematicAspect` da altura total. Cada
barra tera metade do espaco restante. O valor sera limitado para evitar barras
invalidas em orientacoes extremas.

Uma mudanca de `ViewportSize` enquanto a letterboxing estiver ativa recalculara
o destino e animara as barras para a nova altura.

## Arquivos envolvidos

### Novo

- `src/client/cinematics/CinematicLetterbox.luau`

### Alterados

- `src/client/cinematics/CinematicController.luau`
- `src/client/init.client.luau`

Nao serao alterados `App.luau`, `MachineRoomCinematicController.luau`, as
timelines, scripts server-side ou testes unitarios.

## Verificacao

Sem abrir ou alterar testes unitarios, verificar:

- lint dos scripts de producao;
- build Rojo do projeto principal;
- execucao visual no Roblox Studio, incluindo entrada, UI oculta, saida e
  interrupcao da cinematic;
- `git diff --check` e preservacao de alteracoes preexistentes fora do escopo.

## Criterios de sucesso

- Toda cinematic que entra em `playing` exibe barras pretas responsivas.
- Entrada e saida sao suaves e duram aproximadamente `0.35s`.
- Inventario, objetivos, notificacoes e dialogos nao ficam visiveis durante a
  cinematic.
- A UI principal volta ao estado anterior depois da saida.
- `stop()` e falhas nao deixam barras, UI desabilitada ou callbacks antigos
  ativos.
- A cinematic continua funcionando mesmo se a dependencia visual nao for
  fornecida.
