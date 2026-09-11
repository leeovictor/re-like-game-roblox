--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	weaponName: string,
	loadedAmmo: string,
	reserveAmmo: string,
}

local function CombatStatus(props: Props)
	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(224, 76),
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = theme.accent,
			Transparency = 0.25,
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 16),
			Font = Enum.Font.Gotham,
			Text = "ARMA EQUIPADA",
			TextColor3 = theme.textMuted,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Weapon = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 24),
			Size = UDim2.new(1, -28, 0, 22),
			Font = Enum.Font.GothamBold,
			Text = props.weaponName,
			TextColor3 = theme.text,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Ammo = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 49),
			Size = UDim2.new(1, -28, 0, 18),
			Font = Enum.Font.GothamBold,
			Text = string.format("CARREGADA  %s    DISPONÍVEL  %s", props.loadedAmmo, props.reserveAmmo),
			TextColor3 = theme.success,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

return CombatStatus
