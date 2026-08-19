--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local runner = require(script.Parent:WaitForChild("TestEZClientRunner"))

local function waitForCharacter(player: Player): Model
	while true do
		local character = player.Character
		if character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil then
			return character
		end
		RunService.Heartbeat:Wait()
	end
end

task.defer(function()
	local player = Players.LocalPlayer
	waitForCharacter(player)
	RunService.PreRender:Wait()

	local result = runner.run()
	print(string.format(
		"[TestEZ][Client] %d passed, %d failed, %d skipped",
		result.passed,
		result.failed,
		result.skipped
	))
	for _, message in result.errors do
		warn(string.format("[TestEZ][Client] %s", message))
	end
end)
