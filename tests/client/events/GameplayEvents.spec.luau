--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local GameplayEvents = require(client.events.GameplayEvents)

return function()
    describe("GameplayEvents", function()
        local connections: { any } = {}

        afterEach(function()
            for _, connection in connections do
                connection:Disconnect()
            end
            connections = {}
        end)

        it("delivers the same event to one subscriber", function()
            local received: any = nil
            table.insert(connections, GameplayEvents.subscribe(function(event: any)
                received = event
            end))

            local event: any = { name = "item_collected", itemId = "access_card" }
            GameplayEvents.emit(event)

            expect(received).to.equal(event)
        end)

        it("delivers to multiple subscribers and stops after disconnect", function()
            local firstCalls = 0
            local secondCalls = 0
            local first = GameplayEvents.subscribe(function(_event: any)
                firstCalls += 1
            end)
            local second = GameplayEvents.subscribe(function(_event: any)
                secondCalls += 1
            end)
            table.insert(connections, first)
            table.insert(connections, second)

            GameplayEvents.emit({ name = "door_entered", doorKey = "main_exit" })
            first:Disconnect()
            GameplayEvents.emit({ name = "door_entered", doorKey = "main_exit" })

            expect(firstCalls).to.equal(1)
            expect(secondCalls).to.equal(2)
        end)

        it("does not replay an event to a later subscriber", function()
            GameplayEvents.emit({ name = "item_collected", itemId = "fuse" })
            local received = false
            table.insert(connections, GameplayEvents.subscribe(function(_event: any)
                received = true
            end))

            expect(received).to.equal(false)
        end)
    end)
end
