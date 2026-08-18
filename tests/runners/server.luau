--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SharedRunner = require(ReplicatedStorage.TestEZRunnerShared)

export type Result = SharedRunner.Result

export type Runner = {
	run: () -> Result,
}

local runner = {} :: Runner

function runner.run(): Result
	local testRoots = {
		ReplicatedStorage.TestEZTests.Shared :: Instance,
		ServerScriptService.TestEZTests.Server :: Instance,
	}
	return SharedRunner.run(testRoots)
end

return runner
