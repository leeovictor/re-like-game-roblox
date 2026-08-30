local StarterPlayer = game:GetService("StarterPlayer")

local config = require(StarterPlayer.StarterPlayerScripts.Client.enemies.config)
local EnemiesTypes = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)

local attacking: EnemiesTypes.StateObject<EnemiesTypes.EnemyContext> = {
	onBegin = function(context)
		local enemy = context.enemy
		enemy.ellapsedAttackingTime = 0
	end,
	update = function (context, dt: number)
		local enemy = context.enemy

		enemy.ellapsedAttackingTime += dt
		local turnProgress = math.clamp(enemy.ellapsedAttackingTime / config.ATTACKING_TURN_TIME, 0, 1)
		local enemyRoot = enemy.root
		local enemyStartCFrame = enemy.attackingEnemyStartCFrame
		local enemyTargetCFrame = enemy.attackingEnemyTargetCFrame
		local playerStartCFrame = enemy.attackingPlayerStartCFrame
		local playerTargetCFrame = enemy.attackingPlayerTargetCFrame
		if enemyRoot ~= nil and enemyStartCFrame ~= nil and enemyTargetCFrame ~= nil then
			local interpolatedCFrame = enemyStartCFrame:Lerp(enemyTargetCFrame, turnProgress)
			enemyRoot.CFrame = CFrame.new(enemyRoot.Position) * (interpolatedCFrame - interpolatedCFrame.Position)
		end
		if playerStartCFrame ~= nil and playerTargetCFrame ~= nil then
			local interpolatedCFrame = playerStartCFrame:Lerp(playerTargetCFrame, turnProgress)
			enemy.movementController:setCFrame(interpolatedCFrame)
		end

		if enemy.ellapsedAttackingTime < config.ATTACKING_TIME then return end
		return 'stunned'
	end,
	onEnd = function(context)
		local enemy = context.enemy
		local state = context.systemState
		if enemy.attackTargetHumanoid ~= nil then
			enemy.attackTargetHumanoid:TakeDamage(config.ATTACKING_DAMAGE)
		end
        
		enemy.playerAttackOwner = false
		state.playerAttackInProgress = false
		state.playerInvulnerableUntil = os.clock() + config.PLAYER_INVULNERABILITY_TIME
        
		enemy.ellapsedAttackingTime = 0
		enemy.attackTargetHumanoid = nil
		enemy.attackingEnemyStartCFrame = nil
		enemy.attackingEnemyTargetCFrame = nil
		enemy.attackingPlayerStartCFrame = nil
		enemy.attackingPlayerTargetCFrame = nil
	end,
}

return attacking
