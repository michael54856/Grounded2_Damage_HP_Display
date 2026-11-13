-- Pure/fake tests only. Native venom values were validated in the saved log.
local Core,M=require("PoisonDisplayCore"),{}
function M.run()
    local count=0
    local function check(value,message)
        assert(value,"Poison display self-test: " .. message); count=count+1
    end
    local config={Enabled=true,Row=2,ReferenceMaximum=100,UpdateIntervalMs=16,AnimationIntervalMs=16,
        FillTweenSeconds=0,DiscoveryInterval=1,ErrorRetrySeconds=2,MaxBars=2,MaxCachedWidgets=8,AppearanceRetryFrames=3,
        BarWidth=120,HeightScale=1,IconHeightScale=2,IconAspectRatio=1,IconGap=-4,FillInsetHeightScale=0,
        ColumnGap=12,ColumnRowGap=4,MaxEffectRows=5,ChillRow=1,OffsetX=0,OffsetY=0,HideWhenInactive=true,
        FullEffectEnabled=true,FullFlashSeconds=0.18,FullPulseSeconds=1,
        PoisonColor={R=0.66,G=0.30,B=1.0,A=1},
        ChillingColor={R=0.4,G=0.78,B=1,A=1},FrozenColor={R=0.4,G=0.78,B=1,A=1}}
    local function sample(value)
        return {{id=11,path="Venom Fixture",values={CurrentVenomLevel=value,bIsActive=false,bAutoActivate=false}}}
    end
    local model=Core.model(sample(35),config)
    check(model.fraction == 0.35 and model.current == 35 and model.maximum_source == "configured_observed_reference",
        "direct current uses a clearly labeled configurable reference, not a fabricated native maximum")
    check(model.phase == "poison","poison display does not inherit frozen state semantics")
    check(Core.model(sample(100),config).fraction == 1,"observed full level renders full")
    check(Core.model(sample(99.417),config).fraction == 99.417/100,"decay follows actual sampled levels")
    local empty,reason=Core.model(sample(0),config)
    check(not empty and Core.inactive(reason),"zero current hides the bar without guessing a timer")
    check(not Core.model(sample(-1),config) and not Core.model(sample(101),config),"negative and above-reference values are not silently misrepresented")
    check(not Core.model({},config) and not Core.model(sample(0/0),config),"missing or invalid current hides instead of becoming zero")
    local ambiguous=sample(10); ambiguous[2]=sample(20)[1]
    check(not Core.model(ambiguous,config),"distinct current providers are never summed or mixed")
    local altered={ReferenceMaximum=80,HideWhenInactive=true}
    check(Core.model(sample(40),altered).fraction == 0.5 and not Core.model(sample(40),{ReferenceMaximum=0}),
        "reference maximum is configurable and must be valid")
    check(not Core.model({{id=12,values={CurrentPoisonGasLevel=100}}},config),
        "poison gas is a separate channel and cannot substitute for venom")
    local mixed=sample(35); mixed[1].values.CurrentPoisonGasLevel=100
    check(Core.model(mixed,config).current == 35,"gas current is never added to venom")
    check(not Core.model(sample(math.huge),config),"non-finite current is rejected")
    check(not Core.model(sample(10),{ReferenceMaximum=0/0}),"non-finite reference is rejected")
    local health,viewport={X=300,Y=50,width=400,height=20},{X=1920,Y=1080}
    local rect=Core.rect(health,viewport,config)
    local ice_rect=Core.rect(health,viewport,config,1)
    check(rect.row == 2 and rect.X == ice_rect.X and rect.Y == ice_rect.Y+ice_rect.height+config.ColumnRowGap,
        "explicit row placement shares the dynamic column geometry")
    check(rect.bar.width == 120 and rect.bar.height == health.height
        and rect.bar.X == rect.icon.width+config.IconGap,"fixed bar width, native height and close icon alignment persist")

    local function property(key,kind)
        return {GetFName=function() return {ToString=function() return key end} end,
            GetFullName=function() return kind .. " /Script/Maine.VenomComponent:" .. key end}
    end
    local function class(name,kind)
        return {name=name,GetSuperStruct=function() return nil end,
            ForEachProperty=function(_,callback)
                callback(property("VenomDecayPerSecond","FloatProperty"))
                callback(property("CurrentVenomLevel",kind))
            end}
    end
    local actor={id=1,name="Actor",kind="actor"}
    local component={id=11,name="Venom",kind="venom",owner=actor,CurrentVenomLevel=35,
        class=class("VenomFloat","FloatProperty"),GetClass=function(self) return self.class end}
    local foreign={id=12,name="Foreign",kind="venom",CurrentVenomLevel=80,
        class=component.class,GetClass=component.GetClass}
    actor.VenomComponent=foreign
    local resets,native_reads=0,0
    local base={valid=function(value) return value ~= nil end,live=function(value) return value ~= nil and not value.dead end,
        is_a=function(value,path)
            return value.kind == "actor" and path == "/Script/Maine.SurvivalCreature"
                or value.kind == "venom" and path == "/Script/Maine.VenomComponent"
        end,
        name=function(value) return value.name end,address=function(value) return value.id end,
        belongs=function(value,owner) return value == owner or value.owner == owner end,
        components=function() return {component,foreign} end,
        member=function(value,key)
            if value.kind == "venom" then
                check(value == component and key == "CurrentVenomLevel","display reads only owned current, not extra probe fields or another creature")
                native_reads=native_reads+1
            end
            return value[key]
        end,
        log=function() end,reset=function() resets=resets+1 end}
    local probe_config={MaxClassDepth=8,MaxFieldsPerClass=256,MaxComponentsToInspect=64,MaxProvidersPerTarget=16}
    local adapter=require("PoisonDisplayUE").new(base,probe_config)
    local schema=adapter.schema(component)
    check(#schema.fields == 1 and schema.fields[1].key == "CurrentVenomLevel" and #schema.getters == 0,
        "display verifies the reflected float and adds no new native getter")
    local reader=require("ElementAccumulationReader")
    local providers=reader.build(actor,adapter,probe_config)
    local values=reader.read(actor,providers,adapter)
    check(#providers == 1 and Core.model(values,config).current == 35 and native_reads == 1,
        "foreign references are rejected and only the owned current field is sampled")
    local bad={kind="venom",name="Bad",class=class("VenomWrongType","IntProperty"),GetClass=component.GetClass}
    check(#adapter.schema(bad).fields == 0,"unsupported reflected current type is rejected")
    adapter.reset()
    check(resets == 0,"poison reset preserves the shared cold adapter's caches")
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
        local ui=require("ChillDisplayUI").new(fake_ui,config,{Tag="POISON",WidgetPrefix="G2Poison",
            IconFile="poison_icon.png",Phases={"poison"},Colors={poison=config.PoisonColor}})
        local controller={}
        local function entry(value,key,position)
            return {rect=position or rect,model=Core.model(sample(value),config),key=key or "poison-a"}
        end
        ui.prepare(controller)
        check(imports == 3 and ui.widget.visibility == 2,"poison assets are preloaded once before first use")
        ui.render(controller,{entry(35)},0)
        local node=ui.nodes[1]
        check(#constructed == 3+config.MaxBars*23,"one poison phase includes a reusable equal-distance outline group")
        check(node.outline.texture == node.fills.poison.image.texture
            and node.outline_slot.ZOrder < node.frame_slot.ZOrder and node.frame_slot.ZOrder < node.clip_slot.ZOrder,
            "poison outline shares the original inside_bar texture and sits behind the background and fill")
        check(node.icon.texture.path:match("/poison_icon%.png$") and node.fills.poison.image.color == config.PoisonColor,
            "poison icon retains its art and white fill receives purple tint")
        check(node.clip_slot.Size.X == rect.fill.width*0.35 and node.fills.poison.slot.Size.X == rect.fill.width,
            "partial poison progress clips the original full-width image")
        check(node.slot.Position.Y == rect.Y and node.frame_slot.Position.X == node.icon_slot.Size.X-4,
            "second-row layout and reduced icon gap reach the native slots")
        ui.render(controller,{entry(100)},1)
        check(ui.has_active() and node.full_since == 1,"full poison level starts the shared flash/pulse")
        check(node.outline.visibility == 3 and node.outline_slot.Size.X == rect.bar.width+4
            and node.outline.color.R == 1 and node.outline.color.G == 0.72 and node.outline.color.B == 0.12,
            "full poison level uses the same gold rim as ice")
        local first_color=node.fills.poison.image.color.R
        ui.animate(1.5)
        check(node.outline.color.A == 1 and node.outline_slot.Size.X == rect.bar.width+4 and node.icon.color.A == 1,
            "poison inside pulse leaves gold outline and icon steady")
        check(node.fills.poison.image.color.R < first_color and node.clip_slot.Size.X == rect.fill.width,
            "full pulse animates appearance without decreasing the recorded value")
        ui.render(controller,{entry(100)},1.6)
        check(node.full_since == 1,"repeated full samples do not restart animation")
        ui.render(controller,{entry(100,"poison-a",ice_rect)},1.7)
        check(node.full_since == 1 and node.slot.Position.Y == ice_rect.Y,
            "moving poison up into the first available slot preserves its full animation")
        ui.animate(6)
        check(node.clip_slot.Size.X == rect.fill.width,"full poison level does not invent a reset countdown")
        ui.render(controller,{entry(99.417)},6.2)
        check(node.outline.visibility == 2 and node.frame.color.A == 1,
            "poison decay hides the full-value rim immediately")
        check(node.full_since == nil and node.fills.poison.image.color == config.PoisonColor
            and node.clip_slot.Size.X == rect.fill.width*(99.417/100),"decay stops full animation and follows current immediately")
        ui.render(controller,{})
        check(not ui.visible and not ui.has_active(),"zero/death/hidden target removes poison overlay")
        ui.render(controller,{entry(25,"new-target")},7)
        check(node.clip_slot.Size.X == rect.fill.width*0.25 and node.icon.color.A == 1,
            "new target has no old full effect or stale fill")
        local ice=require("ChillDisplayUI").new(fake_ui,config)
        ice.render(controller,{{rect=ice_rect,key="ice",model={phase="chilling",fraction=0.5,current=40,maximum=80}}},7)
        check(ice.nodes[1].fills.chilling ~= nil and ice.nodes[1].fills.frozen ~= nil
            and ice.nodes[1].fills.poison == nil and node.fills.chilling == nil,
            "shared renderer keeps the two effect instances' phases isolated")
        check(ice.nodes[1].icon.texture.path:match("/ice_icon%.png$")
            and ui.widget.name:match("^G2PoisonHUD_") and ice.widget.name:match("^G2ChillHUD_"),
            "ice and poison use separate icons and native object identities")
        ice.clear()
        check(ui.visible and ui.nodes[1] == node,"clearing ice widgets does not clear poison widgets")
        check(node.outline.visibility == 2 and node.clip_slot.Size.X == rect.fill.width*0.25,
            "a reused partial target has no stale full-rim or fake secondary fill")
        ui.clear()
    end)
    StaticConstructObject,FName=saved_construct,saved_fname
    if not ui_ok then error(ui_error) end
    return count
end
return M
