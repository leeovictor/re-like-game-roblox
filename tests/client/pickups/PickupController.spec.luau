--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupController = require(client.pickups.PickupController)

local fixtures: { Instance } = {}

local function track<T>(instance: T & Instance): T & Instance
	table.insert(fixtures, instance)
	return instance
end

local function newController(requests: { any }): any
	local controller = PickupController.new({
		collect = function(request: { pickup: Instance }): ()
			table.insert(requests, request)
		end,
	})
	return controller
end

local function expectOnlyPickup(assert: any, request: any, target: Instance): ()
	assert(request.pickup == target).to.equal(true)
	local keys = 0
	for _ in request do
		keys += 1
	end
	assert(keys).to.equal(1)
end

return function()
	describe("PickupController", function()
		beforeEach(function()
			fixtures = {}
		end)

		afterEach(function()
			for _, fixture in fixtures do
				fixture:Destroy()
			end
			fixtures = {}
		end)

		it("sends a Part reference without client-derived item data", function()
			local requests: { any } = {}
			local controller = newController(requests)
			local part = track(Instance.new("Part"))

			controller.interact(part)

			expect(#requests).to.equal(1)
			expectOnlyPickup(expect, requests[1], part)
		end)

		it("sends a Model reference without client-derived item data", function()
			local requests: { any } = {}
			local controller = newController(requests)
			local model = track(Instance.new("Model"))

			controller.interact(model)

			expect(#requests).to.equal(1)
			expectOnlyPickup(expect, requests[1], model)
		end)

		it("ignores an instance that is not a pickup root", function()
			local requests: { any } = {}
			local controller = newController(requests)
			local folder = track(Instance.new("Folder"))

			controller.interact(folder)

			expect(#requests).to.equal(0)
		end)
	end)
end
