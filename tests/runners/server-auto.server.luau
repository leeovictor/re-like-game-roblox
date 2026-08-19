--!strict

local Players = game:GetService("Players")
local runner = require(script.Parent:WaitForChild("TestEZRunner"))

task.defer(function()
	local players = Players:GetPlayers()
	if #players == 0 then
		table.insert(players, Players.PlayerAdded:Wait())
	end
	for _, player in players do
		player:LoadCharacterAsync()
		local character = player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart")
	end

	local result = runner.run()
	print(string.format(
		"[TestEZ][Server] %d passed, %d failed, %d skipped",
		result.passed,
		result.failed,
		result.skipped
	))
	for _, message in result.errors do
		warn(string.format("[TestEZ][Server] %s", message))
	end
end)
