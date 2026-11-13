local Core,M = require("StunProbeCore"),{}
function M.point(value)
    if value and Core.finite(value.X) and Core.finite(value.Y) then return {X=value.X,Y=value.Y} end
end
function M.model(result)
    local pair = result and result.pair
    if not pair or pair.status ~= "getter_pair_observed" or not Core.finite(pair.current)
        or not Core.finite(pair.maximum) or pair.current < 0 or pair.maximum <= 0 then return nil end
    local state = pair.provider and pair.provider.state
    if not state or (state.check ~= "agree" and state.check ~= "enum_only") then return nil end
    local phase = state.phase
    if phase ~= "normal" and phase ~= "stunned" and phase ~= "cooldown" then return nil end
    return {phase=phase,current=pair.current,maximum=pair.maximum,
        fraction=phase == "stunned" and 1 or math.max(0,math.min(1,pair.current / pair.maximum))}
end
function M.rect(top,bottom,viewport,config)
    top,bottom,viewport = M.point(top),M.point(bottom),M.point(viewport)
    if not top or not bottom or not viewport or viewport.X <= 0 or viewport.Y <= 0 then return nil end
    local native_width,native_height = bottom.X-top.X,bottom.Y-top.Y
    if native_width <= 0 or native_height <= 0 or config.WidthScale <= 0 or config.HeightScale <= 0 then return nil end
    local width = native_width * config.WidthScale
    local height = native_height * config.HeightScale
    if width > viewport.X or height > viewport.Y then return nil end
    local x = (top.X + bottom.X - width) / 2 + config.OffsetX
    local y = bottom.Y + config.GapBelowHealthBar + config.OffsetY
    -- Never turn a hidden/offscreen bar into an unrelated fixed screen meter.
    if top.X < 0 or bottom.X > viewport.X or top.Y < 0 or bottom.Y > viewport.Y
        or y < 0 or y + height > viewport.Y then return nil end
    x = math.max(0,math.min(viewport.X-width,x))
    return {X=x,Y=y,width=width,height=height}
end
function M.frame(tween,now)
    if not tween then return nil end
    if tween.duration <= 0 then return tween.to end
    if now >= tween.start+tween.duration then return tween.to end
    if now <= tween.start then return tween.from end
    local t = math.max(0,math.min(1,(now-tween.start)/tween.duration))
    return tween.from + (tween.to-tween.from)*t
end
function M.tween(previous,target,now,duration,snap)
    local from = not snap and M.frame(previous,now) or target
    return {from=from or target,to=target,start=now,duration=math.max(0,duration)}
end
function M.asset_directory(source,override)
    if type(override) == "string" and override ~= "" then return override:gsub("\\","/"):gsub("/+$","") end
    if type(source) ~= "string" or source:sub(1,1) ~= "@" then return nil end
    local path = source:sub(2):gsub("\\","/")
    local root = path:match("^(.*)/Scripts/[^/]+%.lua$")
    if root then return root .. "/Assets" end
end
return M
