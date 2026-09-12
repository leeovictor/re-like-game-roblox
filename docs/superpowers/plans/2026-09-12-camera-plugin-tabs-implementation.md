# Camera Plugin Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganizar o painel do plugin Camera System em abas `Shots` e `Zones`, com paineis de edicao fixos no rodape, rascunho salvo por `Save Changes`, rename e delete de shots/zonas, conforme `docs/superpowers/specs/2026-09-12-camera-plugin-tabs-design.md`.

**Architecture:** Dois componentes de painel novos (`ShotEditPanel` e `ZoneEditPanel`) no padrao imperativo dos modulos existentes (`.new(parent, callbacks)` com metatable). O `CameraSystemWidget` vira orquestrador das abas, listas, status e paineis. O `CameraSystemModel` ganha `renameShot`, `renameZone`, `deleteShot` e `deleteZone`, e `validate` passa a aceitar sistema vazio. `ShotSelector` ganha popup para cima e seleção explicita; `CameraSystemDialog` ganha labels de confirmacao para o modal de delete.

**Tech Stack:** Luau `--!strict` em plugin Roblox montado por Rojo (`plugin.project.json`), UI construida com `Instance.new` e `DockWidgetPluginGui`. Sem framework de testes no plugin: a verificacao e lint Selene, typecheck `luau-lsp` com sourcemap do plugin, build Rojo e checklist manual no Studio.

## Global Constraints

- Nao faca commits ao escrever nem ao implementar este plano (`AGENTS.md` do repositorio). Commit so com pedido explicito do usuario. Nao existem passos de commit neste plano.
- Todo modulo do plugin usa `--!strict`; nao use `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Modulos novos ficam em `plugin/camera/` e sao importados com `require(script.Parent.NomeDoModulo)`.
- O plugin e construido por `plugin.project.json`; `src/shared/camera/CameraSystemData.luau` entra como `script.Parent.Parent.CameraSystemData`. Nao altere esse mapeamento.
- Textos de UI em ingles: `Shots`, `Zones`, `New Shot`, `New Zone`, `Apply To Camera`, `Capture Camera`, `Set Default`, `Move Up`, `Move Down`, `Delete`, `Close`, `Save Changes`, `Shot Name`, `Field of View`, `Zone Name`, `Shot`, `No shots yet`, `No zones yet`, `Cannot delete: referenced by zones ...`, `Valid camera system`, erros `Shot name is required`, `Zone name is required`, `Shot "<nome>" already exists`, `Zone "<nome>" already exists`, `Field of View must be between 1 and 120`, `Select a shot`.
- Cores de UI (`Color3.fromRGB`/`Color3.new`) ficam exclusivamente em `plugin/camera/CameraSystemStyle.luau`; `CameraSystemPreview` continua usando `Color3.fromHSV` para os markers, fora do escopo.
- O formato persistido (`CameraSystemData`), o runtime, o preview e o ciclo materializar/persistir/destruir parts nao mudam.
- `UIFlexItem` com `Enum.UIFlexMode.Fill` e suportado pelas definicoes versionadas (`typecheck/globalTypes.None.d.luau:15397`).
- Comandos de verificacao (executar de `/home/leonardo/Projects/dungeon-game-canve`):

```bash
selene --config selene.roblox.toml plugin

rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap /tmp/plugin-sourcemap.json \
  --formatter gnu \
  plugin

rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

- A ordem do typecheck e `rojo sourcemap` antes de `luau-lsp analyze`.
- Nao existe teste automatizado no plugin (`TestEZ` foi removido do repositorio). Nenhuma tarefa pode ser declarada concluida sem rodar os comandos acima; a Task 7 contem o checklist manual no Studio.

---

### Task 1: Operacoes de rename e delete no `CameraSystemModel`

**Files:**
- Modify: `plugin/camera/CameraSystemModel.luau` (funcoes novas depois de `setDefaultShot`, por volta da linha 262; ajuste em `validate`, por volta da linha 528)

**Interfaces:**
- Consumes: nada.
- Produces: `CameraSystemModel.renameShot(self, shot: Part, newName: string): ()`, `CameraSystemModel.renameZone(self, zone: Part, newName: string): ()`, `CameraSystemModel.deleteShot(self, shot: Part): ()`, `CameraSystemModel.deleteZone(self, zone: Part): ()`. A Task 6 consome essas funcoes em `init.plugin.luau`. `validate` passa a aceitar sistema sem shots.

- [ ] **Step 1: Adicionar as quatro operacoes**

Em `plugin/camera/CameraSystemModel.luau`, insira os quatro blocos abaixo logo depois da funcao `setDefaultShot` (que termina antes de `createZone`):

```luau
function CameraSystemModel.renameShot(self: Model, shot: Part, newName: string): ()
	local ownedShot = self:_ownedShot(shot)
	local shotName = requireNonEmptyName(newName)
	local hierarchy = self:_hierarchy()
	local existing = hierarchy.shots:FindFirstChild(shotName)
	assert(existing == nil or existing == ownedShot, string.format('Shot "%s" already exists', shotName))

	local previousName = ownedShot.Name
	setWaypoint(self.changeHistoryService, "Camera System: Begin rename shot")
	ownedShot.Name = shotName
	for _, child in hierarchy.zones:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(SHOT_ID) == previousName then
			child:SetAttribute(SHOT_ID, shotName)
		end
	end
	if hierarchy.root:GetAttribute(DEFAULT_SHOT_ID) == previousName then
		hierarchy.root:SetAttribute(DEFAULT_SHOT_ID, shotName)
	end
	setWaypoint(self.changeHistoryService, "Camera System: End rename shot")
end

function CameraSystemModel.renameZone(self: Model, zone: Part, newName: string): ()
	local ownedZone = self:_ownedZone(zone)
	local zoneName = requireNonEmptyName(newName)
	local hierarchy = self:_hierarchy()
	local existing = hierarchy.zones:FindFirstChild(zoneName)
	assert(existing == nil or existing == ownedZone, string.format('Zone "%s" already exists', zoneName))

	setWaypoint(self.changeHistoryService, "Camera System: Begin rename zone")
	ownedZone.Name = zoneName
	setWaypoint(self.changeHistoryService, "Camera System: End rename zone")
end

function CameraSystemModel.deleteShot(self: Model, shot: Part): ()
	local ownedShot = self:_ownedShot(shot)
	local hierarchy = self:_hierarchy()
	local referencing: { string } = {}
	for _, child in hierarchy.zones:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(SHOT_ID) == ownedShot.Name then
			table.insert(referencing, child.Name)
		end
	end
	assert(
		#referencing == 0,
		string.format('Shot "%s" is referenced by zones: %s', ownedShot.Name, table.concat(referencing, ", "))
	)

	local wasDefault = hierarchy.root:GetAttribute(DEFAULT_SHOT_ID) == ownedShot.Name
	setWaypoint(self.changeHistoryService, "Camera System: Begin delete shot")
	ownedShot:Destroy()
	if wasDefault then
		local remaining = self:listShots()
		if remaining[1] ~= nil then
			hierarchy.root:SetAttribute(DEFAULT_SHOT_ID, remaining[1].Name)
		else
			hierarchy.root:SetAttribute(DEFAULT_SHOT_ID, nil)
		end
	end
	setWaypoint(self.changeHistoryService, "Camera System: End delete shot")
end

function CameraSystemModel.deleteZone(self: Model, zone: Part): ()
	local ownedZone = self:_ownedZone(zone)
	setWaypoint(self.changeHistoryService, "Camera System: Begin delete zone")
	ownedZone:Destroy()
	setWaypoint(self.changeHistoryService, "Camera System: End delete zone")
end
```

- [ ] **Step 2: Aceitar sistema sem shots em `validate`**

Substitua este trecho:

```luau
	local defaultShotId = rootFolder:GetAttribute(DEFAULT_SHOT_ID)
	local seenOrders: { [number]: BasePart? } = {}
	if type(defaultShotId) ~= "string" or defaultShotId == "" or shots[defaultShotId] == nil then
		add("CameraSystem DefaultShotId must reference an existing shot")
	end
```

por:

```luau
	local defaultShotId = rootFolder:GetAttribute(DEFAULT_SHOT_ID)
	local seenOrders: { [number]: BasePart? } = {}
	if next(shots) ~= nil and (type(defaultShotId) ~= "string" or defaultShotId == "" or shots[defaultShotId] == nil) then
		add("CameraSystem DefaultShotId must reference an existing shot")
	end
```

- [ ] **Step 3: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado em `/tmp/camera-system-plugin.rbxmx`.

---

### Task 2: `ShotSelector` com seleção explicita e popup para cima

**Files:**
- Modify: `plugin/camera/ShotSelector.luau` (arquivo inteiro)
- Modify: `plugin/camera/CameraSystemWidget.luau` (uma linha em `openNewZoneDialog`)

**Interfaces:**
- Consumes: `CameraSystemStyle`.
- Produces: `ShotSelector.new(parent: Instance, onChanged: (() -> ())?, options: { openUpward: boolean? }?): Selector`, `ShotSelector.setOptions(self, names: { string }, selectedName: string?, defaultName: string?)`, `ShotSelector.syncOptions(self, names: { string }, defaultName: string?)`; `selected` continua exposto em `getSelected`. As Tasks 5 e 6 consomem.

- [ ] **Step 1: Substituir `plugin/camera/ShotSelector.luau` pelo conteudo final**

