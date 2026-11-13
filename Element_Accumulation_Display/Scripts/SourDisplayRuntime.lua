local Core,Shared,M=require("SourDisplayCore"),require("ChillDisplayRuntime"),{}
function M.new(ue,config,probe_config,ui,reader)
    return Shared.new(ue,config,probe_config,ui,reader,Core,"SOUR")
end
function M.start()
    local config=require("SourDisplayConfig")
    local ue=require("SourDisplayUE").new()
    local ui=require("ChillDisplayUI").new(ue,config,{Tag="SOUR",WidgetPrefix="G2Sour",
        IconFile="sour_icon.png",Phases={"sour"},Colors={sour=config.SourColor}})
    M.active=M.new(ue,config,require("ElementAccumulationConfig"),ui)
    M.events=require("ChillDisplayEvents").new(ue,RegisterHook,NotifyOnNewObject,ExecuteInGameThread,
        function(widgets) M.active.update(widgets) end,"SOUR")
    M.events.prepare()
    M.loop=LoopInGameThreadWithDelay(config.UpdateIntervalMs,M.active.update)
    M.animation_loop=LoopInGameThreadWithDelay(config.AnimationIntervalMs,M.active.fast)
    ue.log("SOUR_UI_LOADED version=0.4.0-alpha; auto_display=" .. tostring(config.Enabled)
        .. "; sample_ms=" .. config.UpdateIntervalMs .. "; standalone_row=" .. (config.Row or 1)
        .. "; reference_max=" .. config.ReferenceMaximum .. "; max_source=configured_observed_reference"
        .. "; native_current=CurrentCorrosionLevel; F5=diagnostic_capture_only")
end
return M
