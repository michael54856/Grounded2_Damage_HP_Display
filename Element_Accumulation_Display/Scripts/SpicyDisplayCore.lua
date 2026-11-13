local Base,Layout,M=require("ElementAccumulationCore"),require("ChillDisplayCore"),{}
setmetatable(M,{__index=Layout})
function M.inactive(reason) return reason == "inactive" or reason == "cold_temperature" end
function M.model(samples,config)
    local provider,current
    for _,sample in ipairs(samples) do
        local value=sample.values.CurrentBodyTemperature
        if Base.finite(value) then
            if provider then return nil,"multiple_temperature_providers" end
            provider,current=sample,value
        end
    end
    if not provider then return nil,"current_temperature_unavailable" end
    if current < 0 then return nil,"cold_temperature" end
    if current == 0 and config.HideWhenInactive then return nil,"inactive" end
    local maximum=provider.values.MaxSizzle
    if not Base.finite(maximum) or maximum <= 0 then return nil,"native_max_sizzle_unavailable" end
    if current > maximum+0.001 then return nil,"above_native_maximum" end
    return {phase="spicy",current=current,maximum=maximum,
        fraction=math.min(1,current/maximum),maximum_source="native_MaxSizzle",provider_id=provider.id}
end
return M
