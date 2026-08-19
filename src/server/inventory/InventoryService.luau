--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryStore = require(script.Parent.InventoryStore)
local inventoryTypes = require(ReplicatedStorage.Shared.inventory.items)
local remotes = require(ReplicatedStorage.Shared.remotes)
local inventoryChanged = remotes.InventoryChanged :: RemoteEvent
local getInventory = remotes.GetInventory :: RemoteFunction

type InventoryState = inventoryTypes.InventoryState
type ItemInstance = inventoryTypes.ItemInstance
type ItemAttributes = inventoryTypes.ItemAttributes
type UseMutations = {
	consumeInstance: boolean?,
	consumeQuantity: number?,
	updateAttributes: ItemAttributes?,
	equipSlot: string?,
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

local function copyState(state: InventoryState): InventoryState
	return InventoryStore.copyState(state)
end

function InventoryService.new(): Service
	local loadedStates: { [Player]: InventoryState } = {}
	local started = false
	local service = {} :: Service

	local function initializePlayer(player: Player): ()
		if player.Parent == nil or loadedStates[player] ~= nil then
			return
		end

		local snapshot = InventoryStore.defaultInventory()
		loadedStates[player] = snapshot
		inventoryChanged:FireClient(player, copyState(snapshot))
		if player:IsDescendantOf(Players) then
			player:LoadCharacterAsync()
		end
	end

	local function removePlayer(player: Player): ()
		loadedStates[player] = nil
	end

	function service:start(): ()
		if started then
			return
		end
		started = true
		Players.CharacterAutoLoads = false
		Players.PlayerAdded:Connect(initializePlayer)
		Players.PlayerRemoving:Connect(removePlayer)
		for _, player in Players:GetPlayers() do
			initializePlayer(player)
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
