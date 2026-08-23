--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameplayEvents = require(script.Parent.Parent.events.GameplayEvents)
local Signal = require(ReplicatedStorage.Packages.Signal)
local defaultDefinitions = require(script.Parent.ObjectiveConfig)

export type EventFilter = {
	event: GameplayEvents.EventName,
	doorKey: string?,
	itemId: string?,
	areaKey: string?,
}

export type Facts = {
	hasEvent: (
		self: Facts,
		eventName: GameplayEvents.EventName,
		fields: { [string]: string | number | boolean }?
	) -> boolean,
	latest: (
		self: Facts,
		eventName: GameplayEvents.EventName
	) -> GameplayEvents.GameplayEvent?,
}

export type ObjectiveDefinition = {
	id: string,
	text: string,
	initial: boolean?,
	startsWhen: EventFilter?,
	requires: { string }?,
	completesWhen: EventFilter?,
	completeIf: ((facts: Facts) -> boolean)?,
}

export type ObjectiveView = {
	id: string,
	text: string,
	completed: boolean,
}

export type ObjectiveState = {
	objectives: { ObjectiveView },
}

export type EventSource = {
	subscribe: (
		self: EventSource,
		callback: (event: GameplayEvents.GameplayEvent) -> ()
	) -> GameplayEvents.SignalConnection,
}

export type Dependencies = {
	events: EventSource,
	playSound: () -> (),
	cleanupSound: (() -> ())?,
}

export type ObjectiveController = {
	start: () -> (),
	stop: () -> (),
	getState: () -> ObjectiveState?,
	changed: any,
	activated: any,
}

export type Module = {
	new: (definitions: any, dependencies: Dependencies?) -> ObjectiveController,
	start: () -> (),
	stop: () -> (),
	getState: () -> ObjectiveState?,
	changed: any,
	activated: any,
}

local function matches(event: GameplayEvents.GameplayEvent, filter: EventFilter): boolean
	if event.name ~= filter.event then
		return false
	end
	if filter.doorKey ~= nil then
		return (event :: any).doorKey == filter.doorKey
	end
	if filter.itemId ~= nil then
		return (event :: any).itemId == filter.itemId
	end
	if filter.areaKey ~= nil then
		return (event :: any).areaKey == filter.areaKey
	end
	return true
end

local function makeDefaultSound(): (() -> (), () -> ())
	local sound: Sound? = nil
	local function play(): ()
		if sound == nil then
			local createdSound = Instance.new("Sound")
			createdSound.SoundId = "rbxassetid://131940090612749"
			createdSound.Parent = SoundService
			sound = createdSound
		end
		local currentSound = sound
		if currentSound == nil then
			return
		end
		if currentSound.SoundId ~= "" then
			SoundService:PlayLocalSound(currentSound)
		end
	end
	local function cleanup(): ()
		if sound ~= nil then
			sound:Destroy()
			sound = nil
		end
	end
	return play, cleanup
end

local function validateFilter(filter: any, label: string): ()
	assert(type(filter) == "table", label .. " must be a table")
	local event = filter.event
	local knownEvents = {
		door_blocked = true,
		door_unlocked = true,
		door_entered = true,
		item_collected = true,
		area_entered = true,
		switches_changed = true,
	}
	assert(type(event) == "string" and knownEvents[event] == true, label .. " has unknown event")
	local allowed = { event = true, doorKey = true, itemId = true, areaKey = true }
	for key, value in filter do
		assert(allowed[key] == true, label .. " has incompatible field " .. tostring(key))
		if key ~= "event" then
			assert(type(value) == "string" and value ~= "", label .. " has an invalid field")
		end
	end
end

