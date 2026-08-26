--!strict

local PathfindingService = game:GetService("PathfindingService")
local CharacterRoot = require(script.Parent.Parent.player.CharacterRoot)

local DETECTION_RADIUS_REF = 10
local PATH_RECOMPUTE_INTERVAL = 1
local CHASE_TURN_SPEED = 1.8
local CHASE_STUCK_TIME = 0.4
local CHASE_STUCK_TURN_SPEED = 8
local CHASE_STUCK_CHECK_INTERVAL = 0.2
local CHASE_STUCK_MIN_MOVEMENT = 0.05
local CHASE_WAYPOINT_REACHED_DISTANCE = 1.5
local ATTACK_DISTANCE_REF = 6.8
local ATTACK_DISTANCE_MAX_REDUCTION = 0.3
local ATTACK_TIME_MIN = 1
local ATTACK_TIME_MAX = 1.7
local TRY_ATTACK_TURN_SPEED = 12

export type State = "idle" | "chasing" | "try_attack" | "attacking" | "stunned"
export type MovementController = {
	acquireMovementLock: (self: MovementController) -> (() -> ()),
	setLookVector: (self: MovementController, lookVector: Vector3) -> (),
	setCFrame: (self: MovementController, cframe: CFrame) -> (),
}
export type EnemyContext = {
	enemy: Enemy,
}

export type Enemy = {
	model: Model,
	state: State,
	humanoid: Humanoid?,
	root: BasePart?,
	path: Path?,
	pathElapsed: number,
	chaseWaypoints: { PathWaypoint },
	chaseWaypointIndex: number,
	chaseDirection: Vector3,
	chaseProgressPosition: Vector3,
	chaseProgressElapsed: number,
	chaseStuckElapsed: number,
	destroyed: boolean,
	update: (self: Enemy, deltaTime: number) -> (),
	destroy: (self: Enemy) -> (),
	currentState: StateObject<EnemyContext>,
	detectionRadius: number,
	attackTriggerDistance: number,
	ellapsedAttackTime: number,
	realAttackTime: number?,
	attackDirection: Vector3?,
	oldSpeed: number?,
	attackSetup: boolean,
	attackEffectResolved: boolean,
	debugHitbox: BasePart?,
	ellapsedStuntime: number,
	realStunTime: number?,
	ellapsedAttackingTime: number,
	attackTargetHumanoid: Humanoid?,
	movementController: MovementController,
	movementLockRelease: (() -> ())?,
	attackingEnemyStartCFrame: CFrame?,
	attackingEnemyTargetCFrame: CFrame?,
	attackingPlayerStartCFrame: CFrame?,
	attackingPlayerTargetCFrame: CFrame?,
	playerAttackOwner: boolean,
}

export type StateMachine<C> = {
	states: { [string]: StateObject<C> }
}

export type StateObject<C> = {
	update: (context: C, deltaTime: number) -> string?,
	onBegin: (context: C) -> ()?,
	onEnd: (context: C) -> ()?,
}

local playerAttackInProgress = false
local playerInvulnerableUntil = 0

local function failPath(self: Enemy, message: string): ()
	warn(("[Enemy:%s] %s"):format(self.model.Name, message))
end

local function gamble(chance: number): boolean
	assert(chance >= 0 and chance <= 100, 'change must be between 0 and 100')
	local gen = math.random(1, 100)
	return gen >= 1 and gen <= chance
end

local function getAttackTriggerDistance(): number
	return ATTACK_DISTANCE_REF - math.random() * ATTACK_DISTANCE_MAX_REDUCTION
end

local function getAttackTime(): number
	return ATTACK_TIME_MIN + math.random() * (ATTACK_TIME_MAX - ATTACK_TIME_MIN)
end

local function canStartPlayerAttack(): boolean
	return not playerAttackInProgress and os.clock() >= playerInvulnerableUntil
end

local DEFAULT_CHASE_DIRECTION = Vector3.new(0, 0, -1)

local function horizontalUnit(direction: Vector3, fallback: Vector3): Vector3
	local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
	if horizontalDirection.Magnitude == 0 then
		return fallback
	end
	return horizontalDirection.Unit
end

