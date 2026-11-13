-- Venom and poison gas are independent candidates, not interchangeable readings.
local Base,M=require("ElementAccumulationCore"),{}
setmetatable(M,{__index=Base})
M.LevelFields={"CurrentVenomLevel","CurrentPoisonGasLevel"}
function M.related(name)
    local lower=tostring(name):lower()
    return lower:find("venom",1,true) ~= nil or lower:find("poison",1,true) ~= nil
        or lower:find("toxin",1,true) ~= nil
end
function M.safe_field(name,kind,focused)
    if not focused and not M.related(name) then return false end
    return kind == "FloatProperty" or kind == "DoubleProperty" or kind == "IntProperty" or kind == "BoolProperty"
end
function M.accepted(kind,value)
    if kind == "BoolProperty" then return type(value) == "boolean" end
    if kind == "IntProperty" then return Base.integer(value) end
    return (kind == "FloatProperty" or kind == "DoubleProperty") and Base.finite(value)
end
function M.safe_getter() return false end
local function candidate(values,keys)
    for _,key in ipairs(keys) do if Base.finite(values[key]) then return Base.number(values[key]),key end end
    return "unavailable","unavailable"
end
function M.describe(provider)
    local v=provider.values
    local venom,venom_key=candidate(v,{"MaxVenomLevel","MaximumVenomLevel","VenomThreshold"})
    local gas,gas_key=candidate(v,{"MaxPoisonGasLevel","MaximumPoisonGasLevel","PoisonGasThreshold"})
    local generic,generic_key=candidate(v,{"MaximumLevel","MaxLevel","MaxValue","Threshold"})
    return "POISON_SAMPLE venom_current=" .. Base.number(v.CurrentVenomLevel)
        .. " poison_gas_current=" .. Base.number(v.CurrentPoisonGasLevel)
        .. " venom_max_candidate=" .. venom .. " venom_max_source=" .. venom_key
        .. " gas_max_candidate=" .. gas .. " gas_max_source=" .. gas_key
        .. " generic_max_candidate=" .. generic .. " generic_max_source=" .. generic_key
        .. " raw_venom_ratio=" .. Base.number(v.VenomRatio)
        .. " raw_poison_gas_ratio=" .. Base.number(v.PoisonGasRatio)
        .. " provider_id=" .. provider.id .. " source=" .. provider.path .. " interpretation=unverified"
end
return M
