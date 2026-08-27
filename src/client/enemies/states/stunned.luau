local StarterPlayer = game:GetService("StarterPlayer")
local EnemiesTypes = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)
local utils = require(StarterPlayer.StarterPlayerScripts.Client.enemies.utils)

local Stunned: EnemiesTypes.StateObject<EnemiesTypes.EnemyContext> = {
    onBegin = function (context)
        local enemy = context.enemy
		
		enemy.ellapsedStuntime = 0
		enemy.realStunTime = utils.rollStunDuration()
		if enemy.humanoid ~= nil and enemy.humanoid.MoveDirection ~= Vector3.zero then
			enemy.humanoid:Move(Vector3.zero, false)
		end
    end,
	update = function (context, dt: number)
        local enemy = context.enemy
        
		enemy.ellapsedStuntime += dt
		if enemy.ellapsedStuntime >= (enemy.realStunTime :: number) then
			return "chasing"
		end
		
		return
	end,
	onEnd = function(context)
		local enemy = context.enemy
		enemy.ellapsedStuntime = 0
		enemy.realStunTime = nil
	end
}

return Stunned