local function updateChaseMovement(self: Enemy, root: BasePart, humanoid: Humanoid, playerRoot: BasePart, dt: number): ()
	self.chaseProgressElapsed += dt
	if self.chaseProgressElapsed >= CHASE_STUCK_CHECK_INTERVAL then
		local movementSinceLastCheck = (root.Position - self.chaseProgressPosition).Magnitude
		if movementSinceLastCheck < CHASE_STUCK_MIN_MOVEMENT then
			self.chaseStuckElapsed += self.chaseProgressElapsed
		else
			self.chaseStuckElapsed = 0
		end
		self.chaseProgressPosition = root.Position
		self.chaseProgressElapsed = 0
	end

	while self.chaseWaypointIndex <= #self.chaseWaypoints do
		local waypoint = self.chaseWaypoints[self.chaseWaypointIndex]
		local distanceToWaypoint = (waypoint.Position - root.Position).Magnitude
		if distanceToWaypoint > CHASE_WAYPOINT_REACHED_DISTANCE then
			break
		end
		self.chaseWaypointIndex += 1
	end

	local waypoint: PathWaypoint? = if self.chaseWaypointIndex <= #self.chaseWaypoints
		then self.chaseWaypoints[self.chaseWaypointIndex]
		else nil
	local targetPosition = if waypoint ~= nil then waypoint.Position else playerRoot.Position
	local currentDirection = horizontalUnit(root.CFrame.LookVector, self.chaseDirection)
	local targetDirection = horizontalUnit(targetPosition - root.Position, currentDirection)
	local turnSpeed = if self.chaseStuckElapsed >= CHASE_STUCK_TIME then CHASE_STUCK_TURN_SPEED else CHASE_TURN_SPEED
	local blend = 1 - math.exp(-turnSpeed * dt)
	local movementDirection = horizontalUnit(currentDirection:Lerp(targetDirection, blend), targetDirection)

	self.chaseDirection = movementDirection
	humanoid:Move(movementDirection, false)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + movementDirection)
	root.AssemblyAngularVelocity = Vector3.zero
end

local IdleState: StateObject<EnemyContext> = {
	update = function (context, dt: number)
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

local ChasingState: StateObject<EnemyContext> = {
	update = function (context, dt: number)
		context.enemy.pathElapsed += dt
		local playerRoot = CharacterRoot.get()
		local root = context.enemy.root
		local path = context.enemy.path
		
		if root == nil or path == nil or playerRoot == nil then
			return 'idle'
		end

		if (playerRoot.Position - root.Position).Magnitude <= context.enemy.attackTriggerDistance then
			context.enemy.attackTriggerDistance = getAttackTriggerDistance()
			context.enemy.pathElapsed = 0;
			return 'try_attack';
		end
		local humanoid = context.enemy.humanoid
		if humanoid == nil then
			return 'idle'
		end

		if context.enemy.pathElapsed >= PATH_RECOMPUTE_INTERVAL then
			context.enemy.pathElapsed = 0
			local ok, errorMessage = pcall(function()
				path:ComputeAsync(root.Position, playerRoot.Position)
			end)

			if not ok then
				failPath(context.enemy, ("ComputeAsync failed: %s"):format(tostring(errorMessage)))
				return 'idle'
			end

			if path.Status ~= Enum.PathStatus.Success then
				failPath(context.enemy, ("Pathfinding failed with status: %s"):format(path.Status.Name))
				return 'idle'
			end

			local waypoints = path:GetWaypoints()
			for _, waypoint in waypoints do
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					failPath(context.enemy, "jump waypoint is unsupported")
					return
				end
			end

			if #waypoints < 2 then
				failPath(context.enemy, "no usable waypoint")
				return
			end

			context.enemy.chaseWaypoints = waypoints
			context.enemy.chaseWaypointIndex = 2
		end

		updateChaseMovement(context.enemy, root, humanoid, playerRoot, dt)
		return
	end
}

local ATTACK_DIRECTION_MIN_ANGLE = 10
local ATTACK_DIRECTION_MAX_ANGLE = 20
local ATTACK_MOVEMENT_DIRECTION_WEIGHT = 0.7
local ATTACK_INITIAL_SPEED = 8
local ATTACK_PEAK_SPEED = 10
local ATTACK_END_SPEED = 0
local ATTACK_ACCELERATION_RATIO = 0.2
local ATTACK_EFFECTIVE_CHANCE = 90
local ATTACKING_PLAYER_DISTANCE = 2.5
local PLAYER_INVULNERABILITY_TIME = 1

local debugEnabled = true
local hitBox = {
	size = Vector3.new(2, 2, 1.5),
	rootOffset = CFrame.new(0, 1, -1)
}

local function createDebugHitbox(): BasePart
	local part = Instance.new('Part');
	part.CanCollide = false
	part.Transparency = 0.6
	part.Color = Color3.fromRGB(255, 0, 0)
	part.Size = hitBox.size
	part.Parent = workspace
	return part
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
		enemyRoot.Position.X + directionToPlayer.X * ATTACKING_PLAYER_DISTANCE,
		playerRoot.Position.Y,
		enemyRoot.Position.Z + directionToPlayer.Z * ATTACKING_PLAYER_DISTANCE
	)
	local playerTargetCFrame = CFrame.lookAt(playerTargetPosition, playerTargetPosition + playerDirection)
	return enemyTargetCFrame, playerTargetCFrame
