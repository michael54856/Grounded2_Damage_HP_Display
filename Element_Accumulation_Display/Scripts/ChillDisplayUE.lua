local Base,Core = require("ElementAccumulationUE"),require("ChillDisplayCore")
local M = setmetatable({}, {__index=Base})
local bridge,verified,panel_api
local COUNT,CHILD = "/Script/UMG.PanelWidget:GetChildrenCount","/Script/UMG.PanelWidget:GetChildAt"
function M.reset_layout() panel_api = nil end
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
    for _,spec in ipairs(expected) do
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
        if not M.live(object) then finished=true; break end
        if not shown(object) then return false end
        object=M.call(object,"/Script/UMG.Widget:GetParent")
    end
    if not finished then return false end
    object=widget
    for _=1,16 do
        if not M.live(object) then return true end
        if M.is_a(object,"/Script/UMG.Widget") and not shown(object) then return false end
        object=object:GetOuter()
    end
    return false
end
function M.class_key(object)
    local ok,name=pcall(function() return object:GetClass():GetFName():ToString() end)
    return ok and name or ""
end
local function panel_ready()
    if panel_api ~= nil then return panel_api end
    local ok,err=pcall(function()
        local count=M.parameters(assert(M.find(COUNT),"GetChildrenCount missing"))
        local child=M.parameters(assert(M.find(CHILD),"GetChildAt missing"))
        assert(#count == 1 and count[1].key == "ReturnValue" and count[1].kind == "IntProperty","unexpected count signature")
        assert(#child == 2 and child[1].key == "Index" and child[1].kind == "IntProperty"
            and child[2].key == "ReturnValue"
            and (child[2].kind == "ObjectProperty" or child[2].kind == "ObjectPtrProperty"),"unexpected child signature")
    end)
    panel_api=ok
    if not ok then M.log("CHILL_LAYOUT_API_UNAVAILABLE " .. tostring(err)) end
    return panel_api
end
function M.widget_children(object,limit)
    local children={}
    if not M.live(object) or not M.is_a(object,"/Script/UMG.Widget") then return children,true end
    if M.is_a(object,"/Script/UMG.UserWidget") then
        local root=M.member(M.member(object,"WidgetTree"),"RootWidget")
        if M.live(root) and M.is_a(root,"/Script/UMG.Widget") then children[1]=root; return children,false end
        return children,true
    end
    if not M.is_a(object,"/Script/UMG.PanelWidget") then return children,false end
    if not panel_ready() then return children,true end
    local count=M.call(object,COUNT)
    assert(type(count) == "number" and count >= 0 and count == math.floor(count) and count < math.huge,"invalid child count")
    local incomplete=count > limit
    for i=0,math.min(count,limit)-1 do
        local child=M.unwrap(M.call(object,CHILD,i))
        if M.live(child) and M.is_a(child,"/Script/UMG.Widget") then children[#children+1]=child
        else incomplete=true end
    end
    return children,incomplete
end
function M.image_resource(object)
    local ok,value=pcall(function() return M.member(object,"Brush").ResourceObject end)
    return ok and M.valid(value) and value or nil
end
function M.viewport(controller)
    local size=M.static("/Script/UMG.WidgetLayoutLibrary","GetViewportSize",controller)
    local scale=M.static("/Script/UMG.WidgetLayoutLibrary","GetViewportScale",controller)
    if type(scale) ~= "number" or scale ~= scale or scale <= 0 then return nil end
    return Core.point({X=size.X/scale,Y=size.Y/scale})
end
function M.widget_rect(widget,controller)
    if not M.live(widget) or not M.is_a(widget,"/Script/UMG.Widget") then return nil end
    if not bridge then bridge=require("ChillDisplayGeometry").new(M,RegisterHook) end
    return bridge.read(widget,function(geometry)
        local size=Core.point(M.static("/Script/UMG.SlateBlueprintLibrary","GetLocalSize",geometry))
        if not size or size.X <= 0 or size.Y <= 0 then return nil end
        local function convert(point)
            local pixel,result={},{}
            M.static("/Script/UMG.SlateBlueprintLibrary","LocalToViewport",controller,geometry,point,pixel,result)
            return Core.point(result)
        end
        local top,bottom=convert({X=0,Y=0}),convert(size)
        if top and bottom and bottom.X > top.X and bottom.Y > top.Y then
            return {X=top.X,Y=top.Y,width=bottom.X-top.X,height=bottom.Y-top.Y}
        end
    end)
end
function M.bar_rect(controller,bar,viewport,config,row)
    if not M.live(bar) or not M.is_a(bar,"/Script/UMG.ProgressBar") or not M.visible(bar) then return nil end
    local health=M.widget_rect(bar,controller)
    if not health then return nil end
    local rect=Core.rect(health,viewport,config,row or config.ChillRow or 1)
    if rect then
        M.once("chill-column-ready","CHILL_COLUMN_READY rows=" .. config.MaxEffectRows
            .. " row=" .. rect.row .. " gap=" .. config.ColumnGap .. " icon_gap=" .. config.IconGap)
    else
        M.once("chill-column-space","CHILL_COLUMN_UNAVAILABLE insufficient_left_or_vertical_space_or_invalid_layout")
    end
    return rect
end
return M
