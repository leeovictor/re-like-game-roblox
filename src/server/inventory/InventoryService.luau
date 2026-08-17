--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryStore = require(script.Parent.InventoryStore)
local inventoryTypes = require(ReplicatedStorage.Shared.inventory.items)
local remotes = require(ReplicatedStorage.Shared.remotes)
local inventoryChanged = remotes.InventoryChanged :: RemoteEvent
local getInventory = remotes.GetInventory :: RemoteFunction

type InventoryState = {
	version: number,
	items: { inventoryTypes.ItemInstance },
	equipped: { [string]: string },
}
type ItemInstance = inventoryTypes.ItemInstance
type ItemAttributes = inventoryTypes.ItemAttributes
type UseMutations = {
	consumeInstance: boolean?,
	consumeQuantity: number?,
	updateAttributes: ItemAttributes?,
	equipSlot: string?,
}

type Persistence = {
	load: (self: Persistence, userId: number) -> InventoryState?,
	save: (self: Persistence, userId: number, state: InventoryState) -> (),
}

export type Service = {
	start: (self: Service) -> (),
	addInstance: (self: Service, player: Player, instance: ItemInstance) -> boolean,
	addQuantity: (self: Service, player: Player, itemId: string, quantity: number, uid: string?) -> boolean,
	find: (self: Service, player: Player, uid: string) -> ItemInstance?,
	removeInstance: (self: Service, player: Player, uid: string) -> boolean,
	removeQuantity: (self: Service, player: Player, uid: string, quantity: number) -> boolean,
	updateAttributes: (self: Service, player: Player, uid: string, attributes: ItemAttributes) -> boolean,
	equip: (self: Service, player: Player, slot: string, uid: string) -> boolean,
	applyUseMutations: (self: Service, player: Player, uid: string, mutations: UseMutations) -> boolean,
	getSnapshot: (self: Service, player: Player) -> InventoryState?,
}

local InventoryService = {}
local loadBackoffSeconds = { 0.1, 0.2, 0.4, 0.8, 1.6 }
local loadFailureMessage = "Falha ao carregar dados"

local function copyState(state: InventoryState): InventoryState
	return InventoryStore.copyState(state)
end

