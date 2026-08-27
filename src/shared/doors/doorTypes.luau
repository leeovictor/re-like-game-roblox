--!strict

export type DoorAction = "unlock" | "enter"

export type DoorFailureReason =
	"invalid_door"
	| "too_far"
	| "ambiguous_side"
	| "locked"
	| "already_unlocked"
	| "missing_item"
	| "busy"
	| "invalid_config"
	| "sealed"

export type DoorRequest = {
	door: Model,
	action: DoorAction,
}

export type DoorActionResult = {
	success: boolean,
	reason: DoorFailureReason?,
	action: DoorAction?,
}

return {
	DOOR_TAG = "Door",
	DOORWAY_NAME = "Doorway",
	CENTER_NAME = "Center",
	LOCKED_DIALOGUE_NAME = "LockedDialogue",
	SEALED_DIALOGUE_NAME = "SealedDialogue",
	LOCKED_ATTRIBUTE = "Locked",
	SEALED_ATTRIBUTE = "Sealed",
	REQUIRED_ITEM_ID_ATTRIBUTE = "RequiredItemId",
	DOOR_KEY_ATTRIBUTE = "DoorKey",
	FALLBACK_LOCKED_MESSAGE = "Porta trancada.",
	FALLBACK_SEALED_MESSAGE = "A porta esta selada.",
}
