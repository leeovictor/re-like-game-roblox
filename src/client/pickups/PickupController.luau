--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local remotes = require(ReplicatedStorage.Shared.remotes)

export type Dependencies = {
	collect: (request: { pickup: Instance }) -> (),
}

local function createController(dependencies: Dependencies): interactionTypes.InteractionHandler
	local controller = {} :: interactionTypes.InteractionHandler

	function controller.interact(target: Instance): ()
		if not target:IsA("BasePart") and not target:IsA("Model") then
			return
		end
		dependencies.collect({ pickup = target })
	end

	return controller
end

local defaultDependencies: Dependencies = {
	collect = function(request): ()
		local remote = remotes.CollectPickup
		if not remote:IsA("RemoteFunction") then
			return
		end
		remote:InvokeServer(request)
	end,
}

local defaultController = createController(defaultDependencies)

return {
	new = createController,
	interact = defaultController.interact,
}
