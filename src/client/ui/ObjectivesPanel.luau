--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
local useObjectives = require(StarterPlayer.StarterPlayerScripts.Client.objectives.useObjectives)

type Props = {
	visible: boolean,
	objectives: useObjectives.ObjectiveState?,
}

local function ObjectivesPanel(props: Props)
	if not props.visible then
		return nil
	end
	local objectives = props.objectives
	if objectives == nil then
		return nil
	end

	local objectiveRows = {}
	for index, objective in objectives.objectives do
		local marker = if objective.completed then "[x] " else "* "
		objectiveRows[objective.id] = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Size = UDim2.new(1, -24, 0, 28),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = Enum.Font.Gotham,
			Text = marker .. objective.text,
			TextColor3 = if objective.completed then theme.successMuted else theme.objectiveText,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		})
	end
	objectiveRows.ListLayout = React.createElement("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	return React.createElement("Frame", {
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		SizeConstraint = React.createElement("UISizeConstraint", {
			MaxSize = Vector2.new(340, 1000),
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 24),
			Font = Enum.Font.GothamBold,
			Text = "OBJETIVOS",
			TextColor3 = theme.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 44),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, objectiveRows),
	})
end

return ObjectivesPanel
