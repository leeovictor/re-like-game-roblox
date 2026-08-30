--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local StarterPlayer = game:GetService("StarterPlayer")

local InventoryControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController)

local function useInventory(controller: InventoryControllerModule.InventoryController)
	local inventory, setInventory = React.useState(controller:getState())

	React.useEffect(function()
		local connection = controller.changed:Connect(function(snapshot)
			setInventory(snapshot)
		end)

		return function()
			connection:Disconnect()
		end
	end, { controller })

	return inventory
end

return useInventory
