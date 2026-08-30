--!strict

local StarterPlayer = game:GetService("StarterPlayer")
local PlayerTypes = require(StarterPlayer.StarterPlayerScripts.Client.player.types)

local ReloadingState: PlayerTypes.StateObject = {
	update = function(context)
		context.stopMovement()
		if context.combat.state ~= "neutral" then
			return
		end

		if context.input.aiming then
			local accepted, targetDirection = context.beginAim()
			if accepted then
				context.setAimTarget(targetDirection)
				context.transition("Aiming")
				return
			end
		end

		context.transition("Free")
	end,
}

return ReloadingState
