--!strict
local config: { any } = {
	{
		id = "find_exit",
		text = "Encontre uma saída",
		initial = true,
		completesWhen = {
			event = "cinematic_play_ended",
			timelineId = "generator-power-off"
		}
	},
	{
		id = "access_facility",
		text = "Entre na instalação subterrânea",
		initial = nil,
		startsWhen = {
			event = "cinematic_play_ended",
			timelineId = "generator-power-on",
		},
		completesWhen = {
			event = "door_entered",
			doorKey = "facility_entrance",
		},
	},
	{
		id = "restart_generator",
		text = "Religue o gerador",
		startsWhen = {
			event = "cinematic_play_ended",
			timelineId = "generator-power-off"
		},
		completesWhen = {
			event = "cinematic_play_ended",
			doorKey = "generator-power-on",
		},
	}
}

return config
