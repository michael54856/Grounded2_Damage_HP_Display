local Core,M = require("ElementAccumulationCore"),{}
function M.build(actor,ue,config)
    local queue, seen, providers = {},{},{}
    local function enqueue(object)
        if #queue >= config.MaxComponentsToInspect + 1 then
            ue.once("node-limit:" .. tostring(ue.address(actor)),"PROVIDER_SCAN_LIMIT actor=" .. ue.name(actor)); return
        end
        if not ue.live(object) or not ue.belongs(object,actor) then return end
        local id = ue.address(object)
        if not id or seen[id] then return end
        seen[id] = true
        queue[#queue+1] = object
    end
    enqueue(actor)
    local ok, components = pcall(ue.components,actor)
    if ok then for _, component in ipairs(components) do enqueue(component) end
    else ue.once("components:" .. tostring(ue.address(actor)),"COMPONENT_ENUM_ERROR " .. tostring(components)) end
    local index = 1
    while index <= #queue do
        local object = queue[index]
        index = index + 1
        local inspected, schema = pcall(ue.schema,object)
        if inspected then
            if #schema.fields > 0 or #schema.getters > 0 then
                if #providers < config.MaxProvidersPerTarget then
                    local provider = {object=object,schema=schema,path=ue.name(object),id=ue.address(object)}
                    providers[#providers+1] = provider
                    ue.once("provider:" .. provider.id,"PROVIDER actor=" .. ue.name(actor) .. " source=" .. provider.path)
                else ue.once("provider-limit:" .. tostring(ue.address(actor)),"PROVIDER_LIMIT actor=" .. ue.name(actor)) end
            end
            for _, field in ipairs(schema.references) do enqueue(ue.member(object,field)) end
        else ue.once("schema:" .. tostring(ue.address(object)),"SCHEMA_ERROR " .. ue.name(object) .. " " .. tostring(schema)) end
    end
    return providers
end
function M.read(actor,providers,ue)
    local samples = {}
    for _,provider in ipairs(providers) do
        if ue.live(provider.object) and ue.belongs(provider.object,actor) then
            samples[#samples+1] = {id=provider.id,path=provider.path,
                values=ue.values(provider.object,provider.schema),enum_info=provider.schema.enum_info}
        end
    end
    return samples
end
return M
