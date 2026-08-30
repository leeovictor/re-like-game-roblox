local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local GameplayEvents = require(StarterPlayer.StarterPlayerScripts.Client.events.GameplayEvents)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type ContextNames = 'PlayContext' | 'DialogueContext'

export type InputActionType = "Boolean" | "Direction1d" | "Direction2d" | "ViewportPosition"
const InputActionTypes = {
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

export type Context = {
    GetActionState: (action: string) -> any,
    BindActionStateChanged: (action: string, callback: (state: any) -> ()) -> RBXScriptSignal,
    SetEnabled: (enabled: boolean) -> ()
}

function createContext(spec: ContextSpec)
    local _actionsStates: { [string]: {
        previous: any,
        current: any
    } } = {}
    local _stateChangedSignals = {}
    local _heartbeatCon = nil
    local _enabled = false
    local _actionsTypeMap = {}

    local function tryTriggerChangeEvent(name: string)
        if _actionsStates[name].current ~= _actionsStates[name].previous then  
            _stateChangedSignals[name]:Fire(_actionsStates[name].current)
        end
    end

    local function getActionValue(action: Action)
        local pressed = {}
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
        
        error('input action type not implemented: '..action.type)
    end

    local function startUpdateActions()
        if _heartbeatCon ~= nil then
            return
        end

        _heartbeatCon = RunService.Heartbeat:Connect(function ()
            for i, action in ipairs(spec.actions) do
                local value = getActionValue(action)
                
                _actionsStates[action.name].previous = _actionsStates[action.name].current
                _actionsStates[action.name].current = value
                tryTriggerChangeEvent(action.name)
            end
        end)
    end

    local function stopUpdateActions()
        if not _heartbeatCon then
            return
        end
        _heartbeatCon:Disconnect()
        _heartbeatCon = nil
    end
    
    local function restoreDefaults()
        for name, v in pairs(_actionsStates) do
            v.previous = v.current
            
            if _actionsTypeMap[name] == InputActionTypes.Boolean then
                v.current = false
            elseif _actionsTypeMap[name] == InputActionTypes.Direction1d then
                v.current = 0
            else
                error('não foi possível restauar o valor padrão da action '..name..' pois o tipo '.._actionsTypeMap[name]..' não é conhecido')
            end
            
            tryTriggerChangeEvent(name)
        end
    end

    local function setDefaults(action: Action)
        local value = getActionValue(action)
        _actionsStates[action.name] = {
            previous = value,
            current = value
        }
    end

    for i, action in ipairs(spec.actions) do
        setDefaults(action)
        _actionsTypeMap[action.name] = action.type
        _stateChangedSignals[action.name] = Signal.new()
    end
    
    return {
        GetActionState = function (action: string)
            if not _actionsStates[action] then
                error('Ação ' .. action .. ' não existe no contexto de input ' .. spec.name)
            end
            
            return _actionsStates[action].current
        end,
        BindActionStateChanged = function (action: string, callback: (state: any) -> ())
            if not _actionsStates[action] then
                error('Ação ' .. action .. ' não existe no contexto de input ' .. spec.name)
            end

            return _stateChangedSignals[action]:Connect(callback)
        end,
        SetEnabled = function (enabled: boolean)
            if enabled == _enabled then
                return
            end
           
            if enabled then
                for i, action in ipairs(spec.actions) do setDefaults(action) end
                startUpdateActions()
            else
                stopUpdateActions()
                restoreDefaults()
            end
            
            _enabled = enabled
        end
    }
end

local InputManager = {}

InputManager.ContextNames = {
    PlayContext = 'PlayContext',
    DialogueContext = 'DialogueContext'
}
InputManager.Contexts = {} :: { [ContextNames]: Context }
local currentContextName = InputManager.ContextNames.PlayContext
local controlsEnabled = true

function InputManager.init()
    InputManager.Contexts['PlayContext'] = createContext(playContextSpec)
    InputManager.Contexts['DialogueContext'] = createContext(dialogueContextSpec)
    InputManager.Contexts['PlayContext'].SetEnabled(controlsEnabled)
end

function InputManager.switchContext(contextName: ContextNames)
    InputManager.Contexts[currentContextName].SetEnabled(false)
    currentContextName = contextName
    InputManager.Contexts[currentContextName].SetEnabled(controlsEnabled)
end

function InputManager.disable()
    InputManager.Contexts[currentContextName].SetEnabled(false)
    controlsEnabled = false
end

function InputManager.enable()
    InputManager.Contexts[currentContextName].SetEnabled(true)
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