end

local tryAttack: StateObject<EnemyContext> = {
	update = function (context, dt: number)
		local enemy = context.enemy
		
		if not enemy.humanoid then
			return 'idle'
		end

		local playerRoot = CharacterRoot.get()
		local root = enemy.root

		if not playerRoot or not root then
			return 'idle'
		end
		
		if not enemy.attackSetup then
			enemy.realAttackTime = getAttackTime()
			enemy.oldSpeed = enemy.humanoid.WalkSpeed
			enemy.humanoid.WalkSpeed = ATTACK_INITIAL_SPEED
			local attackDirection = (playerRoot.Position - root.Position).Unit
			local attackAngle = math.rad(math.random(ATTACK_DIRECTION_MIN_ANGLE, ATTACK_DIRECTION_MAX_ANGLE))
			local attackDirectionSign = if math.random(0, 1) == 0 then -1 else 1

			local playerCharacter = playerRoot.Parent
			local playerHumanoid = if playerCharacter ~= nil then playerCharacter:FindFirstChildOfClass("Humanoid") else nil
			-- When the player is stopped, their facing direction is the best available prediction.
			local movementDirection = if playerHumanoid ~= nil and playerHumanoid.MoveDirection.Magnitude > 0
				then playerHumanoid.MoveDirection.Unit
				else playerRoot.CFrame.LookVector
			local positiveAngleDirection = CFrame.Angles(0, attackAngle, 0):VectorToWorldSpace(attackDirection)
			local negativeAngleDirection = CFrame.Angles(0, -attackAngle, 0):VectorToWorldSpace(attackDirection)
			local alignmentDifference = positiveAngleDirection:Dot(movementDirection)
				- negativeAngleDirection:Dot(movementDirection)

			if math.abs(alignmentDifference) > 0.001 and math.random() < ATTACK_MOVEMENT_DIRECTION_WEIGHT then
				attackDirectionSign = if alignmentDifference > 0 then 1 else -1
			end

			attackAngle *= attackDirectionSign
			print('attack angle', attackAngle)
			local attackMovementDirection = CFrame.Angles(0, attackAngle, 0):VectorToWorldSpace(attackDirection)
			enemy.attackDirection = horizontalUnit(attackMovementDirection, root.CFrame.LookVector)
			enemy.debugHitbox = if debugEnabled then createDebugHitbox() else nil
			
			enemy.attackSetup = true
		end
		
		enemy.ellapsedAttackTime += dt
		local attackTime = enemy.realAttackTime :: number
		local attackDirection = enemy.attackDirection
		if attackDirection == nil then
			return 'idle'
		end
		local currentDirection = horizontalUnit(root.CFrame.LookVector, attackDirection)
		local blend = 1 - math.exp(-TRY_ATTACK_TURN_SPEED * dt)
		local movementDirection = horizontalUnit(currentDirection:Lerp(attackDirection, blend), attackDirection)
		enemy.humanoid:Move(movementDirection, false)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + movementDirection)
		local attackProgress = math.clamp(enemy.ellapsedAttackTime / attackTime, 0, 1)
		if attackProgress <= ATTACK_ACCELERATION_RATIO then
			local accelerationProgress = attackProgress / ATTACK_ACCELERATION_RATIO
			enemy.humanoid.WalkSpeed = ATTACK_INITIAL_SPEED
				+ (ATTACK_PEAK_SPEED - ATTACK_INITIAL_SPEED) * accelerationProgress
		else
			local decelerationProgress = (attackProgress - ATTACK_ACCELERATION_RATIO)
				/ (1 - ATTACK_ACCELERATION_RATIO)
			enemy.humanoid.WalkSpeed = ATTACK_PEAK_SPEED
				+ (ATTACK_END_SPEED - ATTACK_PEAK_SPEED) * decelerationProgress
		end
		
		-- check for player collision with the hitbox
		if enemy.debugHitbox ~= nil then
			enemy.debugHitbox.CFrame = root.CFrame * hitBox.rootOffset
		end
		
		local params = OverlapParams.new()
		local playerCharacter = playerRoot.Parent
		if playerCharacter == nil then
			return 'idle'
		end
		params.IncludeInstances = { playerCharacter }
		local result = workspace:GetPartBoundsInBox(root.CFrame * hitBox.rootOffset, hitBox.size, params)
		if #result > 0 and not enemy.attackEffectResolved then
			enemy.attackEffectResolved = true
			if not canStartPlayerAttack() then
				print('player attack blocked')
				return
			end
			if not gamble(ATTACK_EFFECTIVE_CHANCE) then
				print('player not attacked. gamble lose')
				return
			end
			print('player attacked')

			enemy.ellapsedAttackTime = 0
			enemy.attackSetup = false
			enemy.realAttackTime = nil
			enemy.attackDirection = nil
			enemy.humanoid.WalkSpeed = enemy.oldSpeed :: number
			enemy.humanoid:Move(Vector3.zero, false)
			if enemy.debugHitbox ~= nil then
				enemy.debugHitbox:Destroy()
				enemy.debugHitbox = nil
			end
			enemy.attackEffectResolved = false
			enemy.attackTargetHumanoid = playerCharacter:FindFirstChildOfClass('Humanoid')
			enemy.movementLockRelease = enemy.movementController:acquireMovementLock()
			enemy.attackingEnemyStartCFrame = root.CFrame
			enemy.attackingPlayerStartCFrame = playerRoot.CFrame
			enemy.attackingEnemyTargetCFrame, enemy.attackingPlayerTargetCFrame = getAttackOrientations(root, playerRoot)
			enemy.movementController:setLookVector(playerRoot.CFrame.LookVector)
			enemy.playerAttackOwner = true
			playerAttackInProgress = true
			return 'attacking'
		end
		
		if enemy.ellapsedAttackTime >= attackTime then
			enemy.ellapsedAttackTime = 0
			enemy.attackSetup = false
			enemy.realAttackTime = nil
			enemy.attackDirection = nil
			enemy.humanoid.WalkSpeed = enemy.oldSpeed :: number
			enemy.humanoid:Move(Vector3.zero, false)
			if enemy.debugHitbox ~= nil then
				enemy.debugHitbox:Destroy()
				enemy.debugHitbox = nil
			end
			enemy.attackEffectResolved = false
			return 'stunned'
		end
		
		return
	end
}

