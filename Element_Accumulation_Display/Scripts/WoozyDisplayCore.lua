local Base,Layout,M=require("ElementAccumulationCore"),require("ChillDisplayCore"),{}
setmetatable(M,{__index=Layout})
function M.inactive(reason) return reason == "inactive" end
function M.rect(health,viewport,config,row)
    return Layout.rect(health,viewport,config,row or config.Row or 1)
end
function M.model(samples,config)
    local provider,current
    for _,sample in ipairs(samples) do
        local value=sample.values.CurrentPoisonGasLevel
        if Base.finite(value) then
            if provider then return nil,"multiple_gas_providers" end
            provider,current=sample,value
        end
    end
    if not provider then return nil,"current_gas_unavailable" end
    local maximum=config.ReferenceMaximum
    if not Base.finite(maximum) or maximum <= 0 then return nil,"invalid_reference_maximum" end
    if current < 0 then return nil,"negative_gas_level" end
    -- Do not silently render a newly observed larger range using the wrong cap.
    if current > maximum+0.001 then return nil,"above_reference_maximum" end
    if current == 0 and config.HideWhenInactive then return nil,"inactive" end
    return {phase="woozy",current=current,maximum=maximum,
        fraction=math.min(1,current/maximum),maximum_source="configured_observed_reference",
        provider_id=provider.id}
end
return M
