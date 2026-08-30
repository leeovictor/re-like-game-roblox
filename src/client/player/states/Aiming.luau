--!strict

local StarterPlayer = game:GetService("StarterPlayer")
local PlayerTypes = require(StarterPlayer.StarterPlayerScripts.Client.player.types)

local AimingState: PlayerTypes.StateObject = {
	update = function(context, deltaTime)
		context.stopMovement()
		context.updateAimRotation(deltaTime)
	end,
	onAimChanged = function(context, aiming)
		if aiming then
			return
		end
		context.endAim()
		context.transition("Free")
	end,
	onShoot = function(context)
		context.shoot()
		if context.combat.state == "reloading" then
			context.transition("Reloading")
		end
	end,
	onReload = function(context)
		if context.requestReload() then
			context.transition("Reloading")
		end
	end,
}

return AimingState
