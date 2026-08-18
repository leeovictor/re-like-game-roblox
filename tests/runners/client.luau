--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedRunner = require(ReplicatedStorage.TestEZRunnerShared)

export type Result = SharedRunner.Result

export type Runner = {
	run: () -> Result,
}

local runner = {} :: Runner

function runner.run(): Result
	local player = Players.LocalPlayer
	local playerScripts = player:WaitForChild("PlayerScripts")
	local testRoot = playerScripts:WaitForChild("TestEZTests"):WaitForChild("Client")
	return SharedRunner.run({ testRoot })
end

return runner
