--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local GameplayEvents = require(StarterPlayer.StarterPlayerScripts.Client.events.GameplayEvents)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type ContextNames = 'PlayContext' | 'DialogueContext'

export type InputActionType = "Boolean" | "Direction1d" | "Direction2d" | "ViewportPosition"
local InputActionTypes: {
    Boolean: "Boolean",
    Direction1d: "Direction1d",
    Direction2d: "Direction2d",
    ViewportPosition: "ViewportPosition"
} = {
    Boolean = "Boolean",
    Direction1d = "Direction1d",
    Direction2d = "Direction2d",
    ViewportPosition = "ViewportPosition"
}

export type Action = {
    name: string,
    type: InputActionType,
    bindings: { Enum.KeyCode }
}

export type ContextSpec = {
    name: string,
    actions: { Action }
}

type ActionState = {
    previous: any,
    current: any
}

type SignalConnection = {
    Disconnect: (self: SignalConnection) -> ()
}

type StateChangedSignal = {
    Fire: (self: StateChangedSignal, state: any) -> (),
    Connect: (self: StateChangedSignal, callback: (state: any) -> ()) -> SignalConnection
}

export type Context = {
    spec: ContextSpec,
    _actionsStates: { [string]: ActionState },
    _stateChangedSignals: { [string]: StateChangedSignal },
    _heartbeatCon: RBXScriptConnection?,
    _enabled: boolean,
    _actionsTypeMap: { [string]: InputActionType },
    GetActionState: (self: Context, action: string) -> any,
    BindActionStateChanged: (self: Context, action: string, callback: (state: any) -> ()) -> SignalConnection,
    SetEnabled: (self: Context, enabled: boolean) -> ()
}

local playContextSpec: ContextSpec = {
    name = 'PlayContext',
    actions = {
        {
            name = 'Sprint',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.LeftShift }
        },
        {
            name = 'Rotate',
            type = InputActionTypes.Direction1d,
            bindings = { Enum.KeyCode.A, Enum.KeyCode. D }
        },
        {
            name = 'Move',
            type = InputActionTypes.Direction1d,
            bindings = { Enum.KeyCode.W, Enum.KeyCode.S }
        },
        {
            name = 'Interact',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.E }
        },
        {
            name = 'Aim',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.MouseRightButton }
        },
        {
            name = 'Shoot',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.MouseLeftButton }
        },
        {
            name = 'Reload',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.R }
        }
    }
}

local dialogueContextSpec: ContextSpec = {
    name = 'DialogueContext',
    actions = {
        {
            name = 'Interact',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.E }
        },
        {
            name = 'OptionRight',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.D }
        },
        {
            name = 'OptionLeft',
            type = InputActionTypes.Boolean,
            bindings = { Enum.KeyCode.A }
        },
    }
}

local Context = {}
Context.__index = Context

local function tryTriggerChangeEvent(self: Context, name: string): ()
    local actionState = self._actionsStates[name]
    local stateChangedSignal = self._stateChangedSignals[name]
    assert(actionState ~= nil and stateChangedSignal ~= nil, "Input action state is not initialized")
    if actionState.current ~= actionState.previous then
        stateChangedSignal:Fire(actionState.current)
    end
end

local function getActionValue(_self: Context, action: Action): any
    local pressed: { [number]: boolean } = {}
    for i, binding in ipairs(action.bindings) do
        if binding == Enum.KeyCode.MouseRightButton then
            pressed[i] = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        elseif binding == Enum.KeyCode.MouseLeftButton then
            pressed[i] = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        else
            pressed[i] = UserInputService:IsKeyDown(binding)
        end
    end

    if action.type == InputActionTypes.Boolean then
        return pressed[1]
    end
    if action.type == InputActionTypes.Direction1d then
        local up = if pressed[1] then -1 else 0
        local down = if pressed[2] then 1 else 0
        return up + down
    end

    error('input action type not implemented: ' .. action.type)
end

local function startUpdateActions(self: Context): ()
    if self._heartbeatCon ~= nil then
        return
    end

    self._heartbeatCon = RunService.Heartbeat:Connect(function()
        for _, action in ipairs(self.spec.actions) do
            local actionState = self._actionsStates[action.name]
            assert(actionState ~= nil, "Input action state is not initialized")
            local value = getActionValue(self, action)

            actionState.previous = actionState.current
            actionState.current = value
            tryTriggerChangeEvent(self, action.name)
        end
    end)
