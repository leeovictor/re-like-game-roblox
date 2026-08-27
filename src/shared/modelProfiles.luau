--!strict

local ModelProfiles = {}

local PROFILES_FOLDER_NAME = "Profiles"

local BLOCKED_PROPERTIES: { [string]: boolean } = {
	Name = true,
	Parent = true,
}

export type ProfileError = {
	message: string,
	entryName: string?,
	targetName: string?,
	propertyName: string?,
}

export type ProfileResult = {
	success: boolean,
	applied: number,
	errors: { ProfileError },
}

type ProfileOperation = {
	target: Instance,
	propertyName: string,
	value: any,
	previousValue: any,
	entryName: string,
}

local function makeError(
	message: string,
	entry: Instance?,
	target: Instance?,
	propertyName: string?
): ProfileError
	return {
		message = message,
		entryName = if entry ~= nil then entry.Name else nil,
		targetName = if target ~= nil then target:GetFullName() else nil,
		propertyName = propertyName,
	}
end

local function resultWithError(error: ProfileError): ProfileResult
	return {
		success = false,
		applied = 0,
		errors = { error },
	}
end

local function rollback(operations: { ProfileOperation }, errors: { ProfileError }): ()
	for index = #operations, 1, -1 do
		local operation = operations[index]
		local target: any = operation.target
		local ok, restoreError = pcall(function()
			target[operation.propertyName] = operation.previousValue
		end)
		if not ok then
			table.insert(errors, makeError(
				string.format(
					"nao foi possivel restaurar a propriedade: %s",
					tostring(restoreError)
				),
				nil,
				operation.target,
				operation.propertyName
			))
		end
	end
end

function ModelProfiles.setProfile(model: Model, profile: string): ProfileResult
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return resultWithError(makeError("o alvo precisa ser um Model", nil, nil, nil))
	end

	if type(profile) ~= "string" or profile == "" then
		return resultWithError(makeError("o nome do profile precisa ser uma string nao vazia", nil, nil, nil))
	end

	local profilesFolder = model:FindFirstChild(PROFILES_FOLDER_NAME)
	if profilesFolder == nil then
		return resultWithError(makeError(
			string.format('o modelo precisa conter uma Folder chamada "%s"', PROFILES_FOLDER_NAME),
			nil,
			model,
			nil
		))
	end
	if not profilesFolder:IsA("Folder") then
		return resultWithError(makeError(
			string.format('"%s" precisa ser uma Folder', PROFILES_FOLDER_NAME),
			profilesFolder,
			model,
			nil
		))
	end

	local profileInstance = profilesFolder:FindFirstChild(profile)
	if profileInstance == nil or not profileInstance:IsA("Configuration") then
		return resultWithError(makeError(
			string.format('o profile "%s" precisa existir como Configuration', profile),
			nil,
			model,
			nil
		))
	end

	local errors: { ProfileError } = {}
	local operations: { ProfileOperation } = {}
	local seenProperties: { [Instance]: { [string]: boolean } } = {}

	for _, entry in profileInstance:GetChildren() do
		if not entry:IsA("ObjectValue") then
			table.insert(errors, makeError(
				"todos os filhos do profile precisam ser ObjectValue",
				entry,
				nil,
				nil
			))
			continue
		end

		local objectValue = entry :: ObjectValue
		local target = objectValue.Value
		if target == nil then
			table.insert(errors, makeError("ObjectValue precisa ter Value preenchido", entry, nil, nil))
			continue
		end
		if target ~= model and not target:IsDescendantOf(model) then
			table.insert(errors, makeError(
				"o alvo precisa pertencer ao proprio Model",
				entry,
				target,
				nil
			))
			continue
		end
		if target == profilesFolder or target:IsDescendantOf(profilesFolder) then
			table.insert(errors, makeError(
				"o profile nao pode alterar a propria configuracao",
				entry,
				target,
				nil
			))
			continue
		end

		local attributes = objectValue:GetAttributes()
		if next(attributes) == nil then
			table.insert(errors, makeError("ObjectValue precisa ter ao menos um atributo", entry, target, nil))
			continue
		end

		local targetProperties = seenProperties[target]
		if targetProperties == nil then
			targetProperties = {}
			seenProperties[target] = targetProperties
		end

		for propertyName, value in attributes do
			if BLOCKED_PROPERTIES[propertyName] then
				table.insert(errors, makeError(
					string.format('a propriedade "%s" nao pode ser alterada por um profile', propertyName),
					entry,
					target,
					propertyName
				))
				continue
			end
			if targetProperties[propertyName] then
				table.insert(errors, makeError(
					"a mesma propriedade foi declarada mais de uma vez",
					entry,
					target,
					propertyName
				))
				continue
			end
			targetProperties[propertyName] = true

			local dynamicTarget: any = target
			local readOk, previousValue = pcall(function()
				return dynamicTarget[propertyName]
			end)
			if not readOk then
				table.insert(errors, makeError(
					"a propriedade nao existe ou nao pode ser lida",
					entry,
					target,
					propertyName
				))
				continue
			end

			table.insert(operations, {
				target = target,
				propertyName = propertyName,
				value = value,
				previousValue = previousValue,
				entryName = entry.Name,
			})
		end
	end

	if #errors > 0 then
		return {
			success = false,
			applied = 0,
			errors = errors,
		}
	end

	local appliedOperations: { ProfileOperation } = {}
	for _, operation in operations do
		table.insert(appliedOperations, operation)
		local target: any = operation.target
		local ok, assignmentError = pcall(function()
			target[operation.propertyName] = operation.value
		end)
		if not ok then
			local assignmentIssue = makeError(
				string.format("nao foi possivel atribuir a propriedade: %s", tostring(assignmentError)),
				nil,
				operation.target,
				operation.propertyName
			)
			table.insert(errors, assignmentIssue)
			rollback(appliedOperations, errors)
			return {
				success = false,
				applied = 0,
				errors = errors,
			}
		end
	end

	return {
		success = true,
		applied = #operations,
		errors = {},
	}
end

return ModelProfiles
