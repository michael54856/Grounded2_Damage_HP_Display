local Base,M = require("ElementAccumulationCore"),{}
function M.point(value)
    if value and Base.finite(value.X) and Base.finite(value.Y) then return {X=value.X,Y=value.Y} end
end
function M.inactive(reason) return reason == "inactive" or reason == "hot_state" end
function M.model(samples,config)
    local candidate,reason = Base.candidate(samples)
    if not candidate then return nil,reason end
    local provider,raw = candidate.provider,candidate.raw
    if candidate.key ~= "GetCurrentBodyTemperature()" then return nil,"getter_unavailable" end
    local threshold = provider.values.MaxChill
    if not Base.finite(threshold) or threshold >= 0 then return nil,"invalid_cold_threshold" end
    local state = provider.values["GetCurrentBodyTemperatureState()"]
    local names = provider.enum_info and provider.enum_info.names
    local name = type(names) == "table" and names[state] or nil
    local leaf = type(name) == "string" and name:match("([^:]+)$") or nil
    local frozen = provider.values["IsFrozen()"]
    if type(frozen) ~= "boolean" then return nil,"frozen_flag_unavailable" end
    local phase
    if leaf == "MaxChill" then
        if not frozen or math.abs(raw-threshold) > 0.01 then return nil,"state_conflict" end
        phase = "frozen"
    elseif leaf == "Chilling" then
        if frozen or raw >= 0 then return nil,"state_conflict" end
        phase = "chilling"
    elseif leaf == "Normal" then
        if frozen or raw < 0 then return nil,"state_conflict" end
        if config.HideWhenInactive then return nil,"inactive" end
        phase = "chilling"
    elseif leaf == "Sizzling" or leaf == "MaxSizzle" then return nil,"hot_state"
    else return nil,"unknown_temperature_state" end
    local maximum,current = -threshold,math.max(0,-raw)
    return {phase=phase,current=current,maximum=maximum,raw=raw,
        fraction=phase == "frozen" and 1 or math.max(0,math.min(1,current/maximum))}
end
function M.rect(health,viewport,config,row)
    if not health or not Base.finite(health.X) or not Base.finite(health.Y)
        or not Base.finite(health.width) or not Base.finite(health.height)
        or health.width <= 0 or health.height <= 0 or not M.point(viewport) then return nil end
    local bar_width,bar_height = config.BarWidth,health.height*config.HeightScale
    if not Base.finite(bar_width) then return nil end
    local icon_height = health.height*config.IconHeightScale
    local icon_width = icon_height*config.IconAspectRatio
    local width,height = icon_width+config.IconGap+bar_width,math.max(icon_height,bar_height)
    local inset = bar_height*config.FillInsetHeightScale
    if bar_width <= 2*inset or bar_height <= 2*inset or icon_width <= 0
        or icon_height <= 0 or icon_width+config.IconGap < 0 or inset < 0 or width > viewport.X then return nil end
    row = row or config.ChillRow or 1
    if not Base.integer(row) or row < 1 or row > config.MaxEffectRows
        or config.ColumnGap < 0 or config.ColumnRowGap < 0 then return nil end
    local x=health.X-config.ColumnGap-width+config.OffsetX
    -- First bar aligns vertically with native health; its taller icon extends
    -- upward. Every later row has the same footprint and a fixed row gap.
    local top=math.max(0,health.Y+bar_height-height)
    local y=top+(row-1)*(height+config.ColumnRowGap)+config.OffsetY
    if health.X < 0 or health.Y < 0 or health.X+health.width > viewport.X
        or x < 0 or x+width > health.X or y < 0 or y+height > viewport.Y then return nil end
    -- Never clamp the left column over native health when there is no room.
    local bar_x,bar_y = icon_width+config.IconGap,height-bar_height
    return {X=x,Y=y,width=width,height=height,row=row,
        icon={X=0,Y=height-icon_height,width=icon_width,height=icon_height},
        bar={X=bar_x,Y=bar_y,width=bar_width,height=bar_height},
        fill={X=bar_x+inset,Y=bar_y+inset,width=bar_width-2*inset,height=bar_height-2*inset}}
end
function M.full_frame_rect(bar,config)
    local thickness=math.max(0,config.FullFrameThickness or 2)
    return {X=bar.X-thickness,Y=bar.Y-thickness,
        width=bar.width+2*thickness,height=bar.height+2*thickness}
end
-- Dilate the original silhouette in UMG units. Every stamp keeps the original
-- image dimensions, so rounded ends are never stretched differently per axis.
M.FrameStampDirections=16
function M.full_frame_stamps(bar,config)
    local border=M.full_frame_rect(bar,config)
    local thickness=(border.width-bar.width)/2
    local stamps={{X=thickness,Y=thickness,width=bar.width,height=bar.height}}
    for index=0,M.FrameStampDirections-1 do
        local angle=index*2*math.pi/M.FrameStampDirections
        stamps[#stamps+1]={X=thickness+thickness*math.cos(angle),Y=thickness+thickness*math.sin(angle),
            width=bar.width,height=bar.height}
    end
    return border,stamps
end
function M.full_effect(elapsed,config)
    if config.FullPulseEnabled == false then return {mix=0,alpha=1,pulse=0} end
    elapsed=math.max(0,elapsed)
    local period=math.max(0.1,config.FullPulseSeconds)
    local pulse=0.5+0.5*math.cos(elapsed*2*math.pi/period)
    local flash=config.FullFlashSeconds > 0 and math.max(0,1-elapsed/config.FullFlashSeconds) or 0
    return {mix=math.max(flash,0.15+0.5*pulse),alpha=0.78+0.22*pulse,pulse=pulse}
end
function M.frame(tween,now)
    if not tween then return nil end
    if tween.duration <= 0 or now >= tween.start+tween.duration then return tween.to end
    if now <= tween.start then return tween.from end
    return tween.from+(tween.to-tween.from)*(now-tween.start)/tween.duration
end
function M.tween(previous,target,now,duration,snap)
    return {from=not snap and M.frame(previous,now) or target,to=target,start=now,duration=math.max(0,duration)}
end
function M.asset_directory(source,override)
    if type(override) == "string" and override ~= "" then return (override:gsub("\\","/"):gsub("/+$","")) end
    local path=type(source) == "string" and source:sub(1,1) == "@" and source:sub(2):gsub("\\","/") or nil
    local root=path and path:match("^(.*)/Scripts/[^/]+%.lua$")
    if root then return root .. "/Assets" end
end
return M
