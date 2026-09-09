--!strict

export type InteractionType = "Door" | "Pickup" | "Dialogue" | "Switch" | "Document"

export type InteractionHandler = {
	interact: (target: Instance) -> (),
}

export type ProbeConfig = {
	size: Vector3,
	forwardOffset: number,
}

return {
	INTERACTABLE_TAG = "Interactable",
	INTERACTION_TYPE_ATTRIBUTE = "InteractionType",
	DOOR_TYPE = "Door",
	PICKUP_TYPE = "Pickup",
	DIALOGUE_TYPE = "Dialogue",
	SWITCH_TYPE = "Switch",
	DOCUMENT_TYPE = "Document",
	DIALOGUE_FOLDER_NAME = "Dialogue",
	ITEM_ID_ATTRIBUTE = "ItemId",
	QUANTITY_ATTRIBUTE = "Quantity",
	DOCUMENT_ID_ATTRIBUTE = "DocumentId",
}