```luau
--!strict

local UserInputService = game:GetService("UserInputService")

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local TextInput = require(script.Parent.TextInput)

local ShotSelector = {}
ShotSelector.__index = ShotSelector

export type Options = {
	openUpward: boolean?,
}

export type Selector = typeof(setmetatable(
	{} :: {
		root: Frame,
		fieldLabel: TextLabel,
		fieldStroke: UIStroke,
		popup: Frame,
		search: TextBox,
		list: ScrollingFrame,
		options: { string },
		selected: string?,
		defaultName: string?,
		openUpward: boolean,
		onChanged: (() -> ())?,
		inputConnection: RBXScriptConnection?,
		destroyed: boolean,
	},
	ShotSelector
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function isPointInside(frame: GuiObject, position: Vector2): boolean
	local topLeft = frame.AbsolutePosition
	local bottomRight = topLeft + frame.AbsoluteSize
	return position.X >= topLeft.X
		and position.X <= bottomRight.X
		and position.Y >= topLeft.Y
		and position.Y <= bottomRight.Y
end

function ShotSelector.new(parent: Instance, onChanged: (() -> ())?, options: Options?): Selector
	local root = make("Frame", parent) :: Frame
	root.Name = "ShotSelector"
	root.Size = UDim2.new(1, 0, 0, CameraSystemStyle.inputHeight)
	root.BackgroundTransparency = 1

	local field = make("TextButton", root) :: TextButton
	field.Name = "Field"
	field.Size = UDim2.fromScale(1, 1)
	field.BackgroundColor3 = CameraSystemStyle.input
	field.BorderSizePixel = 0
	field.Text = ""
	field.AutoButtonColor = true
	local fieldCorner = make("UICorner", field) :: UICorner
	fieldCorner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
	local fieldStroke = make("UIStroke", field) :: UIStroke
	fieldStroke.Color = CameraSystemStyle.outline
	fieldStroke.Thickness = 1
	fieldStroke.Transparency = CameraSystemStyle.outlineTransparency

	local fieldLabel = make("TextLabel", field) :: TextLabel
	fieldLabel.Name = "Value"
	fieldLabel.Position = UDim2.new(0, 6, 0, 0)
	fieldLabel.Size = UDim2.new(1, -26, 1, 0)
	fieldLabel.BackgroundTransparency = 1
	fieldLabel.TextColor3 = CameraSystemStyle.mutedText
	fieldLabel.TextSize = CameraSystemStyle.textSize
	fieldLabel.TextXAlignment = Enum.TextXAlignment.Left
	fieldLabel.TextTruncate = Enum.TextTruncate.AtEnd
	fieldLabel.Text = "Select a shot"

	local chevron = make("TextLabel", field) :: TextLabel
	chevron.Name = "Chevron"
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.fromScale(1, 0.5)
	chevron.Size = UDim2.new(0, 20, 1, 0)
	chevron.BackgroundTransparency = 1
	chevron.TextColor3 = CameraSystemStyle.mutedText
	chevron.TextSize = CameraSystemStyle.smallTextSize
	chevron.Text = "v"

	local popup = make("Frame", root) :: Frame
	popup.Name = "Popup"
	popup.Size = UDim2.new(1, 0, 0, 0)
	popup.AutomaticSize = Enum.AutomaticSize.Y
	popup.BackgroundColor3 = CameraSystemStyle.popup
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.ZIndex = 50
	local popupCorner = make("UICorner", popup) :: UICorner
	popupCorner.CornerRadius = UDim.new(0, 6)
	local popupStroke = make("UIStroke", popup) :: UIStroke
	popupStroke.Color = CameraSystemStyle.outline
	popupStroke.Thickness = 1
	popupStroke.Transparency = CameraSystemStyle.outlineTransparency
	local popupPadding = make("UIPadding", popup) :: UIPadding
	popupPadding.PaddingTop = UDim.new(0, 4)
	popupPadding.PaddingBottom = UDim.new(0, 4)
	popupPadding.PaddingLeft = UDim.new(0, 4)
	popupPadding.PaddingRight = UDim.new(0, 4)
	local popupLayout = make("UIListLayout", popup) :: UIListLayout
	popupLayout.Padding = UDim.new(0, 4)
	popupLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local search = TextInput.new(popup, { placeholder = "Search shots", layoutOrder = 1 })
	search.Name = "Search"

	local list = make("ScrollingFrame", popup) :: ScrollingFrame
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 0, 0)
	list.CanvasSize = UDim2.new()
	list.ScrollingEnabled = true
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.ScrollBarThickness = 6
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.LayoutOrder = 2
	local listLayout = make("UIListLayout", list) :: UIListLayout
	listLayout.Padding = UDim.new(0, 2)

	local openUpward = options ~= nil and options.openUpward == true
	if openUpward then
		popup.AnchorPoint = Vector2.new(0, 1)
		popup.Position = UDim2.new(0, 0, 0, -4)
	else
		popup.Position = UDim2.new(0, 0, 1, 4)
	end

	local selector = setmetatable({
		root = root,
		fieldLabel = fieldLabel,
		fieldStroke = fieldStroke,
		popup = popup,
		search = search,
		list = list,
		options = {},
		selected = nil,
		defaultName = nil,
		openUpward = openUpward,
		onChanged = onChanged,
		inputConnection = nil,
		destroyed = false,
	}, ShotSelector) :: Selector

	field.Activated:Connect(function()
		if selector.popup.Visible then
			selector:close()
		else
			selector:open()
		end
	end)

	search:GetPropertyChangedSignal("Text"):Connect(function()
		selector:renderOptions(search.Text)
	end)

	root.Destroying:Connect(function()
		selector:close()
	end)

	return selector
end

function ShotSelector.updateFieldLabel(self: Selector)
	if self.selected == nil then
		self.fieldLabel.Text = "Select a shot"
		self.fieldLabel.TextColor3 = CameraSystemStyle.mutedText
	else
		self.fieldLabel.Text = self.selected
		self.fieldLabel.TextColor3 = CameraSystemStyle.text
	end
end

function ShotSelector.renderOptions(self: Selector, filter: string)
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local normalized = string.lower(filter)
	local matches = 0
	for index, name in self.options do
		if normalized == "" or string.find(string.lower(name), normalized, 1, true) ~= nil then
			matches += 1
			local button = make("TextButton", self.list) :: TextButton
			button.Name = "Option_" .. name
			button.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
			button.Text = if name == self.defaultName then name .. "  (default)" else name
			button.BackgroundColor3 = if name == self.selected then CameraSystemStyle.accent else CameraSystemStyle.item
			button.BorderSizePixel = 0
			button.TextColor3 = CameraSystemStyle.text
			button.TextSize = CameraSystemStyle.textSize
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.AutoButtonColor = true
			button.LayoutOrder = index
			local buttonCorner = make("UICorner", button) :: UICorner
			buttonCorner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
			local buttonStroke = make("UIStroke", button) :: UIStroke
			buttonStroke.Color = CameraSystemStyle.outline
			buttonStroke.Thickness = 1
			buttonStroke.Transparency = CameraSystemStyle.outlineTransparency
			local buttonPadding = make("UIPadding", button) :: UIPadding
			buttonPadding.PaddingLeft = UDim.new(0, 8)
			buttonPadding.PaddingRight = UDim.new(0, 8)
			button.Activated:Connect(function()
				self.selected = name
				self:updateFieldLabel()
				self:close()
				if self.onChanged ~= nil then
					self.onChanged()
				end
			end)
		end
	end

	if matches == 0 then
		local empty = make("TextLabel", self.list) :: TextLabel
		empty.Name = "Empty"
		empty.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
		empty.BackgroundTransparency = 1
		empty.TextColor3 = CameraSystemStyle.mutedText
		empty.TextSize = CameraSystemStyle.smallTextSize
		empty.Text = "No shots found"
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.LayoutOrder = 1
		local emptyPadding = make("UIPadding", empty) :: UIPadding
		emptyPadding.PaddingLeft = UDim.new(0, 8)
	end

	local itemCount = if matches == 0 then 1 else matches
	local contentHeight = itemCount * CameraSystemStyle.buttonHeight + (itemCount - 1) * 2
	self.list.CanvasSize = UDim2.fromOffset(0, contentHeight)
	self.list.Size = UDim2.new(1, 0, 0, math.min(contentHeight, CameraSystemStyle.listMaxHeight))
end

function ShotSelector.setOptions(self: Selector, names: { string }, selectedName: string?, defaultName: string?)
	local options: { string } = {}
	for _, name in names do
		table.insert(options, name)
	end
	self.options = options
	self.defaultName = defaultName
	self.selected = nil
	if selectedName ~= nil then
		for _, name in self.options do
			if name == selectedName then
				self.selected = selectedName
				break
			end
		end
	end
	self:updateFieldLabel()
	if self.popup.Visible then
		self:renderOptions(self.search.Text)
	end
end

function ShotSelector.syncOptions(self: Selector, names: { string }, defaultName: string?)
	local options: { string } = {}
	for _, name in names do
		table.insert(options, name)
	end
	self.options = options
	self.defaultName = defaultName
	if self.selected ~= nil and table.find(options, self.selected) == nil then
		self.selected = nil
	end
	self:updateFieldLabel()
	if self.popup.Visible then
		self:renderOptions(self.search.Text)
	end
end

function ShotSelector.getSelected(self: Selector): string?
	return self.selected
end

function ShotSelector.isOpen(self: Selector): boolean
	return self.popup.Visible
end

function ShotSelector.open(self: Selector)
	if self.destroyed or self.popup.Visible then
		return
	end
	self.search.Text = ""
	self:renderOptions("")
	self.popup.Visible = true
	self.fieldStroke.Color = CameraSystemStyle.accent
	self.search:CaptureFocus()
	self.inputConnection = UserInputService.InputBegan:Connect(function(input)
		if self.destroyed or not self.popup.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			self:close()
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		local insideField = isPointInside(self.root, position)
		local insidePopup = isPointInside(self.popup, position)
		if not insideField and not insidePopup then
			self:close()
		end
	end)
end

function ShotSelector.close(self: Selector)
	if not self.popup.Visible then
		return
	end
	self.popup.Visible = false
	self.fieldStroke.Color = CameraSystemStyle.outline
	if self.inputConnection ~= nil then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
end

function ShotSelector.destroy(self: Selector)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:close()
	self.root:Destroy()
end

return ShotSelector
```

