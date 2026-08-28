local Locator = {}

local serviceRegistry : { [string]: any } = {}

function Locator.get<T>(name: string): T
    if not serviceRegistry[name] then
        warn('Locator: no service registered with name: ' .. name .. '. Retuning nil')
    end
    return serviceRegistry[name]
end

function Locator.register(name: string, instance: any)
    if serviceRegistry[name] ~= nil then
        error('trying to register a instance with a name that already is registered')
    end

    serviceRegistry[name] = instance
end

return Locator