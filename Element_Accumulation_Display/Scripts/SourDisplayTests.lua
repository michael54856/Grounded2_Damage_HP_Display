-- Pure/fake tests only. Native corrosion values were validated in the saved log.
local Core,M=require("SourDisplayCore"),{}
function M.run()
    local count=0
    local function check(value,message)
        assert(value,"Sour display self-test: " .. message); count=count+1
    end
    local config={Enabled=true,Row=2,ReferenceMaximum=100,UpdateIntervalMs=16,AnimationIntervalMs=16,
        FillTweenSeconds=0,DiscoveryInterval=1,ErrorRetrySeconds=2,MaxBars=2,MaxCachedWidgets=8,AppearanceRetryFrames=3,
        BarWidth=120,HeightScale=1,IconHeightScale=2,IconAspectRatio=1,IconGap=-4,FillInsetHeightScale=0,
        ColumnGap=12,ColumnRowGap=4,MaxEffectRows=5,ChillRow=1,OffsetX=0,OffsetY=0,HideWhenInactive=true,
        FullEffectEnabled=true,FullFlashSeconds=0.18,FullPulseSeconds=1,
        SourColor={R=0.42,G=0.95,B=0.16,A=1},
        ChillingColor={R=0.4,G=0.78,B=1,A=1},FrozenColor={R=0.4,G=0.78,B=1,A=1}}
    local function sample(value)
        return {{id=11,path="Corrosion Fixture",values={CurrentCorrosionLevel=value,bIsActive=false,bAutoActivate=false}}}
    end
    local model=Core.model(sample(35),config)
    check(model.fraction == 0.35 and model.current == 35 and model.maximum_source == "configured_observed_reference",
        "direct current uses a clearly labeled configurable reference, not a fabricated native maximum")
    check(model.phase == "sour","sour display does not inherit frozen state semantics")
    check(Core.model(sample(100),config).fraction == 1,"observed full level renders full")
    check(Core.model(sample(99.417),config).fraction == 99.417/100,"decay follows actual sampled levels")
    local empty,reason=Core.model(sample(0),config)
    check(not empty and Core.inactive(reason),"zero/death clear hides the bar without guessing a timer")
    check(not Core.model(sample(-1),config) and not Core.model(sample(101),config),"negative and above-reference values are not silently misrepresented")
    check(not Core.model({},config) and not Core.model(sample(0/0),config),"missing or invalid current hides instead of becoming zero")
    local ambiguous=sample(10); ambiguous[2]=sample(20)[1]
    check(not Core.model(ambiguous,config),"distinct current providers are never summed or mixed")
    local altered={ReferenceMaximum=80,HideWhenInactive=true}
    check(Core.model(sample(40),altered).fraction == 0.5 and not Core.model(sample(40),{ReferenceMaximum=0}),
        "reference maximum is configurable and must be valid")
    local health,viewport={X=300,Y=50,width=400,height=20},{X=1920,Y=1080}
    local rect=Core.rect(health,viewport,config)
    local ice_rect=Core.rect(health,viewport,config,1)
    check(rect.row == 2 and rect.X == ice_rect.X and rect.Y == ice_rect.Y+ice_rect.height+config.ColumnRowGap,
        "green sour row sits below the ice row in the dedicated column")
    check(rect.bar.width == 120 and rect.bar.height == health.height
        and rect.bar.X == rect.icon.width+config.IconGap,"fixed bar width, native height and close icon alignment persist")

    local function property(key,kind)
        return {GetFName=function() return {ToString=function() return key end} end,
            GetFullName=function() return kind .. " /Script/Maine.CorrosionComponent:" .. key end}
    end
    local function class(name,kind)
        return {name=name,GetSuperStruct=function() return nil end,
            ForEachProperty=function(_,callback)
                callback(property("CorrosionDecayPerSecond","FloatProperty"))
                callback(property("CurrentCorrosionLevel",kind))
            end}
    end
    local actor={id=1,name="Actor",kind="actor"}
    local component={id=11,name="Corrosion",kind="corrosion",owner=actor,CurrentCorrosionLevel=35,
        class=class("CorrosionFloat","FloatProperty"),GetClass=function(self) return self.class end}
    local foreign={id=12,name="Foreign",kind="corrosion",CurrentCorrosionLevel=80,
        class=component.class,GetClass=component.GetClass}
    actor.CorrosionComponent=foreign
    local resets,native_reads=0,0
    local base={valid=function(value) return value ~= nil end,live=function(value) return value ~= nil and not value.dead end,
        is_a=function(value,path)
            return value.kind == "actor" and path == "/Script/Maine.SurvivalCreature"
                or value.kind == "corrosion" and path == "/Script/Maine.CorrosionComponent"
        end,
        name=function(value) return value.name end,address=function(value) return value.id end,
        belongs=function(value,owner) return value == owner or value.owner == owner end,
        components=function() return {component,foreign} end,
        member=function(value,key)
            if value.kind == "corrosion" then
                check(value == component and key == "CurrentCorrosionLevel","display reads only owned current, not extra probe fields or another creature")
                native_reads=native_reads+1
            end
            return value[key]
        end,
        log=function() end,reset=function() resets=resets+1 end}
    local probe_config={MaxClassDepth=8,MaxFieldsPerClass=256,MaxComponentsToInspect=64,MaxProvidersPerTarget=16}
    local adapter=require("SourDisplayUE").new(base,probe_config)
    local schema=adapter.schema(component)
    check(#schema.fields == 1 and schema.fields[1].key == "CurrentCorrosionLevel" and #schema.getters == 0,
        "display verifies the reflected float and adds no new native getter")
    local reader=require("ElementAccumulationReader")
    local providers=reader.build(actor,adapter,probe_config)
    local values=reader.read(actor,providers,adapter)
    check(#providers == 1 and Core.model(values,config).current == 35 and native_reads == 1,
        "foreign references are rejected and only the owned current field is sampled")
    local bad={kind="corrosion",name="Bad",class=class("CorrosionWrongType","IntProperty"),GetClass=component.GetClass}
    check(#adapter.schema(bad).fields == 0,"unsupported reflected current type is rejected")
    adapter.reset()
    check(resets == 0,"sour reset preserves the shared cold adapter's caches")
    component.dead=true
    check(#reader.read(actor,providers,adapter) == 0,"destroyed providers cannot retain stale values")
    component.dead=false

    -- UI construction checks continue below using fake UObjects.
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
        local ui=require("ChillDisplayUI").new(fake_ui,config,{Tag="SOUR",WidgetPrefix="G2Sour",
            IconFile="sour_icon.png",Phases={"sour"},Colors={sour=config.SourColor}})
        local controller={}
        local function entry(value,key,position)
            return {rect=position or rect,model=Core.model(sample(value),config),key=key or "sour-a"}
        end
        ui.prepare(controller)
        check(imports == 3 and ui.widget.visibility == 2,"sour assets are preloaded once before first use")
        ui.render(controller,{entry(35)},0)
        local node=ui.nodes[1]
        check(#constructed == 3+config.MaxBars*23,"one sour phase includes a reusable equal-distance outline group")
        check(node.outline.texture == node.fills.sour.image.texture
            and node.outline_slot.ZOrder < node.frame_slot.ZOrder and node.frame_slot.ZOrder < node.clip_slot.ZOrder,
            "sour outline shares the original inside_bar texture and sits behind the background and fill")
        check(node.icon.texture.path:match("/sour_icon%.png$") and node.fills.sour.image.color == config.SourColor,
            "sour icon retains its art and white fill receives green tint")
        check(node.clip_slot.Size.X == rect.fill.width*0.35 and node.fills.sour.slot.Size.X == rect.fill.width,
            "partial sour progress clips the original full-width image")
        check(node.slot.Position.Y == rect.Y and node.frame_slot.Position.X == node.icon_slot.Size.X-4,
            "second-row layout and reduced icon gap reach the native slots")
        ui.render(controller,{entry(100)},1)
        check(ui.has_active() and node.full_since == 1,"full sour level starts the shared flash/pulse")
        check(node.outline.visibility == 3 and node.outline_slot.Size.X == rect.bar.width+4
            and node.outline.color.R == 1 and node.outline.color.G == 0.72 and node.outline.color.B == 0.12,
            "full sour level uses the same gold rim as ice")
        local first_color=node.fills.sour.image.color.R
        ui.animate(1.5)
        check(node.outline.color.A == 1 and node.outline_slot.Size.X == rect.bar.width+4 and node.icon.color.A == 1,
            "sour inside pulse leaves gold outline and icon steady")
        check(node.fills.sour.image.color.R < first_color and node.clip_slot.Size.X == rect.fill.width,
            "full pulse animates appearance without decreasing the recorded value")
        ui.render(controller,{entry(100)},1.6)
        check(node.full_since == 1,"repeated full samples do not restart animation")
        ui.render(controller,{entry(100,"sour-a",ice_rect)},1.7)
        check(node.full_since == 1 and node.slot.Position.Y == ice_rect.Y,
            "moving sour up into the first available slot preserves its full animation")
        ui.animate(6)
        check(node.clip_slot.Size.X == rect.fill.width,"full sour level does not invent a reset countdown")
        ui.render(controller,{entry(99.417)},6.2)
        check(node.outline.visibility == 2 and node.frame.color.A == 1,
            "sour decay hides the full-value rim immediately")
        check(node.full_since == nil and node.fills.sour.image.color == config.SourColor
            and node.clip_slot.Size.X == rect.fill.width*(99.417/100),"decay stops full animation and follows current immediately")
        ui.render(controller,{})
        check(not ui.visible and not ui.has_active(),"zero/death/hidden target removes sour overlay")
        ui.render(controller,{entry(25,"new-target")},7)
        check(node.clip_slot.Size.X == rect.fill.width*0.25 and node.icon.color.A == 1,
            "new target has no old full effect or stale fill")
        local ice=require("ChillDisplayUI").new(fake_ui,config)
        ice.render(controller,{{rect=ice_rect,key="ice",model={phase="chilling",fraction=0.5,current=40,maximum=80}}},7)
        check(ice.nodes[1].fills.chilling ~= nil and ice.nodes[1].fills.frozen ~= nil
            and ice.nodes[1].fills.sour == nil and node.fills.chilling == nil,
            "shared renderer keeps the two effect instances' phases isolated")
        check(ice.nodes[1].icon.texture.path:match("/ice_icon%.png$")
            and ui.widget.name:match("^G2SourHUD_") and ice.widget.name:match("^G2ChillHUD_"),
            "ice and sour use separate icons and native object identities")
        ice.clear()
        check(ui.visible and ui.nodes[1] == node,"clearing ice widgets does not clear sour widgets")
        check(node.outline.visibility == 2 and node.clip_slot.Size.X == rect.fill.width*0.25,
            "a reused partial target has no stale full-rim or fake secondary fill")
        ui.clear()
    end)
    StaticConstructObject,FName=saved_construct,saved_fname
    if not ui_ok then error(ui_error) end
    local now,available,visible=0,true,true
    local controller,pawn,target,other,widget,bar={id=1,world=9},{id=2},{id=3},{id=4},{id=5},{}
    controller.Pawn=pawn
    local active_actor,level=target,35
    local reads,builds,clears,resets,last_entries,last_actor=0,0,0,0,nil,nil
    local fake={
        live=function(value) return value ~= nil end,same=function(a,b) return a == b end,
        world=function(value) return value.world or 9 end,address=function(value) return value and (value.id or 6) end,
        local_player=function() if available then return controller,pawn,9 end end,
        member=function(value,key)
            if value == widget then
                if key == "bShowing" then return visible elseif key == "TargetActor" then return active_actor
                elseif key == "HealthBar" then return bar end
            end
            return value[key]
        end,
        all=function() return {widget} end,hud_widget=function() return true end,
        target_from_widget=function() if visible then return active_actor end end,
        visible=function() return visible end,time=function() return now end,
        viewport=function() return viewport end,bar_rect=function(_,_,_,settings)
            check(settings.Row == 2,"sour runtime passes the second-row configuration"); return rect
        end,
        reset=function() resets=resets+1 end,name=function() return "Fixture" end,once=function() end,
    }
    local ui={prepare=function() end,clear=function() clears=clears+1 end,hide=function() last_entries={} end,
        has_active=function() return false end,animate=function() end,render=function(_,entries) last_entries=entries end}
    local source_reader={build=function() builds=builds+1; return {} end,
        read=function(value) reads=reads+1; last_actor=value; return sample(level) end}
    local runtime=require("SourDisplayRuntime").new(fake,config,probe_config,ui,source_reader)
    runtime.update()
    check(#last_entries == 1 and last_entries[1].model.current == 35 and builds == 1,"sour UI starts automatically without F5 capture")
    now,level=0.016,60; runtime.update()
    check(reads == 2 and builds == 1 and last_entries[1].model.current == 60,"16ms updates reuse the verified provider")
    now,level=0.032,0; runtime.update()
    check(#last_entries == 0 and builds == 1,"zero hides without forcing provider discovery")
    now,level=2,0; runtime.update()
    check(#last_entries == 0 and builds == 1,"inactive current never causes repeated provider rebuilds")
    level,now=100,2.016; runtime.update()
    check(last_entries[1].model.fraction == 1,"new live accumulation redisplays full level")
    active_actor,level,now=other,20,2.032; runtime.fast()
    check(last_actor == other and builds == 2 and last_entries[1].model.current == 20,"native target changes immediately bind the new actor")
    visible,now=false,2.048; runtime.fast()
    check(#last_entries == 0,"native health hide also hides sour")
    visible,now=true,2.064; runtime.fast()
    check(#last_entries == 1 and builds == 2,"same target reappearance reuses its source")
    available,controller.Pawn=false,{}
    runtime.update()
    check(clears == 1 and resets == 1,"world/pawn context cleanup clears only the sour instance")
    return count
end
return M