- [ ] **Step 2: Ajustar o call site no widget atual**

Em `plugin/camera/CameraSystemWidget.luau`, dentro de `openNewZoneDialog`, substitua:

```luau
	shotSelector:setOptions(names, self.defaultShotId)
```

por:

```luau
	shotSelector:setOptions(names, self.defaultShotId, self.defaultShotId)
```

Esse ajuste mantem o modal de zona atual funcionando com a nova assinatura ate a Task 6 reescrever o widget.

- [ ] **Step 3: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

---

### Task 3: Labels configuraveis no `CameraSystemDialog`

**Files:**
- Modify: `plugin/camera/CameraSystemDialog.luau` (tipo `Callbacks`, assinatura de `new`, criacao dos botoes)

**Interfaces:**
- Consumes: `CameraSystemStyle`.
- Produces: `CameraSystemDialog.new(gui: DockWidgetPluginGui, title: string, callbacks: Callbacks, options: Options?): Dialog` com `Options = { confirmText: string?, cancelText: string? }`. Sem `options`, os textos continuam `Cancel` e `Create`. A Task 6 consome com `{ confirmText = "Delete", cancelText = "Cancel" }`.

- [ ] **Step 1: Adicionar o tipo `Options`**

Depois do bloco `export type Callbacks` (antes de `export type Dialog`), adicione:

```luau
export type Options = {
	confirmText: string?,
	cancelText: string?,
}
```

- [ ] **Step 2: Alterar a assinatura e os textos dos botoes**

Substitua:

```luau
function CameraSystemDialog.new(gui: DockWidgetPluginGui, title: string, callbacks: Callbacks): Dialog
```

por:

```luau
function CameraSystemDialog.new(gui: DockWidgetPluginGui, title: string, callbacks: Callbacks, options: Options?): Dialog
```

Logo depois dessa linha, adicione:

```luau
	local confirmText = if options ~= nil and options.confirmText ~= nil then options.confirmText else "Create"
	local cancelText = if options ~= nil and options.cancelText ~= nil then options.cancelText else "Cancel"
```

Substitua:

```luau
	cancelButton.Text = "Cancel"
```

por:

```luau
	cancelButton.Text = cancelText
```

Substitua:

```luau
	confirmButton.Text = "Create"
```

por:

```luau
	confirmButton.Text = confirmText
```

- [ ] **Step 3: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

---

### Task 4: `ShotEditPanel` (painel de edicao de shot)

**Files:**
- Create: `plugin/camera/ShotEditPanel.luau`

**Interfaces:**
- Consumes: `CameraSystemStyle`, `TextInput`.
- Produces: tipo `Panel` com campo publico `root: Frame`; API `ShotEditPanel.new(parent: Instance, callbacks: Callbacks): Panel`, `ShotEditPanel.show(self, shot: BasePart)`, `ShotEditPanel.update(self, shot: BasePart)`, `ShotEditPanel.hide(self)`, `ShotEditPanel.setError(self, message: string?)`, `ShotEditPanel.getEditingPart(self): BasePart?`, `ShotEditPanel.destroy(self)`. `Callbacks = { onApply, onCapture, onSetDefault, onDelete, onSave, onClose }`. A Task 6 consome.

- [ ] **Step 1: Criar `plugin/camera/ShotEditPanel.luau`**

```luau
--!strict

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local TextInput = require(script.Parent.TextInput)

local ShotEditPanel = {}
ShotEditPanel.__index = ShotEditPanel

export type Callbacks = {
	onApply: (BasePart) -> (),
	onCapture: (BasePart) -> (),
	onSetDefault: (BasePart) -> (),
	onDelete: (BasePart) -> (),
	onSave: (BasePart, string, number) -> (),
	onClose: () -> (),
}

export type Panel = typeof(setmetatable(
	{} :: {
		root: Frame,
		callbacks: Callbacks,
		nameInput: TextBox,
		fovInput: TextBox,
		errorLabel: TextLabel,
		saveButton: TextButton,
		closeButton: TextButton,
		deleteButton: TextButton,
		applyButton: TextButton,
		captureButton: TextButton,
		defaultButton: TextButton,
		editingPart: BasePart?,
		baseName: string,
		baseFov: string,
		syncing: boolean,
		destroyed: boolean,
	},
	ShotEditPanel
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function trim(value: string): string
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function styleButton(button: TextButton, background: Color3)
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.5
end

local function setFieldText(self: Panel, field: TextBox, text: string)
	self.syncing = true
	field.Text = text
	self.syncing = false
end

local function shotNameTaken(part: BasePart, name: string): boolean
	local parent = part.Parent
	if parent == nil then
		return false
	end
	for _, sibling in parent:GetChildren() do
		if sibling ~= part and sibling.Name == name then
			return true
		end
	end
	return false
end

local function isDirty(self: Panel): boolean
	return trim(self.nameInput.Text) ~= self.baseName or trim(self.fovInput.Text) ~= self.baseFov
end

local function evaluate(self: Panel, renderError: boolean)
	local part = self.editingPart
	if part == nil then
		return
	end
	local name = trim(self.nameInput.Text)
	local fovText = trim(self.fovInput.Text)
	local fov = tonumber(fovText)
	local error: string? = nil
	if name == "" then
		error = "Shot name is required"
	elseif shotNameTaken(part, name) then
		error = string.format('Shot "%s" already exists', name)
	elseif fov == nil or fov < 1 or fov > 120 then
		error = "Field of View must be between 1 and 120"
	end
	if renderError then
		self:setError(error)
	end
	setButtonEnabled(self.saveButton, error == nil and isDirty(self))
end

function ShotEditPanel.new(parent: Instance, callbacks: Callbacks): Panel
	local root = make("Frame", parent) :: Frame
	root.Name = "ShotEditPanel"
	root.Size = UDim2.new(1, 0, 0, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundColor3 = CameraSystemStyle.panel
	root.BorderSizePixel = 0
	root.Visible = false
	local corner = make("UICorner", root) :: UICorner
	corner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
	local padding = make("UIPadding", root) :: UIPadding
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	local layout = make("UIListLayout", root) :: UIListLayout
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local actions = make("Frame", root) :: Frame
	actions.Name = "Actions"
	actions.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight * 2 + 4)
	actions.BackgroundTransparency = 1
	actions.LayoutOrder = 1
	local actionsGrid = make("UIGridLayout", actions) :: UIGridLayout
	actionsGrid.CellSize = UDim2.new(0.5, -3, 0, CameraSystemStyle.buttonHeight)
	actionsGrid.CellPadding = UDim2.new(0, 6, 0, 4)
	actionsGrid.FillDirection = Enum.FillDirection.Horizontal
	actionsGrid.FillDirectionMaxCells = 2
	actionsGrid.SortOrder = Enum.SortOrder.LayoutOrder

	local applyButton = make("TextButton", actions) :: TextButton
	applyButton.Name = "Apply"
	applyButton.Text = "Apply To Camera"
	applyButton.LayoutOrder = 1
	styleButton(applyButton, CameraSystemStyle.input)

	local captureButton = make("TextButton", actions) :: TextButton
	captureButton.Name = "Capture"
	captureButton.Text = "Capture Camera"
	captureButton.LayoutOrder = 2
	styleButton(captureButton, CameraSystemStyle.input)

	local defaultButton = make("TextButton", actions) :: TextButton
	defaultButton.Name = "Default"
	defaultButton.Text = "Set Default"
	defaultButton.LayoutOrder = 3
	styleButton(defaultButton, CameraSystemStyle.input)

	local nameInput = TextInput.new(root, {
		placeholder = "Shot name",
		label = "Shot Name",
		layoutOrder = 2,
	})

	local fovInput = TextInput.new(root, {
		placeholder = "Field of View (1-120)",
		label = "Field of View",
		layoutOrder = 3,
	})

	local errorLabel = make("TextLabel", root) :: TextLabel
	errorLabel.Name = "Error"
	errorLabel.Size = UDim2.new(1, 0, 0, 0)
	errorLabel.AutomaticSize = Enum.AutomaticSize.Y
	errorLabel.TextWrapped = true
	errorLabel.TextXAlignment = Enum.TextXAlignment.Left
	errorLabel.TextColor3 = CameraSystemStyle.errorText
	errorLabel.BackgroundTransparency = 1
	errorLabel.TextSize = CameraSystemStyle.smallTextSize
	errorLabel.Text = ""
	errorLabel.Visible = false
	errorLabel.LayoutOrder = 4

	local footer = make("Frame", root) :: Frame
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 5
	local footerLayout = make("UIListLayout", footer) :: UIListLayout
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.Padding = UDim.new(0, 4)
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local spacer = make("Frame", footer) :: Frame
	spacer.Name = "Spacer"
	spacer.Size = UDim2.new(1, -224, 1, 0)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 1

	local deleteButton = make("TextButton", footer) :: TextButton
	deleteButton.Name = "Delete"
	deleteButton.Text = "Delete"
	deleteButton.Size = UDim2.new(0, 60, 1, 0)
	deleteButton.LayoutOrder = 2
	styleButton(deleteButton, CameraSystemStyle.input)
	deleteButton.TextColor3 = CameraSystemStyle.errorText

	local closeButton = make("TextButton", footer) :: TextButton
	closeButton.Name = "Close"
	closeButton.Text = "Close"
	closeButton.Size = UDim2.new(0, 56, 1, 0)
	closeButton.LayoutOrder = 3
	styleButton(closeButton, CameraSystemStyle.input)

	local saveButton = make("TextButton", footer) :: TextButton
	saveButton.Name = "Save"
	saveButton.Text = "Save Changes"
	saveButton.Size = UDim2.new(0, 96, 1, 0)
	saveButton.LayoutOrder = 4
	styleButton(saveButton, CameraSystemStyle.accent)

	local panel = setmetatable({
		root = root,
		callbacks = callbacks,
		nameInput = nameInput,
		fovInput = fovInput,
		errorLabel = errorLabel,
		saveButton = saveButton,
		closeButton = closeButton,
		deleteButton = deleteButton,
		applyButton = applyButton,
		captureButton = captureButton,
		defaultButton = defaultButton,
		editingPart = nil,
		baseName = "",
		baseFov = "",
		syncing = false,
		destroyed = false,
	}, ShotEditPanel) :: Panel

	nameInput:GetPropertyChangedSignal("Text"):Connect(function()
		if panel.syncing then
			return
		end
		evaluate(panel, true)
	end)
	fovInput:GetPropertyChangedSignal("Text"):Connect(function()
		if panel.syncing then
			return
		end
		evaluate(panel, true)
	end)

	applyButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onApply(part)
		end
	end)
	captureButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onCapture(part)
		end
	end)
	defaultButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onSetDefault(part)
		end
	end)
	deleteButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onDelete(part)
		end
	end)
	closeButton.Activated:Connect(function()
		callbacks.onClose()
	end)
	saveButton.Activated:Connect(function()
		local part = panel.editingPart
		if part == nil then
			return
		end
		local fov = tonumber(trim(panel.fovInput.Text))
		if fov == nil then
			return
		end
		callbacks.onSave(part, trim(panel.nameInput.Text), fov)
	end)

	return panel
end

function ShotEditPanel.show(self: Panel, shot: BasePart)
	self.editingPart = shot
	self.baseName = shot.Name
	self.baseFov = tostring(shot:GetAttribute("FieldOfView") or "")
	setFieldText(self, self.nameInput, self.baseName)
	setFieldText(self, self.fovInput, self.baseFov)
	evaluate(self, true)
	self.root.Visible = true
end

function ShotEditPanel.update(self: Panel, shot: BasePart)
	if self.editingPart ~= shot then
		return
	end
	local name = shot.Name
	local fovText = tostring(shot:GetAttribute("FieldOfView") or "")
	if trim(self.nameInput.Text) == self.baseName and self.baseName ~= name then
		setFieldText(self, self.nameInput, name)
		self.baseName = name
	end
	if trim(self.nameInput.Text) == name then
		self.baseName = name
	end
	if trim(self.fovInput.Text) == self.baseFov and self.baseFov ~= fovText then
		setFieldText(self, self.fovInput, fovText)
		self.baseFov = fovText
	end
	if trim(self.fovInput.Text) == fovText then
		self.baseFov = fovText
	end
	evaluate(self, false)
end

function ShotEditPanel.hide(self: Panel)
	self.editingPart = nil
	self.root.Visible = false
end

function ShotEditPanel.setError(self: Panel, message: string?)
	if message == nil then
		self.errorLabel.Text = ""
		self.errorLabel.Visible = false
	else
		self.errorLabel.Text = message
		self.errorLabel.Visible = true
	end
end

function ShotEditPanel.getEditingPart(self: Panel): BasePart?
	return self.editingPart
end

function ShotEditPanel.destroy(self: Panel)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.editingPart = nil
	self.root:Destroy()
end

return ShotEditPanel
```

