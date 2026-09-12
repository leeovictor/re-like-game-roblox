# Camera Plugin Create Flows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir o campo de nome compartilhado do painel do plugin Camera System por modais dedicados para `New Shot` e `New Zone`, com seletor de shot pesquisável e shot padrao pre-selecionado no fluxo de zona.

**Architecture:** Tres modulos de UI novos em `plugin/camera/`: `CameraSystemStyle` (tokens visuais), `CameraSystemDialog` (shell de modal com scrim, conteudo, erro inline e rodape Cancel/Create) e `ShotSelector` (dropdown com busca). O `CameraSystemWidget` compoe esses modulos nos fluxos, guarda o snapshot de shots/zonas/default vindo do `refresh` e remove o `nameInput`. O `init.plugin.luau` passa nomes por argumento e o `CameraSystemModel.createZone` recebe o shot escolhido explicitamente.

**Tech Stack:** Luau `--!strict` em plugin Roblox montado por Rojo (`plugin.project.json`), UI construida com `Instance.new` e `DockWidgetPluginGui`. Sem framework de testes no plugin: a verificacao e lint Selene, typecheck `luau-lsp` com sourcemap do plugin, build Rojo e checklist manual no Studio.

## Global Constraints

- Nao faca commits ao escrever nem ao implementar este plano (`AGENTS.md` do repositorio). Commit so com pedido explicito do usuario. Nao existem passos de commit neste plano.
- Todo modulo do plugin usa `--!strict`; nao use `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Modulos novos ficam em `plugin/camera/` e sao importados com `require(script.Parent.NomeDoModulo)`.
- O plugin e construido por `plugin.project.json`; `src/shared/camera/CameraSystemData.luau` entra como `script.Parent.Parent.CameraSystemData`. Nao altere esse mapeamento.
- Textos de UI em ingles: `Cancel`, `Create`, `Enter the shot name`, `Enter the zone name`, `Select a shot`, `Search shots`, `No shots found`, `(default)`, erros `Shot "<nome>" already exists` e `Zone "<nome>" already exists`.
- Cores de UI (`Color3.fromRGB`/`Color3.new`) ficam exclusivamente em `CameraSystemStyle.luau`; `CameraSystemPreview` continua usando `Color3.fromHSV` para os markers, fora do escopo.
- Valores de comportamento fixos: zona nova com centro em `camera.Focus.Position` e tamanho `Vector3.new(10, 10, 10)`; nomes sao comparados por igualdade exata contra o snapshot do ultimo `refresh`.
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
- Nao existe teste automatizado no plugin (`TestEZ` foi removido do repositorio). Nenhuma tarefa pode ser declarada concluida sem rodar os comandos acima e, quando a mudanca afetar UI, sem o checklist manual da Task 6.

---

### Task 1: Tokens visuais (`CameraSystemStyle`) e migracao do widget

**Files:**
- Create: `plugin/camera/CameraSystemStyle.luau`
- Modify: `plugin/camera/CameraSystemWidget.luau` (substituir todas as cores hardcoded por tokens)

**Interfaces:**
- Consumes: nada.
- Produces: modulo `CameraSystemStyle` com os campos `background`, `panel`, `input`, `text`, `mutedText`, `accent`, `errorText`, `scrim` (`Color3`), `scrimTransparency`, `buttonHeight`, `inputHeight`, `cardPadding`, `listMaxHeight`, `textSize`, `smallTextSize` (`number`). As Tasks 2, 3 e 5 consomem esse modulo.

- [ ] **Step 1: Criar `CameraSystemStyle.luau`**

```luau
--!strict

export type Tokens = {
	background: Color3,
	panel: Color3,
	input: Color3,
	text: Color3,
	mutedText: Color3,
	accent: Color3,
	errorText: Color3,
	scrim: Color3,
	scrimTransparency: number,
	buttonHeight: number,
	inputHeight: number,
	cardPadding: number,
	listMaxHeight: number,
	textSize: number,
	smallTextSize: number,
}

local CameraSystemStyle: Tokens = {
	background = Color3.fromRGB(24, 25, 29),
	panel = Color3.fromRGB(45, 48, 55),
	input = Color3.fromRGB(32, 34, 39),
	text = Color3.fromRGB(235, 235, 235),
	mutedText = Color3.fromRGB(150, 155, 165),
	accent = Color3.fromRGB(70, 90, 125),
	errorText = Color3.fromRGB(255, 120, 120),
	scrim = Color3.fromRGB(0, 0, 0),
	scrimTransparency = 0.5,
	buttonHeight = 26,
	inputHeight = 26,
	cardPadding = 10,
	listMaxHeight = 140,
	textSize = 13,
	smallTextSize = 12,
}

