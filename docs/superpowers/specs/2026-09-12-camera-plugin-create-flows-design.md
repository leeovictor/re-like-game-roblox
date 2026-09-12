# Camera System Plugin: Modais de Criação de Shot e Zona

Esta spec complementa `2026-08-17-camera-system-plugin-design.md` e
`2026-09-12-camera-system-persistence-design.md`. Ela mantem o modelo
persistido, o runtime e os demais comandos do painel; muda apenas a interface
dos fluxos de criacao de shot e de zona.

## Objetivo

Substituir o campo de texto compartilhado `Name for new shot or zone` por
modais dedicados:

- `New Shot` abre um modal que pede o nome do shot.
- `New Zone` abre um modal que pede o nome da zona e a selecao de um shot,
  com busca por nome.

O rascunho de referencia mostra um modal simples por fluxo e um seletor de shot
com busca. As cores e o layout do rascunho sao ilustrativos; o visual segue o
tema escuro ja usado pelo painel do plugin.

## Decisoes

- O modal e um overlay dentro do proprio `DockWidgetPluginGui`, nao uma janela
  flutuante sobre o viewport.
- Cada fluxo usa um modal proprio, sem campo de nome compartilhado no painel.
- No fluxo de zona, a escolha do shot e obrigatoria e o shot padrao
  (`DefaultShotId`) vem pre-selecionado quando existir.
- Sem nenhum shot, o botao `New Zone` fica desabilitado.
- Textos da interface em ingles, consistentes com o restante do plugin
  (`Cancel`, `Create`, `Enter the shot name`, `Enter the zone name`,
  `Select a shot`).
- `Assign Shot`, captura, aplicacao, FOV, default e reordenacao permanecem
  como estao.
- O `CameraSystemModel` segue como barreira final de validacao; os modais
  fazem apenas validacao local antecipada.

## Componentes

Todos os modulos ficam em `plugin/camera/` com `--!strict`.

### CameraSystemStyle.luau (novo)

Modulo puro com os tokens visuais do plugin:

- Cores: fundo do painel, fundo de input, fundo de botao, texto, texto
  apagado, destaque de selecao, cor de erro e scrim.
- Medidas: altura de botao e input, padding do card, espacamento, largura
  minima do card, altura maxima da lista do seletor.
- Tamanhos de texto.

Os tres modulos de UI (`CameraSystemWidget`, `CameraSystemDialog` e
`ShotSelector`) consomem esses tokens, removendo as cores hardcoded atuais.

### CameraSystemDialog.luau (novo)

Shell reutilizavel de modal. Responsabilidades:

- Criar scrim full-size sobre o conteudo do dock e card centralizado com
  largura adaptada ao painel e altura automatica.
- Expor uma area de conteudo onde o fluxo monta labels, inputs e seletor.
- Renderizar o rodape com `Cancel` e `Create`.
- Renderizar erro inline (label oculta quando nao ha erro).
- Habilitar/desabilitar `Create` conforme o fluxo informar.
- Fechar com `Cancel` ou Esc e bloquear interacao com o painel atras sem
  fechar ao clicar no scrim.
- Destruir a propria GUI ao fechar; o fluxo cria um dialog novo a cada
  abertura, entao o formulario nunca preserva estado antigo.

API publica:

```luau
CameraSystemDialog.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Dialog
CameraSystemDialog.destroy(self: Dialog)
CameraSystemDialog.setError(self: Dialog, message: string?)
CameraSystemDialog.setConfirmEnabled(self: Dialog, enabled: boolean)
```

`Callbacks` contem `onCancel: () -> ()` e `onConfirm: () -> ()`. O dialog se
destroi antes de chamar o callback correspondente.

### ShotSelector.luau (novo)

Dropdown pesquisavel de shots por nome. Responsabilidades:

- Campo fechado com o shot selecionado ou placeholder `Select a shot` e
  indicador de abertura (chevron).
- Popup ancorado abaixo do campo, com TextBox de busca focada ao abrir e lista
  de opcoes em `ScrollingFrame` com altura maxima.
- Filtro case-insensitive por substring, aplicado a cada mudanca de texto.
- Shot padrao marcado como `(default)` na lista.
- Lista vazia apos filtro exibe `No shots found`.
- Clique em uma opcao seleciona e fecha o popup.
- Clique fora do seletor ou Esc fecha o popup sem alterar a selecao.
- Destruido junto com o dialog que o contem.

API publica:

```luau
ShotSelector.new(parent: Instance, onChanged: (() -> ())?): ShotSelector
ShotSelector.setOptions(self: ShotSelector, names: { string }, defaultName: string?)
ShotSelector.getSelected(self: ShotSelector): string?
ShotSelector.close(self: ShotSelector)
ShotSelector.destroy(self: ShotSelector)
```

`setOptions` define a selecao inicial como `defaultName` quando ele existir na
lista. `onChanged` e disparado a cada selecao valida para o fluxo reavaliar se
`Create` pode ser habilitado.

### CameraSystemWidget.luau (alterado)

- Remove o `nameInput` e o placeholder compartilhado.
- `refresh` passa a guardar `shots`, `zones`, `defaultShotId` e erros no
  proprio widget, para que os fluxos consultem o snapshot mais recente.
- Ganha `openNewShotDialog()` e `openNewZoneDialog()`; abrir um modal destrói o
  anterior, mantendo no maximo um dialog ativo.
