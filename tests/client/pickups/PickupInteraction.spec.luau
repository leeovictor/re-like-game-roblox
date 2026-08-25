--!strict

local Players = game:GetService("Players")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupInteraction = require(client.pickups.PickupInteraction)
local GameplayEvents = require(client.events.GameplayEvents)

return function()
	describe("PickupInteraction", function()
		local fixtures: { Instance }
		local manager: any
		local managerCalls: number
		local lastTarget: Instance?
		local managerResult: any
		local connections: { any }

		beforeEach(function()
			fixtures = {}
			connections = {}
			managerCalls = 0
			lastTarget = nil
			managerResult = { success = true, itemId = "access_card" }
			manager = {
				collect = function(_self: any, target: Instance): any
					managerCalls += 1
					lastTarget = target
					return managerResult
				end,
			}
		end)

		afterEach(function()
			for _, connection in connections do
				connection:Disconnect()
			end
			for _, fixture in fixtures do
				fixture:Destroy()
			end
		end)

		it("delegates supported roots to the manager", function()
			local part = Instance.new("Part")
			table.insert(fixtures, part)
			local interaction = PickupInteraction.new({ manager = manager })

			interaction.interact(part)

			expect(managerCalls).to.equal(1)
			expect(lastTarget).to.equal(part)
		end)

		it("publishes item_collected only after manager success", function()
			local part = Instance.new("Part")
			table.insert(fixtures, part)
			local interaction = PickupInteraction.new({ manager = manager })
			local events: { any } = {}
			table.insert(connections, GameplayEvents.subscribe(function(event)
				table.insert(events, event)
			end))

			interaction.interact(part)

			expect(events[1].name).to.equal("item_collected")
			expect(events[1].itemId).to.equal("access_card")
		end)

		it("does not publish an event when collection fails", function()
			local part = Instance.new("Part")
			table.insert(fixtures, part)
			managerResult = { success = false, reason = "too_far" }
			local interaction = PickupInteraction.new({ manager = manager })
			local events: { any } = {}
			table.insert(connections, GameplayEvents.subscribe(function(event)
				table.insert(events, event)
			end))

			interaction.interact(part)

			expect(#events).to.equal(0)
		end)

		it("ignores unsupported instances", function()
			local folder = Instance.new("Folder")
			table.insert(fixtures, folder)
			local interaction = PickupInteraction.new({ manager = manager })

			interaction.interact(folder)

			expect(managerCalls).to.equal(0)
		end)
	end)
end