return CameraSystemStyle
```

- [ ] **Step 2: Migrar o widget para os tokens**

Em `plugin/camera/CameraSystemWidget.luau`, adicione o require junto aos demais (antes de `local CameraSystemWidget = {}`):

```luau
local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
```

Substitua `styleButton` por:

```luau
local function styleButton(button: TextButton)
	button.BackgroundColor3 = CameraSystemStyle.panel
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end
```

Substitua as cores e medidas de `makeButton`:

```luau
	button.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
```

Substitua o corpo de `makeInput` por:

```luau
	local input = make("TextBox", parent) :: TextBox
	input.Size = UDim2.new(1, 0, 0, CameraSystemStyle.inputHeight)
	input.PlaceholderText = placeholder
	input.Text = ""
	input.ClearTextOnFocus = false
	input.TextColor3 = CameraSystemStyle.text
	input.BackgroundColor3 = CameraSystemStyle.input
	input.BorderSizePixel = 0
	return input
```

No `new`, troque `root.BackgroundColor3 = Color3.fromRGB(24, 25, 29)` por `root.BackgroundColor3 = CameraSystemStyle.background`, e no `status` troque `Color3.fromRGB(255, 170, 120)` por `CameraSystemStyle.errorText` e `status.TextSize = 12` por `status.TextSize = CameraSystemStyle.smallTextSize`.

Em `updateSelectionVisuals`, troque as quatro ocorrencias de cor:

```luau
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
```

- [ ] **Step 3: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado em `/tmp/camera-system-plugin.rbxmx`.

- [ ] **Step 4: Conferir que nenhuma cor sobrou fora do Style**

Run: `rg -n "Color3\.(fromRGB|new)" plugin`

Expected: ocorrencias apenas em `plugin/camera/CameraSystemStyle.luau`.

---

### Task 2: `ShotSelector` (dropdown pesquisavel)

**Files:**
- Create: `plugin/camera/ShotSelector.luau`

**Interfaces:**
- Consumes: `CameraSystemStyle` (Task 1).
- Produces: tipo `Selector` com campo publico `root: Frame` e API `ShotSelector.new(parent: Instance, onChanged: (() -> ())?): Selector`, `ShotSelector.setOptions(self, names: { string }, defaultName: string?)`, `ShotSelector.getSelected(self): string?`, `ShotSelector.isOpen(self): boolean`, `ShotSelector.close(self)`, `ShotSelector.destroy(self)`. A Task 5 consome essa API.

- [ ] **Step 1: Criar `ShotSelector.luau`**

```luau
--!strict

local UserInputService = game:GetService("UserInputService")

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)

local ShotSelector = {}
ShotSelector.__index = ShotSelector

