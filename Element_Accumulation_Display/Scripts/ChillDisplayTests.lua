-- Pure/fake checks only: no native hooks, imported images, or game changes.
local Core,M = require("ChillDisplayCore"),{}
function M.run()
    local count=0
    local function check(value,message)
        assert(value,"Chill UI self-test: " .. message)
        count=count+1
    end
    -- Fixed settings keep tests independent of the user's config.
    local config={Enabled=true,UpdateIntervalMs=100,AnimationIntervalMs=16,FillTweenSeconds=0.1,
        DiscoveryInterval=1,MaxCachedWidgets=8,AppearanceRetryFrames=3,ErrorRetrySeconds=2,
        MaxBars=2,BarWidth=120,HeightScale=1,IconHeightScale=2,IconAspectRatio=1,
        IconGap=-4,FillInsetHeightScale=0,ColumnGap=12,ColumnRowGap=4,MaxEffectRows=5,ChillRow=1,
        OffsetX=0,OffsetY=0,HideWhenInactive=true,
        FullEffectEnabled=true,FullFlashSeconds=0.18,FullPulseSeconds=1,
        FullFrameThickness=2,
        ChillingColor={R=0.4,G=0.78,B=1,A=1},FrozenColor={R=0.4,G=0.78,B=1,A=1}}
    local function cold(raw,state,frozen,threshold)
        return {{id=1,path="fixture",values={["GetCurrentBodyTemperature()"]=raw,
            ["GetCurrentBodyTemperatureState()"]=state,["IsFrozen()"]=frozen,MaxChill=threshold or -80},
            enum_info={names={[7]="EBodyTemperatureState::Normal",[9]="EBodyTemperatureState::Chilling",
                [11]="EBodyTemperatureState::MaxChill",[13]="EBodyTemperatureState::Sizzling"}}}}
    end
    local model=Core.model(cold(-40,9,false),config)
    check(model.current == 40 and model.maximum == 80 and model.fraction == 0.5,"native threshold, no assumed max=100")
    check(Core.model(cold(-80,11,true),config).phase == "frozen","enum names rather than hardcoded ordinals")
    check(Core.model(cold(-40,9,false),config).fraction == 0.5,"thaw can retain accumulation")
    local value,reason=Core.model(cold(0,7,false),config)
    check(not value and Core.inactive(reason),"normal/inactive hides without discovery retries")
    value,reason=Core.model(cold(20,13,false),config)
    check(not value and Core.inactive(reason),"heat is not displayed as cold")
    check(not Core.model(cold(-40,11,true),config) and not Core.model(cold(-40,9,true),config),"contradictory frozen state hides")
    check(not Core.model(cold(-40,9,false,0),config),"invalid threshold hides")
    local missing=cold(-40,9,false); missing[1].values["GetCurrentBodyTemperature()"]=nil
    missing[1].values.CurrentBodyTemperature=-40
    check(not Core.model(missing,config),"unverified field-only readings are not displayed")
    missing=cold(-40,9,false); missing[1].enum_info=nil
    check(not Core.model(missing,config),"missing enum metadata does not guess a phase")
    local ambiguous=cold(-40,9,false); ambiguous[2]=ambiguous[1]
    check(not Core.model(ambiguous,config),"ambiguous providers do not combine unrelated data")
    local health,viewport={X=300,Y=50,width=400,height=20},{X=1920,Y=1080}
    local rect=Core.rect(health,viewport,config)
    check(rect.X == 132 and rect.Y == 30 and rect.width == 156 and rect.height == 40,
        "dedicated column is placed to the left of native health")
    check(rect.X+rect.width+config.ColumnGap == health.X and rect.Y+rect.bar.Y == health.Y,
        "first progress bar aligns vertically with native health and leaves a clear horizontal gap")
    check(rect.bar.width == 120 and rect.bar.height == health.height,
        "bar uses fixed width and exactly native health bar height")
    local short_health=Core.rect({X=300,Y=50,width=200,height=20},viewport,config)
    local long_health=Core.rect({X=300,Y=50,width=800,height=20},viewport,config)
    check(short_health.bar.width == 120 and long_health.bar.width == 120
        and short_health.fill.width == long_health.fill.width and short_health.X == long_health.X,
        "different monster health bar lengths never resize or shift a left-anchored column")
    check(rect.icon.X+rect.icon.width+config.IconGap == rect.bar.X and rect.bar.Y > rect.icon.Y
        and rect.icon.Y+rect.icon.height == rect.bar.Y+rect.bar.height,
        "bar moves four units toward the icon and their bottoms still align")
    check(rect.fill.X == rect.bar.X and rect.fill.Y == rect.bar.Y
        and rect.fill.width == rect.bar.width and rect.fill.height == rect.bar.height,
        "matching PNG frame and fill canvases use the identical transform")
    local lower=Core.rect(health,viewport,config,2)
    check(lower.X == rect.X and lower.Y == 74,"second effect row stacks downward in the same left column")
    local previous=rect
    for row=2,5 do
        local next_row=Core.rect(health,viewport,config,row)
        check(next_row.X == rect.X and next_row.Y == previous.Y+previous.height+config.ColumnRowGap,
            "five future effect rows have stable spacing and no overlap")
        previous=next_row
    end
    check(not Core.rect(health,viewport,config,0) and not Core.rect(health,viewport,config,6),"row indices stay within the dedicated five-row column")
    check(not Core.rect({X=100,Y=50,width=400,height=20},viewport,config),"insufficient left space never clamps the column over native health")
    check(not Core.rect({X=300,Y=1070,width=400,height=20},viewport,config),"offscreen bars hide")
    local effect=Core.full_effect(0,config)
    local dimmer=Core.full_effect(0.5,config)
    check(effect.mix == 1 and dimmer.mix < effect.mix and dimmer.alpha < effect.alpha,"full value flashes then pulses gently")
    check(dimmer.alpha >= 0.78 and dimmer.alpha <= 1 and dimmer.mix >= 0 and dimmer.mix <= 1,"full animation preserves bounded color and opacity")
    local static_effect=Core.full_effect(0,{FullPulseEnabled=false})
    check(static_effect.mix == 0 and static_effect.alpha == 1 and static_effect.pulse == 0,
        "static full mode disables both the initial flash and ongoing pulse")
    local border=Core.full_frame_rect(rect.bar,config)
    check(border.X == rect.bar.X-2 and border.Y == rect.bar.Y-2
        and border.width == rect.bar.width+4 and border.height == rect.bar.height+4,
        "outline expands by a uniform two UMG units on every side")
    local bounds,stamps=Core.full_frame_stamps(rect.bar,config)
    check(#stamps == 17 and bounds.width == border.width,"outline has a bounded center and sixteen equally spaced offsets")
    for index,stamp in ipairs(stamps) do
        check(stamp.width == rect.bar.width and stamp.height == rect.bar.height,"outline copies preserve original aspect and dimensions")
        if index > 1 then
            check(math.abs((stamp.X-2)^2+(stamp.Y-2)^2-4) < 0.000001,"each outline copy is offset by the same UMG distance")
        end
    end
    check(Core.asset_directory("@D:/Mods/Renamed/Scripts/ChillDisplayUI.lua") == "D:/Mods/Renamed/Assets","assets are relative to installed mod")
    local tween=Core.tween(Core.tween(nil,0.2,0,0.1,false),0.8,1,0.1,false)
    check(math.abs(Core.frame(tween,1.05)-0.5) < 0.00001,"smooth interpolation between native samples")
    check(Core.frame(tween,2) == 0.8,"never extrapolate accumulation")
    local saved_construct,saved_fname = StaticConstructObject,FName
    local ui_ok,ui_error = pcall(function()
        FName = function(value) return value end
        local constructed,imports = {},0
        StaticConstructObject = function(class,outer,name)
            local object = {class=class,outer=outer,name=name}
            function object:SetVisibility(value) self.visibility=value end
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
        local ui = require("ChillDisplayUI").new(fake_ui,config)
        local controller={}
        local function entry(fraction,phase,key,position)
            return {rect=position or rect,model={fraction=fraction,phase=phase or "chilling",current=40,maximum=80},key=key or "a"}
        end
        ui.prepare(controller)
        check(imports == 3 and ui.widget.visibility == 2,"preload frame, white fill and ice icon before combat")
        ui.render(controller,{entry(0.4)},0)
        local node=ui.nodes[1]
        check(#constructed == 3+config.MaxBars*24,"fixed widget pool includes a reusable unstretched outline group per bar")
        check(node.outline.texture == node.fills.chilling.image.texture and imports == 3,
            "outline reuses inside_bar texture without extra imports")
        check(node.outline_slot.ZOrder < node.frame_slot.ZOrder and node.frame_slot.ZOrder < node.clip_slot.ZOrder
            and node.clip_slot.ZOrder < node.icon_slot.ZOrder,
            "colored silhouette is behind opaque background, progress and icon in that order")
        check(node.outline.visibility == 2,"partial accumulation has no full-value rim")
        check(node.fills.chilling.slot.Size.X == rect.fill.width and node.clip_slot.Size.X == rect.fill.width*0.4,
            "clip full image without squeezing its rounded shape")
        check(node.icon_slot.Position.X+node.icon_slot.Size.X+config.IconGap == node.frame_slot.Position.X
            and node.icon_slot.Position.Y+node.icon_slot.Size.Y == node.frame_slot.Position.Y+node.frame_slot.Size.Y,
            "actual icon and frame slots overlap the transparent margins and bottom-align")
        check(node.icon.texture.path:match("/ice_icon%.png$")
            and node.frame.texture.path:match("/backgroundframe%.png$")
            and node.fills.chilling.image.texture.path:match("/inside_bar%.png$"),
            "overlay imports the three supplied statusBar assets")
        check(node.fills.chilling.image.color == config.ChillingColor
            and node.fills.chilling.image.color.R == 0.4 and node.fills.chilling.image.color.B == 1,
            "white fill receives the light blue ice tint without recoloring the icon")
        ui.render(controller,{entry(0.8)},0.1); ui.animate(0.15)
        check(math.abs(node.clip_slot.Size.X-rect.fill.width*0.6) < 0.0001,"animate between 100ms readings")
        ui.animate(0.21)
        check(node.clip_slot.Size.X == rect.fill.width*0.8 and not ui.has_active(),"animation settles at sampled value")
        ui.render(controller,{entry(0.8,"chilling","a",lower)},0.22)
        check(node.slot.Position.Y == 74 and imports == 3,"column row changes reuse the existing overlay without recreating assets")
        ui.render(controller,{entry(1,"frozen")},0.3)
        check(node.clip_slot.Size.X == rect.fill.width and node.fills.frozen.image.visibility == 3
            and node.fills.chilling.image.visibility == 2,"freezing immediately displays full meter")
        check(ui.has_active() and not node.moving and node.full_since == 0.3,
            "full meter continues animating after its numeric fill stops moving")
        check(node.outline.visibility == 3 and node.outline_slot.Position.X == rect.bar.X-2
            and node.outline_slot.Position.Y == rect.bar.Y-2 and node.outline_slot.Size.X == rect.bar.width+4,
            "full value reveals the thick colored inside_bar silhouette behind the normal frame")
        check(node.outline_stamps[2].slot.Size.X == rect.bar.width
            and node.outline_stamps[2].slot.Size.Y == rect.bar.height
            and node.outline_stamps[2].slot.Position.X == 4,
            "native outline layers keep the original bar size and use equal-distance offsets")
        check(node.outline.color.R == 1 and node.outline.color.G == 0.72 and node.outline.color.B == 0.12
            and node.frame.color.R == 1 and node.frame_slot.Size.X == rect.bar.width,
            "full ice rim is gold while the original frame retains its dimensions and opaque center")
        local full_red=node.fills.frozen.image.color.R
        ui.render(controller,{entry(1,"frozen")},0.35)
        check(node.full_since == 0.3,"repeated full samples do not restart the flash")
        ui.render(controller,{entry(1,"frozen","a",lower)},0.36)
        check(node.full_since == 0.3 and node.slot.Position.Y == lower.Y,
            "row compaction moves a full meter without restarting its frame/fill animation")
        ui.animate(0.8)
        check(node.outline_slot.Size.X == rect.bar.width+4 and node.outline.color.A == 1,
            "outline thickness and opacity stay fixed while the inside pulses")
        check(node.fills.frozen.image.color.R < full_red and node.icon.color.A == 1
            and node.clip_slot.Size.X == rect.fill.width,"only inside tint/opacity pulse while the icon and true value stay steady")
        ui.render(controller,{entry(0.5,"chilling")},0.9)
        check(node.outline_group.visibility == 2,"leaving full hides the whole stamped outline")
        check(node.outline.visibility == 2 and node.frame.color.A == 1,
            "leaving full hides the thick rim and leaves the normal frame intact")
        check(node.clip_slot.Size.X == rect.fill.width*0.5 and node.full_since == nil
            and node.icon.color.A == 1 and node.fills.chilling.image.color == config.ChillingColor,
            "thaw restores actual residual accumulation, base tint and opaque icon immediately")
        ui.render(controller,{entry(1,"frozen","b")},1.0)
        check(node.full_since == 1.0,"new full target gets its own flash start time")
        ui.render(controller,{entry(0.2,"chilling","c")},1.1)
        check(node.clip_slot.Size.X == rect.fill.width*0.2,"new target never inherits old interpolation")
        ui.render(controller,{entry(1,"chilling","c")},1.2)
        config.FullFrameEffectEnabled=false
        ui.render(controller,{entry(1,"chilling","c")},1.21)
        check(node.outline.visibility == 2 and node.full_since == 1.2,
            "turning off only the rim preserves the existing full animation clock")
        config.FullFrameEffectEnabled=true
        ui.render(controller,{entry(1,"chilling","c")},1.22)
        check(node.outline.visibility == 3 and node.full_since == 1.2,
            "reenabling the rim does not restart the full effect")
        ui.render(controller,{entry(0.8,"chilling","c")},1.25)
        check(node.full_since == nil and node.icon.color.A == 1
            and node.fills.chilling.image.color == config.ChillingColor,
            "dropping below full restores normal appearance even without a state change")
        config.FullEffectEnabled=false
        ui.render(controller,{entry(1,"frozen","disabled")},1.3)
        check(node.full_since == nil and not ui.has_active(),"disabled full animation idles at an otherwise steady full meter")
        config.FullEffectEnabled=true
        config.FullPulseEnabled=false
        ui.render(controller,{entry(1,"frozen","static-gold")},1.4)
        check(node.outline.visibility == 3 and node.outline_slot.Size.X == rect.bar.width+4
            and node.outline.color.R == 1 and node.outline.color.G == 0.72 and node.outline.color.A == 1,
            "static full mode shows a fixed two-unit opaque gold rim")
        check(not ui.has_active(),"a settled static full meter does not request animation work")
        check(node.fills.frozen.image.color.R == config.FrozenColor.R and node.icon.color.A == 1,
            "a full meter keeps its attribute color and opaque icon without an initial white flash")
        ui.animate(3.9)
        check(node.outline_slot.Size.X == rect.bar.width+4 and node.outline.color.A == 1
            and node.fills.frozen.image.color.R == config.FrozenColor.R and node.icon.color.A == 1,
            "later frames do not change rim thickness, fill tint or opacity in static mode")
        ui.render(controller,{entry(0.6,"chilling","static-gold")},4)
        check(node.outline.visibility == 2,"static gold rim disappears as soon as the value drops below full")
        ui.render(controller,{})
        check(ui.widget.visibility == 2 and not ui.has_active(),"no active cold hides the overlay")
        local old=ui.widget; ui.clear()
        check(old.removed and #ui.nodes == 0,"context cleanup detaches overlay")
    end)
    StaticConstructObject,FName=saved_construct,saved_fname
    if not ui_ok then error(ui_error) end

    local now,available,visible,layouts = 0,true,true,true
    local controller,pawn,actor,actor2,bar,widget2 = {id=1,world=3},{id=2},{id=4},{id=5},{},{}
    controller.Pawn = pawn
    local target,widgets,result = actor,{widget2},nil
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
    local function sample(current,phase,conflict)
        return cold(-current,phase == "stunned" and 11 or current == 0 and 7 or 9,
            phase == "stunned" or conflict == "conflict",-75)
    end
    result=sample(30,"normal")
    local runtime = require("ChillDisplayRuntime").new(fake,config,require("ElementAccumulationConfig"),ui,reader)
    runtime.update()
    check(#last_entries == 1 and builds == 1,"UI starts automatically without F5")
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
    check(#last_entries == 0,"native bar visibility also controls the cold overlay")
    local before_idle = animations
    runtime.animate()
    check(animations == before_idle,"hidden bars have no animation clock/render work")
    visible,layouts,now=true,false,1.3; runtime.update()
    check(#last_entries == 0,"missing native geometry never uses a guessed screen location")
    layouts,result,now=true,sample(30,"chilling"),1.4; runtime.update()
    check(last_entries[1].model.phase == "chilling","actual temperature state selects the accumulating meter")
    result,now=sample(30,"stunned","conflict"),1.5; runtime.update()
    check(#last_entries == 0,"conflicting native state hides stale graphics")
    result,now=sample(30,"normal"),601; runtime.update()
    check(#last_entries == 1,"UI has no diagnostic capture timeout")
    local inactive_builds=builds
    result,now=sample(0,"normal"),601.01; runtime.update()
    now=605; runtime.update()
    check(#last_entries == 0 and builds == inactive_builds,"inactive temperature does not repeatedly rebuild providers")
    available,controller.Pawn,now=false,{},605.1; runtime.update()
    check(clears == 1,"pawn changes clear old widgets and provider bindings")
    available,controller.Pawn,visible,layouts,now=true,pawn,false,true,700
    result=sample(30,"normal")
    local hidden_runtime = require("ChillDisplayRuntime").new(fake,config,require("ElementAccumulationConfig"),ui,reader)
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
    return count
end
return M
