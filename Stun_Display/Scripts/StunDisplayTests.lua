-- Pure/fake UE regressions. Never import textures or register native hooks here.
local Core,M = require("StunDisplayCore"),{}
function M.run()
    local count = 0
    local function check(value,message)
        assert(value,"Stun_Display UI self-test: " .. message)
        count = count + 1
    end
    -- Fixed fixtures: user changes to width, spacing, colors or Enabled must
    -- not invalidate startup tests or temporarily change the live settings.
    local config = {Enabled=true,Opacity=0.75,UpdateIntervalMs=100,AnimationIntervalMs=16,FillTweenSeconds=0.1,
        DiscoveryInterval=1,MaxCachedWidgets=8,AppearanceRetryFrames=3,ErrorRetrySeconds=2,
        MaxBars=2,WidthScale=0.5,HeightScale=1,GapBelowHealthBar=0,OffsetX=0,OffsetY=0,
        NormalColor={R=1,G=1,B=1,A=1},StunnedColor={R=1,G=1,B=1,A=1},CooldownColor={R=1,G=1,B=1,A=1}}
    local function sample(current,phase,check_state)
        return {pair={current=current,maximum=75,status="getter_pair_observed",
            provider={state={phase=phase,check=check_state or "agree"}}}}
    end
    check(Core.model(sample(30,"normal")).fraction == 0.4,"normal fill uses direct current/max")
    check(Core.model(sample(0,"stunned")).fraction == 1,"stunned state is a full meter independent of ratio")
    check(Core.model(sample(30,"cooldown")).fraction == 0.4,"cooldown uses remaining current/max")
    check(Core.model(sample(90,"normal")).fraction == 1 and Core.model(sample(0,"normal")).fraction == 0,
        "only the rendered percentage is clamped")
    check(not Core.model(sample(30,"unknown")) and not Core.model(sample(30,"stunned","conflict")),
        "unknown/conflicting states never look like normal accumulation")
    check(not Core.model({}) and not Core.model(sample(-1,"normal")),"missing/invalid samples hide the bar")
    local field_pair = sample(20,"normal"); field_pair.pair.status = "field_pair_unverified"
    check(not Core.model(field_pair),"an unverified raw max is not silently used for the UI")
    local rect = Core.rect({X=100,Y=20},{X=500,Y=40},{X=1920,Y=1080},config)
    check(rect.X == 200 and rect.Y == 40 and rect.width == 200,"half-width meter is centered directly against the health bar bottom")
    check(rect.height == 20,"meter height matches native health bar height rather than source aspect ratio")
    check(not Core.rect({X=0,Y=0},{X=0,Y=20},{X=1920,Y=1080},config)
        and not Core.rect({X=-5,Y=20},{X=100,Y=40},{X=1920,Y=1080},config),"unlaid-out/offscreen bars are hidden")
    check(not Core.rect({X=0,Y=1050},{X=400,Y=1070},{X=1920,Y=1080},config),
        "a bar below the screen is not clamped over the health bar")
    check(Core.asset_directory("@C:\\Game\\Mods\\Stun_Display\\Scripts\\StunDisplayUI.lua") == "C:/Game/Mods/Stun_Display/Assets",
        "assets resolve from installed script location without a username or Steam directory")
    check(Core.asset_directory("@D:/Mods/Renamed/Scripts/StunDisplayUI.lua") == "D:/Mods/Renamed/Assets"
        and Core.asset_directory("=string") == nil,"renaming/moving the mod does not bind it to a workspace path")
    local first = Core.tween(nil,0.2,0,0.1,false)
    local moving = Core.tween(first,0.8,1,0.1,false)
    check(math.abs(Core.frame(moving,1.05)-0.5) < 0.00001,"render frames interpolate between real samples")
    check(Core.frame(moving,2) == 0.8 and Core.frame(moving,0) == 0.2,"interpolation is bounded and never predicts unobserved values")
    local retargeted = Core.tween(moving,0.9,1.05,0.1,false)
    check(math.abs(Core.frame(retargeted,1.05)-0.5) < 0.00001,"new samples continue from the displayed fraction without a jump")
    check(Core.frame(Core.tween(moving,0,1.05,0.1,true),1.05) == 0,"state/target changes snap instead of carrying old accumulation")

    local hooked,widget,other = nil,{},{}
    local geometry = {type=function() return "UScriptStruct" end}
    local fake_geometry = {
        find=function() return {} end,parameters=function() return {{key="ReturnValue",kind="StructProperty"}} end,
        same=function(a,b) return a == b end,unwrap=function(value) return value:get() end,log=function() end,
    }
    local bridge
    fake_geometry.call = function(context)
        hooked({get=function() return other end},{get=function() return geometry end})
        local returns = select("#",hooked({get=function() return context end},{get=function() return geometry end}))
        check(returns == 0,"geometry observer does not override other mods or native return")
    end
    bridge = require("StunDisplayGeometry").new(fake_geometry,function(_,_,post) hooked=post; return 1,2 end)
    check(bridge.read(widget,function(value) return value == geometry and 123 end) == 123,
        "opaque native geometry is consumed synchronously for the requested widget")
    check(not pcall(bridge.read,widget,function() error("test consumer failure") end),"geometry consumer failures are reported")
    check(bridge.read(widget,function() return 456 end) == 456,"a failed geometry read does not leave a stale pending request")

    -- Exercise actual UI construction/layout with fake UObjects. Confirm that
    -- fill width stays fixed while the clipping parent changes width.
    local saved_construct,saved_fname = StaticConstructObject,FName
    local ui_ok,ui_error = pcall(function()
        FName = function(value) return value end
        local constructed,imports = {},0
        StaticConstructObject = function(class,outer,name)
            local object = {class=class,outer=outer,name=name}
            function object:SetVisibility(value) self.visibility=value end
            function object:SetRenderOpacity(value) self.opacity=value end
            function object:SetOwningPlayer(value) self.owner=value end
            function object:AddToViewport(value) self.z=value end
            function object:RemoveFromParent() self.removed=true end
            function object:SetBrushFromTexture(value,match) self.texture,self.match=value,match end
            function object:SetClipping(value) self.clipping=value end
            function object:SetColorAndOpacity(value) self.color=value end
            function object:AddChildToCanvas(child)
                child.parent=self
                local slot = {writes={}}
                for _,method in ipairs({"SetAutoSize","SetAnchors","SetAlignment","SetPosition","SetZOrder","SetSize"}) do
                    local key = method
                    slot[key] = function(self,value)
                        self[key:sub(4)] = value
                        self.writes[key] = (self.writes[key] or 0) + 1
                    end
                end
                return slot
            end
            constructed[#constructed+1] = object
            return object
        end
        local fake_ui = {live=function(object) return type(object) == "table" and not object.dead end,
            find=function(path) return path end,verify_ui_api=function() end,log=function() end,once=function() end,
            texture=function(_,path) imports=imports+1; return {path=path} end}
        local ui = require("StunDisplayUI").new(fake_ui,config)
        local controller = {}
        ui.prepare(controller)
        check(imports == 4 and ui.widget.visibility == 2 and not ui.has_active(),
            "PNG assets and hidden widget pool can be warmed before the first monster bar appears")
        ui.render(controller,{{rect=rect,model=Core.model(sample(30,"normal"))}})
        local node = ui.nodes[1]
        check(imports == 4 and #ui.nodes == config.MaxBars,"four PNG imports are shared by the fixed bar pool")
        check(#constructed == 3+config.MaxBars*7,"fixed pool includes an empty-region clip without gradient strip widgets")
        check(ui.widget.opacity == 1 and node.frame.opacity == 0.75,
            "opacity applies once to the actual frame image without a second parent multiplier")
        for _,fill in pairs(node.fills) do
            check(fill.image.opacity == 0.75,"yellow, red and blue images each explicitly have 75 percent opacity")
        end
        check(node.fills.normal.slot.Size.X == rect.width and node.clip_slot.Size.X == rect.width*0.4,
            "partial fill clips a full-width image instead of squeezing it")
        check(node.clip.clipping == 1 and node.frame_slot.Size.X == rect.width,
            "clipping affects only the fill, leaving the frame intact")
        check(node.frame_clip.clipping == 1 and node.frame_clip_slot.Position.X == node.clip_slot.Size.X
            and node.frame_clip_slot.Size.X+node.clip_slot.Size.X == rect.width
            and node.frame_slot.Position.X == -node.clip_slot.Size.X,
            "empty background and colored fill partition the bar without stacked alpha")
        ui.render(controller,{{rect=rect,model=Core.model(sample(60,"normal"))}},0.1)
        ui.animate(0.15)
        check(math.abs(node.clip_slot.Size.X-rect.width*0.6) < 0.0001,"animation advances the clip between native samples")
        ui.animate(0.21)
        check(node.clip_slot.Size.X == rect.width*0.8,"animation reaches the last real sample without extrapolation")
        check(not ui.has_active() and node.frame_slot.writes.SetSize == 1,
            "settled animation idles and unchanged geometry does not repeatedly invalidate frame layout")
        ui.render(controller,{{rect=rect,model=Core.model(sample(75,"stunned"))}},0.3)
        local red,blue,gold = node.fills.stunned,node.fills.cooldown,node.fills.normal
        check(node.clip_slot.Size.X == rect.width and red.image.visibility == 3 and gold.image.visibility == 2
            and blue.image.visibility == 2 and red.image.texture.path:match("/stunBar_inside_red%.png$"),
            "stun immediately uses the full original-alpha red texture")
        check(node.frame_clip.visibility == 2 and node.frame_clip_slot.Size.X == 0,
            "full colored bar has no opaque background underneath")
        check(red.image.color == config.StunnedColor and red.image.color.R == 1 and red.image.color.G == 1 and red.image.color.B == 1,
            "precolored red texture is not darkened by another saturated tint")
        for _,fill in pairs(node.fills) do
            check(fill.slot.Size.X == rect.width and fill.slot.Size.Y == rect.height and fill.image.texture ~= nil,
                "all PNG variants share the frame transform and keep native brush references even while hidden")
        end
        ui.render(controller,{{rect=rect,model=Core.model(sample(30,"cooldown"))}},0.4)
        check(blue.image.visibility == 3 and red.image.visibility == 2
            and blue.image.texture.path:match("/stunBar_inside_blue%.png$") and imports == 4,
            "cooldown switches to the original-alpha blue PNG without importing or rebuilding")
        check(node.frame_clip_slot.Position.X == node.clip_slot.Size.X
            and node.frame_clip_slot.Size.X+node.clip_slot.Size.X == rect.width,
            "background clipping follows cooldown interpolation as well")
        ui.render(controller,{{rect=rect,model=Core.model(sample(0,"normal"))}},0.5)
        check(node.clip.visibility == 2 and node.panel.visibility == 3,"empty meter keeps its background and hides the fill")
        check(node.frame_clip.visibility == 3 and node.frame_clip_slot.Size.X == rect.width
            and node.frame_slot.Position.X == 0,"zero fill restores the whole translucent background")
        ui.render(controller,{})
        check(ui.widget.visibility == 2 and not ui.has_active(),"no eligible target hides the entire overlay and idles animation")
        ui.render(controller,{{key="another-actor",rect=rect,model=Core.model(sample(15,"normal"))}},0.6)
        check(node.clip_slot.Size.X == rect.width*0.2,"redisplaying a new actor never interpolates from the previous target")
        local old_widget = ui.widget
        ui.clear()
        check(old_widget.removed and #ui.nodes == 0 and ui.widget == nil,"context cleanup removes the overlay and references")
    end)
    StaticConstructObject,FName = saved_construct,saved_fname
    if not ui_ok then error(ui_error) end

    local now,available,visible,layouts = 0,true,true,true
    local controller,pawn,actor,actor2,bar,widget2 = {id=1,world=3},{id=2},{id=4},{id=5},{},{}
    controller.Pawn = pawn
    local target,widgets,result = actor,{widget2},sample(30,"normal")
    local renders,clears,builds,last_entries,reads,animations,geometry_reads,scans,warms = 0,0,0,nil,0,0,0,0,0
    local fake = {
        live=function(object) return object ~= nil end,same=function(a,b) return a == b end,
        local_player=function() if available then return controller,pawn,3 end end,
        world=function(object) return object.world end,time=function() return now end,
        member=function(object,key)
            if object == widget2 then
                if key == "HealthBar" then return bar elseif key == "bShowing" then return visible
                elseif key == "TargetActor" then return target end
            end
            return object[key]
        end,
        address=function(object) if object then return object.id or 6 end end,
        all=function() scans=scans+1; return widgets end,
        hud_widget=function(object) return available and not object.foreign end,
        target_from_widget=function() if visible then return target end end,visible=function() return visible end,
        viewport=function() return {X=1920,Y=1080} end,bar_rect=function() geometry_reads=geometry_reads+1; if layouts then return rect end end,
        once=function() end,name=function() return "Fake" end,reset=function() end,
    }
    local ui = {clear=function() clears=clears+1 end,hide=function() last_entries={} end,
        prepare=function() warms=warms+1 end,
        animate=function() animations=animations+1 end,
        has_active=function() return last_entries and #last_entries > 0 end,
        render=function(_,entries) renders=renders+1; last_entries=entries end}
    local reader = {build=function() builds=builds+1; return {} end,
        read=function() reads=reads+1; return result end}
    local runtime = require("StunDisplayRuntime").new(fake,config,require("StunProbeConfig"),ui,reader)
    runtime.update()
    check(#last_entries == 1 and builds == 1,"UI starts automatically without F6")
    now=0.1; runtime.update()
    check(builds == 1 and reads == 2,"sampling reuses provider discovery")
    for i=1,6 do now=0.1+i*0.016; runtime.fast() end
    check(animations == 6 and reads == 2 and builds == 1 and geometry_reads == 2 and renders == 2 and scans == 1,
        "high frequency animation does not poll monsters, scan objects, remeasure geometry or rebuild widgets")
    target,now=actor2,0.2; runtime.fast()
    check(#last_entries == 1 and builds == 2 and scans == 1 and last_entries[1].key:find(":5",1,true),
        "fast HUD checks bind a new actor immediately without waiting for global discovery or showing the old actor")
    now=1.1; runtime.update()
    check(builds == 2 and #last_entries == 1,"next discovery binds the newly displayed actor")
    visible,now=false,1.2; runtime.update()
    check(#last_entries == 0,"native bar visibility also controls the stun overlay")
    local before_idle = animations
    runtime.animate()
    check(animations == before_idle,"hidden bars have no animation clock/render work")
    visible,layouts,now=true,false,1.3; runtime.update()
    check(#last_entries == 0,"missing native geometry never uses a guessed screen location")
    layouts,result,now=true,sample(30,"cooldown"),1.4; runtime.update()
    check(last_entries[1].model.phase == "cooldown","actual state selects the cooldown meter")
    result,now=sample(30,"stunned","conflict"),1.5; runtime.update()
    check(#last_entries == 0,"conflicting native state hides stale graphics")
    result,now=sample(30,"normal"),601; runtime.update()
    check(#last_entries == 1,"UI has no diagnostic capture timeout")
    available,controller.Pawn,now=false,{},601.1; runtime.update()
    check(clears == 1,"pawn changes clear old widgets and provider bindings")
    available,controller.Pawn,visible,layouts,now=true,pawn,false,true,700
    local hidden_runtime = require("StunDisplayRuntime").new(fake,config,require("StunProbeConfig"),ui,reader)
    local before_builds,before_warms = builds,warms
    hidden_runtime.update()
    local before_scans = scans
    check(#last_entries == 0 and builds == before_builds and warms == before_warms+1,
        "hidden native HUD widgets are cached and resources preloaded without reading a monster")
    visible,now=true,700.016; hidden_runtime.fast()
    check(#last_entries == 1 and scans == before_scans and builds == before_builds+1,
        "a cached hidden bar is displayed on the fast check without waiting one second")
    visible,now=false,700.032; hidden_runtime.fast()
    check(#last_entries == 0,"a cached HUD hide is reflected on the fast check")
    visible,now=true,700.048; hidden_runtime.fast()
    check(#last_entries == 1 and builds == before_builds+1 and warms == before_warms+1,
        "reappearing on the same actor reuses providers and the warmed overlay")
    local created = {id=7,bShowing=true,TargetActor=actor2,HealthBar=bar}
    hidden_runtime.update({created})
    check(#last_entries == 2 and scans == before_scans,"new-widget events can add a HUD widget between global scans")
    hidden_runtime.update({{id=8,foreign=true}})
    check(#last_entries == 2,"event notifications cannot admit another player's HUD widget")
    -- Cached geometry may be zero in the appearance frame. Retry only a bounded
    -- number of fast frames, then return to the normal sample interval.
    layouts,now=false,701.1; hidden_runtime.update()
    visible,now=false,701.116; hidden_runtime.fast()
    visible,now=true,701.132; hidden_runtime.fast()
    local retry_reads = reads
    for i=1,8 do now=701.132+i*0.016; hidden_runtime.fast() end
    check(reads-retry_reads <= config.AppearanceRetryFrames,"unavailable layout cannot create an unbounded high-frequency sampling loop")
    require("StunDisplayEventTests").run(check)
    return count
end
return M
