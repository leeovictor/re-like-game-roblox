--!strict

-- Escada de prioridade de input do cliente: dialogo precisa sobrepor
-- movimento e interacao para roubar WASD enquanto um dialogo esta ativo.
local ActionPriorities = {
	MOVEMENT = Enum.ContextActionPriority.Medium.Value,
	INTERACTION = Enum.ContextActionPriority.Medium.Value,
	COMBAT = Enum.ContextActionPriority.Medium.Value + 1,
	DIALOGUE = Enum.ContextActionPriority.Medium.Value + 2,
}

return ActionPriorities
