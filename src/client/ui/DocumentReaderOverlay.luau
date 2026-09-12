--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local React = require(ReplicatedStorage.Packages.React)
local StarterPlayer = game:GetService("StarterPlayer")
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

local DocumentReaderControllerModule =
	require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)

type Props = {
	enabled: boolean,
	state: DocumentReaderControllerModule.DocumentReaderState,
	visible: boolean,
	onExitComplete: () -> (),
	onNextPage: () -> (),
	onPreviousPage: () -> (),
}

local TRANSITION_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PANEL_BACKGROUND_TRANSPARENCY = 0.18
local SHADE_BACKGROUND_TRANSPARENCY = 0.42
local PANEL_EXIT_OFFSET = 18

local function DocumentReaderOverlay(props: Props)
	local shadeRef = React.useRef(nil :: Frame?)
	local panelRef = React.useRef(nil :: Frame?)
	local contentRef = React.useRef(nil :: CanvasGroup?)
	local strokeRef = React.useRef(nil :: UIStroke?)
	local transitionIdRef = React.useRef(0)
	local onExitCompleteRef = React.useRef(props.onExitComplete)
	onExitCompleteRef.current = props.onExitComplete

	React.useEffect(function()
		local blur = Instance.new("BlurEffect")
		blur.Name = "DocumentReaderBlur"
		blur.Size = 18
		blur.Parent = Lighting

		return function()
			blur:Destroy()
		end
	end, {})

	React.useEffect(function()
		transitionIdRef.current += 1
		local transitionId = transitionIdRef.current
		local shade = shadeRef.current
		local panel = panelRef.current
		local content = contentRef.current
		local stroke = strokeRef.current
		if shade == nil or panel == nil or content == nil or stroke == nil then
			return
		end

		local exitPosition = UDim2.new(0.5, 0, 0.5, PANEL_EXIT_OFFSET)
		local openPosition = UDim2.fromScale(0.5, 0.5)
		if props.visible then
			shade.BackgroundTransparency = 1
			panel.BackgroundTransparency = 1
			panel.Position = exitPosition
			content.GroupTransparency = 1
			stroke.Transparency = 1
		end

		local shadeTween = TweenService:Create(shade, TRANSITION_INFO, {
			BackgroundTransparency = if props.visible then SHADE_BACKGROUND_TRANSPARENCY else 1,
		})
		local panelTween = TweenService:Create(panel, TRANSITION_INFO, {
			BackgroundTransparency = if props.visible then PANEL_BACKGROUND_TRANSPARENCY else 1,
			Position = if props.visible then openPosition else exitPosition,
		})
		local contentTween = TweenService:Create(content, TRANSITION_INFO, {
			GroupTransparency = if props.visible then 0 else 1,
		})
		local strokeTween = TweenService:Create(stroke, TRANSITION_INFO, {
			Transparency = if props.visible then 0.25 else 1,
		})
		local completionConnection: RBXScriptConnection? = nil
		if not props.visible then
			completionConnection = panelTween.Completed:Connect(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and transitionIdRef.current == transitionId then
					onExitCompleteRef.current()
				end
			end)
		end

		shadeTween:Play()
		panelTween:Play()
		contentTween:Play()
		strokeTween:Play()

		return function()
			if completionConnection ~= nil then
				completionConnection:Disconnect()
			end
			shadeTween:Cancel()
			panelTween:Cancel()
			contentTween:Cancel()
			strokeTween:Cancel()
		end
	end, { props.visible })

	local page = props.state.document.pages[props.state.pageIndex]
	local pageContent = if page ~= nil then page.content else ""
	local pageCount = #props.state.document.pages

	return React.createElement("ScreenGui", {
		DisplayOrder = 2000,
		Enabled = props.enabled,
		IgnoreGuiInset = true,
		Name = "DocumentReaderGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Shade = React.createElement("Frame", {
			Active = true,
			BackgroundColor3 = theme.black,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ref = shadeRef,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}),
		Panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = theme.panel,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			ref = panelRef,
			Size = UDim2.fromScale(0.82, 0.74),
			ZIndex = 2,
		}, {
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(760, 560),
				MinSize = Vector2.new(280, 240),
			}),
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = React.createElement("UIStroke", {
				Color = theme.success,
				ref = strokeRef,
				Transparency = 1,
			}),
			Content = React.createElement("CanvasGroup", {
				BackgroundTransparency = 1,
				GroupTransparency = 1,
				ref = contentRef,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
			}, {
				Title = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.RobotoMono,
					Position = UDim2.fromOffset(28, 24),
					Size = UDim2.new(1, -56, 0, 26),
					Text = props.state.document.displayName,
					TextColor3 = theme.success,
					TextSize = 16,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 3,
				}),
				Page = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.RobotoMono,
					Position = UDim2.fromOffset(28, 58),
					Size = UDim2.new(1, -56, 1, -116),
					Text = pageContent,
					TextColor3 = theme.text,
					TextSize = 17,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					RichText = true,
					ZIndex = 3,
				}),
				PreviousPage = React.createElement("TextButton", {
					Active = props.visible,
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					Font = Enum.Font.RobotoMono,
					Position = UDim2.new(0, 10, 0.5, -20),
					Selectable = false,
					Size = UDim2.fromOffset(24, 40),
					Text = "<",
					TextColor3 = theme.success,
					TextSize = 28,
					Visible = props.state.pageIndex > 1,
					ZIndex = 4,
					[React.Event.Activated] = function()
						if props.visible then
							props.onPreviousPage()
						end
					end,
				}),
				NextPage = React.createElement("TextButton", {
					Active = props.visible,
					AnchorPoint = Vector2.new(1, 0),
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					Font = Enum.Font.RobotoMono,
					Position = UDim2.new(1, -10, 0.5, -20),
					Selectable = false,
					Size = UDim2.fromOffset(24, 40),
					Text = ">",
					TextColor3 = theme.success,
					TextSize = 28,
					Visible = props.state.pageIndex < pageCount,
					ZIndex = 4,
					[React.Event.Activated] = function()
						if props.visible then
							props.onNextPage()
						end
					end,
				}),
				PageIndicator = React.createElement("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundTransparency = 1,
					Font = Enum.Font.RobotoMono,
					Position = UDim2.new(0.5, 0, 1, -24),
					Size = UDim2.new(1, -56, 0, 20),
					Text = string.format("PAGINA %d/%d", props.state.pageIndex, pageCount),
					TextColor3 = theme.textMuted,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 3,
				}),
			}),
		}),
	})
end

return DocumentReaderOverlay
