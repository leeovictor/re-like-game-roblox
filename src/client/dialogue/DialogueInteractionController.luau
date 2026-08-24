--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

type InteractionHandler = interactionTypes.InteractionHandler

export type Dependencies = {
	show: (text: string, callback: ((nil, string) -> ())?) -> (),
}

type Message = {
	name: string,
	text: string,
}

local function createController(dependencies: Dependencies): InteractionHandler
	local warned: { [Instance]: boolean } = {}

	local function warnInvalid(target: Instance, reason: string): ()
		if warned[target] then
			return
		end
		warned[target] = true
		warn(string.format("Dialogue target %s: %s", target:GetFullName(), reason))
	end

	local function readMessages(target: Instance): { Message }
		local folder = target:FindFirstChild(interactionTypes.DIALOGUE_FOLDER_NAME)
		if folder == nil then
			warnInvalid(target, "missing Dialogue folder")
			return {}
		end
		if not folder:IsA("Folder") then
			warnInvalid(target, "Dialogue must be a Folder")
			return {}
		end

		local messages: { Message } = {}
		for _, child in folder:GetChildren() do
			if child:IsA("StringValue") and child.Value ~= "" then
				table.insert(messages, { name = child.Name, text = child.Value })
			end
		end

		if #messages == 0 then
			warnInvalid(target, "Dialogue folder has no non-empty StringValue")
			return {}
		end

		table.sort(messages, function(left, right)
			return left.name < right.name
		end)
		return messages
	end

	local controller = {} :: InteractionHandler
	function controller.interact(target: Instance): ()
		if not target:IsA("BasePart") and not target:IsA("Model") then
			return
		end

		local messages = readMessages(target)
		if #messages == 0 then
			return
		end

		local index = 1
		local function nextMessage(_: nil, reason: string): ()
			if reason ~= "completed" then
				return
			end

			index += 1
			local message = messages[index]
			if message ~= nil then
				dependencies.show(message.text, nextMessage)
			end
		end

		dependencies.show(messages[1].text, nextMessage)
	end

	return controller
end

return {
	new = createController,
}