- [ ] **Step 2: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

---

### Task 5: `ZoneEditPanel` (painel de edicao de zona)

**Files:**
- Create: `plugin/camera/ZoneEditPanel.luau`

**Interfaces:**
- Consumes: `CameraSystemStyle`, `TextInput`, `ShotSelector` (Task 2, com `{ openUpward = true }`).
- Produces: tipo `Panel` com campo publico `root: Frame`; API `ZoneEditPanel.new(parent: Instance, callbacks: Callbacks): Panel`, `ZoneEditPanel.show(self, zone: BasePart, shotNames: { string }, defaultShotId: string?)`, `ZoneEditPanel.update(self, zone, shotNames, defaultShotId, canMoveUp: boolean, canMoveDown: boolean)`, `ZoneEditPanel.hide(self)`, `ZoneEditPanel.setError(self, message: string?)`, `ZoneEditPanel.getEditingPart(self): BasePart?`, `ZoneEditPanel.destroy(self)`. `Callbacks = { onMoveUp, onMoveDown, onDelete, onSave, onClose }`. A Task 6 consome.

- [ ] **Step 1: Criar `plugin/camera/ZoneEditPanel.luau`**

```luau
--!strict

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local ShotSelector = require(script.Parent.ShotSelector)
local TextInput = require(script.Parent.TextInput)

local ZoneEditPanel = {}
ZoneEditPanel.__index = ZoneEditPanel

export type Callbacks = {
	onMoveUp: (BasePart) -> (),
	onMoveDown: (BasePart) -> (),
	onDelete: (BasePart) -> (),
	onSave: (BasePart, string, string) -> (),
	onClose: () -> (),
}

export type Panel = typeof(setmetatable(
	{} :: {
		root: Frame,
		callbacks: Callbacks,
		nameInput: TextBox,
		selector: ShotSelector.Selector,
		errorLabel: TextLabel,
		saveButton: TextButton,
		closeButton: TextButton,
		deleteButton: TextButton,
		moveUpButton: TextButton,
		moveDownButton: TextButton,
		editingPart: BasePart?,
		baseName: string,
		baseShotId: string?,
		syncing: boolean,
		destroyed: boolean,
	},
	ZoneEditPanel
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function trim(value: string): string
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function styleButton(button: TextButton, background: Color3)
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.5
end

local function setFieldText(self: Panel, field: TextBox, text: string)
	self.syncing = true
	field.Text = text
	self.syncing = false
end

local function zoneNameTaken(zone: BasePart, name: string): boolean
	local parent = zone.Parent
	if parent == nil then
		return false
	end
	for _, sibling in parent:GetChildren() do
		if sibling ~= zone and sibling.Name == name then
			return true
		end
	end
	return false
end

local function isDirty(self: Panel): boolean
	local selected = self.selector:getSelected()
	return trim(self.nameInput.Text) ~= self.baseName or (selected or "") ~= (self.baseShotId or "")
end

local function evaluate(self: Panel, renderError: boolean)
	local zone = self.editingPart
	if zone == nil then
		return
	end
	local name = trim(self.nameInput.Text)
	local selected = self.selector:getSelected()
	local error: string? = nil
	if name == "" then
		error = "Zone name is required"
	elseif zoneNameTaken(zone, name) then
		error = string.format('Zone "%s" already exists', name)
	elseif selected == nil then
		error = "Select a shot"
	end
	if renderError then
		self:setError(error)
	end
	setButtonEnabled(self.saveButton, error == nil and isDirty(self))
end

local function currentShotId(zone: BasePart): string?
	local value = zone:GetAttribute("ShotId")
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function ZoneEditPanel.new(parent: Instance, callbacks: Callbacks): Panel
	local root = make("Frame", parent) :: Frame
	root.Name = "ZoneEditPanel"
	root.Size = UDim2.new(1, 0, 0, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundColor3 = CameraSystemStyle.panel
	root.BorderSizePixel = 0
	root.Visible = false
	local corner = make("UICorner", root) :: UICorner
	corner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
	local padding = make("UIPadding", root) :: UIPadding
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	local layout = make("UIListLayout", root) :: UIListLayout
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local actions = make("Frame", root) :: Frame
	actions.Name = "Actions"
	actions.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	actions.BackgroundTransparency = 1
	actions.LayoutOrder = 1
	local actionsLayout = make("UIListLayout", actions) :: UIListLayout
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.Padding = UDim.new(0, 6)
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local moveUpButton = make("TextButton", actions) :: TextButton
	moveUpButton.Name = "MoveUp"
	moveUpButton.Text = "Move Up"
	moveUpButton.Size = UDim2.new(0.5, -3, 1, 0)
	moveUpButton.LayoutOrder = 1
	styleButton(moveUpButton, CameraSystemStyle.input)

	local moveDownButton = make("TextButton", actions) :: TextButton
	moveDownButton.Name = "MoveDown"
	moveDownButton.Text = "Move Down"
	moveDownButton.Size = UDim2.new(0.5, -3, 1, 0)
	moveDownButton.LayoutOrder = 2
	styleButton(moveDownButton, CameraSystemStyle.input)

	local nameInput = TextInput.new(root, {
		placeholder = "Zone name",
		label = "Zone Name",
		layoutOrder = 2,
	})

	local shotLabel = make("TextLabel", root) :: TextLabel
	shotLabel.Name = "ShotLabel"
	shotLabel.Size = UDim2.new(1, 0, 0, 0)
	shotLabel.AutomaticSize = Enum.AutomaticSize.Y
	shotLabel.BackgroundTransparency = 1
	shotLabel.TextColor3 = CameraSystemStyle.text
	shotLabel.TextSize = CameraSystemStyle.textSize
	shotLabel.TextXAlignment = Enum.TextXAlignment.Left
	shotLabel.Text = "Shot"
	shotLabel.LayoutOrder = 3

	local selector = ShotSelector.new(root, nil, { openUpward = true })
	selector.root.LayoutOrder = 4

	local errorLabel = make("TextLabel", root) :: TextLabel
	errorLabel.Name = "Error"
	errorLabel.Size = UDim2.new(1, 0, 0, 0)
	errorLabel.AutomaticSize = Enum.AutomaticSize.Y
	errorLabel.TextWrapped = true
	errorLabel.TextXAlignment = Enum.TextXAlignment.Left
	errorLabel.TextColor3 = CameraSystemStyle.errorText
	errorLabel.BackgroundTransparency = 1
	errorLabel.TextSize = CameraSystemStyle.smallTextSize
	errorLabel.Text = ""
	errorLabel.Visible = false
	errorLabel.LayoutOrder = 5

	local footer = make("Frame", root) :: Frame
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 6
	local footerLayout = make("UIListLayout", footer) :: UIListLayout
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.Padding = UDim.new(0, 4)
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local spacer = make("Frame", footer) :: Frame
	spacer.Name = "Spacer"
	spacer.Size = UDim2.new(1, -224, 1, 0)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 1

	local deleteButton = make("TextButton", footer) :: TextButton
	deleteButton.Name = "Delete"
	deleteButton.Text = "Delete"
	deleteButton.Size = UDim2.new(0, 60, 1, 0)
	deleteButton.LayoutOrder = 2
	styleButton(deleteButton, CameraSystemStyle.input)
	deleteButton.TextColor3 = CameraSystemStyle.errorText

	local closeButton = make("TextButton", footer) :: TextButton
	closeButton.Name = "Close"
	closeButton.Text = "Close"
	closeButton.Size = UDim2.new(0, 56, 1, 0)
	closeButton.LayoutOrder = 3
	styleButton(closeButton, CameraSystemStyle.input)

	local saveButton = make("TextButton", footer) :: TextButton
	saveButton.Name = "Save"
	saveButton.Text = "Save Changes"
	saveButton.Size = UDim2.new(0, 96, 1, 0)
	saveButton.LayoutOrder = 4
	styleButton(saveButton, CameraSystemStyle.accent)

	local panel = setmetatable({
		root = root,
		callbacks = callbacks,
		nameInput = nameInput,
		selector = selector,
		errorLabel = errorLabel,
		saveButton = saveButton,
		closeButton = closeButton,
		deleteButton = deleteButton,
		moveUpButton = moveUpButton,
		moveDownButton = moveDownButton,
		editingPart = nil,
		baseName = "",
		baseShotId = nil,
		syncing = false,
		destroyed = false,
	}, ZoneEditPanel) :: Panel

	selector.onChanged = function()
		evaluate(panel, true)
	end

	nameInput:GetPropertyChangedSignal("Text"):Connect(function()
		if panel.syncing then
			return
		end
		evaluate(panel, true)
	end)

	moveUpButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone ~= nil then
			callbacks.onMoveUp(zone)
		end
	end)
	moveDownButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone ~= nil then
			callbacks.onMoveDown(zone)
		end
	end)
	deleteButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone ~= nil then
			callbacks.onDelete(zone)
		end
	end)
	closeButton.Activated:Connect(function()
		callbacks.onClose()
	end)
	saveButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone == nil then
			return
		end
		local shotName = panel.selector:getSelected()
		if shotName == nil then
			return
		end
		callbacks.onSave(zone, trim(panel.nameInput.Text), shotName)
	end)

	return panel
end

function ZoneEditPanel.show(self: Panel, zone: BasePart, shotNames: { string }, defaultShotId: string?)
	self.editingPart = zone
	self.baseName = zone.Name
	setFieldText(self, self.nameInput, self.baseName)
	local shotName = currentShotId(zone)
	self.selector:setOptions(shotNames, shotName, defaultShotId)
	self.baseShotId = shotName
	evaluate(self, true)
	self.root.Visible = true
end

function ZoneEditPanel.update(
	self: Panel,
	zone: BasePart,
	shotNames: { string },
	defaultShotId: string?,
	canMoveUp: boolean,
	canMoveDown: boolean
)
	if self.editingPart ~= zone then
		return
	end
	local name = zone.Name
	if trim(self.nameInput.Text) == self.baseName and self.baseName ~= name then
		setFieldText(self, self.nameInput, name)
		self.baseName = name
	end
	if trim(self.nameInput.Text) == name then
		self.baseName = name
	end

	local shotId = currentShotId(zone)
	local selected = self.selector:getSelected()
	if selected == self.baseShotId and self.baseShotId ~= shotId then
		self.selector:setOptions(shotNames, shotId, defaultShotId)
		self.baseShotId = shotId
	else
		self.selector:syncOptions(shotNames, defaultShotId)
		if self.selector:getSelected() == shotId then
			self.baseShotId = shotId
		end
	end

	setButtonEnabled(self.moveUpButton, canMoveUp)
	setButtonEnabled(self.moveDownButton, canMoveDown)
	evaluate(self, false)
end

function ZoneEditPanel.hide(self: Panel)
	self.selector:close()
	self.editingPart = nil
	self.root.Visible = false
end

function ZoneEditPanel.setError(self: Panel, message: string?)
	if message == nil then
		self.errorLabel.Text = ""
		self.errorLabel.Visible = false
	else
		self.errorLabel.Text = message
		self.errorLabel.Visible = true
	end
end

function ZoneEditPanel.getEditingPart(self: Panel): BasePart?
	return self.editingPart
end

function ZoneEditPanel.destroy(self: Panel)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.editingPart = nil
	self.root:Destroy()
end

return ZoneEditPanel
```

