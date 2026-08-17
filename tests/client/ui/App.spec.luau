--!strict

local fs = require("@lune/fs")
local harness = require("../../support/harness")

harness.describe("App inventory children", function()
	harness.it("does not pass an element array as a nested React child", function()
		local source = fs.readFile("src/client/ui/App.luau")
		harness.assert.equal(
			string.find(source, "Rows = inventoryRows", 1, true),
			nil,
			"inventory rows must be keyed directly in the ScrollingFrame children"
		)
	end)
end)
