--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

export type EventName =
    "door_blocked"
    | "door_unlocked"
    | "door_entered"
    | "item_collected"
    | "area_entered"
    | "switches_changed"
    | "cinematic_started"
    | "cinematic_play_ended"

export type GameplayEvent =
    { name: "door_blocked", doorKey: string }
    | { name: "door_unlocked", doorKey: string }
    | { name: "door_entered", doorKey: string }
    | { name: "item_collected", itemId: string }
    | { name: "area_entered", areaKey: string }
    | { name: "switches_changed", switchesOn: number }
    | { name: "cinematic_started", timelineId: string }
    | { name: "cinematic_play_ended", timelineId: string }

export type SignalConnection = {
    Disconnect: (self: SignalConnection) -> (),
}

export type GameplayEvents = {
    emit: (event: GameplayEvent) -> (),
    subscribe: (callback: (event: GameplayEvent) -> ()) -> SignalConnection,
}

type EventSignal = {
    Fire: (self: EventSignal, event: GameplayEvent) -> (),
    Connect: (
        self: EventSignal,
        callback: (event: GameplayEvent) -> ()
    ) -> SignalConnection,
}

local changed = (Signal.new() :: any) :: EventSignal

local function emit(event: GameplayEvent): ()
    changed:Fire(event)
end

local function subscribe(callback: (event: GameplayEvent) -> ()): SignalConnection
    return changed:Connect(callback)
end

return {
    emit = emit,
    subscribe = subscribe,
} :: GameplayEvents