- [ ] **Step 2: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

---

### Task 6: Widget com abas e integracao no `init.plugin.luau`

**Files:**
- Modify: `plugin/camera/CameraSystemWidget.luau` (arquivo inteiro)
- Modify: `plugin/init.plugin.luau` (bloco `local callbacks = {...}`)

**Interfaces:**
- Consumes: `ShotEditPanel.Panel` (Task 4), `ZoneEditPanel.Panel` (Task 5), `ShotSelector.setOptions` (Task 2), `CameraSystemDialog` com `options` (Task 3), operacoes do model (Task 1).
- Produces: `CameraSystemWidget` com campos `gui`, `activeTab`, `shotSelection`, `zoneSelection`, `shots`, `zones`, `defaultShotId`, `dialog`, `shotPanel`, `zonePanel`; API `new`, `refresh(shots, zones, defaultShotId, errors)`, `setActiveTab(tab)`, `setSelection(instance?)`, `clearSelection()`, `closeShotPanel()`, `closeZonePanel()`, `requestDeleteShot(shot)`, `requestDeleteZone(zone)`, `closeDialog()`, `openConfirmDialog(title, message, onConfirm)`, `openNewShotDialog()`, `openNewZoneDialog()`, `destroy()`; callbacks `onCreateShot(name, fov)`, `onCreateZone(name, shotName)`, `onCaptureCamera(shot)`, `onApplyCamera(shot)`, `onSetDefault(shot)`, `onMoveZone(zone, delta)`, `onSaveShot(shot, name, fov)`, `onSaveZone(zone, name, shotName)`, `onDeleteShot(shot)`, `onDeleteZone(zone)`, `onSelect(instance)`, `classifySelection(instance)`, `getDefaultFieldOfView()`.

- [ ] **Step 1: Substituir `plugin/camera/CameraSystemWidget.luau` pelo conteudo final**

