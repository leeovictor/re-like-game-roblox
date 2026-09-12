--!strict

export type DocumentPage = {
	content: string,
}

export type Document = {
	id: string,
	displayName: string,
	pages: { DocumentPage },
}

local catalog: { [string]: any } = {
	["november-report"] = {
		id = "november-report",
		displayName = "Relatório de Novembro",
		pages = {
			{
				content = "<b>Relatório de Novembro</b>\n\nA manutenção confirmou que o gerador permanece instável.",
			},
			{ content = "Os registros indicam que a falha começou antes do isolamento da instalação." },
		},
	},
	["maintenance-log"] = {
		id = "maintenance-log",
		displayName = "Diário de Manutenção",
		pages = {
			{ content = "<b>Diário de Manutenção</b>\n\n03:40 — O corredor norte perdeu energia novamente." },
			{ content = "04:15 — A equipe encontrou marcas recentes perto da sala de máquinas." },
			{ content = "04:50 — O acesso foi lacrado até que alguém explique os ruídos vindos do subsolo." },
		},
	},
	["security-memo"] = {
		id = "security-memo",
		displayName = "Memorando de Segurança",
		pages = {
			{
				content = "<b>Memorando de Segurança</b>\n\nTodos os funcionários devem permanecer nas áreas iluminadas.",
			},
			{
				content = "Se o alarme tocar, não use os elevadores. A saída de emergência deve ser operada manualmente.",
			},
		},
	},
	["patient-record"] = {
		id = "patient-record",
		displayName = "Registro de Observação",
		pages = {
			{
				content = "<b>Registro de Observação</b>\n\nO paciente repete a mesma frase desde a última troca de turno.",
			},
			{
				content = "Quando perguntado sobre a origem da voz, aponta para as paredes e pede que as luzes permaneçam apagadas.",
			},
		},
	},
}

local warnedInvalid: { [string]: boolean } = {}

local function validateDocument(id: string, value: any): (Document?, string?)
	if type(value) ~= "table" then
		return nil, "entry must be a table"
	end
	if type(value.id) ~= "string" or value.id == "" then
		return nil, "id must be a non-empty string"
	end
	if value.id ~= id then
		return nil, "id must match the catalog key"
	end
	if type(value.displayName) ~= "string" or value.displayName == "" then
		return nil, "displayName must be a non-empty string"
	end
	if type(value.pages) ~= "table" or #value.pages == 0 then
		return nil, "pages must contain at least one page"
	end

	for index = 1, #value.pages do
		local page = value.pages[index]
		if type(page) ~= "table" then
			return nil, string.format("pages[%d] must be a table", index)
		end
		if type(page.content) ~= "string" then
			return nil, string.format("pages[%d].content must be a string", index)
		end
	end

	return value :: Document, nil
end

local DocumentData = {
	catalog = catalog,
}

function DocumentData.get(id: string): Document?
	local value = catalog[id]
	if value == nil then
		return nil
	end

	local document, reason = validateDocument(id, value)
	if document == nil then
		if not warnedInvalid[id] then
			warnedInvalid[id] = true
			warn(string.format("[DocumentData] Invalid document %s: %s", id, reason :: string))
		end
		return nil
	end
	return document
end

return DocumentData
