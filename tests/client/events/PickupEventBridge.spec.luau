--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local Bridge = require(client.events.PickupEventBridge)

return function()
	describe("PickupEventBridge", function()
		it("converts a confirmed item id into item_collected", function()
			local callback: ((string) -> ())? = nil
			local disconnected = false
			local events: { any } = {}
			local source = {
				Connect = function(_self: any, nextCallback: (string) -> ())
					callback = nextCallback
					return {
						Disconnect = function()
							disconnected = true
						end,
					}
				end,
			}
			local bridge = Bridge.new({
				source = source,
				emit = function(event: any)
					table.insert(events, event)
				end,
			})

			bridge.start()
			callback = assert(callback, "bridge callback")
			callback("access_card")

			expect(events[1].name).to.equal("item_collected")
			expect(events[1].itemId).to.equal("access_card")
			bridge.stop()
			expect(disconnected).to.equal(true)
		end)

		it("does not duplicate the source connection on repeated start", function()
			local connections = 0
			local disconnects = 0
			local source = {
				Connect = function(_self: any, _callback: (string) -> ())
					connections += 1
					return {
						Disconnect = function()
							disconnects += 1
						end,
					}
				end,
			}
			local bridge = Bridge.new({
				source = source,
				emit = function(_event: any) end,
			})

			bridge.start()
			bridge.start()
			bridge.stop()
			bridge.stop()

			expect(connections).to.equal(1)
			expect(disconnects).to.equal(1)
		end)
	end)
end