local function validateDefinitions(definitions: any): ()
	local ids: { [string]: boolean } = {}
	for index, definition in definitions do
		local value = definition :: any
		assert(type(value.id) == "string" and value.id ~= "", "definition " .. index .. " has invalid id")
		assert(not ids[value.id], "duplicate ids: " .. value.id)
		ids[value.id] = true
		assert(type(value.text) == "string" and value.text ~= "", value.id .. " has invalid text")
		assert(value.initial == true or value.startsWhen ~= nil or value.requires ~= nil, value.id .. " has missing activation gate")
		local hasEventCompletion = value.completesWhen ~= nil
		local hasPredicateCompletion = value.completeIf ~= nil
		assert(hasEventCompletion or hasPredicateCompletion, value.id .. " has missing completion condition")
		assert(hasEventCompletion ~= hasPredicateCompletion, value.id .. " has two completion conditions")
		if value.startsWhen ~= nil then
			validateFilter(value.startsWhen, value.id .. " startsWhen")
		end
		if value.completesWhen ~= nil then
			validateFilter(value.completesWhen, value.id .. " completesWhen")
		end
		if value.requires ~= nil then
			local dependencies: { [string]: boolean } = {}
			local required = value.requires :: { string }
			for _, dependency in required do
				assert(type(dependency) == "string" and dependency ~= "", value.id .. " has invalid dependency")
				assert(not dependencies[dependency], value.id .. " has duplicate dependency")
				dependencies[dependency] = true
			end
		end
	end
	for _, definition in definitions do
		local required = definition.requires
		if required ~= nil then
			for _, dependency in required do
				assert(ids[dependency], "unknown dependency: " .. dependency)
			end
		end
	end
	local visiting: { [string]: boolean } = {}
	local visited: { [string]: boolean } = {}
	local byId: { [string]: ObjectiveDefinition } = {}
	for _, definition in definitions do
		byId[definition.id] = definition
	end
		local function visit(id: string): ()
		if visiting[id] then
			error("dependency cycle: " .. id, 0)
		end
		if visited[id] then
			return
		end
		visiting[id] = true
		local required = byId[id].requires
		if required ~= nil then
			for _, dependency in required do
				visit(dependency)
			end
		end
		visiting[id] = nil
		visited[id] = true
	end
	for _, definition in definitions do
		visit(definition.id)
	end
end

