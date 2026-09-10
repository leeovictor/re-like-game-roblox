--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Locator = require(ReplicatedStorage.Shared.locator.locator)
local DocumentsControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentsController)
local DocumentReaderControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

export type DocumentInteraction = interactionTypes.InteractionHandler

local function createInteraction(): DocumentInteraction
	local documents: DocumentsControllerModule.DocumentsController = Locator.get("DocumentsController")
	local reader: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")
	assert(documents ~= nil, "DocumentInteraction requires DocumentsController")
	assert(reader ~= nil, "DocumentInteraction requires DocumentReaderController")
	assert(type(documents.collect) == "function", "DocumentInteraction DocumentsController is required")
	assert(type(reader.open) == "function", "DocumentInteraction DocumentReaderController is required")

	local warned: { [Instance]: { [string]: boolean } } = {}

	local function warnInvalid(target: Instance, code: string, reason: string): ()
		local targetWarnings = warned[target]
		if targetWarnings == nil then
			targetWarnings = {}
			warned[target] = targetWarnings
		end
		if targetWarnings[code] then
			return
		end
		targetWarnings[code] = true
		warn(string.format("Document target %s: %s", target:GetFullName(), reason))
	end

	local interaction = {} :: DocumentInteraction

	function interaction.interact(target: Instance): ()
		if not target:IsA("BasePart") and not target:IsA("Model") then
			warnInvalid(target, "invalid-root", "root must be a Model or BasePart")
			return
		end

		local documentId = target:GetAttribute(interactionTypes.DOCUMENT_ID_ATTRIBUTE)
		if type(documentId) ~= "string" or documentId == "" then
			warnInvalid(target, "missing-id", "DocumentId must be a non-empty string")
			return
		end

		local document = documents.getDocument(documentId)
		if document == nil then
			warnInvalid(target, "unknown-id", string.format("unknown or invalid DocumentId %q", documentId))
			return
		end

		if documents.has(documentId) then
			warnInvalid(target, "duplicate-id", string.format("DocumentId %q was already collected", documentId))
			return
		end

		local collected = documents.collect(documentId)
		if collected == nil then
			warnInvalid(target, "collect-failed", string.format("could not collect DocumentId %q", documentId))
			return
		end

		target:Destroy()
		reader.open(document.id)
	end

	return interaction
end

return {
	new = createInteraction,
}
