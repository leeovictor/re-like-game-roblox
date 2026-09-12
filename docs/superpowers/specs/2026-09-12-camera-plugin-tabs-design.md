# Camera System Plugin: Abas de Shots e Zones com Paineis de Edicao

Esta spec complementa `2026-08-17-camera-system-plugin-design.md`,
`2026-09-12-camera-system-persistence-design.md` e
`2026-09-12-camera-plugin-create-flows-design.md`. Ela reorganiza a interface
do painel em abas, move as acoes para paineis de edicao contextuais e adiciona
rename e delete de shots e zonas. O formato persistido, o runtime, o preview,
os modais de criacao e o ciclo materializar/persistir/destruir parts
permanecem inalterados.

## Objetivo

- Duas abas, `Shots` e `Zones`. Cada aba exibe sua listagem, seu botao de
  criacao e seu painel de edicao.
- O painel de edicao fica fixo no rodape do dock e aparece quando ha um item
  selecionado na aba ativa.
- Os campos nome e FOV (shot), e nome e shot atribuido (zona), formam um
  rascunho aplicado por `Save Changes`; as demais acoes sao imediatas.
- Rename e delete passam a existir para shots e zonas.

## Decisoes

- Abas `Shots` e `Zones`, com `Shots` ativa por padrao.
- Cada aba guarda sua propria selecao. Selecionar um Part de shot ou zona no
  Studio ativa a aba correspondente; selecionar qualquer outro objeto ou
  esvaziar a selecao fecha os dois paineis.
- Trocar de aba fecha o painel da aba anterior e descarta seu rascunho. A
  selecao daquela aba e mantida, entao voltar reabre o painel com os valores
  atuais do Part.
- `Save Changes` habilita apenas quando ha alteracoes pendentes e os campos sao
  validos. `Close`, trocar de item ou de aba, ou selecionar outro objeto
  descartam o rascunho silenciosamente, sem modal de confirmacao. Ao reabrir o
  painel, os campos voltam aos valores atuais do Part.
- Acoes de camera (`Apply To Camera`, `Capture Camera`, `Set Default`) e de
  ordenacao (`Move Up`, `Move Down`) continuam imediatas.
- O shot de uma zona e escolhido por um dropdown pesquisavel no painel da zona
  (reuso do `ShotSelector`), sem selecao cruzada entre abas.
- Delete de shot e bloqueado enquanto existir zona com `ShotId` igual ao nome
  do shot; a mensagem lista as zonas. Delete de zona e sempre permitido. Nos
  dois casos permitidos ha modal de confirmacao.
- Ao deletar o shot marcado como `DefaultShotId`, o primeiro shot restante
  assume o default. Sem shots restantes, o atributo e removido e o sistema
  vazio passa a ser valido.
- Textos da interface continuam em ingles, consistentes com o restante do
  plugin (`Shots`, `Zones`, `New Shot`, `New Zone`, `Save Changes`, `Close`,
  `Delete`, `Shot Name`, `Field of View`, `Zone Name`, `Shot`).
- O `CameraSystemModel` segue como barreira final de validacao; os paineis
  fazem apenas validacao local antecipada.

## Componentes

Todos os modulos ficam em `plugin/camera/` com `--!strict`. Nenhum token novo
de `CameraSystemStyle` e necessario: os componentes reusam `background`,
`panel`, `input`, `item`, `accent`, `errorText`, `buttonHeight`,
`inputHeight`, `cornerRadius`, `fieldSpacing`, `labelSpacing`, `textSize` e
`smallTextSize`.

### Layout do widget

`CameraSystemWidget` deixa de ser um `ScrollingFrame` unico e passa a ser um
`Frame` com `UIListLayout` vertical, nesta ordem:

1. `TabBar`: `Frame` com altura `buttonHeight`; dois `TextButton` de 50% da
   largura, `Shots` e `Zones`. A aba ativa usa `accent` como fundo; a inativa
   usa `panel`.
2. `ContentArea`: `Frame` com `UIFlexItem` (`FlexMode.Fill`) para absorver a
   altura restante. Contem dois `ScrollingFrame` de `Size 1,1` (`ShotsContent`
   e `ZonesContent`); apenas o da aba ativa fica visivel. Cada um tem
   `UIPadding`, `UIListLayout`, o botao de criacao no topo e as linhas abaixo.
   Sem itens, exibe label muted `No shots yet` ou `No zones yet`.
3. `Status`: `TextLabel` de altura automatica com `Valid camera system` ou a
   lista de erros de `model:validate()`, como hoje.