- O botao `New Zone` fica desabilitado quando o snapshot nao tem shots.
- Callbacks mudam de `onNewShot`/`onNewZone` para
  `onCreateShot(name: string)` e `onCreateZone(name: string, shotName: string)`.
- A secao Actions mantem `New Shot`, `Capture Camera`, `Apply To Camera`,
  `Set Default` e `New Zone`, agora sem o campo de texto.

### init.plugin.luau (alterado)

- `onCreateShot(name)` captura a camera atual e chama `createShot`.
- `onCreateZone(name, shotName)` resolve o shot pelo nome em
  `CameraSystem.Shots` (assert se nao existir) e chama `createZone` com o shot
  explicito.
- O restante do wiring e o ciclo de ativacao/desativacao permanecem iguais.

### CameraSystemModel.luau (alterado)

`createZone` passa a aceitar o shot escolhido:

```luau
CameraSystemModel.createZone(self, name: string, cframe: CFrame, size: Vector3, shot: Part?): Part
```

- Com `shot` informado: valida que o part pertence a `CameraSystem.Shots`
  antes de criar a zona e grava `ShotId` com o nome do shot.
- Sem `shot`: mantem o fallback atual para `DefaultShotId` (compatibilidade).
- A zona continua sendo criada com `Order` incremental, aparencia padrao e
  waypoints de undo existentes.

## Comportamento Dos Fluxos

### New Shot

1. Botao `New Shot` abre o dialog com label `Enter the shot name`, TextBox com
   foco automatico, `Cancel` e `Create`.
2. `Create` so habilita com nome trimado nao-vazio e sem colisao com shot
   existente. A colisao e verificada por igualdade exata contra os nomes do
   snapshot; o model continua a barreira final para o caso em que o nome mudou
   desde o ultimo `refresh`.
3. Colisao exibe erro inline `Shot "<nome>" already exists`.
4. Enter confirma o dialog quando `Create` esta habilitado.
5. Confirmar cria o shot com `CFrame` e `FieldOfView` da camera no momento do
   clique, seleciona o Part no Studio, fecha o dialog e atualiza o painel.
6. `Cancel` ou Esc fecham descartando o formulario.

### New Zone

1. Botao `New Zone` (desabilitado sem shots) abre o dialog com label
   `Enter the zone name`, TextBox, label `Select a shot`, `ShotSelector` com o
   shot padrao pre-selecionado, `Cancel` e `Create`.
2. `Create` so habilita com nome trimado nao-vazio, sem colisao com zona
   existente e com shot selecionado.
3. Colisao exibe erro inline `Zone "<nome>" already exists`.
4. Confirmar cria a zona com centro em `camera.Focus.Position`, tamanho
   `10x10x10`, `ShotId` do shot escolhido, seleciona o Part no Studio, fecha o
   dialog e atualiza o painel.
5. O seletor segue o comportamento descrito em `ShotSelector.luau`; a busca e
   apenas um filtro visual e nao altera a selecao ate um clique.

## Fluxo De Dados

```text
refresh() (init)
    -> widget.refresh(shots, zones, defaultShotId, errors)  -- snapshot
botao New Shot / New Zone
    -> widget:openNewShotDialog() / openNewZoneDialog()
        -> CameraSystemDialog + ShotSelector
Create
    -> callbacks.onCreateShot(name) / onCreateZone(name, shotName)
        -> model:createShot / createZone
            -> refresh()
```

- Nenhuma mudanca em `CameraSystemData`, no formato JSON ou no runtime.
- Nenhuma mudanca no ciclo materializar/persistir/destruir parts.
- O dialog trabalha com o snapshot do ultimo `refresh`; o model recomputa
  ordem, defaults e validacao semanticamente.

## Tratamento De Erros

- Validacao local no dialog: nome vazio, nome duplicado e ausencia de shot
  mantem `Create` desabilitado e mostram erro inline quando aplicavel.
- Falha inesperada do model (por exemplo, shot removido no Explorer enquanto o
  dialog estava aberto) segue o padrao atual: `run()` captura com `pcall`,
  emite `warn` e o status do painel mostra o erro apos o `refresh`.
- Os asserts existentes do model continuam sendo a barreira final.
- Modulos novos e alterados permanecem `--!strict`, sem `--!nocheck`.

## Verificacao

- `selene --config selene.roblox.toml plugin`
- `rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json`
- `rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json`
  seguido de `luau-lsp analyze` com as configuracoes do README.
- `scripts/plugin-build.sh` para instalar a build no Studio.

Checklist manual no Studio:

- `New Shot`: modal abre com foco; nome vazio e duplicado bloqueiam; criar
  seleciona o shot e fecha; Esc e Cancel descartam.
- `New Zone`: modal abre com default pre-selecionado; busca filtra; opcao sem
  resultado mostra `No shots found`; clique-fora/Esc fecham sem trocar a
  selecao; criar associa o shot escolhido.
- Sem shots: `New Zone` desabilitado.
- Painel estreito e redimensionado: card e dropdown sem overflow.
- Undo/Redo das criacoes; persistencia ao desativar e reativar o editor.
- Demais comandos do painel inalterados.

## Fora De Escopo

- `Assign Shot` continua com o campo de texto `ShotId`.
- Navegacao por setas/teclado na lista do seletor.
- Busca no painel principal (shots/zonas) e edicao de nome depois de criado.
- Internacionalizacao ou troca de idioma da interface.
- Janela flutuante sobre o viewport ou modal em `ScreenGui` separado.
- Mudancas no formato persistido, no runtime, no preview ou na validacao
  semantica.
