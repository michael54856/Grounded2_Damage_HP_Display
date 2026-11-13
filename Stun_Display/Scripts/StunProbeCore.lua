local M = {}
function M.finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
function M.number(value)
    if not M.finite(value) then return "unavailable" end
    return (string.format("%.6f", value):gsub("0+$", ""):gsub("%.$", ""))
end
function M.related(name)
    local lower = tostring(name):lower()
    return lower:find("stun", 1, true) ~= nil or lower:find("stagger", 1, true) ~= nil
end
function M.scalar_kind(kind)
    return ({FloatProperty=true,DoubleProperty=true,IntProperty=true,UInt32Property=true,
        Int64Property=true,UInt64Property=true,ByteProperty=true,EnumProperty=true,BoolProperty=true})[kind] == true
end
function M.object_kind(kind)
    return kind == "ObjectProperty" or kind == "ObjectPtrProperty"
end
-- Never call arbitrary functions just because their names contain 'Stun'.
M.read_getters = {
    GetCurrentStun=true, GetCurrentStunValue=true, GetStunValue=true,
    GetMaxStun=true, GetMaxStunValue=true, GetStunRatio=true,
}
M.read_fields = {CurrentStunValue=true,MaxStunValue=true,StunDecayRate=true}
function M.safe_field(name,kind)
    return M.read_fields[name] == true and (kind == "FloatProperty" or kind == "DoubleProperty")
end
function M.function_path(full_name)
    return (full_name:gsub("^Function%s+",""))
end
function M.safe_getter(name, fields)
    return M.read_getters[name] == true and #fields == 1
        and fields[1].key == "ReturnValue"
        and (fields[1].kind == "FloatProperty" or fields[1].kind == "DoubleProperty")
end
local function first(values, names)
    for _, key in ipairs(names) do if M.finite(values[key]) then return values[key], key end end
end
function M.pair(provider)
    local values = provider.values
    local current, current_key = first(values, {"CurrentStunValue","GetCurrentStun()","GetCurrentStunValue()","GetStunValue()"})
    local maximum, maximum_key = first(values, {"GetMaxStun()","GetMaxStunValue()","MaxStunValue"})
    if not M.finite(current) or not M.finite(maximum) or maximum <= 0 or current < 0 then return nil end
    return {current=current,maximum=maximum,current_key=current_key,maximum_key=maximum_key,
        provider=provider, score=maximum_key == "MaxStunValue" and 10 or 20,
        status=maximum_key == "MaxStunValue" and "field_pair_unverified" or "getter_pair_observed"}
end
function M.select(providers, config)
    local best, ambiguous
    for _, provider in ipairs(providers) do
        local filter = config.PreferredProviderPathContains
        if not filter or provider.path:lower():find(filter:lower(), 1, true) then
            local pair = M.pair(provider)
            if pair then
                if not best or pair.score > best.score then best, ambiguous = pair, false
                elseif pair.score == best.score then ambiguous = true end
            end
        end
    end
    if ambiguous then return nil, "multiple_providers" end
    if best then return best end
    return nil, "no_direct_current_max_pair"
end
function M.ratio_relation(current, maximum, reported)
    if not M.finite(current) or not M.finite(maximum) or maximum <= 0 or not M.finite(reported) then return "unavailable" end
    local calculated = current / maximum
    local direct = math.abs(calculated - reported) <= 0.015
    local inverse = math.abs(1 - calculated - reported) <= 0.015
    if direct and inverse then return "direct_or_inverse" end
    return direct and "direct" or inverse and "inverse" or "mismatch"
end
function M.values_text(values)
    local keys, parts = {}, {}
    for key in pairs(values) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = values[key]
        parts[#parts+1] = key .. "=" .. (type(value) == "number" and M.number(value) or tostring(value))
    end
    return table.concat(parts, " ")
end
function M.should_report(previous, fingerprint, now, heartbeat)
    return not previous or previous.fingerprint ~= fingerprint or now - previous.time >= heartbeat
end
return M
