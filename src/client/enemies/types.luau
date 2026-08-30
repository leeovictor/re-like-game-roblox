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

export type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

export type PlayerAttackStartedEvent = {
	enemy: Enemy,
	attackId: number,
	startCFrame: CFrame,
	targetCFrame: CFrame,
	turnDuration: number,
	duration: number,
}

export type PlayerAttackEndedEvent = {
	enemy: Enemy,
	attackId: number,
	cancelled: boolean,
}

export type PlayerAttackStartedSignal = {
	Fire: (self: PlayerAttackStartedSignal, event: PlayerAttackStartedEvent) -> (),
	Connect: (
		self: PlayerAttackStartedSignal,
		callback: (event: PlayerAttackStartedEvent) -> ()
	) -> SignalConnection,
}

export type PlayerAttackEndedSignal = {
	Fire: (self: PlayerAttackEndedSignal, event: PlayerAttackEndedEvent) -> (),
	Connect: (
		self: PlayerAttackEndedSignal,
		callback: (event: PlayerAttackEndedEvent) -> ()
	) -> SignalConnection,
}

export type PlayerAttackSignals = {
	playerAttackStarted: PlayerAttackStartedSignal,
	playerAttackEnded: PlayerAttackEndedSignal,
}

export type EnemyContext = {
	enemy: Enemy,
	systemState: SystemState,
}

export type Enemy = {
	model: Model,
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
	attackEffectResolved: boolean,
	debugHitbox: BasePart?,
	ellapsedStuntime: number,
	realStunTime: number?,
	ellapsedAttackingTime: number,
	attackTargetHumanoid: Humanoid?,
	attackingEnemyStartCFrame: CFrame?,
	attackingEnemyTargetCFrame: CFrame?,
	playerAttackOwner: boolean,
	playerAttackGeneration: number,
	activePlayerAttackId: number?,
	playerAttackStarted: PlayerAttackStartedSignal,
	playerAttackEnded: PlayerAttackEndedSignal,
}

return {}
