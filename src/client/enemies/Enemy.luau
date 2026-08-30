--!strict

local PathfindingService = game:GetService("PathfindingService")

-- states
local StarterPlayer = game:GetService("StarterPlayer")

local attacking = require(StarterPlayer.StarterPlayerScripts.Client.enemies.states.attacking)
local chasingState = require(StarterPlayer.StarterPlayerScripts.Client.enemies.states.chasingState)
local idleState = require(StarterPlayer.StarterPlayerScripts.Client.enemies.states.idleState)
local stunned = require(StarterPlayer.StarterPlayerScripts.Client.enemies.states.stunned)
local tryAttack = require(StarterPlayer.StarterPlayerScripts.Client.enemies.states.tryAttack)

local config = require(StarterPlayer.StarterPlayerScripts.Client.enemies.config)
local EnemiesTypes = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)
local utils = require(StarterPlayer.StarterPlayerScripts.Client.enemies.utils)

local state: EnemiesTypes.SystemState = {
	playerAttackInProgress = false,
	playerInvulnerableUntil = 0,
	debugEnabled = false
}

local DEFAULT_CHASE_DIRECTION = Vector3.new(0, 0, -1)

local states = {
	['idle'] = idleState,
	['chasing'] = chasingState,
	['try_attack'] = tryAttack,
	['attacking'] = attacking,
	['stunned'] = stunned
}

local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(model: Model, signals: EnemiesTypes.PlayerAttackSignals): EnemiesTypes.Enemy
	assert(model:IsA("Model"), "Enemy requires a Model")
	local root = model:FindFirstChild("HumanoidRootPart")
	assert(root ~= nil and root:IsA("BasePart"), "Enemy requires a BasePart HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid ~= nil, "Enemy requires a Humanoid")
	humanoid.AutoRotate = false

	local self = setmetatable({
		currentState = states['idle'],
		model = model,
		humanoid = humanoid,
		root = root,
		path = PathfindingService:CreatePath({ AgentCanJump = false, Costs = { teste = math.huge } }),
		pathElapsed = config.PATH_RECOMPUTE_INTERVAL,
		chaseWaypoints = {},
		chaseWaypointIndex = 2,
		chaseDirection = utils.horizontalUnit(root.CFrame.LookVector, DEFAULT_CHASE_DIRECTION),
		chaseProgressPosition = root.Position,
		chaseProgressElapsed = 0,
		chaseStuckElapsed = 0,
		destroyed = false,
		detectionRadius = math.random(config.DETECTION_RADIUS_REF, config.DETECTION_RADIUS_REF + 10),
		attackTriggerDistance = utils.rollAttackTriggerDistance(),
		ellapsedAttackTime = 0,
		realAttackTime = nil,
		attackDirection = nil,
		oldSpeed = nil,
		attackEffectResolved = false,
		debugHitbox = nil,
		ellapsedStuntime = 0,
		realStunTime = nil,
		ellapsedAttackingTime = 0,
		attackTargetHumanoid = nil,
		attackingEnemyStartCFrame = nil,
		attackingEnemyTargetCFrame = nil,
		playerAttackOwner = false,
		playerAttackGeneration = 0,
		activePlayerAttackId = nil,
		playerAttackStarted = signals.playerAttackStarted,
		playerAttackEnded = signals.playerAttackEnded,
	}, Enemy)
	return (self :: any) :: EnemiesTypes.Enemy
end

function Enemy.update(self: EnemiesTypes.Enemy, dt: number): ()
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

	local context: EnemiesTypes.EnemyContext = { enemy = self, systemState = state }

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

function Enemy.destroy(self: EnemiesTypes.Enemy): ()
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.playerAttackOwner then
		self.playerAttackOwner = false
		state.playerAttackInProgress = false
	end
	local attackId = self.activePlayerAttackId
	if attackId ~= nil then
		self.activePlayerAttackId = nil
		self.playerAttackEnded:Fire({
			enemy = self,
			attackId = attackId,
			cancelled = true,
		})
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