export type Selector = typeof(setmetatable(
	{} :: {
		root: Frame,
		fieldLabel: TextLabel,
		popup: Frame,
		search: TextBox,
		list: ScrollingFrame,
		options: { string },
		selected: string?,
		defaultName: string?,
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

function ShotSelector.new(parent: Instance, onChanged: (() -> ())?): Selector
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
	popup.Position = UDim2.new(0, 0, 1, 4)
	popup.Size = UDim2.new(1, 0, 0, 0)
	popup.AutomaticSize = Enum.AutomaticSize.Y
	popup.BackgroundColor3 = CameraSystemStyle.panel
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.ZIndex = 50
	local popupCorner = make("UICorner", popup) :: UICorner
	popupCorner.CornerRadius = UDim.new(0, 4)
	local popupPadding = make("UIPadding", popup) :: UIPadding
	popupPadding.PaddingTop = UDim.new(0, 4)
	popupPadding.PaddingBottom = UDim.new(0, 4)
	popupPadding.PaddingLeft = UDim.new(0, 4)
	popupPadding.PaddingRight = UDim.new(0, 4)
	local popupLayout = make("UIListLayout", popup) :: UIListLayout
	popupLayout.Padding = UDim.new(0, 4)
	popupLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local search = make("TextBox", popup) :: TextBox
	search.Name = "Search"
	search.Size = UDim2.new(1, 0, 0, CameraSystemStyle.inputHeight)
	search.PlaceholderText = "Search shots"
	search.Text = ""
	search.ClearTextOnFocus = false
	search.TextColor3 = CameraSystemStyle.text
	search.BackgroundColor3 = CameraSystemStyle.input
	search.BorderSizePixel = 0
	search.TextSize = CameraSystemStyle.textSize
	search.LayoutOrder = 1

	local list = make("ScrollingFrame", popup) :: ScrollingFrame
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.LayoutOrder = 2
	local listConstraint = make("UISizeConstraint", list) :: UISizeConstraint
	listConstraint.MaxSize = Vector2.new(math.huge, CameraSystemStyle.listMaxHeight)
	local listLayout = make("UIListLayout", list) :: UIListLayout
	listLayout.Padding = UDim.new(0, 2)

	local selector = setmetatable({
		root = root,
		fieldLabel = fieldLabel,
		popup = popup,
		search = search,
		list = list,
		options = {},
		selected = nil,
		defaultName = nil,
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
			button.BackgroundColor3 = if name == self.selected
				then CameraSystemStyle.accent
				else CameraSystemStyle.panel
			button.BorderSizePixel = 0
			button.TextColor3 = CameraSystemStyle.text
			button.TextSize = CameraSystemStyle.textSize
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.AutoButtonColor = true
			button.LayoutOrder = index
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
	end
end

function ShotSelector.setOptions(self: Selector, names: { string }, defaultName: string?)
	local options: { string } = {}
	for _, name in names do
		table.insert(options, name)
	end
	self.options = options
	self.defaultName = defaultName
	self.selected = nil
	if defaultName ~= nil then
		for _, name in self.options do
			if name == defaultName then
				self.selected = defaultName
				break
			end
		end
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

- [ ] **Step 2: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

---

### Task 3: `CameraSystemDialog` (shell do modal)

**Files:**
- Create: `plugin/camera/CameraSystemDialog.luau`

**Interfaces:**
- Consumes: `CameraSystemStyle` (Task 1).
- Produces: tipos `Callbacks` (`onCancel: () -> ()`, `onConfirm: () -> ()`, `canCancel: (() -> ())?`) e `Dialog` (campo publico `content: Frame`); API `CameraSystemDialog.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Dialog`, `CameraSystemDialog.focusFirstInput(self)`, `CameraSystemDialog.setError(self, message: string?)`, `CameraSystemDialog.setConfirmEnabled(self, enabled: boolean)`, `CameraSystemDialog.tryConfirm(self)`, `CameraSystemDialog.destroy(self)`. A Task 5 consome essa API.

- [ ] **Step 1: Criar `CameraSystemDialog.luau`**

```luau
--!strict

local UserInputService = game:GetService("UserInputService")

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)

local CameraSystemDialog = {}
CameraSystemDialog.__index = CameraSystemDialog

export type Callbacks = {
	onCancel: () -> (),
	onConfirm: () -> (),
	canCancel: (() -> ())?,
}

export type Dialog = typeof(setmetatable(
	{} :: {
		scrim: TextButton,
		content: Frame,
		errorLabel: TextLabel,
		confirmButton: TextButton,
		callbacks: Callbacks,
		inputConnection: RBXScriptConnection?,
		destroyed: boolean,
	},
	CameraSystemDialog
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function styleFooterButton(button: TextButton, background: Color3)
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

function CameraSystemDialog.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Dialog
	local scrim = make("TextButton", gui) :: TextButton
	scrim.Name = "CameraSystemDialog"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = CameraSystemStyle.scrim
	scrim.BackgroundTransparency = CameraSystemStyle.scrimTransparency
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.Active = true
	scrim.ZIndex = 10

	local card = make("Frame", scrim) :: Frame
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(1, -32, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = CameraSystemStyle.panel
	card.BorderSizePixel = 0
	card.ZIndex = 11
	local cardCorner = make("UICorner", card) :: UICorner
	cardCorner.CornerRadius = UDim.new(0, 6)
	local cardPadding = make("UIPadding", card) :: UIPadding
	cardPadding.PaddingTop = UDim.new(0, CameraSystemStyle.cardPadding)
	cardPadding.PaddingBottom = UDim.new(0, CameraSystemStyle.cardPadding)
	cardPadding.PaddingLeft = UDim.new(0, CameraSystemStyle.cardPadding)
	cardPadding.PaddingRight = UDim.new(0, CameraSystemStyle.cardPadding)
	local cardLayout = make("UIListLayout", card) :: UIListLayout
	cardLayout.Padding = UDim.new(0, 8)
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local content = make("Frame", card) :: Frame
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.ZIndex = 12
	content.LayoutOrder = 1
	local contentLayout = make("UIListLayout", content) :: UIListLayout
	contentLayout.Padding = UDim.new(0, 4)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local errorLabel = make("TextLabel", card) :: TextLabel
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
	errorLabel.LayoutOrder = 2

	local footer = make("Frame", card) :: Frame
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 3
	local footerLayout = make("UIListLayout", footer) :: UIListLayout
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.Padding = UDim.new(0, 6)

	local cancelButton = make("TextButton", footer) :: TextButton
	cancelButton.Name = "Cancel"
	cancelButton.Size = UDim2.new(0, 88, 1, 0)
	cancelButton.Text = "Cancel"
	styleFooterButton(cancelButton, CameraSystemStyle.input)

	local confirmButton = make("TextButton", footer) :: TextButton
	confirmButton.Name = "Create"
	confirmButton.Size = UDim2.new(0, 88, 1, 0)
	confirmButton.Text = "Create"
	styleFooterButton(confirmButton, CameraSystemStyle.accent)

	local dialog = setmetatable({
		scrim = scrim,
		content = content,
		errorLabel = errorLabel,
		confirmButton = confirmButton,
		callbacks = callbacks,
		inputConnection = nil,
		destroyed = false,
	}, CameraSystemDialog) :: Dialog

	cancelButton.Activated:Connect(function()
		dialog:destroy()
		callbacks.onCancel()
	end)
	confirmButton.Activated:Connect(function()
		dialog:tryConfirm()
	end)
	dialog.inputConnection = UserInputService.InputBegan:Connect(function(input)
		if dialog.destroyed then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.Escape then
			return
		end
		if callbacks.canCancel ~= nil and not callbacks.canCancel() then
			return
		end
		dialog:destroy()
		callbacks.onCancel()
	end)

	return dialog
end

function CameraSystemDialog.focusFirstInput(self: Dialog)
	local textBox = self.content:FindFirstChildWhichIsA("TextBox", true)
	if textBox ~= nil then
		(textBox :: TextBox):CaptureFocus()
	end
end

function CameraSystemDialog.setError(self: Dialog, message: string?)
	if message == nil then
		self.errorLabel.Text = ""
		self.errorLabel.Visible = false
	else
		self.errorLabel.Text = message
		self.errorLabel.Visible = true
	end
end

function CameraSystemDialog.setConfirmEnabled(self: Dialog, enabled: boolean)
	self.confirmButton.Active = enabled
	self.confirmButton.AutoButtonColor = enabled
	self.confirmButton.BackgroundTransparency = if enabled then 0 else 0.4
	self.confirmButton.TextTransparency = if enabled then 0 else 0.5
end

function CameraSystemDialog.tryConfirm(self: Dialog)
	if self.destroyed or not self.confirmButton.Active then
		return
	end
	local callbacks = self.callbacks
	self:destroy()
	callbacks.onConfirm()
end

function CameraSystemDialog.destroy(self: Dialog)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.inputConnection ~= nil then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
	self.scrim:Destroy()
end

return CameraSystemDialog
```

- [ ] **Step 2: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

---

### Task 4: `CameraSystemModel.createZone` com shot explicito

**Files:**
- Modify: `plugin/camera/CameraSystemModel.luau:260-296` (funcao `createZone`)

**Interfaces:**
- Consumes: nada.
- Produces: `CameraSystemModel.createZone(self, name: string, cframe: CFrame, size: Vector3, shot: Part?): Part`. A Task 5 chama com o shot escolhido no modal; sem `shot`, o fallback antigo para `DefaultShotId` permanece.

- [ ] **Step 1: Alterar a assinatura e a atribuicao de `ShotId`**

Substitua a funcao `createZone` inteira por:

```luau
function CameraSystemModel.createZone(self: Model, name: string, cframe: CFrame, size: Vector3, shot: Part?): Part
	local zoneName = requireNonEmptyName(name)
	local hierarchy = self:ensureHierarchy()
	assert(hierarchy.zones:FindFirstChild(zoneName) == nil, string.format('Zone "%s" already exists', zoneName))
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "Zone size must be positive on every axis")
	if shot ~= nil then
		assert(
			shot:IsA("BasePart") and shot.Parent == hierarchy.shots,
			string.format('Shot "%s" is not owned by CameraSystem.Shots', shot.Name)
		)
	end

	local nextOrder = 1
	for _, zone in self:listZones() do
		local order = zone:GetAttribute(ORDER)
		if isValidOrder(order) then
			nextOrder = math.max(nextOrder, (order :: number) + 1)
		end
	end

	setWaypoint(self.changeHistoryService, "Camera System: Begin create zone")
	local zone = Instance.new("Part")
	zone.Name = zoneName
	zone.CFrame = cframe
	zone.Size = size
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.Transparency = EDITOR_ZONE_TRANSPARENCY
	zone.Locked = false
	zone:SetAttribute(ORDER, nextOrder)

	if shot ~= nil then
		zone:SetAttribute(SHOT_ID, shot.Name)
	else
		local defaultShotId = hierarchy.root:GetAttribute(DEFAULT_SHOT_ID)
		local defaultShot = if type(defaultShotId) == "string" then hierarchy.shots:FindFirstChild(defaultShotId) else nil
		if defaultShot ~= nil and defaultShot:IsA("BasePart") then
			zone:SetAttribute(SHOT_ID, defaultShotId)
		end
	end
	zone.Parent = hierarchy.zones
	selectInstance(self.selection, zone)
	setWaypoint(self.changeHistoryService, "Camera System: End create zone")
	return zone
end
```

- [ ] **Step 2: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

---

### Task 5: Integracao no widget e no plugin (modais, callbacks, README)

**Files:**
- Modify: `plugin/camera/CameraSystemWidget.luau` (arquivo inteiro)
- Modify: `plugin/init.plugin.luau` (callbacks e `deactivateEditor`)
- Modify: `README.md` (secao "Using", passo 2)

**Interfaces:**
- Consumes: `CameraSystemStyle` (Task 1), `ShotSelector` (Task 2), `CameraSystemDialog` (Task 3), `createZone` com `shot` (Task 4).
- Produces: `CameraSystemWidget` com callbacks `onCreateShot: (string) -> ()` e `onCreateZone: (string, string) -> ()`, metodos `openNewShotDialog()`, `openNewZoneDialog()`, `closeDialog()`, snapshot `shots`/`zones`/`defaultShotId` e botao `New Zone` desabilitado sem shots. O `init.plugin.luau` consome essa API.

- [ ] **Step 1: Substituir `plugin/camera/CameraSystemWidget.luau` pelo conteudo final**

```luau
--!strict

local CameraSystemDialog = require(script.Parent.CameraSystemDialog)
local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local ShotSelector = require(script.Parent.ShotSelector)

local CameraSystemWidget = {}
CameraSystemWidget.__index = CameraSystemWidget

type Callbacks = {
	onCreateShot: (string) -> (),
	onCreateZone: (string, string) -> (),
	onCaptureCamera: () -> (),
	onApplyCamera: () -> (),
	onSetDefault: () -> (),
	onAssignShot: () -> (),
	onMoveZone: (number) -> (),
	onFieldOfView: (number) -> (),
	onSelect: (Instance) -> (),
	classifySelection: (Instance) -> string?,
}

export type Widget = typeof(setmetatable(
	{} :: {
		gui: DockWidgetPluginGui,
		callbacks: Callbacks,
		shotRows: { TextButton },
		zoneRows: { TextButton },
		rowInstances: { [TextButton]: BasePart },
		shotSelection: BasePart?,
		zoneSelection: BasePart?,
		shotIdInput: TextBox,
		fovInput: TextBox,
		status: TextLabel,
		actionButtons: { [string]: TextButton },
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

local function styleButton(button: TextButton)
	button.BackgroundColor3 = CameraSystemStyle.panel
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function makeButton(parent: Instance, text: string, callback: () -> ()): TextButton
	local button = make("TextButton", parent) :: TextButton
	button.Text = text
	button.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	styleButton(button)
	button.Activated:Connect(callback)
	return button
end

local function makeSection(parent: Instance, title: string): (Frame, UIListLayout)
	local section = make("Frame", parent) :: Frame
	section.Name = title
	section.Size = UDim2.new(1, -12, 0, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundTransparency = 1
	local layout = make("UIListLayout", section) :: UIListLayout
	layout.Padding = UDim.new(0, 4)
	return section, layout
end

local function makeInput(parent: Instance, placeholder: string): TextBox
	local input = make("TextBox", parent) :: TextBox
	input.Size = UDim2.new(1, 0, 0, CameraSystemStyle.inputHeight)
	input.PlaceholderText = placeholder
	input.Text = ""
	input.ClearTextOnFocus = false
	input.TextColor3 = CameraSystemStyle.text
	input.BackgroundColor3 = CameraSystemStyle.input
	input.BorderSizePixel = 0
	return input
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

function CameraSystemWidget.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Widget
	gui.Title = "Camera System"

	local root = make("ScrollingFrame", gui) :: ScrollingFrame
	root.Size = UDim2.fromScale(1, 1)
	root.CanvasSize = UDim2.new()
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.ScrollBarThickness = 8
	root.BackgroundColor3 = CameraSystemStyle.background
	root.BorderSizePixel = 0
	local rootLayout = make("UIListLayout", root) :: UIListLayout
	rootLayout.Padding = UDim.new(0, 6)
	local padding = make("UIPadding", root) :: UIPadding
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)

	local widgetRef: Widget? = nil

	local actions = makeSection(root, "Actions")
	makeButton(actions, "New Shot", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewShotDialog()
		end
	end)
	local captureButton = makeButton(actions, "Capture Camera", callbacks.onCaptureCamera)
	local applyButton = makeButton(actions, "Apply To Camera", callbacks.onApplyCamera)
	local defaultButton = makeButton(actions, "Set Default", callbacks.onSetDefault)
	local newZoneButton = makeButton(actions, "New Zone", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewZoneDialog()
		end
	end)

	local shotsSection = makeSection(root, "Shots")
	local fovInput = makeInput(shotsSection, "Field of View (1-120)")
	local fovButton = makeButton(shotsSection, "Set FOV", function()
		local value = tonumber(fovInput.Text)
		if value ~= nil then
			callbacks.onFieldOfView(value)
		end
	end)
	fovButton.Name = "SetFieldOfView"

	local zonesSection = makeSection(root, "Zones")
	local shotIdInput = makeInput(zonesSection, "ShotId")
	local assignButton = makeButton(zonesSection, "Assign Shot", callbacks.onAssignShot)
	local moveUpButton = makeButton(zonesSection, "Move Up", function()
		callbacks.onMoveZone(-1)
	end)
	local moveDownButton = makeButton(zonesSection, "Move Down", function()
		callbacks.onMoveZone(1)
	end)

	local status = make("TextLabel", root) :: TextLabel
	status.Name = "Status"
	status.Size = UDim2.new(1, -12, 0, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = CameraSystemStyle.errorText
	status.BackgroundTransparency = 1
	status.TextSize = CameraSystemStyle.smallTextSize

	local widget = setmetatable({
		gui = gui,
		callbacks = callbacks,
		shotRows = {},
		zoneRows = {},
		rowInstances = {},
		shotSelection = nil,
		zoneSelection = nil,
		shotIdInput = shotIdInput,
		fovInput = fovInput,
		status = status,
		actionButtons = {
			capture = captureButton,
			apply = applyButton,
			default = defaultButton,
			assign = assignButton,
			moveUp = moveUpButton,
			moveDown = moveDownButton,
			fov = fovButton,
			newZone = newZoneButton,
		},
		shots = {},
		zones = {},
		defaultShotId = nil,
		dialog = nil,
	}, CameraSystemWidget) :: Widget

	widgetRef = widget
	return widget
end

function CameraSystemWidget.setSelection(self: Widget, instance: Instance?)
	local selectionKind = if instance == nil then nil else self.callbacks.classifySelection(instance)
	if selectionKind == "shot" and instance ~= nil and instance:IsA("BasePart") then
		self.shotSelection = instance
		self.fovInput.Text = tostring(instance:GetAttribute("FieldOfView") or "")
	elseif selectionKind == "zone" and instance ~= nil and instance:IsA("BasePart") then
		self.zoneSelection = instance
		self.shotIdInput.Text = tostring(instance:GetAttribute("ShotId") or "")
	elseif selectionKind == nil then
		self.shotSelection = nil
		self.zoneSelection = nil
	end
	self:updateSelectionVisuals()
end

function CameraSystemWidget.clearSelection(self: Widget)
	self.shotSelection = nil
	self.zoneSelection = nil
	self.fovInput.Text = ""
	self.shotIdInput.Text = ""
	self:updateSelectionVisuals()
end

function CameraSystemWidget.updateSelectionVisuals(self: Widget)
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
	local hasShot = self.shotSelection ~= nil
	local hasZone = self.zoneSelection ~= nil
	for name, button in self.actionButtons do
		local enabled = if name == "assign"
			then hasShot and hasZone
			elseif name == "moveUp" or name == "moveDown" then hasZone
			elseif name == "fov" or name == "capture" or name == "apply" or name == "default" then hasShot
			elseif name == "newZone" then #self.shots > 0
			else true
		button.Active = enabled
		button.AutoButtonColor = enabled
		button.TextTransparency = if enabled then 0 else 0.5
	end
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

	for _, shot in shots do
		local row = make("TextButton", self.gui:FindFirstChild("ScrollingFrame") :: Instance) :: TextButton
		row.Name = "Shot_" .. shot.Name
		row.Text = string.format("Shot: %s%s", shot.Name, if shot.Name == defaultShotId then " (default)" else "")
		row.Size = UDim2.new(1, -12, 0, 24)
		styleButton(row)
		self.rowInstances[row] = shot
		row.Activated:Connect(function()
			self.shotSelection = shot
			self.callbacks.onSelect(shot)
		end)
		table.insert(self.shotRows, row)
	end

	for _, zone in zones do
		local row = make("TextButton", self.gui:FindFirstChild("ScrollingFrame") :: Instance) :: TextButton
		row.Name = "Zone_" .. zone.Name
		row.Text = string.format("Zone: %s -> %s", zone.Name, tostring(zone:GetAttribute("ShotId") or "<unassigned>"))
		row.Size = UDim2.new(1, -12, 0, 24)
		styleButton(row)
		self.rowInstances[row] = zone
		row.Activated:Connect(function()
			self.zoneSelection = zone
			self.callbacks.onSelect(zone)
		end)
		table.insert(self.zoneRows, row)
	end

	self.status.Text = if #errors == 0 then "Valid camera system" else table.concat(errors, "\n")
	self:updateSelectionVisuals()
end

function CameraSystemWidget.closeDialog(self: Widget)
	if self.dialog == nil then
		return
	end
	local dialog = self.dialog
	self.dialog = nil
	dialog:destroy()
end

function CameraSystemWidget.openNewShotDialog(self: Widget)
	self:closeDialog()

	local dialog: CameraSystemDialog.Dialog? = nil
	local nameInput: TextBox? = nil

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
		local currentInput = nameInput
		if currentDialog == nil or currentInput == nil then
			return
		end
		local name = trim(currentInput.Text)
		local duplicate = name ~= "" and nameAlreadyExists(name)
		if duplicate then
			currentDialog:setError(string.format('Shot "%s" already exists', name))
		else
			currentDialog:setError(nil)
		end
		currentDialog:setConfirmEnabled(name ~= "" and not duplicate)
	end

	dialog = CameraSystemDialog.new(self.gui, {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			local currentInput = nameInput
			if currentInput == nil then
				return
			end
			local name = trim(currentInput.Text)
			if name ~= "" then
				self.callbacks.onCreateShot(name)
			end
		end,
	})
	self.dialog = dialog

	makeLabel(dialog.content, "Enter the shot name", 1)
	local input = makeInput(dialog.content, "Shot name")
	input.LayoutOrder = 2
	nameInput = input
	input:GetPropertyChangedSignal("Text"):Connect(evaluate)
	input.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		if enterPressed and currentDialog ~= nil then
			currentDialog:tryConfirm()
		end
	end)
	dialog:focusFirstInput()
	evaluate()
end

function CameraSystemWidget.openNewZoneDialog(self: Widget)
	self:closeDialog()

	local dialog: CameraSystemDialog.Dialog? = nil
	local nameInput: TextBox? = nil
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
		local currentInput = nameInput
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

	dialog = CameraSystemDialog.new(self.gui, {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			local currentInput = nameInput
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
	self.dialog = dialog

	makeLabel(dialog.content, "Enter the zone name", 1)
	local input = makeInput(dialog.content, "Zone name")
	input.LayoutOrder = 2
	nameInput = input
	input:GetPropertyChangedSignal("Text"):Connect(evaluate)

	makeLabel(dialog.content, "Select a shot", 3)
	local shotSelector = ShotSelector.new(dialog.content, evaluate)
	shotSelector.root.LayoutOrder = 4
	selector = shotSelector
	shotSelector:setOptions(names, self.defaultShotId)

	input.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		local currentSelector = selector
		if enterPressed and currentDialog ~= nil and currentSelector ~= nil and not currentSelector:isOpen() then
			currentDialog:tryConfirm()
		end
	end)
	dialog:focusFirstInput()
	evaluate()
end

function CameraSystemWidget.destroy(self: Widget)
	self:closeDialog()
	self.gui:Destroy()
end

return CameraSystemWidget
```

- [ ] **Step 2: Atualizar os callbacks em `plugin/init.plugin.luau`**

Substitua este bloco:

```luau
			onNewShot = function()
				local name = widget :: any
				run("New Shot", function()
					local camera = Workspace.CurrentCamera
					local shotName = name.nameInput.Text
					assert(shotName ~= "", "Enter a name first")
					local currentModel = model :: any
					currentModel:createShot(shotName, camera)
				end)
			end,
```

por:

```luau
			onCreateShot = function(name: string)
				run("New Shot", function()
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:createShot(name, camera)
				end)
			end,
```

Substitua este bloco:

```luau
			onNewZone = function()
				local currentWidget = widget :: any
				run("New Zone", function()
					local camera = Workspace.CurrentCamera
					local zoneName = currentWidget.nameInput.Text
					assert(zoneName ~= "", "Enter a name first")
					local currentModel = model :: any
					currentModel:createZone(zoneName, CFrame.new(camera.Focus.Position), Vector3.new(10, 10, 10))
				end)
			end,
```

por:

```luau
			onCreateZone = function(name: string, shotName: string)
				run("New Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local shot = hierarchy.shots:FindFirstChild(shotName)
					assert(shot ~= nil and shot:IsA("BasePart"), string.format('Shot "%s" not found', shotName))
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:createZone(name, CFrame.new(camera.Focus.Position), Vector3.new(10, 10, 10), shot :: BasePart)
				end)
			end,
```

- [ ] **Step 3: Fechar o modal ao desativar o editor**

Em `deactivateEditor`, depois de `widget:clearSelection()`, adicione:

```luau
	if widget ~= nil then
		widget:closeDialog()
	end
```

O trecho final fica:

```luau
	if widget ~= nil then
		widget:clearSelection()
	end
	if widget ~= nil then
		widget:closeDialog()
	end
```

- [ ] **Step 4: Atualizar o README**

Na secao "Using", substitua este passo:

```markdown
2. Type a name in the **Actions** input and use **New Shot** or **New Zone**.
   New shots copy the current viewport camera and its `FieldOfView`; new zones
   start as a 10x10x10 part at the camera focus, receive the next `Order`, and
   are assigned to the default shot when one exists.
```

por:

```markdown
2. Use **New Shot** to open the shot modal and name the shot. Use **New Zone**
   to open the zone modal, name the zone, and pick its shot from the searchable
   selector (the default shot is pre-selected; the button is disabled when no
   shots exist). New shots copy the current viewport camera and its
   `FieldOfView`; new zones start as a 10x10x10 part at the camera focus,
   receive the next `Order`, and are assigned to the chosen shot.
```

- [ ] **Step 5: Verificar**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: sem erros de Selene, sem diagnosticos do `luau-lsp` e build gerado.

- [ ] **Step 6: Conferir que o campo antigo sumiu e as cores estao centralizadas**

Run: `rg -n "nameInput|Color3\.(fromRGB|new)" plugin`

Expected: nenhuma ocorrencia de `nameInput`; `Color3` apenas em `plugin/camera/CameraSystemStyle.luau`.

---

### Task 6: Verificacao final (estatica e manual no Studio)

**Files:**
- Nenhum arquivo novo; verificar o estado final do repo.

**Interfaces:**
- Consumes: tudo das Tasks 1-5.
- Produces: evidencia de que o plugin passa nos comandos e nos fluxos manuais.

- [ ] **Step 1: Rodar a verificacao completa**

Run:

```bash
selene --config selene.roblox.toml plugin && rojo sourcemap --include-non-scripts plugin.project.json --output /tmp/plugin-sourcemap.json && luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --sourcemap /tmp/plugin-sourcemap.json --formatter gnu plugin && rojo build -o /tmp/camera-system-plugin.rbxmx plugin.project.json
```

Expected: Selene 0 erros, `luau-lsp` 0 diagnosticos, build gerado.

- [ ] **Step 2: Confirmar que o jogo continua intacto**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json`

Expected: build do jogo gerado sem erro (o plugin nao e mapeado para o place do jogo).

- [ ] **Step 3: Instalar o plugin no Studio**

Run: `scripts/plugin-build.sh`

Expected: arquivo arquivado em `PluginBackups/` e `camera-system-plugin.rbxmx` instalado em `$ROBLOX_PLUGINS_DIR` (padrao `/mnt/c/Users/leona/AppData/Local/Roblox/Plugins`). Reiniciar o Roblox Studio para carregar a build. Se `$ROBLOX_PLUGINS_DIR` nao existir neste ambiente, rode `scripts/plugin-build.sh --no-install` e instale manualmente o `.rbxmx` arquivado em `PluginBackups/` pelo Studio.

- [ ] **Step 4: Checklist manual no Studio**

Com um place que tenha `Workspace.CameraSystem` (ou crie shots a partir do editor):

1. Ativar **Edit Camera System**. Clicar em **New Shot**: o modal abre com o campo `Enter the shot name` focado.
2. Com o nome vazio ou apenas espacos, **Create** fica desabilitado; digitar um nome existente mostra `Shot "<nome>" already exists` e mantem **Create** desabilitado.
3. Criar um shot: o Part e selecionado no Studio, a lista atualiza e o modal fecha. Repetir com Enter no campo de nome.
4. **Cancel** e Esc fecham o modal sem criar; clicar no scrim nao fecha.
5. Sem nenhum shot, **New Zone** esta desabilitado. Criar pelo menos um shot e clicar **New Zone**.
6. No modal de zona: digitar o nome, abrir o seletor, verificar que o default aparece marcado `(default)` e pre-selecionado; digitar no campo `Search shots` filtra por substring (case-insensitive); um termo sem match mostra `No shots found`; clicar numa opcao seleciona e fecha o popup; clique-fora e Esc fecham o popup sem trocar a selecao.
7. Criar a zona: o Part de `10x10x10` e criado no foco da camera, com `ShotId` do shot escolhido, selecionado no Studio.
8. Nome de zona duplicado mostra `Zone "<nome>" already exists` e bloqueia **Create**.
9. Com o seletor aberto, Esc fecha apenas o popup; Esc de novo (popup fechado) fecha o modal.
10. Desativar o editor com um modal aberto: o modal some e nao reaparece ao reativar.
11. Undo/Redo das criacoes funcionam; desativar e reativar o editor persiste `Data` e rematerializa as parts.
12. Redimensionar o dock bem estreito: card e dropdown sem overflow horizontal; os demais comandos (`Capture Camera`, `Apply To Camera`, `Set Default`, `Set FOV`, `Assign Shot`, `Move Up`, `Move Down`) seguem funcionando.

Expected: todos os itens passam. Qualquer falha: corrigir, repetir os Steps 1-3 e o checklist.
