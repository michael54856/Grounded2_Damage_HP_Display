local Core,M = require("StunDisplayCore"),{}
local phases = {"normal","stunned","cooldown"}
local source = debug.getinfo(1,"S").source
local serial = 0
function M.new(ue,config)
    local ui = {nodes={}}
    function ui.hide()
        if ui.visible and ue.live(ui.widget) then ui.widget:SetVisibility(2) end
        ui.visible = false
        for _,node in ipairs(ui.nodes) do node.active,node.moving,node.key,node.tween = false,false,nil,nil end
    end
    function ui.has_active()
        if not ui.visible then return false end
        for _,node in ipairs(ui.nodes) do if node.active and node.moving then return true end end
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
        local object = StaticConstructObject(class,outer,FName("G2Stun_" .. serial .. "_" .. name))
        assert(ue.live(object),"cannot construct stun widget " .. name)
        object:SetVisibility(3) -- HitTestInvisible; never consume mouse/game input.
        return object
    end
    local function attach(canvas,child,z)
        local slot = canvas:AddChildToCanvas(child)
        assert(ue.live(slot),"cannot attach stun widget")
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
            for _,key in ipairs({"panel","slot","frame_clip","frame_clip_slot","frame","frame_slot","clip","clip_slot"}) do
                if not ue.live(node[key]) then return false end
            end
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
            "cannot locate Assets directory; set StunDisplayConfig.AssetDirectory")
        local ok,err = pcall(function()
            -- One import per overlay, not per sample or per target.
            ui.textures = {frame=ue.texture(controller,directory .. "/stunBar_frame.png"),
                normal=ue.texture(controller,directory .. "/stunBar_inside.png"),
                stunned=ue.texture(controller,directory .. "/stunBar_inside_red.png"),
                cooldown=ue.texture(controller,directory .. "/stunBar_inside_blue.png")}
            local widget_class = assert(ue.find("/Script/UMG.UserWidget"),"missing UserWidget")
            ui.widget = StaticConstructObject(widget_class,controller,FName("G2StunHUD_" .. serial))
            assert(ue.live(ui.widget),"cannot construct stun overlay")
            local tree_class = assert(ue.find("/Script/UMG.WidgetTree"),"missing WidgetTree")
            ui.tree = StaticConstructObject(tree_class,ui.widget,FName("G2StunTree_" .. serial))
            assert(ue.live(ui.tree),"cannot construct stun WidgetTree")
            ui.widget.WidgetTree = ui.tree
            ui.canvas = construct("/Script/UMG.CanvasPanel",ui.tree,"Canvas")
            ui.tree.RootWidget = ui.canvas
            ui.widget:SetOwningPlayer(controller)
            -- Apply opacity to the actual images once, rather than stacking it
            -- on the overlay as well. Split empty/filled regions below.
            ui.widget:SetRenderOpacity(1)
            local opacity = config.Opacity or 1
            for i=1,config.MaxBars do
                local node = {}
                node.panel = construct("/Script/UMG.CanvasPanel",ui.tree,"Panel_" .. i)
                node.slot = attach(ui.canvas,node.panel,i)
                node.frame_clip = construct("/Script/UMG.CanvasPanel",ui.tree,"FrameClip_" .. i)
                node.frame_clip_slot = attach(node.panel,node.frame_clip,0)
                node.frame_clip:SetClipping(1)
                node.frame = construct("/Script/UMG.Image",ui.tree,"Frame_" .. i)
                node.frame_slot = attach(node.frame_clip,node.frame,0)
                node.frame:SetBrushFromTexture(ui.textures.frame,false)
                node.frame:SetRenderOpacity(opacity)
                node.clip = construct("/Script/UMG.CanvasPanel",ui.tree,"Clip_" .. i)
                node.clip_slot = attach(node.panel,node.clip,1)
                node.clip:SetClipping(1) -- EWidgetClipping::ClipToBounds
                node.fills = {}
                for index,phase in ipairs(phases) do
                    local image = construct("/Script/UMG.Image",ui.tree,"Fill_" .. phase .. "_" .. i)
                    local slot = attach(node.clip,image,index)
                    image:SetBrushFromTexture(ui.textures[phase],false)
                    image:SetRenderOpacity(opacity)
                    image:SetVisibility(2)
                    node.fills[phase] = {image=image,slot=slot}
                end
                -- Hidden images hold native brush references to all variants;
                -- Lua wrappers alone must not be relied on as engine GC roots.
                node.panel:SetVisibility(2)
                ui.nodes[i] = node
            end
            ui.widget:SetVisibility(2)
            ui.widget:AddToViewport(90)
        end)
        if not ok then ui.clear(); error(err) end
        ue.log("STUN_OVERLAY_READY bars=" .. #ui.nodes .. " assets=" .. directory)
    end
    function ui.prepare(controller)
        ensure(controller) -- Import textures/allocate hidden widgets before combat.
    end
    local function draw_fraction(node,fraction)
        node.moving = node.tween and fraction ~= node.tween.to
        local width = node.rect.width*fraction
        if width ~= node.drawn_width then
            node.clip_slot:SetSize({X=width,Y=node.rect.height})
            -- Keep the full-size background texture, but expose only the empty
            -- segment to the right of the fill. Its dark center must not sit
            -- underneath translucent colored pixels (0.75 over 0.75 => 0.9375).
            node.frame_clip_slot:SetPosition({X=width,Y=0})
            node.frame_clip_slot:SetSize({X=node.rect.width-width,Y=node.rect.height})
            node.frame_slot:SetPosition({X=-width,Y=0})
            node.drawn_width = width
        end
        local visibility = fraction > 0 and 3 or 2
        if visibility ~= node.clip_visibility then node.clip:SetVisibility(visibility); node.clip_visibility = visibility end
        local frame_visibility = fraction < 1 and 3 or 2
        if frame_visibility ~= node.frame_visibility then
            node.frame_clip:SetVisibility(frame_visibility)
            node.frame_visibility = frame_visibility
        end
    end
    function ui.animate(now)
        if not ue.live(ui.widget) then return end
        for _,node in ipairs(ui.nodes) do
            if node.active and node.moving and node.tween then draw_fraction(node,Core.frame(node.tween,now)) end
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
                node.active,node.moving,node.key,node.tween = false,false,nil,nil
            else
                local rect,model = entry.rect,entry.model
                local size = {X=rect.width,Y=rect.height}
                local old = node.rect
                if not old or old.X ~= rect.X or old.Y ~= rect.Y then node.slot:SetPosition({X=rect.X,Y=rect.Y}) end
                if not old or old.width ~= rect.width or old.height ~= rect.height then
                    node.slot:SetSize(size)
                    node.frame_slot:SetSize(size)
                    for _,fill in pairs(node.fills) do fill.slot:SetSize(size) end
                    node.drawn_width = nil
                end
                node.rect = rect
                -- The full image never shrinks: only the parent's clip width changes.
                -- This preserves frame/gradient/pointed ends at partial fill.
                local phase_changed = node.phase ~= model.phase
                local key = entry.key or i
                if not node.tween or node.tween.to ~= model.fraction or phase_changed or node.key ~= key then
                    node.tween = Core.tween(node.tween,model.fraction,now,config.FillTweenSeconds,
                        phase_changed or node.key ~= key or not node.active)
                end
                node.active,node.key = true,key
                if phase_changed then
                    for phase,fill in pairs(node.fills) do fill.image:SetVisibility(phase == model.phase and 3 or 2) end
                    local tint = model.phase == "stunned" and config.StunnedColor
                        or model.phase == "cooldown" and config.CooldownColor or config.NormalColor
                    node.fills[model.phase].image:SetColorAndOpacity(tint)
                    node.phase = model.phase
                end
                draw_fraction(node,Core.frame(node.tween,now))
                node.panel:SetVisibility(3)
                ue.once("stun-visible:" .. model.phase,"STUN_BAR_READY phase=" .. model.phase
                    .. " current=" .. model.current .. " max=" .. model.maximum
                    .. " width=" .. rect.width .. " height=" .. rect.height)
            end
        end
        if not ui.visible then ui.widget:SetVisibility(3); ui.visible = true end
    end
    return ui
end
return M
