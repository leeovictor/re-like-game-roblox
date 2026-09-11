--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)

local INVENTORY_TOGGLE_ACTION = "DungeonInventoryToggle"
local INVENTORY_TOGGLE_PRIORITY = Enum.ContextActionPriority.High.Value + 3

local function useInventoryHotkey(blocked: boolean, onToggle: () -> ())
	local onToggleRef = React.useRef(onToggle)
	onToggleRef.current = onToggle

	React.useEffect(function()
		local playerListWasEnabled = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		ContextActionService:BindActionAtPriority(
			INVENTORY_TOGGLE_ACTION,
			function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
					return Enum.ContextActionResult.Sink
				end
				if blocked then
					return Enum.ContextActionResult.Sink
				end
				onToggleRef.current()
				return Enum.ContextActionResult.Sink
			end,
			false,
			INVENTORY_TOGGLE_PRIORITY,
			Enum.KeyCode.Tab
		)

		return function()
			ContextActionService:UnbindAction(INVENTORY_TOGGLE_ACTION)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, playerListWasEnabled)
		end
	end, { blocked })
end

return useInventoryHotkey
