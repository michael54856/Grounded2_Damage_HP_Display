local M = {}
function M.finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
function M.integer(value) return M.finite(value) and value == math.floor(value) end
function M.number(value)
    if not M.finite(value) then return "unavailable" end
    return (string.format("%.6f",value):gsub("0+$",""):gsub("%.$",""))
end
function M.related(name)
    local lower = tostring(name):lower()
    for _,word in ipairs({"chill","cold","freez","frozen","temperature","statuseffect"}) do
        if lower:find(word,1,true) then return true end
    end
    return false
end
function M.object_kind(kind) return kind == "ObjectProperty" or kind == "ObjectPtrProperty" end
function M.function_path(name) return (name:gsub("^Function%s+","")) end
M.enum_getter_path = "/Script/Maine.BodyTemperatureComponent:GetCurrentBodyTemperatureState"
local getters = {
    ["/Script/Maine.BodyTemperatureComponent:GetCurrentBodyTemperature"]="float",
    ["/Script/Maine.BodyTemperatureComponent:GetCurrentBodyTemperatureRatio"]="float",
    [M.enum_getter_path]="enum",
    ["/Script/Maine.BodyTemperatureComponent:IsFrozen"]="bool",
    ["/Script/Maine.SurvivalCharacter:IsFrozen"]="bool",
    ["/Script/Maine.SurvivalCreature:IsFrozen"]="bool",
}
local floats = {CurrentBodyTemperature=true,PreviousBodyTemperature=true,CurrentBodyTemperaturePerSecond=true,
    NormalBodyTemperature=true,MaxChill=true,ChillRatio=true,ChillRateMultiplier=true,ChillHazardExitDecayRate=true,
    ExitDecayOnAdditiveStatusEffectChillDelayTime=true,FrozenExitChillRatio=true,FrozenDuration=true,FrozenRemainingTime=true}
local booleans = {bChillEnabled=true,bIsFrozen=true,bIsTemperatureSupported=true,bCanFreezeTarget=true}
function M.safe_field(name,kind)
    return (floats[name] == true and (kind == "FloatProperty" or kind == "DoubleProperty"))
        or (booleans[name] == true and kind == "BoolProperty")
end
function M.safe_getter(path,fields)
    if type(fields) ~= "table" or #fields ~= 1 or type(fields[1]) ~= "table" or fields[1].key ~= "ReturnValue" then return false end
    local wanted,field = getters[path],fields[1]
    if wanted == "float" then return field.kind == "FloatProperty" or field.kind == "DoubleProperty" end
    if wanted == "bool" then return field.kind == "BoolProperty" end
    if wanted == "enum" then return field.kind == "EnumProperty" and type(field.enum_info) == "table"
        and type(field.enum_info.names) == "table" and next(field.enum_info.names) ~= nil end
    return false
end
function M.enum_info(path,rows,limit)
    if type(path) ~= "string" or path == "" or type(rows) ~= "table" or #rows == 0
        or not M.integer(limit) or limit <= 0 or #rows > limit then return nil,"invalid_enum_metadata" end
    local info,by_name = {path=path,names={},rows={}},{}
    for _,row in ipairs(rows) do
        if type(row) ~= "table" or type(row.name) ~= "string" or row.name == "" or not M.integer(row.value) then return nil,"invalid_enum_entry" end
        if info.names[row.value] and info.names[row.value] ~= row.name then return nil,"ambiguous_enum_value" end
        if by_name[row.name] ~= nil and by_name[row.name] ~= row.value then return nil,"ambiguous_enum_name" end
        if not info.names[row.value] then info.rows[#info.rows+1] = {name=row.name,value=row.value} end
        info.names[row.value],by_name[row.name] = row.name,row.value
    end
    table.sort(info.rows,function(a,b) return a.value < b.value end)
    return info
end
function M.enum_text(info)
    local parts = {}
    for _,row in ipairs(info.rows) do parts[#parts+1] = row.name .. "=" .. tostring(row.value) end
    return table.concat(parts," ")
end
function M.values_text(values)
    local keys,parts = {},{}
    for key in pairs(values) do keys[#keys+1] = key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local value = values[key]
        parts[#parts+1] = key .. "=" .. (type(value) == "number" and M.number(value) or tostring(value))
    end
    return table.concat(parts," ")
end
function M.state(provider)
    local raw = provider.values["GetCurrentBodyTemperatureState()"]
    local info = provider.enum_info
    local name = M.integer(raw) and info and info.names[raw] or nil
    local frozen = provider.values["IsFrozen()"]
    if type(frozen) ~= "boolean" then frozen = provider.values.bIsFrozen end
    return "state_raw=" .. (M.integer(raw) and tostring(raw) or "unavailable")
        .. " state_name=" .. (name or "unavailable")
        .. " is_frozen=" .. (type(frozen) == "boolean" and tostring(frozen) or "unavailable")
        .. " enum=" .. (info and info.path or "unavailable")
end
function M.candidate(providers)
    local selected,score,ambiguous = nil,0,false
    for _,provider in ipairs(providers) do
        local current,key,rank = provider.values["GetCurrentBodyTemperature()"],"GetCurrentBodyTemperature()",2
        if not M.finite(current) then current,key,rank = provider.values.CurrentBodyTemperature,"CurrentBodyTemperature",1 end
        if M.finite(current) then
            if rank > score then selected,score,ambiguous = {provider=provider,raw=current,key=key},rank,false
            elseif rank == score then ambiguous = true end
        end
    end
    if ambiguous then return nil,"multiple_temperature_providers" end
    if not selected then return nil,"no_direct_temperature_read" end
    return selected
end
function M.describe(providers)
    local candidate,reason = M.candidate(providers)
    if not candidate then return "CHILL_UNRESOLVED reason=" .. reason end
    local provider = candidate.provider
    return "CHILL_SAMPLE raw_temperature=" .. M.number(candidate.raw) .. " raw_source=" .. candidate.key
        .. " max_chill=" .. M.number(provider.values.MaxChill)
        .. " normal_temperature=" .. M.number(provider.values.NormalBodyTemperature)
        .. " getter_ratio=" .. M.number(provider.values["GetCurrentBodyTemperatureRatio()"])
        .. " " .. M.state(provider) .. " source=" .. provider.path .. " interpretation=unverified"
end
function M.should_report(previous,fingerprint,now,heartbeat)
    return not previous or previous.fingerprint ~= fingerprint or now-previous.time >= heartbeat
end
return M
