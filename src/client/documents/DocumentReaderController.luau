--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local DocumentsControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentsController)
local DocumentData = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentData)
local InputManager = require(StarterPlayer.StarterPlayerScripts.Client.InputManager)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type DocumentReaderState = {
	document: DocumentData.Document,
	pageIndex: number,
}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, state: DocumentReaderState?) -> (),
	Connect: (self: ChangedSignal, callback: (state: DocumentReaderState?) -> ()) -> SignalConnection,
}

export type Dependencies = {
	documents: DocumentsControllerModule.DocumentsController,
}

export type DocumentReaderController = {
	changed: ChangedSignal,
	state: DocumentReaderState?,
	started: boolean,
	generation: number,
	inputConnections: { SignalConnection },
	dependencies: Dependencies,
	start: (self: DocumentReaderController) -> (),
	stop: (self: DocumentReaderController) -> (),
	getState: (self: DocumentReaderController) -> DocumentReaderState?,
	open: (self: DocumentReaderController, documentId: string) -> boolean,
	nextPage: (self: DocumentReaderController) -> (),
	previousPage: (self: DocumentReaderController) -> (),
	close: (self: DocumentReaderController) -> (),
}

local DocumentReaderController = {}
DocumentReaderController.__index = DocumentReaderController

local function publish(self: DocumentReaderController, state: DocumentReaderState?): ()
	self.state = state
	self.changed:Fire(state)
end

local function handleClose(self: DocumentReaderController): ()
	self:close()
end

local function bindActions(self: DocumentReaderController): ()
	local context = InputManager.Contexts.DocumentContext
	table.insert(self.inputConnections, context:BindActionStateChanged("PreviousPage", function(state: boolean)
		if state then
			self:previousPage()
		end
	end))
	table.insert(self.inputConnections, context:BindActionStateChanged("NextPage", function(state: boolean)
		if state then
			self:nextPage()
		end
	end))
	table.insert(self.inputConnections, context:BindActionStateChanged("Close", function(state: boolean)
		if state then
			handleClose(self)
		end
	end))
end

function DocumentReaderController.new(dependencies: Dependencies): DocumentReaderController
	assert(type(dependencies) == "table", "DocumentReaderController dependencies are required")
	assert(type(dependencies.documents.getDocument) == "function", "DocumentReaderController documents.getDocument is required")

	local self = setmetatable({
		changed = (Signal.new() :: any) :: ChangedSignal,
		state = nil,
		started = false,
		generation = 0,
		inputConnections = {},
		dependencies = dependencies,
	}, DocumentReaderController)
	return (self :: any) :: DocumentReaderController
end

function DocumentReaderController.start(self: DocumentReaderController): ()
	if self.started then
		return
	end
	self.started = true
	bindActions(self)
end

function DocumentReaderController.stop(self: DocumentReaderController): ()
	if not self.started and self.state == nil then
		return
	end

	self.started = false
	for _, connection in self.inputConnections do
		connection:Disconnect()
	end
	table.clear(self.inputConnections)
	self.generation += 1
	if self.state ~= nil then
		publish(self, nil)
		InputManager.switchContext("PlayContext")
	end
end

function DocumentReaderController.getState(self: DocumentReaderController): DocumentReaderState?
	return self.state
end

function DocumentReaderController.open(self: DocumentReaderController, documentId: string): boolean
	if not self.started then
		return false
	end

	local document = self.dependencies.documents:getDocument(documentId)
	if document == nil then
		return false
	end

	self.generation += 1
	publish(self, {
		document = document,
		pageIndex = 1,
	})
	InputManager.switchContext("DocumentContext")
	return true
end

function DocumentReaderController.nextPage(self: DocumentReaderController): ()
	local current = self.state
	if current == nil then
		return
	end

	if current.pageIndex >= #current.document.pages then
		self:close()
		return
	end

	publish(self, {
		document = current.document,
		pageIndex = current.pageIndex + 1,
	})
end

function DocumentReaderController.previousPage(self: DocumentReaderController): ()
	local current = self.state
	if current == nil then
		return
	end

	publish(self, {
		document = current.document,
		pageIndex = math.max(1, current.pageIndex - 1),
	})
end

function DocumentReaderController.close(self: DocumentReaderController): ()
	if self.state == nil then
		return
	end

	self.generation += 1
	publish(self, nil)
	InputManager.switchContext("PlayContext")
end

return DocumentReaderController