4. `ShotEditPanel` e `ZoneEditPanel`: `AutomaticSize.Y`, somente o painel da
   aba ativa pode estar visivel, e apenas quando houver selecao valida.

As linhas continuam `TextButton` de 24px de altura com fundo `panel` e
`accent` quando selecionadas. O texto segue o formato atual:
`Shot: <nome> (default)` e `Zone: <nome> -> <ShotId ou <unassigned>>`.

### ShotEditPanel.luau (novo)

Painel de edicao de shot na aba `Shots`. Estrutura interna, de cima para
baixo:

1. Linha de acoes: `Apply To Camera`, `Capture Camera`, `Set Default`.
2. `TextInput` `Shot Name` com label.
3. `TextInput` `Field of View` (numerico).
4. Label de erro, oculta quando nao ha erro.
5. Rodape: `Delete` a esquerda, `Close` e `Save Changes` a direita.

API publica:

```luau
ShotEditPanel.new(parent: Instance, callbacks: Callbacks): Panel
ShotEditPanel.show(self: Panel, shot: BasePart): ()   -- reseta o rascunho e exibe
ShotEditPanel.update(self: Panel, shot: BasePart): () -- sincroniza campos limpos e botoes
ShotEditPanel.hide(self: Panel): ()
ShotEditPanel.setError(self: Panel, message: string?): ()
ShotEditPanel.getEditingPart(self: Panel): BasePart?
ShotEditPanel.destroy(self: Panel): ()
```

`Callbacks`:

```luau
type Callbacks = {
	onApply: (BasePart) -> (),
	onCapture: (BasePart) -> (),
	onSetDefault: (BasePart) -> (),
	onDelete: (BasePart) -> (),
	onSave: (BasePart, string, number) -> (),
	onClose: () -> (),
}
```

Regras de rascunho e validacao:

- `show` guarda o Part editado, preenche os campos com `Name` e `FieldOfView`,
  limpa o erro e torna o painel visivel.
- `update` so age quando o Part e o mesmo de `show`; atualiza o campo de nome
  quando ele nao esta dirty, atualiza o FOV quando nao esta dirty e recalcula
  o estado de `Save Changes`. Nao sobrescreve campos dirty e nao limpa o erro.
- Dirty e calculado comparando o texto trimado do nome e o texto do FOV com os
  valores atuais do Part. `Save Changes` fica habilitado somente quando dirty e
  valido, e usa `accent` como fundo; caso contrario fica com transparencia de
  botao desabilitado.
- Erros locais: nome vazio (`Shot name is required`), nome duplicado entre os
  shots do snapshot exceto o proprio shot editado (`Shot "<nome>" already
  exists`) e FOV nao numerico ou fora de 1-120 (`Field of View must be between
  1 and 120`).
- `onSave` recebe o nome trimado como string e o FOV como number.
- As acoes e `Delete` ficam sempre habilitados enquanto o painel esta visivel;
  a checagem de referencia e feita pelo widget.
- `Close` dispara `onClose`; o widget limpa a selecao de shot e esconde o
  painel.

### ZoneEditPanel.luau (novo)

Painel de edicao de zona na aba `Zones`. Estrutura interna, de cima para
baixo:

1. Linha de acoes: `Move Up`, `Move Down`.
2. `TextInput` `Zone Name`.
3. Label `Shot` e `ShotSelector` configurado para abrir o popup para cima.
4. Label de erro.
5. Rodape: `Delete` a esquerda, `Close` e `Save Changes` a direita.

API publica:

```luau
ZoneEditPanel.new(parent: Instance, callbacks: Callbacks): Panel
ZoneEditPanel.show(
	self: Panel,
	zone: BasePart,
	shotNames: { string },
	defaultShotId: string?
): ()
ZoneEditPanel.update(
	self: Panel,
	zone: BasePart,
	shotNames: { string },
	defaultShotId: string?,
	canMoveUp: boolean,
	canMoveDown: boolean
): ()
ZoneEditPanel.hide(self: Panel): ()
ZoneEditPanel.setError(self: Panel, message: string?): ()
ZoneEditPanel.getEditingPart(self: Panel): BasePart?
ZoneEditPanel.destroy(self: Panel): ()
```

`Callbacks`:

```luau
type Callbacks = {
	onMoveUp: (BasePart) -> (),
	onMoveDown: (BasePart) -> (),
	onDelete: (BasePart) -> (),
	onSave: (BasePart, string, string) -> (),
	onClose: () -> (),
}
```

Regras de rascunho e validacao:

- `show` guarda a zona, preenche o nome, seleciona no dropdown o `ShotId`
  atual, limpa o erro e exibe.
- `update` so age quando a zona e a mesma de `show`; sincroniza as opcoes do
  dropdown preservando a selecao do rascunho quando ela ainda existe, atualiza
  o campo de nome quando limpo e ajusta `Move Up`/`Move Down` conforme
  `canMoveUp`/`canMoveDown`. Nao sobrescreve campos dirty e nao limpa o erro.
- Dirty e calculado comparando nome trimado e shot selecionado com `Name` e
  `ShotId` atuais da zona.
- Erros locais: nome vazio (`Zone name is required`), nome duplicado entre as
  zonas do snapshot exceto a propria zona editada (`Zone "<nome>" already
  exists`) e ausencia de shot selecionado (`Select a shot`).
- `onSave` recebe o nome trimado e o nome do shot selecionado.
- `Delete`/`Close` seguem o mesmo contrato do painel de shot.

### ShotSelector.luau (alterado)

- `new` ganha um terceiro parametro opcional de opcoes:

```luau
ShotSelector.new(
	parent: Instance,
	onChanged: (() -> ())?,
	options: { openUpward: boolean? }?
): Selector
```

  Com `openUpward`, o popup ancora acima do campo (`AnchorPoint` `0,1` e
  posicao `0,-4` acima) em vez de abaixo. A deteccao de clique fora continua
  baseada nas posicoes absolutas do campo e do popup.

- A selecao inicial deixa de ser implicitamente o default. `setOptions` passa
  a receber a selecao e o destaque separadamente:

```luau
ShotSelector.setOptions(
	self: Selector,
	names: { string },
	selectedName: string?,
	defaultName: string?
): ()
```

  `selectedName` define a selecao inicial; `defaultName` apenas marca a opcao
  com `(default)` na lista. Os fluxos existentes passam a chamar
  `setOptions(names, defaultShotId, defaultShotId)`.

- Ganha `syncOptions`, que atualiza opcoes e destaque sem resetar a selecao
  atual (preserva `selected` quando o nome ainda existe na lista e re-renderiza
  se o popup estiver aberto):

```luau
ShotSelector.syncOptions(
	self: Selector,
	names: { string },
	defaultName: string?
): ()
```

### CameraSystemDialog.luau (alterado)

`new` ganha um quarto parametro opcional com os textos do rodape:

```luau
CameraSystemDialog.new(
	gui: DockWidgetPluginGui,
	title: string,
	callbacks: Callbacks,
	options: { confirmText: string?, cancelText: string? }?
): Dialog
```

Sem `options`, os textos continuam `Cancel` e `Create`, preservando os modais
de criacao. O modal de delete usa `confirmText = "Delete"` e
`cancelText = "Cancel"`.

### CameraSystemWidget.luau (alterado)

Vira o orquestrador das abas, listas, status e paineis.

Tipo e campos principais:

```luau
export type TabName = "shots" | "zones"

export type Widget = {
	gui: DockWidgetPluginGui,
	activeTab: TabName,
	shotSelection: BasePart?,
	zoneSelection: BasePart?,
	-- listas, linhas, status, paineis, dialog e snapshot interno
}
```

`Callbacks` deixa de ter `onAssignShot` e `onFieldOfView` e passa a ser:

```luau
type Callbacks = {
	onCreateShot: (string, number) -> (),
	onCreateZone: (string, string) -> (),
	onCaptureCamera: (BasePart) -> (),
	onApplyCamera: (BasePart) -> (),
	onSetDefault: (BasePart) -> (),
	onMoveZone: (BasePart, number) -> (),
	onSaveShot: (BasePart, string, number) -> (),
	onSaveZone: (BasePart, string, string) -> (),
	onDeleteShot: (BasePart) -> (),
	onDeleteZone: (BasePart) -> (),
	onSelect: (Instance) -> (),
	classifySelection: (Instance) -> string?,
	getDefaultFieldOfView: () -> number,
}
```

API publica (mantida):

```luau
CameraSystemWidget.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Widget
CameraSystemWidget.refresh(
	self: Widget,
	shots: { BasePart },
	zones: { BasePart },
	defaultShotId: string?,
	errors: { string }
): ()
CameraSystemWidget.setSelection(self: Widget, instance: Instance?): ()
CameraSystemWidget.clearSelection(self: Widget): ()
CameraSystemWidget.closeDialog(self: Widget): ()
CameraSystemWidget.openNewShotDialog(self: Widget): ()
CameraSystemWidget.openNewZoneDialog(self: Widget): ()
CameraSystemWidget.destroy(self: Widget): ()
```

