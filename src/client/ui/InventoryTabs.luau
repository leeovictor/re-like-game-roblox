--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	activeTab: string,
	onTabChanged: (tab: string) -> (),
}

local function InventoryTabs(props: Props)
	return React.createElement("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 28),
	}, {
		Items = React.createElement("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = if props.activeTab == "items" then theme.surfaceActive else theme.surface,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(0.48, -3, 1, 0),
			Text = "ITENS",
			TextColor3 = theme.text,
			TextSize = 11,
			[React.Event.Activated] = function()
				props.onTabChanged("items")
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
		}),
		Documents = React.createElement("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = if props.activeTab == "documents" then theme.surfaceActive else theme.surface,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0.52, 3, 0, 0),
			Size = UDim2.new(0.48, -3, 1, 0),
			Text = "DOCUMENTOS",
			TextColor3 = theme.text,
			TextSize = 11,
			[React.Event.Activated] = function()
				props.onTabChanged("documents")
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
		}),
	})
end

return InventoryTabs
