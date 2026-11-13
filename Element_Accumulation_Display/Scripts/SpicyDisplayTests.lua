-- Fake objects only. Never installs hooks, reads the game or alters actor state.
local Core,Layout,M=require("SpicyDisplayCore"),require("ChillDisplayCore"),{}
function M.run()
    local count=0
    local function check(value,message) assert(value,"Spicy display self-test: " .. message); count=count+1 end
    local config={HideWhenInactive=true,MaxBars=2,BarWidth=120,HeightScale=1,IconHeightScale=2,IconAspectRatio=1,
        IconGap=-4,FillInsetHeightScale=0,ColumnGap=12,ColumnRowGap=4,MaxEffectRows=5,OffsetX=0,OffsetY=0,
        FillTweenSeconds=0,FullEffectEnabled=true,FullPulseEnabled=true,FullFrameEffectEnabled=true,
        FullFlashSeconds=0.18,FullPulseSeconds=1,
        FullFrameThickness=2,SpicyColor={R=1,G=0.24,B=0.06,A=1}}
    local function sample(current,maximum,id) return {{id=id or 11,values={CurrentBodyTemperature=current,MaxSizzle=maximum}}} end
    local model=Core.model(sample(35,100),config)
    check(model.phase == "spicy" and model.fraction == 0.35 and model.maximum_source == "native_MaxSizzle",
        "positive temperature uses the same provider's native maximum")
    check(Core.model(sample(35,70),config).fraction == 0.5,"different monsters can have different maxima")
    check(Core.model(sample(100,100),config).fraction == 1,"recorded full level renders full")
    check(Core.model(sample(98.570038,100),config).fraction == 98.570038/100,"recorded decay follows raw current without a countdown")
    local value,reason=Core.model(sample(0,100),config)
    check(not value and Core.inactive(reason),"natural zero and death clear both remove the item")
    value,reason=Core.model(sample(-20,100),config)
    check(not value and Core.inactive(reason),"negative temperature belongs to cold rather than a spicy bar")
    check(not Core.model(sample(40,nil),config) and not Core.model(sample(40,0),config)
        and not Core.model(sample(40,-1),config),"missing or invalid maximum never falls back to 100")
    check(not Core.model(sample(101,100),config) and not Core.model(sample(0/0,100),config)
        and not Core.model(sample(40,math.huge),config),"out-of-range or nonfinite values do not draw")
    local ambiguous=sample(40,100); ambiguous[2]=sample(20,80,12)[1]
    check(not Core.model(ambiguous,config),"multiple current providers are rejected rather than combined")
    check(not Core.model({{id=11,values={CurrentBodyTemperature=30}},{id=12,values={MaxSizzle=100}}},config),
        "current and maximum cannot be taken from separate sources")

    local function class(name,current_kind,max_kind)
        return {name=name,GetSuperStruct=function() return nil end,
            ForEachProperty=function(_,fn)
                for _,pair in ipairs({{"CurrentBodyTemperature",current_kind},{"MaxSizzle",max_kind},{"FrozenRemainingTime","FloatProperty"}}) do
                    local key,kind=pair[1],pair[2]
                    if fn({GetFName=function() return {ToString=function() return key end} end,
                        GetFullName=function() return kind .. " /Script/Maine.BodyTemperatureComponent:" .. key end}) then break end
                end
            end,
            ForEachFunction=function() error("display must not enumerate/invoke additional native functions") end}
    end
    local good_class=class("TemperatureFloat","FloatProperty","FloatProperty")
    local actor,other={id=1,kind="actor"},{id=2,kind="actor"}
    local component={id=11,kind="temperature",owner=actor,CurrentBodyTemperature=35,MaxSizzle=70,
        class=good_class,GetClass=function(self) return self.class end}
    local foreign={id=12,kind="temperature",owner=other,class=good_class,GetClass=component.GetClass}
    actor.BodyTemperatureComponent=foreign
    local reads,resets={},0
    local base={valid=function(object) return object ~= nil end,live=function(object) return object ~= nil and not object.dead end,
        name=function(object) return object.name or tostring(object.id) end,address=function(object) return object.id end,
        is_a=function(object,path) return object.kind == "actor" and path == "/Script/Maine.SurvivalCreature"
            or object.kind == "temperature" and path == "/Script/Maine.BodyTemperatureComponent" end,
        belongs=function(object,owner) return object == owner or object.owner == owner end,
        components=function() return {component,foreign} end,
        member=function(object,key)
            if object.kind == "temperature" then
                check(object == component and (key == "CurrentBodyTemperature" or key == "MaxSizzle"),
                    "only validated fields on the owned component are read")
                reads[key]=(reads[key] or 0)+1
            end
            return object[key]
        end,
        reset=function() resets=resets+1 end,log=function() end}
    local limits={MaxClassDepth=8,MaxFieldsPerClass=256,MaxComponentsToInspect=64,MaxProvidersPerTarget=16}
    local adapter=require("SpicyDisplayUE").new(base,limits)
    local schema=adapter.schema(component)
    check(#schema.fields == 2 and #schema.getters == 0,"schema selects exactly current/max and adds no getters")
    local reader=require("ElementAccumulationReader")
    local providers=reader.build(actor,adapter,limits)
    local captured=reader.read(actor,providers,adapter)
    check(#providers == 1 and Core.model(captured,config).fraction == 0.5
        and reads.CurrentBodyTemperature == 1 and reads.MaxSizzle == 1,"foreign references are rejected and native max is sampled")
    component.MaxSizzle=140
    check(Core.model(reader.read(actor,providers,adapter),config).fraction == 0.25,"maximum is refreshed along with current")
    local bad={kind="temperature",class=class("TemperatureBadMax","FloatProperty","IntProperty"),GetClass=component.GetClass}
    check(#adapter.schema(bad).fields == 0,"wrong reflected maximum type disables the pair")
    adapter.reset()
    check(resets == 0,"Spicy reset preserves ice/sour caches")
    component.dead=true
    check(#reader.read(actor,providers,adapter) == 0,"destroyed sources do not retain stale progress")

    local saved_construct,saved_fname=StaticConstructObject,FName
    local ok,err=pcall(function()
        FName=function(name) return name end
        StaticConstructObject=function(_,_,name)
            local object={name=name}
            function object:SetVisibility(v) self.visibility=v end
            function object:SetOwningPlayer() end
            function object:AddToViewport() end
            function object:RemoveFromParent() end
            function object:SetBrushFromTexture(v) self.texture=v end
            function object:SetColorAndOpacity(v) self.color=v end
            function object:SetClipping() end
            function object:AddChildToCanvas()
                local slot={}
                for _,method in ipairs({"SetAutoSize","SetAnchors","SetAlignment","SetPosition","SetZOrder","SetSize"}) do
                    local key=method; slot[key]=function(self,v) self[key:sub(4)]=v end
                end
                return slot
            end
            return object
        end
        local imports=0
        local fake={live=function(object) return object ~= nil end,find=function(path) return path end,
            verify_ui_api=function() end,log=function() end,once=function() end,
            texture=function(_,path) imports=imports+1; return {path=path} end}
        local ui=require("ChillDisplayUI").new(fake,config,{Tag="SPICY",WidgetPrefix="G2Spicy",
            IconFile="spicy_icon.png",Phases={"spicy"},Colors={spicy=config.SpicyColor}})
        local health,viewport={X=300,Y=50,width=400,height=20},{X=1920,Y=1080}
        local function entry(current,row)
            return {key="spicy-target",model=Core.model(sample(current,100),config),rect=Layout.rect(health,viewport,config,row or 1)}
        end
        ui.render({}, {entry(35)},0)
        local node=ui.nodes[1]
        check(imports == 3 and node.icon.texture.path:match("/spicy_icon%.png$")
            and node.fills.spicy.image.color == config.SpicyColor,"Spicy uses its supplied icon and orange-red original fill")
        check(node.clip_slot.Size.X == 42 and node.outline.visibility == 2,"partial fill is cropped accurately with no gold frame")
        ui.render({}, {entry(100)},1)
        check(node.outline.visibility == 3 and node.outline.color.R == 1 and node.outline.color.G == 0.72
            and node.outline.color.A == 1 and ui.has_active(),"full Spicy has a static opaque gold frame and an animated inside")
        local initial_green=node.fills.spicy.image.color.G
        ui.animate(1.5)
        check(node.fills.spicy.image.color.G < initial_green and node.fills.spicy.image.color.A < 1
            and node.icon.color.A == 1 and node.outline.color.A == 1
            and node.outline_slot.Size.X == 124 and node.clip_slot.Size.X == 120,
            "Spicy inside flashes while the icon, gold frame and actual full value stay fixed")
        ui.render({}, {entry(100,2)},11)
        check(node.slot.Position.Y == 74 and imports == 3,"dynamic row moves reuse existing assets")
        ui.render({}, {entry(50,2)},12)
        check(node.clip_slot.Size.X == 60 and node.outline.visibility == 2,"decay removes gold frame and immediately follows current")
        ui.render({}, {},13)
        check(not ui.visible,"zero or native health hide removes the overlay")
        ui.clear()
    end)
    StaticConstructObject,FName=saved_construct,saved_fname
    if not ok then error(err) end
    return count
end
return M
