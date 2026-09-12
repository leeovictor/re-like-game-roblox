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

export type Options = {
	confirmText: string?,
	cancelText: string?,
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

function CameraSystemDialog.new(
	gui: DockWidgetPluginGui,
	title: string,
	callbacks: Callbacks,
	options: Options?
): Dialog
	local confirmText = if options ~= nil and options.confirmText ~= nil then options.confirmText else "Create"
	local cancelText = if options ~= nil and options.cancelText ~= nil then options.cancelText else "Cancel"
	local scrim = make("TextButton", gui) :: TextButton
	scrim.Name = "CameraSystemDialog"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = CameraSystemStyle.scrim
	scrim.BackgroundTransparency = CameraSystemStyle.scrimTransparency
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.Active = true

	local card = make("Frame", scrim) :: Frame
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(1, -32, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = CameraSystemStyle.panel
	card.BorderSizePixel = 0
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

	local titleLabel = make("TextLabel", card) :: TextLabel
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 0)
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = CameraSystemStyle.text
	titleLabel.TextSize = CameraSystemStyle.titleTextSize
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = title
	titleLabel.LayoutOrder = 1

	local content = make("Frame", card) :: Frame
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.ZIndex = 2
	content.LayoutOrder = 2
	local contentLayout = make("UIListLayout", content) :: UIListLayout
	contentLayout.Padding = UDim.new(0, CameraSystemStyle.fieldSpacing)
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
	errorLabel.LayoutOrder = 3

	local footer = make("Frame", card) :: Frame
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 4
	local footerLayout = make("UIListLayout", footer) :: UIListLayout
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.Padding = UDim.new(0, 6)

	local cancelButton = make("TextButton", footer) :: TextButton
	cancelButton.Name = "Cancel"
	cancelButton.Size = UDim2.new(0, 88, 1, 0)
	cancelButton.Text = cancelText
	styleFooterButton(cancelButton, CameraSystemStyle.input)

	local confirmButton = make("TextButton", footer) :: TextButton
	confirmButton.Name = "Create"
	confirmButton.Size = UDim2.new(0, 88, 1, 0)
	confirmButton.Text = confirmText
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
