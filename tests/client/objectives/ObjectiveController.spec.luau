--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local ObjectiveController = require(client.objectives.ObjectiveController) :: any
local GameplayEvents = require(client.events.GameplayEvents) :: any
local ObjectiveConfig = require(client.objectives.ObjectiveConfig) :: any

local function newEventSource(): (any, (event: any) -> ())
	local listeners: { [number]: (event: any) -> () } = {}
	local nextId = 0
	local source = {}

	function source:subscribe(callback: (event: any) -> ())
		nextId += 1
		local id = nextId
		listeners[id] = callback
		return {
			Disconnect = function()
				listeners[id] = nil
			end,
		}
	end

	local function emit(event: any): ()
		local snapshot = table.clone(listeners)
		for _, callback in snapshot do
			callback(event)
		end
	end

	return source, emit
end

local function objective(value: any): any
	return value
end

return function()
	describe("ObjectiveController", function()
		local controllers: { any } = {}
		local connections: { any } = {}

		beforeEach(function()
			controllers = {}
			connections = {}
		end)

		afterEach(function()
			for _, controller in controllers do
				controller.stop()
			end
			for _, connection in connections do
				connection:Disconnect()
			end
			controllers = {}
			connections = {}
		end)

		it("starts the initial objective and emits one activation batch", function()
			local source = newEventSource()
			local soundCalls = 0
			local controller = ObjectiveController.new(({ 
				objective({
					id = "find_exit",
					text = "Ache uma saida",
					initial = true,
					completesWhen = { event = "door_blocked", doorKey = "cave_exit" },
				}),
			} :: any), {
				events = source,
				playSound = function()
					soundCalls += 1
				end,
			})
			table.insert(controllers, controller)
			local batches: { { any } } = {}
			table.insert(connections, controller.activated:Connect(function(batch: { any })
				table.insert(batches, batch)
			end))

			controller.start()

			local state = assert(controller.getState())
			expect(#state.objectives).to.equal(1)
			expect(state.objectives[1].id).to.equal("find_exit")
			expect(state.objectives[1].completed).to.equal(false)
			expect(#batches).to.equal(1)
			expect(#batches[1]).to.equal(1)
			expect(soundCalls).to.equal(0)
			controller.playSound()
			expect(soundCalls).to.equal(1)
		end)

		it("records facts before an objective is activated", function()
			local source, emit = newEventSource()
			local controller = ObjectiveController.new(({
				objective({
					id = "find_exit",
					text = "Ache uma saida",
					initial = true,
					completesWhen = { event = "door_blocked", doorKey = "facility_entrance" },
				}),
				objective({
					id = "find_card",
					text = "Encontre o cartao",
					initial = nil,
					startsWhen = { event = "door_blocked", doorKey = "facility_entrance" },
					completesWhen = { event = "item_collected", itemId = "access_card" },
				}),
				objective({
					id = "access_facility",
					text = "Acesse a instalacao",
					initial = nil,
					startsWhen = nil,
					requires = { "find_card" },
					completesWhen = { event = "door_entered", doorKey = "facility_entrance" },
				}),
			} :: any), { events = source, playSound = function() end })
			table.insert(controllers, controller)
			controller.start()
			emit({ name = "item_collected", itemId = "access_card" })
			emit({ name = "door_blocked", doorKey = "facility_entrance" })

			local state = assert(controller.getState())
			expect(#state.objectives).to.equal(1)
			expect(state.objectives[1].id).to.equal("access_facility")
		end)

		it("keeps parallel objectives independently visible", function()
			local source, emit = newEventSource()
			local controller = ObjectiveController.new(({ 
				objective({
					id = "find_gold",
					text = "Encontre ouro",
					initial = nil,
					startsWhen = { event = "door_blocked", doorKey = "main_exit" },
					completesWhen = { event = "item_collected", itemId = "gold" },
				}),
				objective({
					id = "find_silver",
					text = "Encontre prata",
					initial = nil,
					startsWhen = { event = "door_blocked", doorKey = "main_exit" },
					completesWhen = { event = "item_collected", itemId = "silver" },
				}),
				objective({
					id = "open_exit",
					text = "Abra a saida",
					initial = nil,
					startsWhen = nil,
					requires = { "find_gold", "find_silver" },
					completesWhen = { event = "door_entered", doorKey = "main_exit" },
				}),
			} :: any), { events = source, playSound = function() end })
			table.insert(controllers, controller)
			controller.start()
			emit({ name = "door_blocked", doorKey = "main_exit" })
			emit({ name = "item_collected", itemId = "gold" })

			local partial = assert(controller.getState())
			expect(#partial.objectives).to.equal(2)
			expect(partial.objectives[1].completed).to.equal(true)
			expect(partial.objectives[2].completed).to.equal(false)
			emit({ name = "item_collected", itemId = "silver" })

			local complete = assert(controller.getState())
			expect(#complete.objectives).to.equal(1)
			expect(complete.objectives[1].id).to.equal("open_exit")
		end)

		it("evaluates completeIf against facts in either order", function()
			local source, emit = newEventSource()
			local controller = ObjectiveController.new(({ 
				{
					id = "restore_power",
					text = "Restabeleca a energia",
					initial = true,
					completeIf = function(facts: any): boolean
						local switches = facts:latest("switches_changed")
						return facts:hasEvent("item_collected", { itemId = "fuse" })
							and switches ~= nil
							and switches.switchesOn >= 3
					end,
				},
			} :: any), { events = source, playSound = function() end })
			table.insert(controllers, controller)
			controller.start()
			emit({ name = "switches_changed", switchesOn = 3 })
			expect(assert(controller.getState()).objectives[1].completed).to.equal(false)
			emit({ name = "item_collected", itemId = "fuse" })
			expect(assert(controller.getState()).objectives[1].completed).to.equal(true)
		end)

		it("rejects malformed objective graphs before starting", function()
			local invalidCases: { any } = {
				{
					name = "duplicate ids",
					definitions = {
						{ id = "duplicate", text = "One", initial = true, completesWhen = { event = "door_entered", doorKey = "a" } },
						{ id = "duplicate", text = "Two", initial = true, completesWhen = { event = "door_entered", doorKey = "b" } },
					},
				},
				{
					name = "unknown dependency",
					definitions = {
						{ id = "child", text = "Child", requires = { "missing" }, completesWhen = { event = "door_entered", doorKey = "a" } },
					},
				},
				{
					name = "dependency cycle",
					definitions = {
						{ id = "one", text = "One", requires = { "two" }, completesWhen = { event = "door_entered", doorKey = "a" } },
						{ id = "two", text = "Two", requires = { "one" }, completesWhen = { event = "door_entered", doorKey = "b" } },
					},
				},
				{
					name = "missing activation gate",
					definitions = {
						{ id = "orphan", text = "Orphan", completesWhen = { event = "door_entered", doorKey = "a" } },
					},
				},
				{
					name = "missing completion condition",
					definitions = {
						{ id = "unfinished", text = "Unfinished", initial = true },
					},
				},
			}

			for _, invalidCase in invalidCases do
				local source = newEventSource()
				local ok, message = pcall(function()
					local controller = ObjectiveController.new(invalidCase.definitions, {
						events = source,
						playSound = function() end,
					})
					controller.start()
				end)
				expect(ok).to.equal(false)
				expect(string.find(message :: string, invalidCase.name, 1, true) ~= nil).to.equal(true)
			end
		end)

		it("keeps lifecycle idempotent and clears state on stop", function()
			local source, emit = newEventSource()
			local soundCalls = 0
			local controller = ObjectiveController.new({
				{
					id = "find_exit",
					text = "Ache uma saida",
					initial = true,
					completesWhen = { event = "door_blocked", doorKey = "cave_exit" },
				},
			}, {
				events = source,
				playSound = function() soundCalls += 1 end,
			})
			table.insert(controllers, controller)
			controller.start()
			controller.start()
			emit({ name = "door_blocked", doorKey = "other" })
			emit({ name = "door_blocked", doorKey = "cave_exit" })
			emit({ name = "door_blocked", doorKey = "cave_exit" })
			expect(assert(controller.getState()).objectives[1].completed).to.equal(true)
			expect(soundCalls).to.equal(0)
			controller.stop()
			controller.stop()
			expect(controller.getState()).to.equal(nil)
		end)

		it("connects the default event source with a callback", function()
			local controller = ObjectiveController.new({
				{
					id = "find_exit",
					text = "Ache uma saida",
					initial = true,
					completesWhen = { event = "door_blocked", doorKey = "cave_exit" },
				},
				objective({
					id = "find_card",
					text = "Encontre o cartao",
					initial = nil,
					startsWhen = { event = "door_blocked", doorKey = "cave_exit" },
					completesWhen = { event = "item_collected", itemId = "access_card" },
				}),
			})
			table.insert(controllers, controller)

			controller.start()
			GameplayEvents.emit({ name = "door_blocked", doorKey = "cave_exit" })

			local state = assert(controller.getState())
			expect(state.objectives[1].id).to.equal("find_card")
		end)

		it("does not block the facility objective when the card is collected first", function()
			local source, emit = newEventSource()
			local controller = ObjectiveController.new(ObjectiveConfig, {
				events = source,
				playSound = function() end,
			})
			table.insert(controllers, controller)

			controller.start()
			emit({ name = "item_collected", itemId = "access_card" })

			local undiscovered = assert(controller.getState())
			expect(#undiscovered.objectives).to.equal(1)
			expect(undiscovered.objectives[1].id).to.equal("find_exit")

			emit({ name = "door_unlocked", doorKey = "facility_entrance" })

			local state = assert(controller.getState())
			local facilityObjective = nil
			for _, objectiveView in state.objectives do
				if objectiveView.id == "access_facility" then
					facilityObjective = objectiveView
				end
			end
			expect(facilityObjective ~= nil).to.equal(true)
			if facilityObjective == nil then
				return
			end
			expect(facilityObjective.completed).to.equal(false)
		end)
	end)
end
