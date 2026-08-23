--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local useDialogue = require(script.Parent.Parent.dialogue.useDialogue)
local useInventory = require(script.Parent.Parent.inventory.useInventory)
local useObjectiveNotification = require(script.Parent.Parent.objectives.useObjectiveNotification)
local timing = require(script.Parent.Parent.objectives.ObjectiveNotificationTiming)
local useObjectives = require(script.Parent.Parent.objectives.useObjectives)
local usePickupNotification = require(script.Parent.Parent.pickups.usePickupNotification)

local function App()
	local inventoryVisible, setInventoryVisible = React.useState(false)
	local notificationItemId = usePickupNotification()
	local inventory = useInventory()
	local objectives = useObjectives()
	local objectiveNotification = useObjectiveNotification()
	local objectiveNotificationRef = React.useRef(nil :: TextLabel?)
	local dialogue = useDialogue()

	React.useEffect(function()
		local connection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
			if input.KeyCode ~= Enum.KeyCode.T then
				return
			end
			if gameProcessedEvent and UserInputService:GetFocusedTextBox() then
				return
			end

			setInventoryVisible(function(previousVisible: boolean): boolean
				return not previousVisible
			end)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	React.useEffect(function()
		local notification = objectiveNotificationRef.current
		if objectiveNotification == nil or notification == nil then
			return
		end

		local active = true
		local strokeInstance = notification:FindFirstChild("Stroke")
		local stroke = if strokeInstance ~= nil and strokeInstance:IsA("UIStroke") then strokeInstance else nil
		local fadeOut: Tween? = nil
		local strokeFadeOut: Tween? = nil

		local fadeIn = TweenService:Create(notification, TweenInfo.new(timing.fadeInDuration), {
			TextTransparency = 0,
			BackgroundTransparency = 0.08,
		})
		local strokeFadeIn = if stroke ~= nil
			then TweenService:Create(stroke, TweenInfo.new(timing.fadeInDuration), { Transparency = 0.25 })
			else nil

		fadeIn:Play()
		if strokeFadeIn ~= nil then
			strokeFadeIn:Play()
		end

		task.delay(timing.fadeInDuration + timing.visibleDuration, function()
			if not active then
				return
			end
			local nextFadeOut = TweenService:Create(notification, TweenInfo.new(timing.fadeOutDuration), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			fadeOut = nextFadeOut
			strokeFadeOut = if stroke ~= nil
				then TweenService:Create(stroke, TweenInfo.new(timing.fadeOutDuration), { Transparency = 1 })
				else nil
			nextFadeOut:Play()
			if strokeFadeOut ~= nil then
				strokeFadeOut:Play()
			end
		end)

		return function()
			active = false
			fadeIn:Cancel()
			if strokeFadeIn ~= nil then
				strokeFadeIn:Cancel()
			end
			if fadeOut ~= nil then
				fadeOut:Cancel()
			end
			if strokeFadeOut ~= nil then
				strokeFadeOut:Cancel()
			end
		end
	end, { objectiveNotification })

	local inventoryRows = {}

	if inventory ~= nil then
		for index, instance in inventory.items do
			local itemId = instance.itemId
			local item = items[itemId]
			local itemName = if item ~= nil then item.name else itemId
			local quantity = if instance.quantity ~= nil then string.format(" x%d", instance.quantity) else ""

			inventoryRows[tostring(index) .. ":" .. instance.uid] = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Size = UDim2.new(1, -24, 0, 28),
				Font = Enum.Font.Gotham,
				Text = itemName .. quantity,
				TextColor3 = Color3.fromRGB(225, 222, 239),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end

	local listChildren = inventoryRows
	listChildren.ListLayout = React.createElement("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	if inventory == nil then
		listChildren = {
			Loading = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 0, 28),
				Font = Enum.Font.Gotham,
				Text = "Carregando inventário...",
				TextColor3 = Color3.fromRGB(173, 179, 198),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			ListLayout = listChildren.ListLayout,
		}
	end

	local inventoryPanel = if inventoryVisible then React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0),
			BackgroundColor3 = Color3.fromRGB(20, 22, 30),
			BackgroundTransparency = 0.08,
			Position = UDim2.fromOffset(24, 154),
			Size = UDim2.new(1, -48, 0, 220),
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(107, 92, 168),
				Transparency = 0.25,
			}),
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(360, 220),
			}),
			Title = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 12),
				Size = UDim2.new(1, -32, 0, 24),
				Font = Enum.Font.GothamBold,
				Text = "INVENTÁRIO",
				TextColor3 = Color3.fromRGB(241, 237, 255),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			List = React.createElement("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 1, -56),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				ScrollBarImageColor3 = Color3.fromRGB(107, 92, 168),
				ScrollBarThickness = 4,
			}, listChildren),
		})
		else nil

	local objectiveRows = {}
	if objectives ~= nil then
		for index, objective in objectives.objectives do
			local marker = if objective.completed then "[x] " else "* "
			objectiveRows[objective.id] = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Size = UDim2.new(1, -24, 0, 28),
				AutomaticSize = Enum.AutomaticSize.Y,
				Font = Enum.Font.Gotham,
				Text = marker .. objective.text,
				TextColor3 = if objective.completed
					then Color3.fromRGB(173, 196, 162)
					else Color3.fromRGB(225, 222, 239),
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
			})
		end
	end
	objectiveRows.ListLayout = React.createElement("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local objectivePanel = if inventoryVisible and objectives ~= nil then React.createElement("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 30),
		BackgroundTransparency = 0.08,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(107, 92, 168),
			Transparency = 0.25,
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
			TextColor3 = Color3.fromRGB(241, 237, 255),
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
	}) else nil

	local objectiveNotice = if objectiveNotification ~= nil then React.createElement("TextLabel", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 30),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.GothamBold,
		ref = objectiveNotificationRef,
		Text = (if #objectiveNotification == 1 then "NOVO OBJETIVO" else "NOVOS OBJETIVOS")
			.. "\n"
			.. table.concat((function()
				local texts = {}
				for _, objective in objectiveNotification do
					table.insert(texts, objective.text)
				end
				return texts
			end)(), "\n"),
		TextColor3 = Color3.fromRGB(241, 237, 255),
		TextSize = 14,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 12),
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(107, 92, 168),
			Transparency = 1,
		}),
	}) else nil

	local notificationItem = if notificationItemId ~= nil then items[notificationItemId] else nil
	local notificationName = if notificationItem ~= nil then notificationItem.name else notificationItemId
	local dialogueText: string? = nil

	if dialogue ~= nil then
		dialogueText = dialogue.visibleText
		if dialogue.kind == "question" and not dialogue.isTyping then
			local renderedOptions = {}
			for index, option in dialogue.options do
				local marker = if index == dialogue.selectedIndex then "> " else "  "
				table.insert(renderedOptions, marker .. option.text)
			end
			local visibleText: string = dialogue.visibleText or ""
			dialogueText = visibleText .. "\n" .. table.concat(renderedOptions, "    ")
		end
	end

	return React.createElement("ScreenGui", {
		Name = "DungeonGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		ObjectiveStack = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -24, 0, 24),
			Size = UDim2.new(1, -48, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, {
			ListLayout = React.createElement("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(340, 1000),
			}),
			Notice = objectiveNotice,
			Panel = objectivePanel,
		}),
		InventoryPanel = inventoryPanel,
		Dialogue = if dialogueText ~= nil
			then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, 0, 0.8, 0),
				Size = UDim2.new(0.6, 0, 0, 0),
				Font = Enum.Font.RobotoMono,
				RichText = true,
				Text = '<b>' .. dialogueText .. "</b>",
				TextColor3 = Color3.fromRGB(191, 223, 161),
				TextSize = 20,
				TextStrokeColor3 = Color3.fromRGB(20, 22, 30),
				TextStrokeTransparency = 0.05,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				ZIndex = 20,
			})
			else nil,
		PickupNotification = if notificationName ~= nil
			then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.fromRGB(20, 22, 30),
				BackgroundTransparency = 0.08,
				Position = UDim2.new(0, 24, 1, -24),
				Size = UDim2.fromOffset(240, 42),
				Font = Enum.Font.GothamBold,
				Text = "Pegou " .. notificationName,
				TextColor3 = Color3.fromRGB(241, 237, 255),
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
				Stroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(107, 92, 168),
					Transparency = 0.25,
				}),
			})
			else nil,
	})
end

return App
