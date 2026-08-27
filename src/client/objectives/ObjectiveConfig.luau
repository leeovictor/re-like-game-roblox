--!strict

local config: { any } = {
	{
		id = "find_exit",
		text = "Encontre uma saida",
		initial = true,
		completeIf = function(facts)
			return facts:hasEvent("door_blocked", { doorKey = "facility_entrance" })
				or facts:hasEvent("door_unlocked", { doorKey = "facility_entrance" })
				or facts:hasEvent("door_entered", { doorKey = "facility_entrance" })
		end,
	},
	{
		id = "find_access_card",
		text = "Encontre o cartão de acesso",
		initial = nil,
		startsWhen = {
			event = "door_blocked",
			doorKey = "facility_entrance",
		},
		completesWhen = {
			event = "item_collected",
			itemId = "access_card",
		},
	},
	{
		id = "access_facility",
		text = "Entre na instalação subterrânea",
		initial = nil,
		startsWhen = {
			event = "item_collected",
			itemId = "access_card",
		},
		requires = { "find_exit" },
		completesWhen = {
			event = "door_entered",
			doorKey = "facility_entrance",
		},
	},
	{
		id = "restart_generator",
		text = "Reinicie o gerador",
		startsWhen = {
			event = "cinematic_play_ended",
			timelineId = "generator-power-off"
		},
		completesWhen = {
			event = "door_entered",
			doorKey = "facility_entrance",
		},
	}
}

return config
