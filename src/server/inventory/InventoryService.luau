--!strict

local Players = game:GetService("Players")

local InventoryStore = require(script.Parent.InventoryStore)
local remotes = require(script.Parent.Parent.Parent.Parent.ReplicatedStorage.Shared.remotes)
local inventoryChanged = remotes.InventoryChanged :: RemoteEvent
local getInventory = remotes.GetInventory :: RemoteFunction

type InventoryState = {
	version: number,
	items: { string },
}

type Persistence = {
	load: (self: Persistence, userId: number) -> InventoryState?,
	save: (self: Persistence, userId: number, state: InventoryState) -> (),
}

export type Service = {
	start: (self: Service) -> (),
}

local InventoryService = {}
local loadBackoffSeconds = { 0.1, 0.2, 0.4, 0.8, 1.6 }
local loadFailureMessage = "Falha ao carregar dados"

local function copyState(state: InventoryState): InventoryState
	return {
		version = state.version,
		items = table.clone(state.items),
	}
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

	getInventory.OnServerInvoke = function(player: Player): InventoryState?
		local state = loadedStates[player]
		if state == nil then
			return nil
		end
		return copyState(state)
	end

	return service
end

return InventoryService
