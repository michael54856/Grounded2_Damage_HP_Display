local Core,M = require("ChillDisplayCore"),{}
local default_phases = {"chilling","frozen"}
local source = debug.getinfo(1,"S").source
local serial = 0
function M.new(ue,config,options)
    options=options or {}
    local phases=options.Phases or default_phases
    local tag,prefix=options.Tag or "CHILL",options.WidgetPrefix or "G2Chill"
    local function tint_for(phase)
        if options.Colors then return assert(options.Colors[phase],"missing display tint " .. phase) end
        return phase == "frozen" and config.FrozenColor or config.ChillingColor
    end
    local ui = {nodes={}}
    function ui.hide()
        if ui.visible and ue.live(ui.widget) then ui.widget:SetVisibility(2) end
        ui.visible = false
        for _,node in ipairs(ui.nodes) do node.active,node.moving,node.key,node.tween,node.full_since = false,false,nil,nil,nil end
    end
    function ui.has_active()
        if not ui.visible then return false end
        for _,node in ipairs(ui.nodes) do
            if node.active and (node.moving or node.full_since ~= nil and config.FullPulseEnabled ~= false) then return true end
        end
        return false
    end
    function ui.clear()
        if ue.live(ui.widget) then pcall(function() ui.widget:RemoveFromParent() end) end
        ui.widget,ui.canvas,ui.tree,ui.textures = nil,nil,nil,nil
        ui.visible = false
        ui.nodes = {}
    end
    local function construct(path,outer,name)
        local class = assert(ue.find(path),"missing UI class " .. path)
        local object = StaticConstructObject(class,outer,FName(prefix .. "_" .. serial .. "_" .. name))
        assert(ue.live(object),"cannot construct chill widget " .. name)
        object:SetVisibility(3) -- HitTestInvisible; never consume mouse/game input.
        return object
    end
    local function attach(canvas,child,z)
        local slot = canvas:AddChildToCanvas(child)
        assert(ue.live(slot),"cannot attach chill widget")
        slot:SetAutoSize(false)
        slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
        slot:SetAlignment({X=0,Y=0})
        slot:SetPosition({X=0,Y=0})
        slot:SetZOrder(z)
        return slot
    end
    local function usable()
        if not ue.live(ui.widget) or not ue.live(ui.canvas) or #ui.nodes ~= config.MaxBars then return false end
        for _,node in ipairs(ui.nodes) do
            for _,key in ipairs({"panel","slot","icon","icon_slot","outline","outline_group","outline_slot","frame","frame_slot","clip","clip_slot"}) do
                if not ue.live(node[key]) then return false end
            end
            -- The group owns its children; checking the live group above keeps
            -- validation bounded without 34 extra native checks every frame.
            if #node.outline_stamps ~= Core.FrameStampDirections+1 then return false end
            for _,phase in ipairs(phases) do
                if not ue.live(node.fills[phase].image) or not ue.live(node.fills[phase].slot) then return false end
            end
        end
        return true
    end
    local function ensure(controller)
        if usable() then return end
        ui.clear()
        serial = serial + 1
        ue.verify_ui_api()
        local directory = assert(Core.asset_directory(source,config.AssetDirectory),
            "cannot locate Assets directory; set display config AssetDirectory")
        local ok,err = pcall(function()
            -- One import per overlay, not per sample or per target.
            local fill = ue.texture(controller,directory .. "/inside_bar.png")
            ui.textures = {outline=fill,frame=ue.texture(controller,directory .. "/backgroundframe.png"),
                icon=ue.texture(controller,directory .. "/" .. (options.IconFile or "ice_icon.png"))}
            for _,phase in ipairs(phases) do ui.textures[phase]=fill end
            local widget_class = assert(ue.find("/Script/UMG.UserWidget"),"missing UserWidget")
            ui.widget = StaticConstructObject(widget_class,controller,FName(prefix .. "HUD_" .. serial))
            assert(ue.live(ui.widget),"cannot construct chill overlay")
            local tree_class = assert(ue.find("/Script/UMG.WidgetTree"),"missing WidgetTree")
            ui.tree = StaticConstructObject(tree_class,ui.widget,FName(prefix .. "Tree_" .. serial))
            assert(ue.live(ui.tree),"cannot construct chill WidgetTree")
            ui.widget.WidgetTree = ui.tree
            ui.canvas = construct("/Script/UMG.CanvasPanel",ui.tree,"Canvas")
            ui.tree.RootWidget = ui.canvas
            ui.widget:SetOwningPlayer(controller)
            for i=1,config.MaxBars do
                local node = {}
                node.panel = construct("/Script/UMG.CanvasPanel",ui.tree,"Panel_" .. i)
                -- The gold rim extends outside the original bar/panel bounds.
                node.panel:SetClipping(0) -- Inherit; keep the expanded rim visible.
                node.slot = attach(ui.canvas,node.panel,i)
                node.icon = construct("/Script/UMG.Image",ui.tree,"Icon_" .. i)
                node.icon_slot = attach(node.panel,node.icon,3)
                node.icon:SetBrushFromTexture(ui.textures.icon,false)
                -- Original-size copies shifted in a circle form an even rim.
                -- The opaque background masks the center of their union.
                node.outline_group=construct("/Script/UMG.CanvasPanel",ui.tree,"OutlineGroup_" .. i)
                node.outline_group:SetClipping(0)
                node.outline_slot=attach(node.panel,node.outline_group,0)
                node.outline_group:SetVisibility(2)
                node.outline = construct("/Script/UMG.Image",ui.tree,"Outline_" .. i)
                node.outline:SetBrushFromTexture(ui.textures.outline,false)
                node.outline_stamps={{image=node.outline,slot=attach(node.outline_group,node.outline,0)}}
                for direction=1,Core.FrameStampDirections do
                    local image=construct("/Script/UMG.Image",ui.tree,"Outline_" .. i .. "_" .. direction)
                    image:SetBrushFromTexture(ui.textures.outline,false)
                    node.outline_stamps[#node.outline_stamps+1]={image=image,slot=attach(node.outline_group,image,direction)}
                end
                node.outline:SetVisibility(2)
                node.outline_visible=false
                node.frame = construct("/Script/UMG.Image",ui.tree,"Frame_" .. i)
                node.frame_slot = attach(node.panel,node.frame,1)
                node.frame:SetBrushFromTexture(ui.textures.frame,false)
                node.frame:SetColorAndOpacity({R=1,G=1,B=1,A=1})
                node.clip = construct("/Script/UMG.CanvasPanel",ui.tree,"Clip_" .. i)
                node.clip_slot = attach(node.panel,node.clip,2)
                node.clip:SetClipping(1) -- EWidgetClipping::ClipToBounds
                node.fills = {}
                for index,phase in ipairs(phases) do
                    local image = construct("/Script/UMG.Image",ui.tree,"Fill_" .. phase .. "_" .. i)
                    local slot = attach(node.clip,image,index)
                    image:SetBrushFromTexture(ui.textures[phase],false)
                    image:SetVisibility(2)
                    node.fills[phase] = {image=image,slot=slot}
                end
                -- Hidden images hold native brush references to all variants;
                -- Lua wrappers alone must not be relied on as engine GC roots.
                node.panel:SetVisibility(2)
                ui.nodes[i] = node
            end
            ui.widget:SetVisibility(2)
            ui.widget:AddToViewport(91)
        end)
        if not ok then ui.clear(); error(err) end
        ue.log(tag .. "_OVERLAY_READY bars=" .. #ui.nodes .. " assets=" .. directory)
    end
    function ui.prepare(controller)
        ensure(controller) -- Import textures/allocate hidden widgets before combat.
    end
    local function draw_fraction(node,fraction)
        node.moving = node.tween and fraction ~= node.tween.to
        local width = node.rect.fill.width*fraction
        if width ~= node.drawn_width then
            node.clip_slot:SetSize({X=width,Y=node.rect.fill.height})
            node.drawn_width = width
        end
        local visibility = fraction > 0 and 3 or 2
        if visibility ~= node.clip_visibility then node.clip:SetVisibility(visibility); node.clip_visibility = visibility end
    end
    local function draw_effect(node,now,reset)
        local tint=tint_for(node.phase)
        if node.full_since ~= nil then
            local effect=Core.full_effect(now-node.full_since,config)
            node.fills[node.phase].image:SetColorAndOpacity({
                R=tint.R+(1-tint.R)*effect.mix,G=tint.G+(1-tint.G)*effect.mix,
                B=tint.B+(1-tint.B)*effect.mix,A=tint.A*effect.alpha})
            node.icon:SetColorAndOpacity({R=1,G=1,B=1,A=1})
            if config.FullFrameEffectEnabled ~= false then
                local border=Core.full_frame_rect(node.rect.bar,config)
                local old=node.outline_rect
                if not old or old.X ~= border.X or old.Y ~= border.Y
                    or old.width ~= border.width or old.height ~= border.height then
                    local _,stamps=Core.full_frame_stamps(node.rect.bar,config)
                    node.outline_slot:SetPosition({X=border.X,Y=border.Y})
                    node.outline_slot:SetSize({X=border.width,Y=border.height})
                    for index,stamp in ipairs(stamps) do
                        local slot=node.outline_stamps[index].slot
                        slot:SetPosition({X=stamp.X,Y=stamp.Y})
                        slot:SetSize({X=stamp.width,Y=stamp.height})
                    end
                    node.outline_rect=border
                end
                local frame_tint=config.FullFrameColor or {R=1,G=0.72,B=0.12,A=1}
                local color=node.outline_color
                if not color or color.R ~= frame_tint.R or color.G ~= frame_tint.G
                    or color.B ~= frame_tint.B or color.A ~= frame_tint.A then
                    color={R=frame_tint.R,G=frame_tint.G,B=frame_tint.B,A=frame_tint.A}
                    for _,stamp in ipairs(node.outline_stamps) do stamp.image:SetColorAndOpacity(color) end
                    node.outline_color=color
                end
                if not node.outline_visible then
                    node.outline_group:SetVisibility(3); node.outline:SetVisibility(3); node.outline_visible=true
                end
            elseif node.outline_visible then
                node.outline_group:SetVisibility(2); node.outline:SetVisibility(2); node.outline_visible=false
            end
        elseif reset then
            node.fills[node.phase].image:SetColorAndOpacity(tint)
            node.icon:SetColorAndOpacity({R=1,G=1,B=1,A=1})
            if node.outline_visible then
                node.outline_group:SetVisibility(2); node.outline:SetVisibility(2); node.outline_visible=false
            end
        end
    end
    function ui.animate(now)
        if not ue.live(ui.widget) then return end
        for _,node in ipairs(ui.nodes) do
            if node.active and node.moving and node.tween then draw_fraction(node,Core.frame(node.tween,now)) end
            if node.active and node.full_since ~= nil and config.FullPulseEnabled ~= false then draw_effect(node,now) end
        end
    end
    function ui.render(controller,entries,now)
        now = now or 0
        if #entries == 0 then ui.hide(); return end
        ensure(controller)
        for i,node in ipairs(ui.nodes) do
            local entry = entries[i]
            if not entry then
                node.panel:SetVisibility(2)
                node.active,node.moving,node.key,node.tween,node.full_since = false,false,nil,nil,nil
            else
                local rect,model = entry.rect,entry.model
                local size = {X=rect.width,Y=rect.height}
                local old = node.rect
                if not old or old.X ~= rect.X or old.Y ~= rect.Y then node.slot:SetPosition({X=rect.X,Y=rect.Y}) end
                if not old or old.width ~= rect.width or old.height ~= rect.height
                    or old.bar.width ~= rect.bar.width or old.bar.height ~= rect.bar.height
                    or old.bar.X ~= rect.bar.X or old.bar.Y ~= rect.bar.Y
                    or old.icon.width ~= rect.icon.width or old.icon.height ~= rect.icon.height
                    or old.icon.X ~= rect.icon.X or old.icon.Y ~= rect.icon.Y
                    or old.fill.X ~= rect.fill.X or old.fill.Y ~= rect.fill.Y
                    or old.fill.width ~= rect.fill.width or old.fill.height ~= rect.fill.height then
                    node.slot:SetSize(size)
                    node.icon_slot:SetPosition({X=rect.icon.X,Y=rect.icon.Y})
                    node.icon_slot:SetSize({X=rect.icon.width,Y=rect.icon.height})
                    node.frame_slot:SetPosition({X=rect.bar.X,Y=rect.bar.Y})
                    node.frame_slot:SetSize({X=rect.bar.width,Y=rect.bar.height})
                    node.clip_slot:SetPosition({X=rect.fill.X,Y=rect.fill.Y})
                    for _,fill in pairs(node.fills) do fill.slot:SetSize({X=rect.fill.width,Y=rect.fill.height}) end
                    node.drawn_width = nil
                end
                node.rect = rect
                -- The full image never shrinks: only the parent's clip width changes.
                -- This preserves frame/gradient/pointed ends at partial fill.
                local phase_changed = node.phase ~= model.phase
                local key = entry.key or i
                local identity_changed = node.key ~= key or not node.active
                local was_full = node.full_since ~= nil
                if not node.tween or node.tween.to ~= model.fraction or phase_changed or node.key ~= key then
                    node.tween = Core.tween(node.tween,model.fraction,now,config.FillTweenSeconds,
                        phase_changed or node.key ~= key or not node.active)
                end
                node.active,node.key = true,key
                if config.FullEffectEnabled and model.fraction >= 1 then
                    if identity_changed or node.full_since == nil then node.full_since=now end
                else node.full_since=nil end
                if phase_changed then
                    for phase,fill in pairs(node.fills) do fill.image:SetVisibility(phase == model.phase and 3 or 2) end
                    node.phase = model.phase
                end
                draw_fraction(node,Core.frame(node.tween,now))
                draw_effect(node,now,phase_changed or identity_changed or was_full)
                node.panel:SetVisibility(3)
                ue.once(tag:lower() .. "-visible:" .. model.phase,tag .. "_BAR_READY phase=" .. model.phase
                    .. " current=" .. model.current .. " max=" .. model.maximum
                    .. (model.maximum_source and " max_source=" .. model.maximum_source or "")
                    .. " width=" .. rect.bar.width .. " height=" .. rect.bar.height
                    .. " icon_height=" .. rect.icon.height .. " style=left_effect_column; row=" .. tostring(rect.row))
            end
        end
        if not ui.visible then ui.widget:SetVisibility(3); ui.visible = true end
    end
    return ui
end
return M
