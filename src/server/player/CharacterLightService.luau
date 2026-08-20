--!strict

local Players = game:GetService("Players")

local SPOTLIGHT_NAME = "TankFlashlight"
local BODY_LIGHT_ATTACHMENT_NAME = "TankLightAttachment"
local BODY_LIGHT_NAME = "TankBodyLight"

local CHARACTER_ROOT_WAIT_SECONDS = 5

local SPOTLIGHT_ENABLED = true
local SPOTLIGHT_COLOR = Color3.fromRGB(199, 214, 255)
local SPOTLIGHT_BRIGHTNESS = 1.12
local SPOTLIGHT_RANGE = 24
local SPOTLIGHT_ANGLE = 90
local SPOTLIGHT_SHADOWS = true
local SPOTLIGHT_FACE = Enum.NormalId.Front

local BODY_LIGHT_ENABLED = true
local BODY_LIGHT_COLOR = Color3.fromRGB(199, 214, 255)
local BODY_LIGHT_BRIGHTNESS = 0.22
local BODY_LIGHT_RANGE = 3
local BODY_LIGHT_SHADOWS = false
local BODY_LIGHT_ATTACHMENT_POSITION = Vector3.new(0, 0.5, -1.5)

export type Service = {
	start: (self: Service) -> (),
	stop: (self: Service) -> (),
}

local function getRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function configureSpotlight(rootPart: BasePart): ()
	local existing = rootPart:FindFirstChild(SPOTLIGHT_NAME)
	if existing ~= nil and not existing:IsA("SpotLight") then
		existing:Destroy()
		existing = nil
	end

	local spotlight: SpotLight = if existing == nil then Instance.new("SpotLight") else existing :: SpotLight
	spotlight.Name = SPOTLIGHT_NAME
	spotlight.Enabled = SPOTLIGHT_ENABLED
	spotlight.Color = SPOTLIGHT_COLOR
	spotlight.Brightness = SPOTLIGHT_BRIGHTNESS
	spotlight.Range = SPOTLIGHT_RANGE
	spotlight.Angle = SPOTLIGHT_ANGLE
	spotlight.Shadows = SPOTLIGHT_SHADOWS
	spotlight.Face = SPOTLIGHT_FACE
	spotlight.Parent = rootPart
end

local function configureBodyLight(rootPart: BasePart): ()
	local existingAttachment = rootPart:FindFirstChild(BODY_LIGHT_ATTACHMENT_NAME)
	if existingAttachment ~= nil and not existingAttachment:IsA("Attachment") then
		existingAttachment:Destroy()
		existingAttachment = nil
	end

	local attachment: Attachment = if existingAttachment == nil
		then Instance.new("Attachment")
		else existingAttachment :: Attachment
	attachment.Name = BODY_LIGHT_ATTACHMENT_NAME
	attachment.Position = BODY_LIGHT_ATTACHMENT_POSITION
	attachment.Parent = rootPart

	local existingLight = attachment:FindFirstChild(BODY_LIGHT_NAME)
	if existingLight ~= nil and not existingLight:IsA("PointLight") then
		existingLight:Destroy()
		existingLight = nil
	end

	local bodyLight: PointLight = if existingLight == nil
		then Instance.new("PointLight")
		else existingLight :: PointLight
	bodyLight.Name = BODY_LIGHT_NAME
	bodyLight.Enabled = BODY_LIGHT_ENABLED
	bodyLight.Color = BODY_LIGHT_COLOR
	bodyLight.Brightness = BODY_LIGHT_BRIGHTNESS
	bodyLight.Range = BODY_LIGHT_RANGE
	bodyLight.Shadows = BODY_LIGHT_SHADOWS
	bodyLight.Parent = attachment
end

local function configureCharacter(rootPart: BasePart): ()
	configureSpotlight(rootPart)
	configureBodyLight(rootPart)
end

local CharacterLightService = {}

function CharacterLightService.new(): Service
	local started = false
	local playerAddedConnection: RBXScriptConnection? = nil
	local playerRemovingConnection: RBXScriptConnection? = nil
	local characterConnections: { [Player]: RBXScriptConnection? } = {}

	local function setupCharacter(character: Model): ()
		if not started then
			return
		end

		local rootPart: BasePart
		local existingRoot = getRoot(character)
		if existingRoot ~= nil then
			rootPart = existingRoot
		else
			local waitedRoot = character:WaitForChild("HumanoidRootPart", CHARACTER_ROOT_WAIT_SECONDS)
			if waitedRoot == nil or not waitedRoot:IsA("BasePart") then
				return
			end
			rootPart = waitedRoot
		end

		if not started or rootPart.Parent ~= character then
			return
		end

		configureCharacter(rootPart)
	end

	local function bindPlayer(player: Player): ()
		if characterConnections[player] ~= nil then
			return
		end

		characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
			task.spawn(setupCharacter, character)
		end)

		local character = player.Character
		if character ~= nil then
			task.spawn(setupCharacter, character)
		end
	end

	local function unbindPlayer(player: Player): ()
		local characterConnection = characterConnections[player]
		if characterConnection ~= nil then
			characterConnection:Disconnect()
			characterConnections[player] = nil
		end
	end

	local service = {} :: Service

	function service:start(): ()
		if started then
			return
		end

		started = true
		playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
		playerRemovingConnection = Players.PlayerRemoving:Connect(unbindPlayer)

		for _, player in Players:GetPlayers() do
			bindPlayer(player)
		end
	end

	function service:stop(): ()
		if not started then
			return
		end

		started = false
		if playerAddedConnection ~= nil then
			playerAddedConnection:Disconnect()
			playerAddedConnection = nil
		end
		if playerRemovingConnection ~= nil then
			playerRemovingConnection:Disconnect()
			playerRemovingConnection = nil
		end
		for player, characterConnection in characterConnections do
			if characterConnection ~= nil then
				characterConnection:Disconnect()
			end
			characterConnections[player] = nil
		end
	end

	return service
end

return CharacterLightService
