--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local DocumentData = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentData)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type DocumentsState = {
	collectedIds: { string },
}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type ChangedSignal = {
	Fire: (self: ChangedSignal, state: DocumentsState) -> (),
	Connect: (self: ChangedSignal, callback: (state: DocumentsState) -> ()) -> SignalConnection,
}

export type DocumentsController = {
	changed: ChangedSignal,
	start: () -> (),
	stop: () -> (),
	getState: () -> DocumentsState,
	getCollected: () -> { string },
	has: (id: string) -> boolean,
	getDocument: (id: string) -> DocumentData.Document?,
	collect: (id: string) -> DocumentData.Document?,
}

local function makeState(collectedIds: { string }): DocumentsState
	return {
		collectedIds = table.clone(collectedIds),
	}
end

local DocumentsController = {} :: DocumentsController
local started = false
local state = makeState({})
local collectedIds = state.collectedIds

local function publish(): ()
	state = makeState(collectedIds)
	DocumentsController.changed:Fire(state)
end

DocumentsController.changed = (Signal.new() :: any) :: ChangedSignal

function DocumentsController.start(): ()
	if started then
		return
	end
	started = true
	state = makeState(collectedIds)
end

function DocumentsController.stop(): ()
	if not started then
		return
	end
	started = false
	table.clear(collectedIds)
	publish()
end

function DocumentsController.getState(): DocumentsState
	return state
end

function DocumentsController.getCollected(): { string }
	return table.clone(collectedIds)
end

function DocumentsController.has(id: string): boolean
	for _, collectedId in collectedIds do
		if collectedId == id then
			return true
		end
	end
	return false
end

function DocumentsController.getDocument(id: string): DocumentData.Document?
	return DocumentData.get(id)
end

function DocumentsController.collect(id: string): DocumentData.Document?
	if not started or DocumentsController.has(id) then
		return nil
	end

	local document = DocumentsController.getDocument(id)
	if document == nil then
		return nil
	end

	table.insert(collectedIds, id)
	publish()
	return document
end

return DocumentsController
