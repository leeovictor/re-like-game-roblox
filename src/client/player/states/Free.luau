--!strict

local StarterPlayer = game:GetService("StarterPlayer")
local PlayerTypes = require(StarterPlayer.StarterPlayerScripts.Client.player.types)

local FreeState: PlayerTypes.StateObject = {
	update = function(context, deltaTime)
		context.updateFreeMovement(deltaTime)
	end,
	onAimChanged = function(context, aiming)
		if not aiming then
			return
		end
		local accepted, targetDirection = context.beginAim()
		if not accepted then
			return
		end
		context.setAimTarget(targetDirection)
		context.transition("Aiming")
	end,
}

return FreeState
