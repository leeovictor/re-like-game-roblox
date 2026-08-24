--!strict

local Players = game:GetService("Players")

local CharacterRoot = {}

function CharacterRoot.get(): BasePart?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	return root
end

return CharacterRoot
