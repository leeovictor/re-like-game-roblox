--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
local DialogueControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueController)

type Props = {
	dialogue: DialogueControllerModule.DialogState?,
}

local function resolveDialogueText(dialogue: DialogueControllerModule.DialogState): string
	local text = dialogue.visibleText
	if dialogue.kind == "question" and not dialogue.isTyping then
		local renderedOptions = {}
		for index, option in dialogue.options do
			local marker = if index == dialogue.selectedIndex then "> " else "  "
			table.insert(renderedOptions, marker .. option.text)
		end
		text = (dialogue.visibleText or "") .. "\n" .. table.concat(renderedOptions, "    ")
	end
	return text
end

local function DialogueOverlay(props: Props)
	local dialogue = props.dialogue
	if dialogue == nil then
		return nil
	end

	return React.createElement("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0.8, 0),
		Size = UDim2.new(0.6, 0, 0, 0),
		Font = Enum.Font.RobotoMono,
		RichText = true,
		Text = "<b>" .. resolveDialogueText(dialogue) .. "</b>",
		TextColor3 = theme.success,
		TextSize = 20,
		TextStrokeColor3 = theme.panel,
		TextStrokeTransparency = 0.05,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = 20,
	})
end

return DialogueOverlay
