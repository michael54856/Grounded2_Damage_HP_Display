local Core, M = require("StunProbeCore"),{}
local State = require("StunProbeState")
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
function M.read(actor,providers,ue,config)
    local samples,states = {},{}
    for _, provider in ipairs(providers) do
        if ue.live(provider.object) and ue.belongs(provider.object,actor) then
            local sample = {id=provider.id,path=provider.path,values=ue.values(provider.object,provider.schema),
                state_enum=provider.schema.state_enum,state_enabled=provider.schema.state_enabled}
            samples[#samples+1] = sample
            if sample.state_enabled then
                sample.state = State.observe(sample.values,sample.state_enum)
                states[#states+1] = {id=sample.id,path=sample.path,observation=sample.state,values=sample.values}
            end
        end
    end
    local pair, reason = Core.select(samples,config)
    return {pair=pair,reason=reason,providers=samples,states=states}
end
function M.describe(result)
    local pair = result.pair
    if not pair then return "STUN_UNRESOLVED reason=" .. tostring(result.reason) end
    local state_text = pair.provider.state and (" " .. State.describe(pair.provider.state)) or ""
    return "STUN_SAMPLE status=" .. pair.status .. " current=" .. Core.number(pair.current)
        .. " max=" .. Core.number(pair.maximum) .. " current_source=" .. pair.current_key
        .. " max_source=" .. pair.maximum_key .. " ratio_relation="
        .. Core.ratio_relation(pair.current,pair.maximum,pair.provider.values["GetStunRatio()"])
        .. " source=" .. pair.provider.path .. state_text
end
return M
