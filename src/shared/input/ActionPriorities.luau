--!strict

-- Escada de prioridade de input do cliente: dialogo precisa sobrepor
-- movimento e interacao para roubar WASD enquanto um dialogo esta ativo.
local ActionPriorities = {
	MOVEMENT = Enum.ContextActionPriority.High.Value,
	INTERACTION = Enum.ContextActionPriority.High.Value,
	DIALOGUE = Enum.ContextActionPriority.High.Value + 1,
}

return ActionPriorities
