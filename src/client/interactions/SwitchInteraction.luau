local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local DialogueController = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueController)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

type Deps = {
    dialogueController: DialogueController.DialogueController
}

type SwitchData = {
    preAskText: string?,
    askText: string,
    options: { DialogueController.DialogOption },
    handlerName: string,
    enabled: boolean,
}

local function readSwitchDataFromTarget(target: Instance) : SwitchData
    local enabled = target:GetAttribute('enabled')
    local preAskText = target:GetAttribute('preAskText')
    local askText = target:GetAttribute('askText')
    local handlerName = target:GetAttribute('handlerName')
    local optionsFolder = target:FindFirstChild('Options')
    
    assert(askText ~= nil, "askText is required")
    assert(handlerName ~= nil, "handleName is required")
    assert(optionsFolder ~= nil, "handleName is required")

    local options = {}
    for _, instance in ipairs(optionsFolder:GetChildren()) do
        if instance:IsA('Configuration') then
            local id = instance:GetAttribute('id')   
            local text = instance:GetAttribute('text')

            if not id or not text then
                warn('invalid option configuration. missing id or text attribute')
                continue
            end

            table.insert(options, { id = id, text = text })
        end
    end
    
    assert(#options > 0, 'no options can be created. check if valid options are created into the Options folder')
    
    return {
        enabled = enabled,
        preAskText = preAskText,
        askText = askText,
        options = options,
        handlerName = handlerName,
    }
end

return function (deps: Deps)        
    local SwitchInteration = {}
    
    function SwitchInteration.interact(target: Instance)
        local data = readSwitchDataFromTarget(target)

        if not data.enabled then
            deps.dialogueController:show(data.preAskText)
            return
        end
        
        local ok, responseHandler = pcall(function ()
            return require(script.Parent.switchHandlers[data.handlerName])
        end)
        
        if not ok then
            error('SwitchInteraction: the response handler for the switch do not exists in the folder switchHandlers')
        end

        if not data.preAskText then
            deps.dialogueController:ask(data.askText, data.options, responseHandler)
            return
        end
        
        deps.dialogueController:show(data.preAskText, function (_, reason)
            deps.dialogueController:ask(data.askText, data.options, responseHandler)
        end)
    end
    
    return SwitchInteration :: interactionTypes.InteractionHandler
end