local STUN_TIME_MIN = 2
local STUN_TIME_MAX = 3.5
local ATTACKING_TIME = 1.5
local ATTACKING_TURN_TIME = 0.2
local ATTACKING_DAMAGE = 15

local function getStunTime(): number
	return STUN_TIME_MIN + math.random() * (STUN_TIME_MAX - STUN_TIME_MIN)
end

local Stunned: StateObject<EnemyContext> = {
	update = function (context, dt: number)
		local enemy = context.enemy
		
		if not enemy.realStunTime then
			enemy.realStunTime = getStunTime()
		end
	
		if enemy.humanoid ~= nil and enemy.humanoid.MoveDirection ~= Vector3.zero then
			enemy.humanoid:Move(Vector3.zero, false)
		end
		
		enemy.ellapsedStuntime += dt
		if enemy.ellapsedStuntime >= (enemy.realStunTime :: number) then
			enemy.ellapsedStuntime = 0;
			enemy.realStunTime = nil
			return "chasing"
		end
		
		return
	end
}

local attacking: StateObject<EnemyContext> = {
	update = function (context, dt: number)
		local enemy = context.enemy
		if enemy.movementLockRelease == nil then
			enemy.movementLockRelease = enemy.movementController:acquireMovementLock()
		end

		enemy.ellapsedAttackingTime += dt
		local turnProgress = math.clamp(enemy.ellapsedAttackingTime / ATTACKING_TURN_TIME, 0, 1)
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

		if enemy.ellapsedAttackingTime < ATTACKING_TIME then
			return
		end

		if enemy.attackTargetHumanoid ~= nil then
			enemy.attackTargetHumanoid:TakeDamage(ATTACKING_DAMAGE)
		end
		enemy.playerAttackOwner = false
		playerAttackInProgress = false
		playerInvulnerableUntil = os.clock() + PLAYER_INVULNERABILITY_TIME
		if enemy.movementLockRelease ~= nil then
			enemy.movementLockRelease()
			enemy.movementLockRelease = nil
		end
		enemy.ellapsedAttackingTime = 0
		enemy.attackTargetHumanoid = nil
		enemy.attackingEnemyStartCFrame = nil
		enemy.attackingEnemyTargetCFrame = nil
		enemy.attackingPlayerStartCFrame = nil
		enemy.attackingPlayerTargetCFrame = nil
		return 'stunned'
	end,
}

