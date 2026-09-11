--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	itemId: items.ItemId?,
}

local function PickupToast(props: Props)
	local itemId = props.itemId
	if itemId == nil then
		return nil
	end

	local item = items[itemId]
	local name = if item ~= nil then item.name else itemId

	return React.createElement("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(240, 42),
		Font = Enum.Font.GothamBold,
		Text = "Pegou " .. name,
		TextColor3 = theme.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
	})
end

return PickupToast
