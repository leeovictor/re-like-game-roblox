--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

type Props = {
	visible: boolean,
	message: string,
	confirmLabel: string,
	cancelLabel: string,
	onConfirm: () -> (),
	onCancel: () -> (),
}

local function ConfirmationModal(props: Props)
	if not props.visible then
		return nil
	end

	return React.createElement("Frame", {
		Active = true,
		BackgroundColor3 = Color3.fromRGB(8, 9, 14),
		BackgroundTransparency = 0.35,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
	}, {
		Panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(20, 22, 30),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.8, 0, 0, 164),
			ZIndex = 101,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(132, 104, 205),
				Thickness = 1,
			}),
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(360, 164),
				MinSize = Vector2.new(240, 164),
			}),
			Padding = React.createElement("UIPadding", {
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
				PaddingTop = UDim.new(0, 16),
			}),
			Message = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0, 68),
				Text = props.message,
				TextColor3 = Color3.fromRGB(241, 237, 255),
				TextSize = 17,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 102,
			}),
			Buttons = React.createElement("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 0, 1, -48),
				Size = UDim2.new(1, 0, 0, 40),
				ZIndex = 102,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				CancelButton = React.createElement("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = Color3.fromRGB(52, 55, 70),
					Font = Enum.Font.GothamBold,
					LayoutOrder = 1,
					Size = UDim2.new(0.45, -5, 1, 0),
					Text = props.cancelLabel,
					TextColor3 = Color3.fromRGB(225, 222, 239),
					TextSize = 14,
					[React.Event.Activated] = props.onCancel,
					ZIndex = 103,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 6),
					}),
				}),
				ConfirmButton = React.createElement("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = Color3.fromRGB(107, 78, 168),
					Font = Enum.Font.GothamBold,
					LayoutOrder = 2,
					Size = UDim2.new(0.45, -5, 1, 0),
					Text = props.confirmLabel,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 14,
					[React.Event.Activated] = props.onConfirm,
					ZIndex = 103,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 6),
					}),
				}),
			}),
		}),
	})
end

return ConfirmationModal
