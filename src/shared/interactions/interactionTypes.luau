--!strict

export type InteractionType = "Door" | "Pickup" | "Dialogue"

export type InteractionHandler = {
	interact: (target: Instance) -> (),
}

export type ProbeConfig = {
	size: Vector3,
	forwardOffset: number,
}

export type Controller = {
	start: () -> (),
	stop: () -> (),
	register: (interactionType: string, handler: InteractionHandler) -> (),
	setEnabled: (enabled: boolean) -> (),
	isEnabled: () -> boolean,
	getTarget: () -> Instance?,
}

return {
	INTERACTABLE_TAG = "Interactable",
	INTERACTION_TYPE_ATTRIBUTE = "InteractionType",
	DOOR_TYPE = "Door",
	PICKUP_TYPE = "Pickup",
	DIALOGUE_TYPE = "Dialogue",
	DIALOGUE_FOLDER_NAME = "Dialogue",
	ITEM_ID_ATTRIBUTE = "ItemId",
	QUANTITY_ATTRIBUTE = "Quantity",
}
