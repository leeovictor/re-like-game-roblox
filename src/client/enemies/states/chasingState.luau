local StarterPlayer = game:GetService("StarterPlayer")
local config = require(StarterPlayer.StarterPlayerScripts.Client.enemies.config)
local EnemiesTypes = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)
local utils = require(StarterPlayer.StarterPlayerScripts.Client.enemies.utils)
local CharacterRoot = require(StarterPlayer.StarterPlayerScripts.Client.player.CharacterRoot)

local function failPath(self: EnemiesTypes.Enemy, message: string): ()
	warn(("[Enemy:%s] %s"):format(self.model.Name, message))
end

local function updateChaseMovement(self: EnemiesTypes.Enemy, root: BasePart, humanoid: Humanoid, playerRoot: BasePart, dt: number): ()
	self.chaseProgressElapsed += dt
	if self.chaseProgressElapsed >= config.CHASE_STUCK_CHECK_INTERVAL then
		local movementSinceLastCheck = (root.Position - self.chaseProgressPosition).Magnitude
		if movementSinceLastCheck < config.CHASE_STUCK_MIN_MOVEMENT then
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
		if distanceToWaypoint > config.CHASE_WAYPOINT_REACHED_DISTANCE then
			break
		end
		self.chaseWaypointIndex += 1
	end

	local waypoint: PathWaypoint? = if self.chaseWaypointIndex <= #self.chaseWaypoints
		then self.chaseWaypoints[self.chaseWaypointIndex]
		else nil
	local targetPosition = if waypoint ~= nil then waypoint.Position else playerRoot.Position
	local currentDirection = utils.horizontalUnit(root.CFrame.LookVector, self.chaseDirection)
	local targetDirection = utils.horizontalUnit(targetPosition - root.Position, currentDirection)
	local turnSpeed = if self.chaseStuckElapsed >= config.CHASE_STUCK_TIME then config.CHASE_STUCK_TURN_SPEED else config.CHASE_TURN_SPEED
	local blend = 1 - math.exp(-turnSpeed * dt)
	local movementDirection = utils.horizontalUnit(currentDirection:Lerp(targetDirection, blend), targetDirection)

	self.chaseDirection = movementDirection
	humanoid:Move(movementDirection, false)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + movementDirection)
	root.AssemblyAngularVelocity = Vector3.zero
end

local ChasingState: EnemiesTypes.StateObject<EnemiesTypes.EnemyContext> = {
	update = function (context, dt: number)
		context.enemy.pathElapsed += dt
		local playerRoot = CharacterRoot.get()
		local root = context.enemy.root
		local path = context.enemy.path
		
		if root == nil or path == nil or playerRoot == nil then
			return 'idle'
		end

		if (playerRoot.Position - root.Position).Magnitude <= context.enemy.attackTriggerDistance then
			context.enemy.attackTriggerDistance = utils.rollAttackTriggerDistance()
			context.enemy.pathElapsed = 0;
			return 'try_attack';
		end
		local humanoid = context.enemy.humanoid
		if humanoid == nil then
			return 'idle'
		end

		if context.enemy.pathElapsed >= config.PATH_RECOMPUTE_INTERVAL then
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

return ChasingState