```luau
--!strict

local CameraSystemDialog = require(script.Parent.CameraSystemDialog)
local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local ShotEditPanel = require(script.Parent.ShotEditPanel)
local ShotSelector = require(script.Parent.ShotSelector)
local TextInput = require(script.Parent.TextInput)
local ZoneEditPanel = require(script.Parent.ZoneEditPanel)

local CameraSystemWidget = {}
CameraSystemWidget.__index = CameraSystemWidget

export type TabName = "shots" | "zones"

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

export type Widget = typeof(setmetatable(
	{} :: {
		gui: DockWidgetPluginGui,
		callbacks: Callbacks,
		activeTab: TabName,
		shotsContent: ScrollingFrame,
		zonesContent: ScrollingFrame,
		shotsTab: TextButton,
		zonesTab: TextButton,
		shotsEmpty: TextLabel,
		zonesEmpty: TextLabel,
		newZoneButton: TextButton,
		status: TextLabel,
		shotPanel: ShotEditPanel.Panel,
		zonePanel: ZoneEditPanel.Panel,
		shotRows: { TextButton },
		zoneRows: { TextButton },
		rowInstances: { [TextButton]: BasePart },
		shotSelection: BasePart?,
		zoneSelection: BasePart?,
		shots: { BasePart },
		zones: { BasePart },
		defaultShotId: string?,
		dialog: CameraSystemDialog.Dialog?,
	},
	CameraSystemWidget
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function trim(value: string): string
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function styleButton(button: TextButton, background: Color3)
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.5
end

local function makeButton(parent: Instance, text: string, callback: () -> ()): TextButton
	local button = make("TextButton", parent) :: TextButton
	button.Text = text
	button.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	styleButton(button, CameraSystemStyle.panel)
	button.Activated:Connect(callback)
	return button
end

local function makeLabel(parent: Instance, text: string, order: number): TextLabel
	local label = make("TextLabel", parent) :: TextLabel
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = CameraSystemStyle.text
	label.TextSize = CameraSystemStyle.textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = order
	return label
end

local function makeEmptyLabel(parent: Instance, text: string): TextLabel
	local label = make("TextLabel", parent) :: TextLabel
	label.Name = "Empty"
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = CameraSystemStyle.mutedText
	label.TextSize = CameraSystemStyle.smallTextSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = 2
	return label
end

local function makeList(parent: Instance, name: string): ScrollingFrame
	local list = make("ScrollingFrame", parent) :: ScrollingFrame
	list.Name = name
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	local layout = make("UIListLayout", list) :: UIListLayout
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local padding = make("UIPadding", list) :: UIPadding
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	return list
end

local function styleTab(button: TextButton, active: boolean)
	button.BackgroundColor3 = if active then CameraSystemStyle.accent else CameraSystemStyle.panel
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function formatNameList(names: { string }): string
	local quoted: { string } = {}
	for _, name in names do
		table.insert(quoted, string.format('"%s"', name))
	end
	return table.concat(quoted, ", ")
end

function CameraSystemWidget.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Widget
	gui.Title = "Camera System"
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = make("Frame", gui) :: Frame
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = CameraSystemStyle.background
	root.BorderSizePixel = 0
	local rootLayout = make("UIListLayout", root) :: UIListLayout
	rootLayout.Padding = UDim.new(0, 6)
	rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local rootPadding = make("UIPadding", root) :: UIPadding
	rootPadding.PaddingTop = UDim.new(0, 6)
	rootPadding.PaddingBottom = UDim.new(0, 6)
	rootPadding.PaddingLeft = UDim.new(0, 6)
	rootPadding.PaddingRight = UDim.new(0, 6)

	local widgetRef: Widget? = nil

	local tabBar = make("Frame", root) :: Frame
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	tabBar.BackgroundTransparency = 1
	tabBar.LayoutOrder = 1
	local tabLayout = make("UIListLayout", tabBar) :: UIListLayout
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local shotsTab = make("TextButton", tabBar) :: TextButton
	shotsTab.Name = "ShotsTab"
	shotsTab.Text = "Shots"
	shotsTab.Size = UDim2.new(0.5, -3, 1, 0)
	shotsTab.LayoutOrder = 1
	styleTab(shotsTab, true)

	local zonesTab = make("TextButton", tabBar) :: TextButton
	zonesTab.Name = "ZonesTab"
	zonesTab.Text = "Zones"
	zonesTab.Size = UDim2.new(0.5, -3, 1, 0)
	zonesTab.LayoutOrder = 2
	styleTab(zonesTab, false)

	local contentArea = make("Frame", root) :: Frame
	contentArea.Name = "ContentArea"
	contentArea.Size = UDim2.new(1, 0, 0, 0)
	contentArea.BackgroundTransparency = 1
	contentArea.LayoutOrder = 2
	local flex = make("UIFlexItem", contentArea) :: UIFlexItem
	flex.FlexMode = Enum.UIFlexMode.Fill

	local shotsContent = makeList(contentArea, "ShotsContent")
	local newShotButton = makeButton(shotsContent, "New Shot", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewShotDialog()
		end
	end)
	newShotButton.LayoutOrder = 1
	local shotsEmpty = makeEmptyLabel(shotsContent, "No shots yet")

	local zonesContent = makeList(contentArea, "ZonesContent")
	zonesContent.Visible = false
	local newZoneButton = makeButton(zonesContent, "New Zone", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewZoneDialog()
		end
	end)
	newZoneButton.LayoutOrder = 1
	local zonesEmpty = makeEmptyLabel(zonesContent, "No zones yet")

	local status = make("TextLabel", root) :: TextLabel
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = CameraSystemStyle.errorText
	status.BackgroundTransparency = 1
	status.TextSize = CameraSystemStyle.smallTextSize
	status.LayoutOrder = 3

	local shotPanel = ShotEditPanel.new(root, {
		onApply = function(shot: BasePart)
			callbacks.onApplyCamera(shot)
		end,
		onCapture = function(shot: BasePart)
			callbacks.onCaptureCamera(shot)
		end,
		onSetDefault = function(shot: BasePart)
			callbacks.onSetDefault(shot)
		end,
		onDelete = function(shot: BasePart)
			local current = widgetRef
			if current ~= nil then
				current:requestDeleteShot(shot)
			end
		end,
		onSave = function(shot: BasePart, name: string, fieldOfView: number)
			callbacks.onSaveShot(shot, name, fieldOfView)
		end,
		onClose = function()
			local current = widgetRef
			if current ~= nil then
				current:closeShotPanel()
			end
		end,
	})
	shotPanel.root.LayoutOrder = 4

	local zonePanel = ZoneEditPanel.new(root, {
		onMoveUp = function(zone: BasePart)
			callbacks.onMoveZone(zone, -1)
		end,
		onMoveDown = function(zone: BasePart)
			callbacks.onMoveZone(zone, 1)
		end,
		onDelete = function(zone: BasePart)
			local current = widgetRef
			if current ~= nil then
				current:requestDeleteZone(zone)
			end
		end,
		onSave = function(zone: BasePart, name: string, shotName: string)
			callbacks.onSaveZone(zone, name, shotName)
		end,
		onClose = function()
			local current = widgetRef
			if current ~= nil then
				current:closeZonePanel()
			end
		end,
	})
	zonePanel.root.LayoutOrder = 5

	local widget = setmetatable({
		gui = gui,
		callbacks = callbacks,
		activeTab = "shots",
		shotsContent = shotsContent,
		zonesContent = zonesContent,
		shotsTab = shotsTab,
		zonesTab = zonesTab,
		shotsEmpty = shotsEmpty,
		zonesEmpty = zonesEmpty,
		newZoneButton = newZoneButton,
		status = status,
		shotPanel = shotPanel,
		zonePanel = zonePanel,
		shotRows = {},
		zoneRows = {},
		rowInstances = {},
		shotSelection = nil,
		zoneSelection = nil,
		shots = {},
		zones = {},
		defaultShotId = nil,
		dialog = nil,
	}, CameraSystemWidget) :: Widget

	widgetRef = widget

	shotsTab.Activated:Connect(function()
		local current = widgetRef
		if current ~= nil then
			current:setActiveTab("shots")
		end
	end)
	zonesTab.Activated:Connect(function()
		local current = widgetRef
		if current ~= nil then
			current:setActiveTab("zones")
		end
	end)

	return widget
end

function CameraSystemWidget.setActiveTab(self: Widget, tab: TabName)
	self.activeTab = tab
	local shotsActive = tab == "shots"
	self.shotsContent.Visible = shotsActive
	self.zonesContent.Visible = not shotsActive
	styleTab(self.shotsTab, shotsActive)
	styleTab(self.zonesTab, not shotsActive)
	self:updatePanels()
end

function CameraSystemWidget.updateRows(self: Widget)
	for _, row in self.shotRows do
		row.BackgroundColor3 = if self.rowInstances[row] == self.shotSelection
			then CameraSystemStyle.accent
			else CameraSystemStyle.panel
	end
	for _, row in self.zoneRows do
		row.BackgroundColor3 = if self.rowInstances[row] == self.zoneSelection
			then CameraSystemStyle.accent
			else CameraSystemStyle.panel
	end
end

function CameraSystemWidget.updatePanels(self: Widget)
	local shot = self.shotSelection
	if self.activeTab == "shots" and shot ~= nil then
		if self.shotPanel:getEditingPart() ~= shot then
			self.shotPanel:show(shot)
		else
			self.shotPanel:update(shot)
		end
	elseif self.shotPanel.root.Visible then
		self.shotPanel:hide()
	end

	local zone = self.zoneSelection
	if self.activeTab == "zones" and zone ~= nil then
		local names: { string } = {}
		for _, item in self.shots do
			table.insert(names, item.Name)
		end
		local index = table.find(self.zones, zone)
		local canMoveUp = index ~= nil and index > 1
		local canMoveDown = index ~= nil and index < #self.zones
		if self.zonePanel:getEditingPart() ~= zone then
			self.zonePanel:show(zone, names, self.defaultShotId)
		end
		self.zonePanel:update(zone, names, self.defaultShotId, canMoveUp, canMoveDown)
	elseif self.zonePanel.root.Visible then
		self.zonePanel:hide()
	end
end

function CameraSystemWidget.setSelection(self: Widget, instance: Instance?)
	local selectionKind = if instance == nil then nil else self.callbacks.classifySelection(instance)
	if selectionKind == "shot" and instance ~= nil and instance:IsA("BasePart") then
		self.shotSelection = instance
		self:setActiveTab("shots")
	elseif selectionKind == "zone" and instance ~= nil and instance:IsA("BasePart") then
		self.zoneSelection = instance
		self:setActiveTab("zones")
	elseif selectionKind == nil then
		self:clearSelection()
	end
	self:updateRows()
end

function CameraSystemWidget.clearSelection(self: Widget)
	self.shotSelection = nil
	self.zoneSelection = nil
	self.shotPanel:hide()
	self.zonePanel:hide()
	self:updateRows()
end

function CameraSystemWidget.closeShotPanel(self: Widget)
	self.shotSelection = nil
	self.shotPanel:hide()
	self:updateRows()
end

function CameraSystemWidget.closeZonePanel(self: Widget)
	self.zoneSelection = nil
	self.zonePanel:hide()
	self:updateRows()
end

function CameraSystemWidget.refresh(
	self: Widget,
	shots: { BasePart },
	zones: { BasePart },
	defaultShotId: string?,
	errors: { string }
)
	self.shots = shots
	self.zones = zones
	self.defaultShotId = defaultShotId

	for _, row in self.shotRows do
		row:Destroy()
	end
	for _, row in self.zoneRows do
		row:Destroy()
	end
	table.clear(self.shotRows)
	table.clear(self.zoneRows)
	table.clear(self.rowInstances)

	for index, shot in shots do
		local row = make("TextButton", self.shotsContent) :: TextButton
		row.Name = "Shot_" .. shot.Name
		row.Text = string.format("Shot: %s%s", shot.Name, if shot.Name == defaultShotId then " (default)" else "")
		row.Size = UDim2.new(1, -12, 0, 24)
		row.LayoutOrder = index + 2
		styleButton(row, CameraSystemStyle.panel)
		self.rowInstances[row] = shot
		row.Activated:Connect(function()
			self.shotSelection = shot
			self:setActiveTab("shots")
			self:updateRows()
			self.callbacks.onSelect(shot)
		end)
		table.insert(self.shotRows, row)
	end

	for index, zone in zones do
		local row = make("TextButton", self.zonesContent) :: TextButton
		row.Name = "Zone_" .. zone.Name
		row.Text = string.format("Zone: %s -> %s", zone.Name, tostring(zone:GetAttribute("ShotId") or "<unassigned>"))
		row.Size = UDim2.new(1, -12, 0, 24)
		row.LayoutOrder = index + 2
		styleButton(row, CameraSystemStyle.panel)
		self.rowInstances[row] = zone
		row.Activated:Connect(function()
			self.zoneSelection = zone
			self:setActiveTab("zones")
			self:updateRows()
			self.callbacks.onSelect(zone)
		end)
		table.insert(self.zoneRows, row)
	end

	self.shotsEmpty.Visible = #shots == 0
	self.zonesEmpty.Visible = #zones == 0
	setButtonEnabled(self.newZoneButton, #shots > 0)
	self.status.Text = if #errors == 0 then "Valid camera system" else table.concat(errors, "\n")

	if self.shotSelection ~= nil and table.find(shots, self.shotSelection) == nil then
		self.shotSelection = nil
		self.shotPanel:hide()
	end
	if self.zoneSelection ~= nil and table.find(zones, self.zoneSelection) == nil then
		self.zoneSelection = nil
		self.zonePanel:hide()
	end

	self:updateRows()
	self:updatePanels()
end

function CameraSystemWidget.closeDialog(self: Widget)
	if self.dialog == nil then
		return
	end
	local dialog = self.dialog
	self.dialog = nil
	dialog:destroy()
end

function CameraSystemWidget.openConfirmDialog(self: Widget, title: string, message: string, onConfirm: () -> ())
	self:closeDialog()
	local created = CameraSystemDialog.new(self.gui, title, {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			onConfirm()
		end,
	}, { confirmText = "Delete", cancelText = "Cancel" })
	self.dialog = created
	makeLabel(created.content, message, 1)
end

function CameraSystemWidget.requestDeleteShot(self: Widget, shot: BasePart)
	local referencing: { string } = {}
	for _, zone in self.zones do
		if zone:GetAttribute("ShotId") == shot.Name then
			table.insert(referencing, zone.Name)
		end
	end
	if #referencing > 0 then
		self.shotPanel:setError(string.format("Cannot delete: referenced by zones %s", formatNameList(referencing)))
		return
	end
	self:openConfirmDialog("Delete Shot", string.format('Delete shot "%s"?', shot.Name), function()
		self.callbacks.onDeleteShot(shot)
	end)
end

function CameraSystemWidget.requestDeleteZone(self: Widget, zone: BasePart)
	self:openConfirmDialog("Delete Zone", string.format('Delete zone "%s"?', zone.Name), function()
		self.callbacks.onDeleteZone(zone)
	end)
end

function CameraSystemWidget.openNewShotDialog(self: Widget)
	self:closeDialog()

	local dialog: CameraSystemDialog.Dialog? = nil
	local shotNameInput: TextBox? = nil
	local shotFovInput: TextBox? = nil

	local function nameAlreadyExists(name: string): boolean
		for _, shot in self.shots do
			if shot.Name == name then
				return true
			end
		end
		return false
	end

	local function evaluate()
		local currentDialog = dialog
		local currentInput = shotNameInput
		local currentFovInput = shotFovInput
		if currentDialog == nil or currentInput == nil or currentFovInput == nil then
			return
		end
		local name = trim(currentInput.Text)
		local duplicate = name ~= "" and nameAlreadyExists(name)
		local fieldOfView = tonumber(currentFovInput.Text)
		local validFieldOfView = fieldOfView ~= nil and fieldOfView >= 1 and fieldOfView <= 120
		if duplicate then
			currentDialog:setError(string.format('Shot "%s" already exists', name))
		elseif not validFieldOfView then
			currentDialog:setError("FieldOfView must be between 1 and 120")
		else
			currentDialog:setError(nil)
		end
		currentDialog:setConfirmEnabled(name ~= "" and not duplicate and validFieldOfView)
	end

	local created = CameraSystemDialog.new(self.gui, "Create Shot", {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			local currentInput = shotNameInput
			local currentFovInput = shotFovInput
			if currentInput == nil or currentFovInput == nil then
				return
			end
			local name = trim(currentInput.Text)
			local fieldOfView = tonumber(currentFovInput.Text)
			if name ~= "" and fieldOfView ~= nil then
				self.callbacks.onCreateShot(name, fieldOfView)
			end
		end,
	})
	dialog = created
	self.dialog = created

	local input = TextInput.new(created.content, {
		placeholder = "Shot name",
		label = "Enter the shot name",
		layoutOrder = 1,
	})
	shotNameInput = input
	input:GetPropertyChangedSignal("Text"):Connect(evaluate)
	input.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		if enterPressed and currentDialog ~= nil then
			currentDialog:tryConfirm()
		end
	end)

	local fovInput = TextInput.new(created.content, {
		placeholder = "Field of View (1-120)",
		label = "Field of View (1-120)",
		value = tostring(self.callbacks.getDefaultFieldOfView()),
		layoutOrder = 2,
	})
	shotFovInput = fovInput
	fovInput:GetPropertyChangedSignal("Text"):Connect(evaluate)
	fovInput.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		if enterPressed and currentDialog ~= nil then
			currentDialog:tryConfirm()
		end
	end)

	created:focusFirstInput()
	evaluate()
end

function CameraSystemWidget.openNewZoneDialog(self: Widget)
	self:closeDialog()

	local dialog: CameraSystemDialog.Dialog? = nil
	local zoneNameInput: TextBox? = nil
	local selector: ShotSelector.Selector? = nil

	local function nameAlreadyExists(name: string): boolean
		for _, zone in self.zones do
			if zone.Name == name then
				return true
			end
		end
		return false
	end

	local function evaluate()
		local currentDialog = dialog
		local currentInput = zoneNameInput
		local currentSelector = selector
		if currentDialog == nil or currentInput == nil or currentSelector == nil then
			return
		end
		local name = trim(currentInput.Text)
		local duplicate = name ~= "" and nameAlreadyExists(name)
		if duplicate then
			currentDialog:setError(string.format('Zone "%s" already exists', name))
		else
			currentDialog:setError(nil)
		end
		currentDialog:setConfirmEnabled(name ~= "" and not duplicate and currentSelector:getSelected() ~= nil)
	end

	local names: { string } = {}
	for _, shot in self.shots do
		table.insert(names, shot.Name)
	end

	local created = CameraSystemDialog.new(self.gui, "Create Zone", {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			local currentInput = zoneNameInput
			local currentSelector = selector
			if currentInput == nil or currentSelector == nil then
				return
			end
			local name = trim(currentInput.Text)
			local shotName = currentSelector:getSelected()
			if name ~= "" and shotName ~= nil then
				self.callbacks.onCreateZone(name, shotName)
			end
		end,
		canCancel = function()
			local currentSelector = selector
			return currentSelector == nil or not currentSelector:isOpen()
		end,
	})
	dialog = created
	self.dialog = created

	local input = TextInput.new(created.content, {
		placeholder = "Zone name",
		label = "Enter the zone name",
		layoutOrder = 1,
	})
	zoneNameInput = input
	input:GetPropertyChangedSignal("Text"):Connect(evaluate)

	makeLabel(created.content, "Select a shot", 2)
	local shotSelector = ShotSelector.new(created.content, evaluate)
	shotSelector.root.LayoutOrder = 3
	selector = shotSelector
	shotSelector:setOptions(names, self.defaultShotId, self.defaultShotId)

	input.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		local currentSelector = selector
		if enterPressed and currentDialog ~= nil and currentSelector ~= nil and not currentSelector:isOpen() then
			currentDialog:tryConfirm()
		end
	end)
	created:focusFirstInput()
	evaluate()
end

function CameraSystemWidget.destroy(self: Widget)
	self:closeDialog()
	self.gui:Destroy()
end

return CameraSystemWidget
```

