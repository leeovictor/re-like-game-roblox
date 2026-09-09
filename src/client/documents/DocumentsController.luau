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
	started: boolean,
	state: DocumentsState,
	collectedIds: { string },
	start: (self: DocumentsController) -> (),
	stop: (self: DocumentsController) -> (),
	getState: (self: DocumentsController) -> DocumentsState,
	getCollected: (self: DocumentsController) -> { string },
	has: (self: DocumentsController, id: string) -> boolean,
	getDocument: (self: DocumentsController, id: string) -> DocumentData.Document?,
	collect: (self: DocumentsController, id: string) -> DocumentData.Document?,
}

local DocumentsController = {}
DocumentsController.__index = DocumentsController

local function makeState(collectedIds: { string }): DocumentsState
	return {
		collectedIds = table.clone(collectedIds),
	}
end

local function publish(self: DocumentsController): ()
	self.state = makeState(self.collectedIds)
	self.changed:Fire(self.state)
end

function DocumentsController.new(): DocumentsController
	local collectedIds: { string } = {}
	local self = setmetatable({
		changed = (Signal.new() :: any) :: ChangedSignal,
		started = false,
		state = makeState(collectedIds),
		collectedIds = collectedIds,
	}, DocumentsController)
	return (self :: any) :: DocumentsController
end

function DocumentsController.start(self: DocumentsController): ()
	if self.started then
		return
	end
	self.started = true
	self.state = makeState(self.collectedIds)
end

function DocumentsController.stop(self: DocumentsController): ()
	if not self.started then
		return
	end
	self.started = false
	table.clear(self.collectedIds)
	publish(self)
end

function DocumentsController.getState(self: DocumentsController): DocumentsState
	return self.state
end

function DocumentsController.getCollected(self: DocumentsController): { string }
	return table.clone(self.collectedIds)
end

function DocumentsController.has(self: DocumentsController, id: string): boolean
	for _, collectedId in self.collectedIds do
		if collectedId == id then
			return true
		end
	end
	return false
end

function DocumentsController.getDocument(_self: DocumentsController, id: string): DocumentData.Document?
	return DocumentData.get(id)
end

function DocumentsController.collect(self: DocumentsController, id: string): DocumentData.Document?
	if not self.started or self:has(id) then
		return nil
	end

	local document = self:getDocument(id)
	if document == nil then
		return nil
	end

	table.insert(self.collectedIds, id)
	publish(self)
	return document
end

return DocumentsController
