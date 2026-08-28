--!strict

-- Escada de prioridade de input do cliente: dialogo precisa sobrepor
-- movimento e interacao para roubar WASD enquanto um dialogo esta ativo.
local ActionPriorities = {
	MOVEMENT = Enum.ContextActionPriority.High.Value,
	INTERACTION = Enum.ContextActionPriority.High.Value,
	COMBAT = Enum.ContextActionPriority.High.Value + 1,
	DIALOGUE = Enum.ContextActionPriority.High.Value + 2,
}

return ActionPriorities
