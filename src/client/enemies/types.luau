local StarterPlayer = game:GetService("StarterPlayer")
local TankController = require(StarterPlayer.StarterPlayerScripts.Client.player.TankController)

export type State = "idle" | "chasing" | "try_attack" | "attacking" | "stunned"

export type StateMachine<C> = {
	states: { [string]: StateObject<C> }
}

export type StateObject<C> = {
	update: (context: C, deltaTime: number) -> string?,
	onBegin: (context: C) -> ()?,
	onEnd: (context: C) -> ()?,
}

export type SystemState = {
	playerAttackInProgress: boolean,
	playerInvulnerableUntil: number,
	debugEnabled: boolean
}

export type EnemyContext = {
	enemy: Enemy,
	systemState: SystemState,
}

export type Enemy = {
	model: Model,
	state: State,
	humanoid: Humanoid?,
	root: BasePart?,
	path: Path?,
	pathElapsed: number,
	chaseWaypoints: { PathWaypoint },
	chaseWaypointIndex: number,
	chaseDirection: Vector3,
	chaseProgressPosition: Vector3,
	chaseProgressElapsed: number,
	chaseStuckElapsed: number,
	destroyed: boolean,
	update: (self: Enemy, deltaTime: number) -> (),
	destroy: (self: Enemy) -> (),
	currentState: StateObject<EnemyContext>,
	detectionRadius: number,
	attackTriggerDistance: number,
	ellapsedAttackTime: number,
	realAttackTime: number?,
	attackDirection: Vector3?,
	oldSpeed: number?,
	attackSetup: boolean,
	attackEffectResolved: boolean,
	debugHitbox: BasePart?,
	ellapsedStuntime: number,
	realStunTime: number?,
	ellapsedAttackingTime: number,
	attackTargetHumanoid: Humanoid?,
	movementController: TankController.MovementController,
	movementLockRelease: (() -> ())?,
	attackingEnemyStartCFrame: CFrame?,
	attackingEnemyTargetCFrame: CFrame?,
	attackingPlayerStartCFrame: CFrame?,
	attackingPlayerTargetCFrame: CFrame?,
	playerAttackOwner: boolean,
}

return {}