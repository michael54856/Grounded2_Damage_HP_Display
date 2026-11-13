-- Discovery only. Native corrosion names do not yet prove accumulation semantics.
local Base,M = require("ElementAccumulationCore"),{}
setmetatable(M,{__index=Base})
function M.related(name)
    -- "Sour" must not match engine "Source" / "Resource" fields.
    local lower=tostring(name):lower():gsub("source","")
    return lower:find("corros",1,true) ~= nil or lower:find("sour",1,true) ~= nil
        or lower:find("acid",1,true) ~= nil
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
function M.safe_getter() return false end -- First capture never invokes new corrosion functions.
local maximum_fields={"MaxCorrosionLevel","MaximumCorrosionLevel","MaxCorrosion","CorrosionThreshold",
    "MaximumLevel","MaxLevel","MaxValue"}
function M.describe(provider)
    local values=provider.values
    local enabled=type(values.bCorrosionEnabled) == "boolean" and tostring(values.bCorrosionEnabled) or "unavailable"
    local maximum,maximum_key
    for _,key in ipairs(maximum_fields) do
        if Base.finite(values[key]) then maximum,maximum_key=values[key],key; break end
    end
    return "SOUR_SAMPLE raw_corrosion=" .. Base.number(values.CurrentCorrosionLevel)
        .. " previous_corrosion=" .. Base.number(values.PreviousCorrosionLevel)
        .. " raw_ratio=" .. Base.number(values.CorrosionRatio)
        .. " raw_per_second=" .. Base.number(values.CurrentCorrosionPerSecond)
        .. " max_candidate=" .. Base.number(maximum) .. " max_source=" .. (maximum_key or "unavailable")
        .. " enabled=" .. enabled
        .. " provider_id=" .. provider.id .. " source=" .. provider.path .. " interpretation=unverified"
end
return M