- [ ] **Step 2: Substituir o bloco de callbacks em `plugin/init.plugin.luau`**

Substitua o bloco inteiro de `local callbacks = { ... }` (da linha `local callbacks = {` ate o `}` que fecha antes de `local gui = pluginApi:CreateDockWidgetPluginGui`) pelo conteudo abaixo:

```luau
		local callbacks = {
			getDefaultFieldOfView = function(): number
				return Workspace.CurrentCamera.FieldOfView
			end,
			onCreateShot = function(name: string, fieldOfView: number)
				run("New Shot", function()
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:createShot(name, camera, fieldOfView)
				end)
			end,
			onCreateZone = function(name: string, shotName: string)
				run("New Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local shot = hierarchy.shots:FindFirstChild(shotName)
					assert(shot ~= nil and shot:IsA("BasePart"), string.format('Shot "%s" not found', shotName))
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:createZone(
						name,
						CFrame.new(camera.Focus.Position),
						Vector3.new(10, 10, 10),
						shot :: BasePart
					)
				end)
			end,
			onCaptureCamera = function(shot: BasePart)
				run("Capture Camera", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local ownedPart = owned :: BasePart
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:captureCamera(ownedPart, camera)
				end)
			end,
			onApplyCamera = function(shot: BasePart)
				run("Apply To Camera", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local ownedPart = owned :: BasePart
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:applyShot(ownedPart, camera)
				end)
			end,
			onSetDefault = function(shot: BasePart)
				run("Set Default", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local currentModel = model :: any
					currentModel:setDefaultShot(owned :: BasePart)
				end)
			end,
			onSaveShot = function(shot: BasePart, name: string, fieldOfView: number)
				run("Save Shot", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local ownedPart = owned :: BasePart
					local currentModel = model :: any
					if ownedPart.Name ~= name then
						currentModel:renameShot(ownedPart, name)
					end
					if ownedPart:GetAttribute("FieldOfView") ~= fieldOfView then
						currentModel:setFieldOfView(ownedPart, fieldOfView)
					end
				end)
			end,
			onSaveZone = function(zone: BasePart, name: string, shotName: string)
				run("Save Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.zones, zone)
					assert(owned ~= nil, "Select a zone first")
					local ownedPart = owned :: BasePart
					local shot = hierarchy.shots:FindFirstChild(shotName)
					assert(shot ~= nil and shot:IsA("BasePart"), string.format('Shot "%s" not found', shotName))
					local currentModel = model :: any
					if ownedPart.Name ~= name then
						currentModel:renameZone(ownedPart, name)
					end
					if ownedPart:GetAttribute("ShotId") ~= shotName then
						currentModel:assignShot(ownedPart, shot :: BasePart)
					end
				end)
			end,
			onMoveZone = function(zone: BasePart, delta: number)
				run("Move Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.zones, zone)
					assert(owned ~= nil, "Select a zone first")
					local currentModel = model :: any
					currentModel:reorderZone(owned :: BasePart, delta)
				end)
			end,
			onDeleteShot = function(shot: BasePart)
				run("Delete Shot", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local currentModel = model :: any
					currentModel:deleteShot(owned :: BasePart)
				end)
			end,
			onDeleteZone = function(zone: BasePart)
				run("Delete Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.zones, zone)
					assert(owned ~= nil, "Select a zone first")
					local currentModel = model :: any
					currentModel:deleteZone(owned :: BasePart)
				end)
			end,
			onSelect = function(instance: Instance)
				(Selection :: any):Set({ instance })
				if widget ~= nil then
					widget:setSelection(instance)
				end
			end,
			classifySelection = function(instance: Instance): string?
				local hierarchy = (model :: any):ensureHierarchy()
				if instance:IsA("BasePart") and instance.Parent == hierarchy.shots then
					return "shot"
				elseif instance:IsA("BasePart") and instance.Parent == hierarchy.zones then
					return "zone"
				end
				return nil
			end,
		}
```

