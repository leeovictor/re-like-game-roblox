# Objective Notification Component Refactor Design

## Context

`src/client/ui/App.luau` atualmente possui responsabilidades de composição da
interface e também toda a implementação da notificação de objetivos. Isso inclui:

- consumir `useObjectiveNotification()`;
- manter o `TextLabel` ref;
- criar e cancelar os tweens com `TweenService`;
- construir o `TextLabel`, `UIPadding`, `UICorner` e `UIStroke` da notificação.

O objetivo desta refatoração é mover toda a responsabilidade relacionada à
exibição da notificação para um componente React dedicado, sem alterar o
comportamento visual ou o ciclo de vida já aprovado.

## Goals

- Criar `src/client/ui/ObjectiveNotification.luau`.
- Fazer o componente consumir `useObjectiveNotification()` internamente.
- Encapsular no componente o ref, a animação e a árvore visual da notificação.
- Deixar `App.luau` responsável apenas pela composição da interface.
- Preservar posição, layout, textos, cores, transparências e temporização.
- Validar as alterações com Selene, `luau-lsp`, build Rojo e Play manual.

## Non-goals

- Não alterar `ObjectiveController.luau`.
- Não alterar o contrato de `useObjectiveNotification()`.
- Não alterar `ObjectiveNotificationTiming.luau`.
- Não adicionar props ou opções de configuração ao componente.
- Não alterar o painel permanente de objetivos.
- Não alterar a notificação de pickup ou outros sistemas da interface.
- Não criar specs de UI no TestEZ.

## Chosen Architecture

Será usada uma abordagem de componente autocontido. O componente será
stateful e não receberá props:

```text
App
└── ObjectiveStack
    ├── ObjectiveNotification
    └── ObjectivePanel
```

`App.luau` importará `ObjectiveNotification` e o montará como filho de
`ObjectiveStack`:

```lua
Notice = React.createElement(ObjectiveNotification)
```

O componente ficará em `src/client/ui/ObjectiveNotification.luau`, enquanto
os módulos de domínio continuarão em `src/client/objectives/`:

- `useObjectiveNotification.luau`: obtém e agenda os lotes da notificação.
- `ObjectiveNotificationTiming.luau`: fornece as durações compartilhadas.
- `ObjectiveNotification.luau`: controla a apresentação e a animação.
- `App.luau`: compõe os elementos de alto nível da interface.

O mapeamento existente de `src/client` no `default.project.json` já inclui o
novo ModuleScript; nenhuma alteração de projeto será necessária.

## Component Responsibilities

`ObjectiveNotification` terá as seguintes responsabilidades:

1. Chamar `useObjectiveNotification()` internamente.
2. Retornar `nil` quando não houver lote ativo.
3. Montar o `TextLabel` com o título singular ou plural e as descrições dos
   objetivos.
4. Montar `UIPadding`, `UICorner` e `UIStroke` como filhos do label.
5. Inicializar o texto, o background e o stroke completamente transparentes.
6. Executar o fade in e o fade out usando `TweenService` e os valores de
   `ObjectiveNotificationTiming`.
7. Cancelar tweens ativos quando o lote for substituído ou o componente for
   desmontado.

`App.luau` deixará de conter:

- o require de `useObjectiveNotification`;
- o require de `ObjectiveNotificationTiming`;
- o require de `TweenService`;
- o ref da notificação;
- o efeito de animação;
- a variável `objectiveNotice` e sua árvore visual inline.

O `ObjectiveStack`, seu `UIListLayout`, sua posição e o `objectivePanel`
permanecerão inalterados.

## Lifecycle and Animation

O componente será montado permanentemente por `App`, mas produzirá conteúdo
visual apenas quando o hook possuir um lote:

1. O componente chama o hook enquanto seu efeito conecta-se ao controller.
2. Com retorno `nil`, nenhum label visual é criado.
3. Após `entryDelay`, o hook retorna o lote e o componente cria o label com:
   - `TextTransparency = 1`;
   - `BackgroundTransparency = 1`;
   - `UIStroke.Transparency = 1`.
4. Após o commit do React, o efeito obtém o label pelo ref e executa em
   paralelo:
   - texto de `1` para `0`;
   - background de `1` para `0.08`;
   - stroke de `1` para `0.25`.
5. Depois de `fadeInDuration + visibleDuration`, o efeito cria e executa os
   tweens de saída:
   - texto para `1`;
   - background para `1`;
   - stroke para `1`.
6. Ao fim da duração total, o hook limpa o lote. O label permanece montado
   durante todo o fade out.

Ao receber uma nova ativação, o hook limpa o lote anterior imediatamente e
reinicia o atraso de entrada. O cleanup do efeito do componente marcará a
animação anterior como inativa e cancelará seus tweens. O callback atrasado do
fade out usará o guard `active` e não tentará acessar uma instância destruída.

O lookup do stroke continuará defensivo: o componente procurará o filho
chamado `Stroke` e só o animará se ele for um `UIStroke`. Nenhum `task.cancel`
ou mecanismo de fila será introduzido.

## Data Flow

```text
ObjectiveController.activated
        │
        ▼
useObjectiveNotification()
        │  lote atual ou nil
        ▼
ObjectiveNotification
        │  renderiza e anima
        ▼
ObjectiveStack em App
```

O lote não será passado por props e não atravessará `App`. Isso reduz o
contrato público do componente para sua própria presença na árvore React e
mantém a origem dos dados encapsulada no domínio de objetivos.

## Verification

Não serão adicionadas specs de UI ao TestEZ. A validação será feita com:

```bash
selene --config selene.roblox.toml \
  src/client/ui/App.luau \
  src/client/ui/ObjectiveNotification.luau \
  src/client/objectives/ObjectiveNotificationTiming.luau \
  src/client/objectives/useObjectiveNotification.luau
```

O `luau-lsp` será obrigatório e deverá ser executado depois da geração do
sourcemap de teste:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json \
  --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Também serão construídos os projetos principal e de teste com Rojo. No Play
manual, deverão ser confirmados:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

- o atraso inicial de um segundo;
- o fade in, o período totalmente visível e o fade out;
- a substituição correta quando uma ativação ocorre durante um ciclo ativo;
- a ausência de acesso a labels destruídos no Output;
- o funcionamento independente do painel de objetivos;
- a ausência de alteração na notificação de pickup.

## Acceptance Criteria

- `ObjectiveNotification.luau` concentra o hook, a árvore visual e a
  animação da notificação.
- `App.luau` apenas monta `ObjectiveNotification` dentro de
  `ObjectiveStack`.
- O componente não possui props.
- O timing continua centralizado em `ObjectiveNotificationTiming.luau`.
- O contrato de `useObjectiveNotification()` e `ObjectiveController` não muda.
- A interface mantém o comportamento e o visual existentes.
- Selene e `luau-lsp` não produzem diagnósticos novos para a refatoração.
- Os builds Rojo e a verificação manual são concluídos sem regressões.
