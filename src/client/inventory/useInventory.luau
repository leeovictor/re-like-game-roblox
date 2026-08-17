--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local controller = require(script.Parent.InventoryController)

local function useInventory()
	local inventory, setInventory = React.useState(controller.getState())

	React.useEffect(function()
		local connection = controller.changed:Connect(function(snapshot)
			setInventory(snapshot)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	return inventory
end

return useInventory
