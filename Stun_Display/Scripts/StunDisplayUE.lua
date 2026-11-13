local Base,Core = require("StunProbeUE"),require("StunDisplayCore")
local M = setmetatable({}, {__index=Base})
local bridge,verified
function M.static(path,method,...)
    local class = assert(M.find(path),"missing class " .. path)
    return M.call(class:GetCDO(),path .. ":" .. method,...)
end
function M.verify_ui_api()
    if verified then return end
    local expected = {
        {"/Script/Engine.KismetRenderingLibrary:ImportFileAsTexture2D",{
            {"WorldContextObject","ObjectProperty"},{"Filename","StrProperty"},{"ReturnValue","ObjectProperty"}}},
        {"/Script/UMG.Image:SetBrushFromTexture",{{"Texture","ObjectProperty"},{"bMatchSize","BoolProperty"}}},
        {"/Script/UMG.Widget:SetClipping",{{"InClipping","EnumProperty","ByteProperty"}}},
    }
    for _, spec in ipairs(expected) do
        local fields = M.parameters(assert(M.find(spec[1]),"missing UI function " .. spec[1]))
        assert(#fields == #spec[2],"unexpected UI signature " .. spec[1])
        for i,field in ipairs(fields) do
            local wanted = spec[2][i]
            assert(field.key == wanted[1] and (field.kind == wanted[2] or field.kind == wanted[3]),
                "unexpected UI parameter " .. spec[1] .. " " .. field.key .. " " .. field.kind)
        end
    end
    verified = true
end
function M.texture(controller,path)
    M.verify_ui_api()
    local texture = M.static("/Script/Engine.KismetRenderingLibrary","ImportFileAsTexture2D",controller,path)
    assert(M.live(texture) and M.is_a(texture,"/Script/Engine.Texture2D"),"cannot import PNG " .. path)
    return texture
end
function M.hud_widget(widget,controller,world)
    -- Cache local HUD widgets even while bShowing is false.
    if not M.live(widget) or M.world(widget) ~= world then return false end
    local ok,owner = pcall(M.call,widget,"/Script/Maine.GameUserWidget:GetOwningSurvivalPlayerController")
    return ok and M.same(owner,controller)
end
function M.visible(widget)
    local function shown(object)
        if not M.call(object,"/Script/UMG.Widget:IsVisible") then return false end
        local opacity = M.member(object,"RenderOpacity")
        return type(opacity) ~= "number" or opacity > 0
    end
    local object,finished = widget,false
    for _=1,24 do
        if not M.live(object) then finished = true; break end
        if not shown(object) then return false end
        object = M.call(object,"/Script/UMG.Widget:GetParent")
    end
    if not finished then return false end
    -- WidgetTree roots have no panel parent; also respect owning HUD visibility.
    object = widget
    for _=1,16 do
        if not M.live(object) then return true end
        if M.is_a(object,"/Script/UMG.Widget") and not shown(object) then return false end
        object = object:GetOuter()
    end
    return false
end
function M.viewport(controller)
    local size = M.static("/Script/UMG.WidgetLayoutLibrary","GetViewportSize",controller)
    local scale = M.static("/Script/UMG.WidgetLayoutLibrary","GetViewportScale",controller)
    if type(scale) ~= "number" or scale ~= scale or scale <= 0 then return nil end
    return Core.point({X=size.X/scale,Y=size.Y/scale})
end
function M.bar_rect(controller,bar,viewport,config)
    if not M.live(bar) then return nil end
    if not M.is_a(bar,"/Script/UMG.ProgressBar") then
        M.once("stun-bar-class:" .. M.name(bar),"STUN_BAR_LAYOUT_UNAVAILABLE unsupported HealthBar " .. M.name(bar))
        return nil
    end
    if not M.visible(bar) then return nil end
    if not bridge then bridge = require("StunDisplayGeometry").new(M,RegisterHook) end
    return bridge.read(bar,function(geometry)
        local size = Core.point(M.static("/Script/UMG.SlateBlueprintLibrary","GetLocalSize",geometry))
        if not size or size.X <= 0 or size.Y <= 0 then
            M.once("stun-bar-zero-layout","STUN_BAR_LAYOUT_UNAVAILABLE zero native geometry")
            return nil
        end
        local function convert(point)
            local pixel,result = {},{}
            M.static("/Script/UMG.SlateBlueprintLibrary","LocalToViewport",controller,geometry,point,pixel,result)
            return Core.point(result)
        end
        local top,bottom = convert({X=0,Y=0}),convert(size)
        local rect = Core.rect(top,bottom,viewport,config)
        if not rect then
            M.once("stun-bar-layout","STUN_BAR_LAYOUT_UNAVAILABLE viewport conversion or available space"
                .. " top=" .. tostring(top and top.X) .. "," .. tostring(top and top.Y)
                .. " bottom=" .. tostring(bottom and bottom.X) .. "," .. tostring(bottom and bottom.Y))
        end
        return rect
    end)
end
return M