Comportamento:

- `refresh` guarda o snapshot, repovoa as linhas das duas abas, atualiza o
  estado de `New Zone` (`#shots > 0`), atualiza o status e valida as selecoes:
  selecao cujo Part nao esta mais na lista e limpa e o painel correspondente e
  escondido. O painel da aba ativa chama `show` apenas quando o Part
  selecionado difere do Part em edicao; caso contrario chama `update`,
  preservando o rascunho.
- `setSelection` classifica o objeto; shot ativa a aba `Shots`, seleciona e
  mostra o painel; zona ativa a aba `Zones`, seleciona e mostra o painel;
  `nil` ou objeto fora do CameraSystem limpa as duas selecoes e esconde os dois
  paineis, mantendo a aba ativa. Se o objeto classificado for o mesmo Part ja
  aberto no painel, o widget chama `update` em vez de `show`, para nao resetar
  o rascunho.
- Clique em linha define a selecao do widget e chama `callbacks.onSelect(part)`
  (que atualiza a `Selection` do Studio e dispara `SelectionChanged`).
- `clearSelection` esconde os dois paineis, descarta rascunhos e limpa as duas
  selecoes; usado no deactivate.
- `Delete` de shot: o widget verifica no snapshot se alguma zona tem
  `ShotId == shot.Name`. Se houver, mostra erro inline no painel
  (`Cannot delete: referenced by zones "a", "b"`) sem abrir modal. Caso
  contrario abre `CameraSystemDialog` com titulo `Delete Shot`, mensagem
  `Delete shot "<nome>"?`, `Delete`/`Cancel`; confirmar chama
  `callbacks.onDeleteShot(shot)`.
- `Delete` de zona: sempre abre o modal (`Delete zone "<nome>"?`) e confirmar
  chama `callbacks.onDeleteZone(zone)`.
- Criacao e delete compartilham o mesmo slot de dialog; abrir um fecha o outro,
  como hoje.

### CameraSystemModel.luau (alterado)

Adicoes:

```luau
CameraSystemModel.renameShot(self, shot: Part, newName: string): ()
CameraSystemModel.renameZone(self, zone: Part, newName: string): ()
CameraSystemModel.deleteShot(self, shot: Part): ()
CameraSystemModel.deleteZone(self, zone: Part): ()
```

- `renameShot`: exige nome nao-vazio; colisao apenas com shot de nome
  diferente; atualiza `ShotId` das zonas que referenciavam o nome antigo e o
  `DefaultShotId` quando apontava para o shot; renomeia o Part. Waypoints
  Begin/End.
- `renameZone`: exige nome nao-vazio e sem colisao em `Zones`; renomeia o Part.
  Waypoints Begin/End.
- `deleteShot`: exige shot pertencente a `CameraSystem.Shots`; erra se alguma
  zona tem `ShotId` igual ao nome do shot; se `DefaultShotId` apontava para
  ele, promove o primeiro shot restante na ordem de `listShots` (alfabetica)
  apos a remocao, ou remove o atributo quando nao sobra nenhum; destroi o
  Part. Waypoints Begin/End.
- `deleteZone`: exige zona pertencente a `CameraSystem.Zones`; destroi o Part.
  Waypoints Begin/End.
- `setFieldOfView` e `assignShot` existentes sao reusados pelo Save e
  permanecem na API.
- `validate`: a exigencia de `DefaultShotId` valido passa a valer somente
  quando existe pelo menos um shot. As demais validacoes (zonas com `ShotId`
  existente, `Order` unico e inteiro, campos de FOV) continuam iguais.
- `captureConfig`, `writeData`, `materialize`, `destroyParts`, `listShots` e
  `listZones` nao mudam.

### init.plugin.luau (alterado)

Os callbacks passam a receber o Part em vez de o init ler `widget.shotSelection`
e `widget.zoneSelection`:

- `onCaptureCamera(shot)`, `onApplyCamera(shot)` e `onSetDefault(shot)` validam
  o Part pertencente a `CameraSystem.Shots` e chamam a operacao existente.
- `onSaveShot(shot, name, fieldOfView)`: dentro de um unico `run`, chama
  `renameShot` quando o nome mudou e `setFieldOfView` quando o FOV mudou.
- `onSaveZone(zone, name, shotName)`: resolve o shot por nome em
  `CameraSystem.Shots` (assert se nao existir); dentro de um unico `run`,
  chama `renameZone` quando o nome mudou e `assignShot` quando o shot mudou.
