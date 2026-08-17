--!strict

local fs = require("@lune/fs")
local harness = require("../../support/harness")

harness.describe("App inventory children", function()
	harness.it("renders inventory instances by uid and item id", function()
		local source = fs.readFile("src/client/ui/App.luau")
		harness.assert.truthy(string.find(source, "instance.uid", 1, true) ~= nil)
		harness.assert.truthy(string.find(source, "instance.itemId", 1, true) ~= nil)
	end)

	harness.it("does not pass an element array as a nested React child", function()
		local source = fs.readFile("src/client/ui/App.luau")
		harness.assert.equal(
			string.find(source, "Rows = inventoryRows", 1, true),
			nil,
			"inventory rows must be keyed directly in the ScrollingFrame children"
		)
	end)
end)

local function assertContains(source: string, text: string, message: string): ()
	harness.assert.truthy(string.find(source, text, 1, true), message)
end

harness.describe("App inventory controls", function()
	harness.it("starts the inventory hidden and listens for the T key", function()
		local source = fs.readFile("src/client/ui/App.luau")
		assertContains(source, "React.useState(false)", "inventory visibility must start false")
		assertContains(source, "UserInputService.InputBegan", "App must listen for keyboard input")
		assertContains(source, "Enum.KeyCode.T", "App must use the T key")
		assertContains(source, "gameProcessedEvent", "App must receive the processed-input flag")
		assertContains(source, "GetFocusedTextBox", "text input focus must be checked")
		assertContains(source, "gameProcessedEvent and", "processed text input must be ignored")
		assertContains(source, "if inventoryVisible then", "inventory panel must be conditional")
	end)

	harness.it("renders one lower-left pickup notification", function()
		local source = fs.readFile("src/client/ui/App.luau")
		assertContains(source, "usePickupNotification", "App must consume pickup notifications")
		assertContains(source, 'Text = "Pegou "', "notification must use the Pegou prefix")
		assertContains(source, "AnchorPoint = Vector2.new(0, 1)", "notification must anchor at the lower-left")
		assertContains(source, "Position = UDim2.new(0, 24, 1, -24)", "notification must have lower-left offset")
		assertContains(source, "PickupNotification", "notification must have a single keyed UI child")
	end)
end)
