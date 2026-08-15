--!strict

--> Discovers and runs all tests/**/*.spec.luau files.

local fs = require("@lune/fs")
local process = require("@lune/process")
local harness = require("../tests/support/harness")

local function discover(directory: string): { string }
	local files = {}
	local entries = fs.readDir(directory)
	table.sort(entries)
	for _, entry in entries do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			for _, nested in discover(path) do
				table.insert(files, nested)
			end
		elseif fs.isFile(path) and string.match(entry, "%.spec%.luau$") then
			table.insert(files, path)
		end
	end
	return files
end

local function modulePath(path: string): string
	return "../" .. string.gsub(path, "%.luau$", "")
end

local startTime = os.clock()
local testFiles = discover("tests")
local loadFailures = 0
local loadModule: any = require

if #testFiles == 0 then
	print("No test files found (expected tests/**/*.spec.luau).")
else
	for _, path in testFiles do
		local ok, err = xpcall(function()
			loadModule(modulePath(path))
		end, function(message)
			if debug and debug.traceback then
				return debug.traceback(tostring(message), 2)
			end
			return tostring(message)
		end)
		if not ok then
			loadFailures += 1
			warn(string.format("FAIL loading %s\n%s", path, tostring(err)))
		end
	end
end

local result = harness.run()
local elapsed = os.clock() - startTime
local failed = result.failed + loadFailures
print(string.format(
	"Summary: %d suite(s), %d passed, %d failed, %.3fs",
		result.suites,
		result.passed,
		failed,
		elapsed
))

if failed > 0 then
	process.exit(1)
end
