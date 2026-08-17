--!strict

local fs = require("@lune/fs")
local harness = require("../../support/harness")

local function read(path: string): string
	return fs.readFile(path)
end

local function assertContains(source: string, text: string, message: string): ()
	harness.assert.truthy(string.find(source, text, 1, true), message)
end

harness.describe("Pickup notification server contract", function()
	harness.it("registers a dedicated pickup remote event", function()
		local source = read("src/shared/remotes.luau")
		assertContains(
			source,
			'PickupCollected = _ensureRemote("PickupCollected", "RemoteEvent")',
			"shared remotes must expose PickupCollected as a RemoteEvent"
		)
	end)

	harness.it("sends the item only after a successful inventory mutation", function()
		local source = read("src/server/pickups/PickupService.luau")
		local mutationStart = string.find(source, "if inventoryService:addItem(player, itemId) then", 1, true) or 0
		local eventStart = string.find(source, "pickupCollected:FireClient(player, itemId)", 1, true) or 0

		harness.assert.truthy(mutationStart > 0, "pickup service must guard collection with addItem")
		harness.assert.truthy(eventStart > 0, "pickup service must notify the collecting player")
		harness.assert.truthy(eventStart > mutationStart, "pickup event must be sent after addItem succeeds")
	end)
end)

harness.describe("Pickup notification client pipeline", function()
	harness.it("has an idempotent controller lifecycle and remote subscription", function()
		local source = read("src/client/pickups/PickupNotificationController.luau")
		assertContains(source, "export type PickupNotificationController", "controller type must be exported")
		assertContains(source, "function controller.start()", "controller must expose start")
		assertContains(source, "function controller.stop()", "controller must expose stop")
		assertContains(source, "pickupCollected.OnClientEvent", "controller must subscribe to PickupCollected")
		assertContains(source, "changed:Fire(itemId)", "controller must publish the received item ID")
	end)

	harness.it("expires only the latest notification after two seconds", function()
		local source = read("src/client/pickups/usePickupNotification.luau")
		assertContains(source, "task.delay(2", "notification lifetime must be two seconds")
		assertContains(source, "notificationGeneration", "hook must track notification generations")
		assertContains(source, "currentGeneration", "old timers must not clear newer notifications")
		assertContains(source, "controller.changed:Connect", "hook must subscribe to controller changes")
	end)

	harness.it("starts the notification controller before mounting the app", function()
		local source = read("src/client/init.client.luau")
		local startPosition = string.find(source, "PickupNotificationController.start()", 1, true) or 0
		local renderPosition = string.find(source, "root:render", 1, true) or 0

		harness.assert.truthy(startPosition > 0, "client init must start the notification controller")
		harness.assert.truthy(renderPosition > 0, "client init must mount the app")
		harness.assert.truthy(startPosition < renderPosition, "controller must start before React renders")
	end)
end)