- `onMoveZone(zone, delta)`, `onDeleteShot(shot)` e `onDeleteZone(zone)`
  chamam as operacoes correspondentes do model.
- `onCreateShot`, `onCreateZone`, `onSelect`, `classifySelection` e
  `getDefaultFieldOfView` continuam iguais em contrato.
- `run`, `refresh`, persistencia, materialize e o ciclo de
  ativacao/desativacao permanecem como estao.

## Fluxo De Dados

```text
refresh() (init)
    -> widget.refresh(shots, zones, defaultShotId, errors)   -- snapshot
clique em linha ou selecao no Studio
    -> callbacks.onSelect(part) -> Selection:Set
    -> SelectionChanged -> widget:setSelection(part)
        -> ativa aba, atualiza selecao e mostra o painel
Save Shot
    -> callbacks.onSaveShot(shot, name, fov)
        -> run: model:renameShot (se mudou) + model:setFieldOfView (se mudou)
            -> refresh()
Save Zone
    -> callbacks.onSaveZone(zone, name, shotName)
        -> init resolve shot -> run: model:renameZone + model:assignShot
            -> refresh()
Delete (com modal de confirmacao)
    -> callbacks.onDeleteShot/onDeleteZone -> run(model) -> refresh()
Move Up/Down
    -> callbacks.onMoveZone(zone, delta) -> run(model) -> refresh()
```

- Nenhuma mudanca em `CameraSystemData`, no formato JSON ou no runtime.
- Nenhuma mudanca no ciclo materializar/persistir/destruir parts.
- Os paineis trabalham com o snapshot do ultimo `refresh`; o model recomputa
  colisoes, referencias e validacao semanticamente.

## Tratamento De Erros

- Validacao local nos paineis: nome vazio, nome duplicado, FOV invalido e shot
  ausente mantem `Save Changes` desabilitado e mostram erro inline.
- Delete de shot referenciado mostra erro inline com a lista de zonas; o modal
  so abre para deletes permitidos.
- Falha inesperada do model (Part removido no Explorer, colisao criada depois
  do snapshot) segue o padrao atual: `run()` captura com `pcall`, emite `warn`
  e o status mostra o erro apos o `refresh`. O rascunho dirty e preservado no
  painel, porque `update` nao sobrescreve campos dirty.
- Rename com sucesso mas falha posterior no mesmo Save (caso raro, ex.: shot da
  zona removido entre a resolucao e o `assignShot`) deixa a alteracao parcial e
  o status reporta a falha; nao ha rollback.
- Modulos novos e alterados permanecem `--!strict`, sem `--!nocheck`.

## Verificacao

```bash
selene --config selene.roblox.toml plugin
rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json
luau-lsp analyze \
  --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap /tmp/plugin-sourcemap.json \
  plugin
scripts/plugin-build.sh
```

Checklist manual no Studio:

- Abas: `Shots` ativa por padrao; alternar mantem a selecao de cada aba e
  descarta o rascunho da aba deixada; abas vazias mostram o label muted.
- Selecao: clique na linha e selecao no Studio abrem o painel correto e ativam
  a aba; selecionar outro objeto fecha os paineis; Part removido no Explorer
  fecha o painel apos o refresh.
- Shot: editar nome e FOV habilita `Save Changes`; salvar aplica; rename
  reflete nas linhas das zonas e no `(default)`; `Close` descarta; validacoes
  locais bloqueiam.
- Zona: `Save Changes` aplica rename e troca de shot; dropdown abre para cima,
  filtra por busca e marca o default; `Move Up`/`Move Down` desabilitam nas
  extremidades.
- Delete: shot referenciado mostra erro inline sem modal; shot livre abre o
  modal e remove; deletar o default promove o primeiro restante; deletar a
  ultima shot limpa o default e o status fica valido; delete de zona sempre
  permite.
- Undo/redo de rename, delete e movimentacao; persistencia ao desativar e
  reativar o editor; dock estreito e redimensionado sem overflow.
- Modais de criacao existentes inalterados.

## Fora De Escopo

- Mudancas no formato persistido, no runtime, no preview ou na validacao
  semantica fora do descrito.
- Busca nas listas do painel, reordenacao de shots, drag & drop e selecao
  multipla.
- Delete de shot em cascata sobre zonas e reatribuicao automatica de zonas.
- Internacionalizacao ou troca de idioma da interface.
- Mudancas visuais alem do necessario para as abas e paineis.
