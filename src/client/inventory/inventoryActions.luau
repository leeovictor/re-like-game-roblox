--!strict

export type ActionOption = {
	label: string,
	onActivated: () -> (),
}

export type ActionHandlers = {
	dismiss: (uid: string) -> (),
	equip: (uid: string) -> (),
	requestDiscard: (uid: string) -> (),
}

local actionLabelsByItemId: { [string]: { string } } = {
	access_card = { "descartar" },
	bolt_cutter = { "descartar" },
	handgun = { "equipar" },
	handgun_ammo = { "descartar" },
	medkit = { "usar", "descartar" },
}

local function buildActionOptions(uid: string, itemId: string, handlers: ActionHandlers): { ActionOption }
	local options: { ActionOption } = {}
	local labels = actionLabelsByItemId[itemId]
	if labels == nil then
		return options
	end
	for _, label in labels do
		table.insert(options, {
			label = label,
			onActivated = function()
				handlers.dismiss(uid)
				if label == "equipar" then
					handlers.equip(uid)
				elseif label == "descartar" then
					handlers.requestDiscard(uid)
				end
			end,
		})
	end
	return options
end

return {
	buildActionOptions = buildActionOptions,
}
