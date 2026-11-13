-- Pure Lua/fake metadata only; no game object reads, native calls or UI writes.
local Core,M=require("SpicyProbeCore"),{}
function M.run()
    local count=0
    local function check(value,message)
        assert(value,"Spicy probe self-test: " .. message); count=count+1
    end
    check(Core.related("CurrentBodyTemperature") and Core.related("SpicyDamage") and Core.related("SizzleRateMultiplier"),"temperature/spicy/sizzle candidates are discoverable")
    check(not Core.related("MoviePipelineBurnInWidget"),"movie burn-in widgets are not spicy providers")
    check(not Core.related("SourceComponent") and not Core.related("ResourceCounter"),"source/resource names do not match spicy")
    check(Core.safe_field("CurrentBodyTemperature","FloatProperty",false)
        and Core.safe_field("MaximumValue","DoubleProperty",true),"typed current and focused generic maximum candidates can be read")
    check(not Core.safe_field("MaximumValue","DoubleProperty",false)
        and not Core.safe_field("BodyTemperatureState","EnumProperty",true)
        and not Core.safe_field("TemperatureEmitterResults","ArrayProperty",true)
        and not Core.safe_field("CorrosionData","StructProperty",true),"unfocused fields and compound/enum values stay metadata-only")
    check(Core.accepted("BoolProperty",false) and not Core.accepted("BoolProperty",0),"false remains a boolean instead of missing/zero")
    check(Core.accepted("IntProperty",3) and not Core.accepted("IntProperty",3.5)
        and not Core.accepted("FloatProperty",0/0),"invalid numeric return types are rejected")
    check(not Core.safe_getter("/Script/Maine.BodyTemperatureComponent:UpdateCurrentBodyTemperature",{})
        and not Core.safe_getter("/Script/Maine.BodyTemperatureComponent:GetCurrentBodyTemperature",{}),"first probe never invokes new spicy methods")
    local description=Core.describe({id=11,path="Fixture",values={CurrentBodyTemperature=40,SizzleRatio=0.5,bSizzleEnabled=false}})
    check(description:find("raw_temperature=40",1,true) and description:find("max_sizzle_candidate=unavailable",1,true)
        and description:find("enabled=false",1,true),"ratio never invents a maximum and disabled=false is retained")

    local function property(key,kind)
        return {GetFName=function() return {ToString=function() return key end} end,
            GetFullName=function() return kind .. " /Script/Maine.BodyTemperatureComponent:" .. key end}
    end
    local native_calls=0
    local update=setmetatable({name="Function /Script/Maine.BodyTemperatureComponent:UpdateCurrentBodyTemperature",
        GetFName=function() return {ToString=function() return "UpdateCurrentBodyTemperature" end} end},
        {__call=function() native_calls=native_calls+1; error("setter must not execute") end})
    local class={name="Class /Script/Maine.BodyTemperatureComponent",GetSuperStruct=function() return nil end,
        ForEachProperty=function(_,callback)
            for _,field in ipairs({property("CurrentBodyTemperature","FloatProperty"),property("MaxSizzle","DoubleProperty"),
                property("bSizzleEnabled","BoolProperty"),property("TemperatureEmitterResults","ArrayProperty"),
                property("BodyTemperatureState","EnumProperty"),property("SomeResourceCounter","IntProperty")}) do
                if callback(field) then break end
            end
        end,
        ForEachFunction=function(_,callback) callback(update) end}
    local object={name="BodyTemperatureComponent Fixture",focused=true,CurrentBodyTemperature=40,MaxSizzle=80,bSizzleEnabled=false,SomeResourceCounter=2,
        GetClass=function() return class end}
    local schema_logs,base_resets,reads={},0,{}
    local base={valid=function(value) return value ~= nil end,
        name=function(value) return value.name end,
        is_a=function(value,path) return value.focused and path == "/Script/Maine.BodyTemperatureComponent" end,
        parameters=function() return {{key="Value",kind="FloatProperty"}} end,
        member=function(value,key) reads[key]=true; return value[key] end,
        log=function(message) schema_logs[#schema_logs+1]=message end,
        reset=function() base_resets=base_resets+1 end}
    local limits={MaxClassDepth=8,MaxFieldsPerClass=256,MaxFunctionsPerClass=256,MaxSchemasPerCapture=64}
    local ue=require("SpicyProbeUE").new(base,limits)
    local schema=ue.schema(object)
    check(#schema.fields == 4 and #schema.getters == 0,"focused temperature component exposes typed primitive fields only")
    local values=ue.values(object,schema)
    check(values.CurrentBodyTemperature == 40 and values.MaxSizzle == 80 and values.bSizzleEnabled == false,
        "native primitive reads preserve actual values")
    check(not reads.TemperatureEmitterResults and not reads.BodyTemperatureState and native_calls == 0,
        "compound state/effect data and update functions are not read/invoked")
    check(Core.describe({id=11,path="Fixture",values=values}):find("max_sizzle_candidate=80",1,true),
        "maximum candidates come from the same recorded provider")
    local cached=ue.schema(object)
    check(cached == schema,"schema discovery is cached between samples")
    ue.reset()
    check(base_resets == 0 and ue.schema(object) ~= cached,"capture reset does not reset existing cold-display caches")
    local invoked_false=false
    for _,line in ipairs(schema_logs) do if line:find("invoke=false",1,true) then invoked_false=true end end
    check(invoked_false and native_calls == 0,"mutating function metadata is recorded without calling it")

    local now,available=0,false
    local controller,pawn,actor,other={id=1,world=9},{id=2},{id=3,world=9},{id=4,world=9}
    controller.Pawn=pawn
    local foreign,hud={id=5},{id=6}
    local current_target,widgets=actor,{foreign,hud}
    local level,builds,sample_reads,last_actor,resets=0,0,0,nil,0
    local logs={}
    local fake={live=function(value) return value ~= nil and not value.dead end,
        world=function(value) return value.world or 9 end,same=function(a,b) return a == b end,
        member=function(value,key) return value[key] end,address=function(value) return value.id end,
        name=function() return "FixtureCreature" end,time=function() return now end,
        reset=function() resets=resets+1 end,
        local_player=function() if available then return controller,pawn,9 end end,
        all=function(kind) check(kind == "EnemyHealthWidget","discovery stays inside native local monster HUDs"); return widgets end,
        target_from_widget=function(value,owner,world)
            if value == hud and owner == controller and world == 9 then return current_target end
        end,
        log=function(message) logs[#logs+1]=message end,
        once=function(_,message) logs[#logs+1]=message end}
    local config={CaptureSeconds=600,SampleIntervalMs=100,DiscoveryInterval=1,ProviderRefreshInterval=2,HeartbeatSeconds=2}
    local reader={build=function() builds=builds+1; return {} end,
        read=function(value)
            sample_reads=sample_reads+1; last_actor=value
            return {{id=11,path="Temperature Fixture",values={CurrentBodyTemperature=level,bSizzleEnabled=true}}}
        end}
    local function contains(marker)
        for _,line in ipairs(logs) do if line:find(marker,1,true) then return true end end
        return false
    end
    local runtime=require("SpicyProbeRuntime").new(fake,config,reader)
    runtime.update(); runtime.toggle()
    check(sample_reads == 0 and contains("SPICY_CAPTURE_NOT_STARTED"),"idle/menu state performs no capture reads")
    available=true; runtime.toggle(); runtime.update()
    check(sample_reads == 1 and builds == 1 and resets == 1 and last_actor == actor
        and contains("SPICY_CAPTURE_BEGIN") and contains("SPICY_TARGET_READY"),"F5 records the first validated local target")
    level,now=30,0.1; runtime.update()
    check(contains("direction=rise") and contains("raw_temperature=30"),"actual increases are logged without assuming trigger semantics")
    current_target,now=other,0.2; runtime.update()
    check(last_actor == actor and builds == 1,"changing HUD focus does not mix creatures inside one recording")
    widgets,now={},0.3; runtime.update()
    check(last_actor == actor,"a pinned live monster continues recording decay after its health bar hides")
    level,now=100,0.4; runtime.update()
    level,now=0,0.5; runtime.update()
    check(contains("direction=fall previous=100 current=0 observed_peak=100 interpretation=unverified"),
        "full/reset observations retain their raw sequence and do not declare a verified maximum")
    runtime.toggle(); local stopped_reads=sample_reads; now=1; runtime.update()
    check(sample_reads == stopped_reads and contains("SPICY_CAPTURE_END reason=F5"),"second F5 stops reads")
    widgets,current_target={hud},actor
    runtime.toggle(); runtime.update(); stopped_reads=sample_reads
    now=601.1; runtime.update()
    check(sample_reads == stopped_reads and contains("SPICY_CAPTURE_END reason=timeout"),"capture ends after ten minutes without further target reads")
    runtime.toggle(); runtime.update()
    controller.Pawn={}; now=601.2; runtime.update()
    check(contains("SPICY_CAPTURE_END reason=local_context_changed"),"pawn/world context changes stop stale capture")
    controller.Pawn=pawn
    runtime.toggle(); runtime.update()
    actor.dead=true; now=601.3; runtime.update()
    check(contains("SPICY_CAPTURE_END reason=target_unavailable"),"destroyed pinned targets stop rather than switching to another creature")
    actor.dead=false
    local failing=require("SpicyProbeRuntime").new(fake,config,{build=reader.build,read=function() error("fixture read failure") end})
    failing.toggle(); failing.update()
    check(contains("SPICY_CAPTURE_ERROR") and contains("SPICY_CAPTURE_END reason=read_error"),"read failures end only the spicy capture")
    return count
end
return M
