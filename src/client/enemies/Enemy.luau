--!strict

local PathfindingService = game:GetService("PathfindingService")
local CharacterRoot = require(script.Parent.Parent.player.CharacterRoot)

local DETECTION_RADIUS = 200
local PATH_RECOMPUTE_INTERVAL = 0.1

export type State = "idle" | "chasing"
export type Enemy = {
	model: Model,
	state: State,
	humanoid: Humanoid?,
	root: BasePart?,
	path: Path?,
	pathElapsed: number,
	destroyed: boolean,
	update: (self: Enemy, deltaTime: number) -> (),
	destroy: (self: Enemy) -> (),
}

local Enemy = {}
Enemy.__index = Enemy

local function enterIdle(self: Enemy, allowImmediateNextAttempt: boolean): ()
	self.state = "idle"
	self.pathElapsed = if allowImmediateNextAttempt then PATH_RECOMPUTE_INTERVAL else 0
end

local function failPath(self: Enemy, message: string): ()
	warn(("[Enemy:%s] %s"):format(self.model.Name, message))
	enterIdle(self, false)
end

function Enemy.new(model: Model): Enemy
	assert(model:IsA("Model"), "Enemy requires a Model")
	local root = model:FindFirstChild("HumanoidRootPart")
	assert(root ~= nil and root:IsA("BasePart"), "Enemy requires a BasePart HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid ~= nil, "Enemy requires a Humanoid")

	local self = setmetatable({
		model = model,
		state = "idle",
		humanoid = humanoid,
		root = root,
		path = PathfindingService:CreatePath({ AgentCanJump = false, Costs = { teste = math.huge } }),
		pathElapsed = PATH_RECOMPUTE_INTERVAL,
		destroyed = false,
	}, Enemy)
	return (self :: any) :: Enemy
end

function Enemy.update(self: Enemy, deltaTime: number): ()
	if self.destroyed then
		return
	end
	self.pathElapsed += deltaTime
	local playerRoot = CharacterRoot.get()
	local root = self.root
	if playerRoot == nil or root == nil or (playerRoot.Position - root.Position).Magnitude > DETECTION_RADIUS then
		enterIdle(self, true)
		return
	end
	if self.state == "idle" then
		self.state = "chasing"
	end
	if self.pathElapsed < PATH_RECOMPUTE_INTERVAL then
		return
	end
	self.pathElapsed = 0

	local path = self.path :: Path
	local ok, errorMessage = pcall(function()
		path:ComputeAsync(root.Position, playerRoot.Position)
	end)
	if not ok then
		failPath(self, ("ComputeAsync failed: %s"):format(tostring(errorMessage)))
		return
	end
	if path.Status ~= Enum.PathStatus.Success then
		failPath(self, ("Pathfinding failed with status: %s"):format(path.Status.Name))
		return
	end
	local waypoints = path:GetWaypoints()
	for _, waypoint in waypoints do
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			failPath(self, "jump waypoint is unsupported")
			return
		end
	end
	if #waypoints < 2 then
		failPath(self, "no usable waypoint")
		return
	end
	local waypoint = waypoints[2]
	local humanoid = self.humanoid
	if humanoid ~= nil then
		humanoid:MoveTo(waypoint.Position)
	end
end

function Enemy.destroy(self: Enemy): ()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.model:Destroy()
	self.humanoid = nil
	self.root = nil
	self.path = nil
end

return Enemy
