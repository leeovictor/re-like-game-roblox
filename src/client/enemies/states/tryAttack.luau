local StarterPlayer = game:GetService("StarterPlayer")

local config = require(StarterPlayer.StarterPlayerScripts.Client.enemies.config)
local EnemiesTypes = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)
local utils = require(StarterPlayer.StarterPlayerScripts.Client.enemies.utils)
local CharacterRoot = require(StarterPlayer.StarterPlayerScripts.Client.player.CharacterRoot)

local HitBoxSpec = {
	size = Vector3.new(2, 2, 1.5),
	rootOffset = CFrame.new(0, 1, -1)
}

local function createDebugHitbox(): BasePart
	local part = Instance.new('Part');
	part.CanCollide = false
	part.Transparency = 0.6
	part.Color = Color3.fromRGB(255, 0, 0)
	part.Size = HitBoxSpec.size
	part.Parent = workspace
	return part
end

local function resetAttackAttempt(enemy: EnemiesTypes.Enemy): ()
	local humanoid = enemy.humanoid
	if humanoid ~= nil and enemy.oldSpeed ~= nil then
		humanoid.WalkSpeed = enemy.oldSpeed
	end
	if humanoid ~= nil then
		humanoid:Move(Vector3.zero, false)
	end
	if enemy.debugHitbox ~= nil then
		enemy.debugHitbox:Destroy()
		enemy.debugHitbox = nil
	end

	enemy.ellapsedAttackTime = 0
	enemy.realAttackTime = nil
	enemy.attackDirection = nil
	enemy.oldSpeed = nil
	enemy.attackEffectResolved = false
end

local function canStartPlayerAttack(state: EnemiesTypes.SystemState): boolean
	return not state.playerAttackInProgress and os.clock() >= state.playerInvulnerableUntil
end

local function getAttackOrientations(
	enemyRoot: BasePart,
	playerRoot: BasePart
): (CFrame, CFrame)
	local directionToPlayer = Vector3.new(
		playerRoot.Position.X - enemyRoot.Position.X,
		0,
		playerRoot.Position.Z - enemyRoot.Position.Z
	)
	if directionToPlayer.Magnitude == 0 then
		return enemyRoot.CFrame, playerRoot.CFrame
	end
	directionToPlayer = directionToPlayer.Unit

	local enemyTargetCFrame = CFrame.lookAt(enemyRoot.Position, enemyRoot.Position + directionToPlayer)
	local playerLookVector = playerRoot.CFrame.LookVector
	local playerDirection = if playerLookVector:Dot(directionToPlayer) >= 0 then directionToPlayer else -directionToPlayer
	local playerTargetPosition = Vector3.new(
		enemyRoot.Position.X + directionToPlayer.X * config.ATTACKING_PLAYER_DISTANCE,
		playerRoot.Position.Y,
		enemyRoot.Position.Z + directionToPlayer.Z * config.ATTACKING_PLAYER_DISTANCE
	)
	local playerTargetCFrame = CFrame.lookAt(playerTargetPosition, playerTargetPosition + playerDirection)
	return enemyTargetCFrame, playerTargetCFrame
end