end

local function stopUpdateActions(self: Context): ()
    local heartbeatCon = self._heartbeatCon
    if heartbeatCon == nil then
        return
    end
    heartbeatCon:Disconnect()
    self._heartbeatCon = nil
end

local function restoreDefaults(self: Context): ()
    for name, actionState in pairs(self._actionsStates) do
        actionState.previous = actionState.current

        if self._actionsTypeMap[name] == InputActionTypes.Boolean then
            actionState.current = false
        elseif self._actionsTypeMap[name] == InputActionTypes.Direction1d then
            actionState.current = 0
        else
            error('não foi possível restauar o valor padrão da action ' .. name .. ' pois o tipo ' .. self._actionsTypeMap[name] .. ' não é conhecido')
        end

        tryTriggerChangeEvent(self, name)
    end
end

local function setDefaults(self: Context, action: Action): ()
    local value = getActionValue(self, action)
    self._actionsStates[action.name] = {
        previous = value,
        current = value
    }
end

function Context.new(spec: ContextSpec): Context
    local self = setmetatable({
        spec = spec,
        _actionsStates = {},
        _stateChangedSignals = {},
        _heartbeatCon = nil,
        _enabled = false,
        _actionsTypeMap = {}
    }, Context) :: any

    for _, action in ipairs(spec.actions) do
        setDefaults(self, action)
        self._actionsTypeMap[action.name] = action.type
        self._stateChangedSignals[action.name] = (Signal.new() :: any) :: StateChangedSignal
    end

    return self
end

function Context.GetActionState(self: Context, action: string): any
    local actionState = self._actionsStates[action]
    if actionState == nil then
        error('Ação ' .. action .. ' não existe no contexto de input ' .. self.spec.name)
    end

    return actionState.current
end

function Context.BindActionStateChanged(self: Context, action: string, callback: (state: any) -> ()): SignalConnection
    if self._actionsStates[action] == nil then
        error('Ação ' .. action .. ' não existe no contexto de input ' .. self.spec.name)
    end

    local signal = self._stateChangedSignals[action]
    assert(signal ~= nil, "Input action signal is not initialized")
    return signal:Connect(callback)
end

function Context.SetEnabled(self: Context, enabled: boolean): ()
    if enabled == self._enabled then
        return
    end

    if enabled then
        for _, action in ipairs(self.spec.actions) do
            setDefaults(self, action)
        end
        startUpdateActions(self)
    else
        stopUpdateActions(self)
        restoreDefaults(self)
    end

    self._enabled = enabled
end

local InputManager = {}

local contextNames: { PlayContext: ContextNames, DialogueContext: ContextNames } = {
    PlayContext = 'PlayContext',
    DialogueContext = 'DialogueContext'
}
InputManager.ContextNames = contextNames
InputManager.Contexts = {} :: { PlayContext: Context, DialogueContext: Context }
local currentContextName = InputManager.ContextNames.PlayContext
local controlsEnabled = true

function InputManager.init()
    InputManager.Contexts['PlayContext'] = Context.new(playContextSpec)
    InputManager.Contexts['DialogueContext'] = Context.new(dialogueContextSpec)
    InputManager.Contexts['PlayContext']:SetEnabled(controlsEnabled)
end

function InputManager.switchContext(contextName: ContextNames)
    InputManager.Contexts[currentContextName]:SetEnabled(false)
    currentContextName = contextName
    InputManager.Contexts[currentContextName]:SetEnabled(controlsEnabled)
end

function InputManager.disable()
    InputManager.Contexts[currentContextName]:SetEnabled(false)
    controlsEnabled = false
end

function InputManager.enable()
    InputManager.Contexts[currentContextName]:SetEnabled(true)
    controlsEnabled = true
end

GameplayEvents.subscribe(function (event)
    if event.name == 'cinematic_started' then
        InputManager.disable()
    end
    if event.name == 'cinematic_play_ended' then
        InputManager.enable()
    end
end)

return InputManager
