--!strict

local Harness = {}

type TestCase = {
	name: string,
	callback: () -> (),
}

type Suite = {
	name: string,
	cases: { TestCase },
}

local suites: { Suite } = {}
local currentSuite: Suite? = nil

local function formatValue(value: any): string
	return string.format("%q", tostring(value))
end

local Assertions = {}

function Assertions.equal(actual: any, expected: any, message: string?): ()
	if actual ~= expected then
		error(message or string.format("expected %s, got %s", formatValue(expected), formatValue(actual)), 2)
	end
end

function Assertions.near(actual: number, expected: number, tolerance: number, message: string?): ()
	if math.abs(actual - expected) > tolerance then
		error(
			message
				or string.format("expected %s +/- %s, got %s", formatValue(expected), formatValue(tolerance), formatValue(actual)),
			2
		)
	end
end

function Assertions.truthy(value: any, message: string?): ()
	if not value then
		error(message or string.format("expected a truthy value, got %s", formatValue(value)), 2)
	end
end

function Assertions.falsy(value: any, message: string?): ()
	if value then
		error(message or string.format("expected a falsy value, got %s", formatValue(value)), 2)
	end
end

function Assertions.isNil(value: any, message: string?): ()
	if value ~= nil then
		error(message or string.format("expected nil, got %s", formatValue(value)), 2)
	end
end

Harness.assert = Assertions

function Harness.describe(name: string, callback: () -> ()): ()
	local suite: Suite = {
		name = name,
		cases = {},
	}
	table.insert(suites, suite)

	local previousSuite = currentSuite
	currentSuite = suite
	local ok, err = pcall(function(): any
		callback()
		return nil
	end)
	currentSuite = previousSuite
	if not ok then
		error(err, 0)
	end
end

function Harness.it(name: string, callback: () -> ()): ()
	if currentSuite == nil then
		error(string.format("test case %q must be declared inside a suite", name), 2)
	end
	table.insert(currentSuite.cases, {
		name = name,
		callback = callback,
	})
end

function Harness.getSuiteCount(): number
	return #suites
end

function Harness.run(): { suites: number, passed: number, failed: number }
	local passed = 0
	local failed = 0

	for _, suite in suites do
		for _, testCase in suite.cases do
			local ok, err = xpcall(function(): any
				testCase.callback()
				return nil
			end, function(message)
				if debug and debug.traceback then
					return debug.traceback(tostring(message), 2)
				end
				return tostring(message)
			end)
			if ok then
				passed += 1
				print(string.format("PASS %s :: %s", suite.name, testCase.name))
			else
				failed += 1
				warn(string.format("FAIL %s :: %s\n%s", suite.name, testCase.name, tostring(err)))
			end
		end
	end

	return {
		suites = #suites,
		passed = passed,
		failed = failed,
	}
end

return Harness