local tryAttack: EnemiesTypes.StateObject<EnemiesTypes.EnemyContext> = {
	onBegin = function(context)
		local enemy = context.enemy
		local state = context.systemState
		local playerRoot = CharacterRoot.get()
		local root = enemy.root
		local humanoid = enemy.humanoid
		if playerRoot == nil or root == nil or humanoid == nil then
			return
		end

		enemy.ellapsedAttackTime = 0
		enemy.realAttackTime = utils.rollAttackDuration()
		enemy.oldSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = config.ATTACK_INITIAL_SPEED

		local attackDirection = (playerRoot.Position - root.Position).Unit
		local attackAngle = math.rad(math.random(config.ATTACK_DIRECTION_MIN_ANGLE, config.ATTACK_DIRECTION_MAX_ANGLE))
		local attackDirectionSign = if math.random(0, 1) == 0 then -1 else 1
		local playerCharacter = playerRoot.Parent
		local playerHumanoid = if playerCharacter ~= nil then playerCharacter:FindFirstChildOfClass("Humanoid") else nil
		local movementDirection = if playerHumanoid ~= nil and playerHumanoid.MoveDirection.Magnitude > 0
			then playerHumanoid.MoveDirection.Unit
			else playerRoot.CFrame.LookVector
		local positiveAngleDirection = CFrame.Angles(0, attackAngle, 0):VectorToWorldSpace(attackDirection)
		local negativeAngleDirection = CFrame.Angles(0, -attackAngle, 0):VectorToWorldSpace(attackDirection)
		local alignmentDifference = positiveAngleDirection:Dot(movementDirection) - negativeAngleDirection:Dot(movementDirection)
		if math.abs(alignmentDifference) > 0.001 and math.random() < config.ATTACK_MOVEMENT_DIRECTION_WEIGHT then
			attackDirectionSign = if alignmentDifference > 0 then 1 else -1
		end
		attackAngle *= attackDirectionSign
		local attackMovementDirection = CFrame.Angles(0, attackAngle, 0):VectorToWorldSpace(attackDirection)
		enemy.attackDirection = utils.horizontalUnit(attackMovementDirection, root.CFrame.LookVector)
		enemy.debugHitbox = if state.debugEnabled then createDebugHitbox() else nil
		if enemy.debugHitbox ~= nil then
			enemy.debugHitbox.CFrame = root.CFrame * HitBoxSpec.rootOffset
		end
	end,
	update = function (context, dt: number)
		local enemy = context.enemy
        local state = context.systemState
		
		if not enemy.humanoid then
			return 'idle'
		end

		local playerRoot = CharacterRoot.get()
		local root = enemy.root

		if not playerRoot or not root then
			return 'idle'
		end
		
		enemy.ellapsedAttackTime += dt
		local attackTime = enemy.realAttackTime
		local attackDirection = enemy.attackDirection
		if attackTime == nil or attackDirection == nil then
			return 'idle'
		end
		local currentDirection = utils.horizontalUnit(root.CFrame.LookVector, attackDirection)
		local blend = 1 - math.exp(-config.TRY_ATTACK_TURN_SPEED * dt)
		local movementDirection = utils.horizontalUnit(currentDirection:Lerp(attackDirection, blend), attackDirection)
		enemy.humanoid:Move(movementDirection, false)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + movementDirection)
		local attackProgress = math.clamp(enemy.ellapsedAttackTime / attackTime, 0, 1)
		if attackProgress <= config.ATTACK_ACCELERATION_RATIO then
			local accelerationProgress = attackProgress / config.ATTACK_ACCELERATION_RATIO
			enemy.humanoid.WalkSpeed = config.ATTACK_INITIAL_SPEED
				+ (config.ATTACK_PEAK_SPEED - config.ATTACK_INITIAL_SPEED) * accelerationProgress
		else
			local decelerationProgress = (attackProgress - config.ATTACK_ACCELERATION_RATIO)
				/ (1 - config.ATTACK_ACCELERATION_RATIO)
			enemy.humanoid.WalkSpeed = config.ATTACK_PEAK_SPEED
				+ (config.ATTACK_END_SPEED - config.ATTACK_PEAK_SPEED) * decelerationProgress
		end
		
		-- check for player collision with the hitbox
		if enemy.debugHitbox ~= nil then
			enemy.debugHitbox.CFrame = root.CFrame * HitBoxSpec.rootOffset
		end
		
		local params = OverlapParams.new()
		local playerCharacter = playerRoot.Parent
		if playerCharacter == nil then
			return 'idle'
		end
		params.IncludeInstances = { playerCharacter }
		local result = workspace:GetPartBoundsInBox(root.CFrame * HitBoxSpec.rootOffset, HitBoxSpec.size, params)
		if #result > 0 and not enemy.attackEffectResolved then
			enemy.attackEffectResolved = true
			if not canStartPlayerAttack(state) then
				print('player attack blocked')
				return
			end
			if not utils.rollChance(config.ATTACK_EFFECTIVE_CHANCE) then
				print('player not attacked. chance roll failed')
				return
			end
			print('player attacked')

			enemy.attackTargetHumanoid = playerCharacter:FindFirstChildOfClass('Humanoid')
			enemy.attackingEnemyStartCFrame = root.CFrame
			enemy.attackingPlayerStartCFrame = playerRoot.CFrame
			enemy.attackingEnemyTargetCFrame, enemy.attackingPlayerTargetCFrame = getAttackOrientations(root, playerRoot)
			enemy.movementController:setLookVector(playerRoot.CFrame.LookVector)
			enemy.playerAttackOwner = true
			state.playerAttackInProgress = true
			return 'attacking'
		end
		
		if enemy.ellapsedAttackTime >= attackTime then
			return 'stunned'
		end
		
		return
	end,
	onEnd = function(context)
		resetAttackAttempt(context.enemy)
	end,
}

return tryAttack
