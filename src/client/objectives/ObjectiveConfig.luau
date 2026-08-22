--!strict

local config: { any } = {
	{
		id = "find_exit",
		text = "Ache uma saida",
		initial = true,
		completesWhen = {
			event = "door_blocked",
			doorKey = "cave_exit",
		},
	},
	{
		id = "find_access_card",
		text = "Encontre o cartao de acesso",
		initial = nil,
		startsWhen = {
			event = "door_blocked",
			doorKey = "cave_exit",
		},
		completesWhen = {
			event = "item_collected",
			itemId = "access_card",
		},
	},
	{
		id = "access_facility",
		text = "Acesse a instalacao",
		initial = nil,
		startsWhen = nil,
		requires = { "find_access_card" },
		completesWhen = {
			event = "door_entered",
			doorKey = "facility_entrance",
		},
	},
}

return config
