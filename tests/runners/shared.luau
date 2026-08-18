--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestEZ = require(ReplicatedStorage.DevPackages.TestEZ)

export type Result = {
	passed: number,
	failed: number,
	skipped: number,
	errors: { string },
}

local function traceback(message: any): string
	if debug and debug.traceback then
		return debug.traceback(tostring(message), 2)
	end
	return tostring(message)
end

local function appendErrors(target: { string }, source: any): ()
	if type(source) ~= "table" then
		return
	end
	for _, message in source do
		table.insert(target, tostring(message))
	end
end

local function collectErrors(results: any): { string }
	local errors = {}

	local function visit(node: any): ()
		appendErrors(errors, node.errors)
		if type(node.children) ~= "table" then
			return
		end
		for _, child in node.children do
			visit(child)
		end
	end

	visit(results)
	return errors
end

local shared = {}

function shared.run(roots: { Instance }): Result
	local ok, results = xpcall(function(): any
		return TestEZ.TestBootstrap:run(roots)
	end, traceback)
	if not ok then
		return {
			passed = 0,
			failed = 1,
			skipped = 0,
			errors = { tostring(results) },
		}
	end

	return {
		passed = results.successCount,
		failed = results.failureCount,
		skipped = results.skippedCount,
		errors = collectErrors(results),
	}
end

return shared
