-- Spicy is a recording label. Temperature/sizzle names remain candidates until
-- attacks, triggering, recovery and (separately) death are compared in a log.
local Base,M=require("ElementAccumulationCore"),{}
setmetatable(M,{__index=Base})
function M.related(name)
    local lower=tostring(name):lower():gsub("burnin","")
    for _,word in ipairs({"spicy","sizzl","burn","temperature","heat"}) do
        if lower:find(word,1,true) then return true end
    end
    return false
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
function M.safe_getter() return false end -- This recording adds no native getter calls.
function M.describe(provider)
    local v=provider.values
    return "SPICY_SAMPLE raw_temperature=" .. Base.number(v.CurrentBodyTemperature)
        .. " normal_temperature=" .. Base.number(v.NormalBodyTemperature)
        .. " max_sizzle_candidate=" .. Base.number(v.MaxSizzle)
        .. " raw_sizzle_ratio=" .. Base.number(v.SizzleRatio)
        .. " raw_per_second=" .. Base.number(v.CurrentBodyTemperaturePerSecond)
        .. " enabled=" .. (type(v.bSizzleEnabled) == "boolean" and tostring(v.bSizzleEnabled) or "unavailable")
        .. " provider_id=" .. provider.id .. " source=" .. provider.path .. " interpretation=unverified"
end
return M