local states = {
	['idle'] = IdleState,
	['chasing'] = ChasingState,
	['try_attack'] = tryAttack,
	['attacking'] = attacking,
	['stunned'] = Stunned
}

local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(model: Model, movementController: MovementController): Enemy
	assert(model:IsA("Model"), "Enemy requires a Model")
	local root = model:FindFirstChild("HumanoidRootPart")
	assert(root ~= nil and root:IsA("BasePart"), "Enemy requires a BasePart HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid ~= nil, "Enemy requires a Humanoid")
	humanoid.AutoRotate = false

	local self = setmetatable({
		currentState = states['idle'],
		model = model,
		state = "idle",
		humanoid = humanoid,
		root = root,
		path = PathfindingService:CreatePath({ AgentCanJump = false, Costs = { teste = math.huge } }),
		pathElapsed = PATH_RECOMPUTE_INTERVAL,
		chaseWaypoints = {},
		chaseWaypointIndex = 2,
		chaseDirection = horizontalUnit(root.CFrame.LookVector, DEFAULT_CHASE_DIRECTION),
		chaseProgressPosition = root.Position,
		chaseProgressElapsed = 0,
		chaseStuckElapsed = 0,
		destroyed = false,
		detectionRadius = math.random(DETECTION_RADIUS_REF, DETECTION_RADIUS_REF + 10),
		attackTriggerDistance = getAttackTriggerDistance(),
		ellapsedAttackTime = 0,
		realAttackTime = nil,
		attackDirection = nil,
		oldSpeed = nil,
		attackSetup = false,
		attackEffectResolved = false,
		debugHitbox = nil,
		ellapsedStuntime = 0,
		realStunTime = nil,
		ellapsedAttackingTime = 0,
		attackTargetHumanoid = nil,
		movementController = movementController,
		movementLockRelease = nil,
		attackingEnemyStartCFrame = nil,
		attackingEnemyTargetCFrame = nil,
		attackingPlayerStartCFrame = nil,
		attackingPlayerTargetCFrame = nil,
		playerAttackOwner = false,
	}, Enemy)
	return (self :: any) :: Enemy
end

function Enemy.update(self: Enemy, dt: number): ()
	if self.destroyed then
		return
	end

	if self.root ~= nil then
		self.root.AssemblyAngularVelocity = Vector3.zero
	end

	if self.currentState == nil then
		warn('current state is nil on the enemy');
		return
	end

	local context = { enemy = self }

	local newState: string? = self.currentState.update(context, dt)
	if not newState then
		return
	end

	if not states[newState] then
		warn('invalid state: ', newState)
		return;
	end

	if self.currentState == states[newState] then
		warn('trying transition to state equal to previous state')
		return
	end

	if self.currentState.onEnd then
		self.currentState.onEnd(context)
	end
	
	self.currentState = states[newState]

	if self.currentState.onBegin then
		self.currentState.onBegin(context)
	end
end

function Enemy.destroy(self: Enemy): ()
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.playerAttackOwner then
		self.playerAttackOwner = false
		playerAttackInProgress = false
	end
	if self.movementLockRelease ~= nil then
		self.movementLockRelease()
		self.movementLockRelease = nil
	end
	if self.debugHitbox ~= nil then
		self.debugHitbox:Destroy()
		self.debugHitbox = nil
	end
	self.model:Destroy()
	self.humanoid = nil
	self.root = nil
	self.path = nil
	self.attackDirection = nil
end

return Enemy