function InventoryService.new(persistence: Persistence): Service
	local loadedStates: { [Player]: InventoryState } = {}
	local loadingPlayers: { [Player]: boolean } = {}
	local playerGenerations: { [Player]: number } = {}
	local started = false
	local service = {} :: Service

	local function loadPlayer(player: Player, generation: number): ()
		if playerGenerations[player] ~= generation then
			return
		end
		if loadedStates[player] ~= nil or not loadingPlayers[player] then
			return
		end

		local function isCurrent(): boolean
			return playerGenerations[player] == generation
		end

		local state: InventoryState? = nil
		local loadSucceeded = false
		for attempt, backoffSeconds in loadBackoffSeconds do
			if not isCurrent() then
				return
			end
			local ok, result = pcall(function(): InventoryState?
				return persistence:load(player.UserId)
			end)
			if ok then
				state = result
				loadSucceeded = true
				break
			end
			if attempt < #loadBackoffSeconds then
				task.wait(backoffSeconds)
			end
		end

		if not isCurrent() then
			return
		end
		loadingPlayers[player] = nil
		if not loadSucceeded then
			player:Kick(loadFailureMessage)
			return
		end
		local loadedState = if state == nil then InventoryStore.defaultInventory() else state
		if player.Parent == nil then
			return
		end

		local snapshot = copyState(loadedState)
		if not isCurrent() then
			return
		end
		loadedStates[player] = snapshot
		if not isCurrent() then
			loadedStates[player] = nil
			return
		end
		inventoryChanged:FireClient(player, copyState(snapshot))
		if not isCurrent() then
			return
		end
		player:LoadCharacter()
	end

	local function beginLoad(player: Player): ()
		if loadedStates[player] ~= nil or loadingPlayers[player] then
			return
		end
		local generation = (playerGenerations[player] or 0) + 1
		playerGenerations[player] = generation
		loadingPlayers[player] = true
		task.spawn(loadPlayer, player, generation)
	end

	local function removePlayer(player: Player): ()
		playerGenerations[player] = (playerGenerations[player] or 0) + 1
		local snapshot = loadedStates[player]
		loadedStates[player] = nil
		loadingPlayers[player] = nil
		if snapshot == nil then
			return
		end

		local saveSnapshot = copyState(snapshot)
		local ok = pcall(function()
			persistence:save(player.UserId, saveSnapshot)
		end)
		if not ok then
			task.spawn(function()
				task.wait(0.1)
				pcall(function()
					persistence:save(player.UserId, copyState(saveSnapshot))
				end)
			end)
		end
	end

	function service:start(): ()
		if started then
			return
		end
		started = true
		Players.CharacterAutoLoads = false
		Players.PlayerAdded:Connect(beginLoad)
		Players.PlayerRemoving:Connect(removePlayer)
		for _, player in Players:GetPlayers() do
			beginLoad(player)
		end
	end

	local function applyMutation(player: Player, mutation: (InventoryState) -> InventoryState?): boolean
		local state = loadedStates[player]
		if state == nil then
			return false
		end

		local updatedState = mutation(state)
		if updatedState == nil then
			return false
		end

		loadedStates[player] = updatedState
		inventoryChanged:FireClient(player, copyState(updatedState))
		return true
	end

	function service:addInstance(player: Player, instance: ItemInstance): boolean
		return applyMutation(player, function(state): InventoryState?
			return InventoryStore.addInstance(state, instance)
		end)
	end

	function service:addQuantity(player: Player, itemId: string, quantity: number, uid: string?): boolean
		if type(itemId) ~= "string" or itemId == "" or type(quantity) ~= "number" then
			return false
		end
		return applyMutation(player, function(state): InventoryState?
			return InventoryStore.addQuantity(state, itemId, quantity, uid)
		end)
	end

	function service:find(player: Player, uid: string): ItemInstance?
		local state = loadedStates[player]
		if state == nil then
			return nil
		end
		return InventoryStore.findInstance(state, uid)
	end

	function service:removeInstance(player: Player, uid: string): boolean
		return applyMutation(player, function(state): InventoryState?
			return InventoryStore.removeInstance(state, uid)
		end)
	end

	function service:removeQuantity(player: Player, uid: string, quantity: number): boolean
		return applyMutation(player, function(state): InventoryState?
			return InventoryStore.removeQuantity(state, uid, quantity)
		end)
	end

	function service:updateAttributes(player: Player, uid: string, attributes: ItemAttributes): boolean
		return applyMutation(player, function(state): InventoryState?
			return InventoryStore.updateAttributes(state, uid, attributes)
		end)
	end

	function service:equip(player: Player, slot: string, uid: string): boolean
		return applyMutation(player, function(state): InventoryState?
			return InventoryStore.equip(state, slot, uid)
		end)
	end

	function service:applyUseMutations(player: Player, uid: string, mutations: UseMutations): boolean
		if mutations.consumeInstance == true and mutations.consumeQuantity ~= nil then
			return false
		end
		local state = loadedStates[player]
		if state == nil then
			return false
		end

		local candidate = copyState(state)
		if mutations.consumeInstance == true then
			local updated = InventoryStore.removeInstance(candidate, uid)
			if updated == nil then return false end
			candidate = updated
		elseif mutations.consumeQuantity ~= nil then
			local updated = InventoryStore.removeQuantity(candidate, uid, mutations.consumeQuantity)
			if updated == nil then return false end
			candidate = updated
		end
		if mutations.updateAttributes ~= nil then
			local updated = InventoryStore.updateAttributes(candidate, uid, mutations.updateAttributes)
			if updated == nil then return false end
			candidate = updated
		end
		if mutations.equipSlot ~= nil then
			local updated = InventoryStore.equip(candidate, mutations.equipSlot, uid)
			if updated == nil then return false end
			candidate = updated
		end

		loadedStates[player] = candidate
		inventoryChanged:FireClient(player, copyState(candidate))
		return true
	end

	function service:getSnapshot(player: Player): InventoryState?
		local state = loadedStates[player]
		if state == nil then
			return nil
		end
		return copyState(state)
	end

	getInventory.OnServerInvoke = function(player: Player): InventoryState?
		local state = loadedStates[player]
		if state == nil then
			return nil
		end
		return service:getSnapshot(player)
	end

	return service
end

return InventoryService
