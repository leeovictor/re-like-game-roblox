--!strict

local StarterPlayer = game:GetService("StarterPlayer")

local CombatServiceModule = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatService)
local TankControlMath = require(game:GetService("ReplicatedStorage").Shared.player.TankControlMath)

export type PlayerState = "Free" | "Aiming" | "Reloading"

export type InputState = TankControlMath.InputState & {
	running: boolean,
	aiming: boolean,
}

export type StateContext = {
	input: InputState,
	combat: CombatServiceModule.CombatService,
	transition: (nextState: PlayerState) -> (),
	beginAim: () -> (boolean, Vector3?),
	endAim: () -> (),
	shoot: () -> boolean,
	requestReload: () -> boolean,
	updateFreeMovement: (deltaTime: number) -> (),
	updateAimRotation: (deltaTime: number) -> (),
	stopMovement: () -> (),
	setLookVector: (lookVector: Vector3) -> (),
	setAimTarget: (lookVector: Vector3?) -> (),
}

export type StateObject = {
	onBegin: ((context: StateContext) -> ())?,
	onEnd: ((context: StateContext) -> ())?,
	update: (context: StateContext, deltaTime: number) -> (),
	onAimChanged: ((context: StateContext, aiming: boolean) -> ())?,
	onShoot: ((context: StateContext) -> ())?,
	onReload: ((context: StateContext) -> ())?,
}

export type MovementController = {
	setLookVector: (self: MovementController, lookVector: Vector3) -> (),
	setCFrame: (self: MovementController, cframe: CFrame) -> (),
}

export type TransformOverride = {
	setCFrame: (self: TransformOverride, cframe: CFrame) -> boolean,
	release: (self: TransformOverride) -> (),
}

export type PlayerController = MovementController & {
	state: PlayerState,
	started: boolean,
	beginTransformOverride: (
		self: PlayerController,
		attackId: number
	) -> TransformOverride?,
	start: (self: PlayerController) -> (),
	stop: (self: PlayerController) -> (),
}

return {}