local function createController(definitions: any, dependencies: Dependencies?): ObjectiveController
	local playSound, cleanupSound = makeDefaultSound()
	local actualDependencies: Dependencies
	if dependencies ~= nil then
		actualDependencies = dependencies
	else
		actualDependencies = {
			events = {
				subscribe = function(_self: EventSource, callback)
					return GameplayEvents.subscribe(callback)
				end,
			} :: any,
			playSound = playSound,
			cleanupSound = cleanupSound,
		}
	end
	local changed = Signal.new()
	local activated = Signal.new()
	local facts: { GameplayEvents.GameplayEvent } = {}
	local statuses: { [string]: "inactive" | "active" | "completed" } = {}
	local visibleIds: { string } = {}
	local definitionById: { [string]: ObjectiveDefinition } = {}
	local connection: GameplayEvents.SignalConnection? = nil
	local state: ObjectiveState? = nil
	local started = false
	local predicateWarnings: { [string]: boolean } = {}

	local function hasEvent(_self: Facts, eventName: GameplayEvents.EventName, fields: { [string]: string | number | boolean }?): boolean
		for _, event in facts do
			if event.name == eventName then
				local matchesFields = true
				local expectedFields = fields
				if expectedFields ~= nil then
					for key, value in expectedFields do
						if (event :: any)[key] ~= value then
							matchesFields = false
							break
						end
					end
				end
				if matchesFields then
					return true
				end
			end
		end
		return false
	end

	local function latest(_self: Facts, eventName: GameplayEvents.EventName): GameplayEvents.GameplayEvent?
		for index = #facts, 1, -1 do
			if facts[index].name == eventName then
				return facts[index]
			end
		end
		return nil
	end

	local readOnlyFacts = {
		hasEvent = hasEvent,
		latest = latest,
	} :: Facts

	local function gateSatisfied(definition: ObjectiveDefinition): boolean
		if definition.initial ~= true and definition.startsWhen == nil and definition.requires == nil then
			return false
		end
		if definition.startsWhen ~= nil then
			local found = false
			for _, event in facts do
				if matches(event, definition.startsWhen) then
					found = true
					break
				end
			end
			if not found then
				return false
			end
		end
		local required = definition.requires
		if required ~= nil then
			for _, dependency in required do
				if statuses[dependency] ~= "completed" then
					return false
				end
			end
		end
		return true
	end

	local function complete(definition: ObjectiveDefinition): boolean
		if definition.completesWhen ~= nil then
			for _, event in facts do
				if matches(event, definition.completesWhen) then
					return true
				end
			end
			return false
		end
		local ok, result = pcall(definition.completeIf :: (facts: Facts) -> boolean, readOnlyFacts)
		if not ok then
			if not predicateWarnings[definition.id] then
				predicateWarnings[definition.id] = true
				warn("Objective " .. definition.id .. " completeIf failed: " .. tostring(result))
			end
			return false
		end
		return result == true
	end

	local function makeView(id: string): ObjectiveView
		local definition = definitionById[id]
		return {
			id = id,
			text = definition.text,
			completed = statuses[id] == "completed",
		}
	end

	local function publishState(): ()
		local objectives: { ObjectiveView } = {}
		for _, id in visibleIds do
			table.insert(objectives, makeView(id))
		end
		state = { objectives = objectives }
		changed:Fire(state)
	end

	local function process(): ()
		local newlyActivated: { [string]: boolean } = {}
		local statusChanged = true
		while statusChanged do
			statusChanged = false
			for _, definition in definitions do
				if statuses[definition.id] == "inactive" and gateSatisfied(definition) then
					statuses[definition.id] = "active"
					newlyActivated[definition.id] = true
					statusChanged = true
				end
			end
			for _, definition in definitions do
				if statuses[definition.id] == "active" and complete(definition) then
					statuses[definition.id] = "completed"
					statusChanged = true
				end
			end
		end

		local finalNewIds: { string } = {}
		for _, definition in definitions do
			if newlyActivated[definition.id] and statuses[definition.id] == "active" then
				table.insert(finalNewIds, definition.id)
			end
		end
		if next(newlyActivated) ~= nil then
			local nextVisible: { string } = {}
			for _, id in visibleIds do
				if statuses[id] ~= "completed" then
					table.insert(nextVisible, id)
				end
			end
			local additions: { string } = finalNewIds
			if #finalNewIds == 0 then
				local completedNew: { string } = {}
				for _, definition in definitions do
					if newlyActivated[definition.id] then
						table.insert(completedNew, definition.id)
					end
				end
				additions = completedNew
			end
			for _, id in additions do
				table.insert(nextVisible, id)
			end
			visibleIds = nextVisible
		end
		publishState()
		if #finalNewIds > 0 then
			local batch: { ObjectiveView } = {}
			for _, id in finalNewIds do
				table.insert(batch, makeView(id))
			end
			activated:Fire(batch)
			actualDependencies.playSound()
		end
	end

	local controller = {
		changed = changed,
		activated = activated,
	} :: ObjectiveController

	function controller.start(): ()
		if started then
			return
		end
		validateDefinitions(definitions)
		for _, definition in definitions do
			definitionById[definition.id] = definition
			statuses[definition.id] = "inactive"
		end
		started = true
		connection = actualDependencies.events:subscribe(function(event)
			if not started then
				return
			end
			table.insert(facts, event)
			process()
		end)
		process()
	end

	function controller.stop(): ()
		if not started then
			return
		end
		started = false
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
		if actualDependencies.cleanupSound ~= nil then
			actualDependencies.cleanupSound()
		end
		table.clear(facts)
		table.clear(statuses)
		table.clear(visibleIds)
		state = nil
	end

	function controller.getState(): ObjectiveState?
		return state
	end

	return controller
end

local defaultPlaySound, defaultCleanupSound = makeDefaultSound()
local defaultController = createController(defaultDefinitions, {
		events = {
		subscribe = function(_self: EventSource, callback)
			return GameplayEvents.subscribe(callback)
		end,
	} :: any,
	playSound = defaultPlaySound,
	cleanupSound = defaultCleanupSound,
})

return {
	new = createController,
	start = function()
		defaultController.start()
	end,
	stop = function()
		defaultController.stop()
	end,
	getState = function()
		return defaultController.getState()
	end,
	changed = defaultController.changed,
	activated = defaultController.activated,
} :: any
