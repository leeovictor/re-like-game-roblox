local StarterPlayer = game:GetService("StarterPlayer")

local EnemiesTypes = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)
local CharacterRoot = require(StarterPlayer.StarterPlayerScripts.Client.player.CharacterRoot)

local IdleState: EnemiesTypes.StateObject<EnemiesTypes.EnemyContext> = {
	update = function (context)
		local playerRoot = CharacterRoot.get()
		local enemyRoot = context.enemy.root

		if 	playerRoot == nil
			or enemyRoot == nil
			or (playerRoot.Position - enemyRoot.Position).Magnitude > context.enemy.detectionRadius then
			return
		end

		return 'chasing';
	end
}

return IdleState