- [ ] **Step 3: Verificar estaticamente**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

- [ ] **Step 4: Conferir que o wiring antigo sumiu**

Run: `rg -n "onAssignShot|onFieldOfView|nameInput|shotSelection|zoneSelection" plugin`

Expected: nenhuma ocorrencia de `onAssignShot`/`onFieldOfView`/`nameInput`; `shotSelection`/`zoneSelection` apenas em `plugin/camera/CameraSystemWidget.luau`.

- [ ] **Step 5: Smoke test no Studio**

Run: `scripts/plugin-build.sh` e reinicie o Roblox Studio (se `$ROBLOX_PLUGINS_DIR` nao existir neste ambiente, use `scripts/plugin-build.sh --no-install` e instale o `.rbxmx` de `PluginBackups/` manualmente).

Com o editor ativo: as abas aparecem; criar shot abre o painel na aba `Shots`; alternar para `Zones` e voltar mantem a selecao; editar nome/FOV e salvar aplica; deletar uma zona pede confirmacao. Qualquer falha bloqueia a conclusao da task.

---

### Task 7: README e verificacao final

**Files:**
- Modify: `README.md` (secao "Using", passos 3-6)
- Nenhum arquivo novo de codigo.

**Interfaces:**
- Consumes: tudo das Tasks 1-6.
- Produces: documentacao alinhada e evidencia de que o plugin passa nos comandos e no checklist manual.

- [ ] **Step 1: Atualizar o README**

Na secao "Using", substitua os passos 3, 4, 5 e 6:

```markdown
3. Select a shot or zone row in the panel, or pick the part in the viewport.
   The panel and the Studio `Selection` stay in sync.
4. With a shot selected, use **Capture Camera** to overwrite it from the
   viewport camera, **Apply To Camera** to move the viewport camera to the shot,
   **Set Default** to mark it as `DefaultShotId`, and **Set FOV** to apply the
   value in the field-of-view input.
5. With a zone selected, use **Assign Shot** to bind it to the selected shot and
   **Move Up** / **Move Down** to swap `Order` with the adjacent zone.
6. The status line reports validation errors: missing default shot, invalid
   `FieldOfView`, dangling `ShotId`, invalid or duplicate `Order`, and
   non-positive zone `Size`.
```

por:

```markdown
3. The dock is split into **Shots** and **Zones** tabs. Select a row in the
   active tab, or pick the part in the viewport, to open the edit panel fixed at
   the bottom; the Studio `Selection` stays in sync and the matching tab is
   activated automatically.
4. In the shot panel, **Apply To Camera** moves the viewport camera to the shot,
   **Capture Camera** overwrites it from the current camera, and **Set Default**
   marks it as `DefaultShotId`. Edit `Shot Name` and `Field of View` as a draft
   and press **Save Changes** to apply both; **Delete** removes the shot only
   when no zone references it.
5. In the zone panel, **Move Up** / **Move Down** swap `Order` with the adjacent
   zone. Edit `Zone Name` and the shot dropdown as a draft and press
   **Save Changes**; **Delete** removes the zone.
6. **Close**, switching tabs or changing the selection discards the draft. The
   status line reports validation errors: missing default shot, invalid
   `FieldOfView`, dangling `ShotId`, invalid or duplicate `Order`, and
   non-positive zone `Size`.
```

- [ ] **Step 2: Rodar a verificacao completa**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: Selene 0 erros, `luau-lsp` 0 diagnosticos, build gerado.

- [ ] **Step 3: Confirmar que o jogo continua intacto**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json`

Expected: build do jogo gerado sem erro (o plugin nao e mapeado para o place do jogo).

- [ ] **Step 4: Instalar o plugin no Studio**

Run: `scripts/plugin-build.sh`

Expected: arquivo arquivado em `PluginBackups/` e `camera-system-plugin.rbxmx` instalado em `$ROBLOX_PLUGINS_DIR` (padrao `/mnt/c/Users/leona/AppData/Local/Roblox/Plugins`). Reiniciar o Roblox Studio. Se `$ROBLOX_PLUGINS_DIR` nao existir neste ambiente, rode `scripts/plugin-build.sh --no-install` e instale manualmente o `.rbxmx` arquivado em `PluginBackups/`.

- [ ] **Step 5: Checklist manual no Studio**

Com um place que tenha `Workspace.CameraSystem` (ou crie shots a partir do editor):

1. Ativar **Edit Camera System**: as abas `Shots` e `Zones` aparecem, com `Shots` ativa; cada aba vazia mostra `No shots yet` / `No zones yet`; **New Zone** esta desabilitado sem shots.
2. Clicar em **New Shot**: o modal abre com nome e FOV pre-preenchido; criar deixa o shot selecionado, ativa a aba `Shots` e abre o painel de edicao com os valores do shot.
3. Selecionar o Part no viewport: a aba correspondente ativa e o painel abre; selecionar outro objeto qualquer (ou esvaziar a selecao) fecha os paineis.
4. Shot: **Apply To Camera** move a camera do viewport; **Capture Camera** sobrescreve o shot; **Set Default** marca `(default)` na linha. Editar `Shot Name`/`Field of View` destaca **Save Changes**; salvar aplica; `Close` descarta e o painel fecha; reabrir mostra os valores do Part.
5. Rename de shot: renomear um shot referenciado por zona atualiza a linha `Zone: <nome> -> <novo>` e o `(default)` continua correto quando era o default.
6. Validacoes locais: nome vazio/duplicado e FOV fora de 1-120 mostram erro inline e mantem **Save Changes** desabilitado.
7. Delete: com zona referenciando o shot, **Delete** mostra `Cannot delete: referenced by zones ...` sem modal; sem referencia, abre o modal `Delete Shot`, e confirmar remove. Deletar o shot default promove o primeiro restante; deletar a ultima shot limpa o `DefaultShotId` e o status fica `Valid camera system`.
8. Zone: **Move Up**/**Move Down** desabilitam nos extremos e reordenam; o dropdown de shot abre para cima, filtra por busca, marca o default `(default)` e lista `No shots found` quando o filtro nao casa; **Save Changes** aplica rename e troca de shot.
9. Delete de zona sempre abre o modal `Delete Zone` e confirmar remove.
10. Trocar de aba com rascunho sujo descarta o rascunho e mantem a selecao da aba (voltar reabre com os valores do Part).
11. Undo/redo de rename, delete e movimentacao; desativar/reativar o editor persiste `Data` e rematerializa as parts; redimensionar o dock estreito sem overflow nos paineis e no dropdown.
12. Modais de criacao existentes (`Create Shot`/`Create Zone`) continuam funcionando, inclusive Esc, Enter e busca.

Expected: todos os itens passam. Qualquer falha: corrigir, repetir os Steps 2-4 e o checklist.
