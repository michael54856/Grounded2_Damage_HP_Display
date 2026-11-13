-- Pure/fake UE regression tests; no real hooks, timers or engine getter calls.
local Core,M = require("ElementAccumulationCore"),{}
function M.run()
    local count = 0
    local function check(value,message) assert(value,"Element_Accumulation_Display self-test: " .. message); count=count+1 end
    check(Core.finite(-50) and not Core.finite(0/0) and not Core.finite(math.huge),"signed finite temperature is preserved")
    check(Core.number(-0.125) == "-0.125" and Core.number(nil) == "unavailable","missing data is not printed as zero")
    local path = "/Script/Maine.BodyTemperatureComponent:"
    local scalar = {{key="ReturnValue",kind="FloatProperty"}}
    check(Core.safe_getter(path .. "GetCurrentBodyTemperature",scalar),"exact zero-argument numeric getter allowed")
    check(not Core.safe_getter(path .. "SetCurrentBodyTemperature",scalar)
        and not Core.safe_getter(path .. "ClearFrozen",{}) and not Core.safe_getter(path .. "ToggleChill",{}),"state-changing functions are excluded")
    check(not Core.safe_getter("/Script/Other.Component:GetCurrentBodyTemperature",scalar)
        and not Core.safe_getter(path .. "GetCurrentBodyTemperature",{{key="World",kind="ObjectProperty"},scalar[1]})
        and not Core.safe_getter(path .. "GetCurrentBodyTemperature",{false}),"owner path and complete getter signature must match")
    check(Core.safe_field("MaxChill","FloatProperty") and Core.safe_field("bIsFrozen","BoolProperty")
        and not Core.safe_field("FrozenProperties","StructProperty") and not Core.safe_field("CurrentBodyTemperatureState","EnumProperty"),
        "only explicit scalar fields are read; raw structs/enums are not guessed")
    local rows = {{name="ETest::Normal",value=5},{name="ETest::Frozen",value=9}}
    local info = assert(Core.enum_info("/Script/Test.TemperatureState",rows,64))
    check(info.names[9] == "ETest::Frozen" and not Core.enum_info("x",{{name="a",value=1},{name="b",value=1}},64),
        "enum mapping comes from metadata, including ambiguity checks")
    check(Core.safe_getter(Core.enum_getter_path,{{key="ReturnValue",kind="EnumProperty",enum_info=info}})
        and not Core.safe_getter(Core.enum_getter_path,{{key="ReturnValue",kind="EnumProperty"}}),"enum getter requires copied metadata")
    local values = {CurrentBodyTemperature=-49,["GetCurrentBodyTemperature()"]=-50,MaxChill=-100,
        ["GetCurrentBodyTemperatureRatio()"]=0.5,["GetCurrentBodyTemperatureState()"]=5,["IsFrozen()"]=false}
    local provider = {id=20,path="Fake.Temperature",values=values,enum_info=info}
    check(Core.candidate({provider}).raw == -50,"native getter wins while negative raw values remain unchanged")
    check(Core.describe({provider}):find("max_chill=-100",1,true) and Core.state(provider):find("is_frozen=false",1,true),
        "negative thresholds and Boolean false remain visible")
    check(not Core.candidate({{values={["GetCurrentBodyTemperatureRatio()"]=0.5}}}),"ratio cannot manufacture current or a maximum")
    local candidate,reason = Core.candidate({provider,{id=21,path="Other",values=values}})
    check(candidate == nil and reason == "multiple_temperature_providers","equivalent sources remain unresolved")
    check(Core.values_text({A=false,B=0}) == "A=false B=0","false and zero survive raw logging")

    local UE = require("ElementAccumulationUE")
    local saved_find,saved_once = UE.find,UE.once
    local ok,err = pcall(function()
        UE.reset(); UE.once = function() end
        local temperature,frozen,state_value = -50,false,5
        local enum = {IsValid=function() return true end,GetFullName=function() return "Enum /Script/Test.TemperatureState" end}
        function enum:ForEachName(callback)
            for _,row in ipairs(rows) do local name=row.name; if callback({ToString=function() return name end},row.value) then break end end
        end
        local function property(key,kind)
            return {GetFName=function() return {ToString=function() return key end} end,
                GetFullName=function() return kind .. " /Script/Maine.BodyTemperatureComponent:" .. key end,
                GetEnum=function() return enum end}
        end
        local function metadata(key,kind)
            return setmetatable({IsValid=function() return true end,
                GetFullName=function() return "Function " .. path .. key end,
                GetFName=function() return {ToString=function() return key end} end,
                ForEachProperty=function(_,callback) callback(property("ReturnValue",kind)) end},
                {__call=function() error("class-bound metadata must never execute") end})
        end
        local functions = {metadata("GetCurrentBodyTemperature","FloatProperty"),metadata("GetCurrentBodyTemperatureRatio","FloatProperty"),
            metadata("GetCurrentBodyTemperatureState","EnumProperty"),metadata("IsFrozen","BoolProperty")}
        local class = {IsValid=function() return true end,GetFullName=function() return "Class /Script/Maine.BodyTemperatureComponent" end,
            GetSuperStruct=function() return nil end,
            ForEachProperty=function(_,callback) callback(property("CurrentBodyTemperature","FloatProperty")); callback(property("MaxChill","FloatProperty")) end,
            ForEachFunction=function(_,callback) for _,fn in ipairs(functions) do if callback(fn) then break end end end}
        local object = {IsValid=function() return true end,HasAnyFlags=function() return false end,GetClass=function() return class end,
            GetAddress=function() return 501 end,GetFullName=function() return "BodyTemperatureComponent /Test.Creature.Temp" end,
            GetPropertyValue=function(_,key) if key == "MaxChill" then return -100 else return temperature end end}
        UE.find = function(full_path)
            local key = full_path:match(":([^:]+)$")
            return function(context,...)
                assert(context == object and select("#",...) == 0,"getters require the actual component and no extra arguments")
                if key == "GetCurrentBodyTemperature" then return temperature
                elseif key == "GetCurrentBodyTemperatureRatio" then return 0.5
                elseif key == "GetCurrentBodyTemperatureState" then return state_value
                elseif key == "IsFrozen" then return frozen end
                error("unexpected getter")
            end
        end
        local schema = UE.schema(object)
        check(#schema.getters == 4 and schema.enum_info.names[9] == "ETest::Frozen","reflection discovers typed getters and actual enum mapping")
        for _,getter in ipairs(schema.getters) do check(getter.fn == nil,"metadata-bound callable is not stored") end
        local sample = UE.values(object,schema)
        check(sample["GetCurrentBodyTemperature()"] == -50 and sample.MaxChill == -100 and sample["IsFrozen()"] == false,
            "unbound adapter preserves signed scalars and Boolean false")
        state_value,frozen = 1.5,0
        sample = UE.values(object,schema)
        check(sample["GetCurrentBodyTemperatureState()"] == nil and sample["IsFrozen()"] == nil,"invalid native result types fail closed")
        local list,format = UE.component_list({{get=function() return object end}},64)
        check(#list == 1 and format == "lua_table" and list[1] == object,"component enumeration unwraps official UE4SS Lua arrays")
        list,format = UE.component_list({ForEach=function(_,callback) callback(1,{get=function() return object end}) end},64)
        check(#list == 1 and format == "tarray","native TArray remains supported")
        check(not pcall(UE.component_list,{[0]=object},64),"unknown array layouts are not guessed")
    end)
    UE.find,UE.once = saved_find,saved_once
    UE.reset()
    if not ok then error(err) end

    local Reader = require("ElementAccumulationReader")
    local root = {id=1,fields={},schema={fields={},getters={},references={"BodyTemperatureComponent"}}}
    local owned = {id=2,owner=root,fields={},schema={fields={{key="CurrentBodyTemperature"}},getters={},references={}},values=values}
    local foreign = {id=3,owner={},fields={},schema=owned.schema,values=values}
    root.fields.BodyTemperatureComponent = owned
    local fake = {live=function(object) return object ~= nil and not object.dead end,
        belongs=function(object,actor) return object == actor or object.owner == actor end,
        components=function() return {owned,owned,foreign} end,schema=function(object) return object.schema end,
        member=function(object,key) return object.fields[key] end,values=function(object) return object.values end,
        address=function(object) return object.id end,name=function(object) return "Fake_" .. object.id end,once=function() end}
    local config = require("ElementAccumulationConfig")
    local bindings = Reader.build(root,fake,config)
    check(#bindings == 1 and bindings[1].object == owned,"provider discovery deduplicates owned components and rejects foreign ones")
    check(#Reader.read(root,bindings,fake) == 1,"valid owned scalar provider is read")
    owned.owner = foreign
    check(#Reader.read(root,bindings,fake) == 0,"ownership loss invalidates a recorded provider")

    local now,builds,reads,scans = 0,0,0,0
    local controller,pawn,actor,widget = {id=1,world=3},{id=2},{id=4,world=3},{}
    controller.Pawn = pawn
    local shown = true
    local logs = {}
    local runtime_ue = {live=function(object) return object ~= nil end,reset=function() end,
        log=function(message) logs[#logs+1]=message end,once=function() end,
        local_player=function() return controller,pawn,3 end,time=function() return now end,
        same=function(a,b) return a == b end,world=function(object) return object.world end,
        member=function(object,key) return object[key] end,address=function(object) return object.id end,
        name=function() return "FakeCreature" end,all=function() scans=scans+1; return {widget} end,
        target_from_widget=function() if shown then return actor end end}
    local reader = {build=function() builds=builds+1; return {} end,
        read=function() reads=reads+1; return {provider} end}
    local runtime = require("ElementAccumulationRuntime").new(runtime_ue,config,reader)
    runtime.update()
    check(reads == 0 and scans == 0,"inactive capture does no searches or reads")
    runtime.toggle(); runtime.update()
    values["GetCurrentBodyTemperature()"],now=-60,0.1; runtime.update()
    values["GetCurrentBodyTemperatureState()"],values["IsFrozen()"],now=9,true,0.2; runtime.update()
    values["GetCurrentBodyTemperatureState()"],values["IsFrozen()"],now=5,false,0.3; runtime.update()
    local transitions = 0
    for _,line in ipairs(logs) do if line:find("CHILL_STATE_TRANSITION",1,true) then transitions=transitions+1 end end
    check(transitions == 2 and builds == 1 and scans == 1,"state transitions are source-specific and sampling does not rescan every tick")
    shown,now=false,0.4; local before=reads; runtime.update()
    check(reads == before+1,"pinned monster remains readable after its native health bar disappears")
    now=2.1; runtime.update()
    check(builds == 2,"bounded periodic refresh can discover providers added during the effect")
    now=config.CaptureSeconds; runtime.update()
    check(logs[#logs]:find("reason=timeout",1,true),"ten-minute capture stops automatically")
    runtime.toggle(); controller.Pawn={}; runtime.update()
    check(logs[#logs]:find("reason=local_context_changed",1,true),"pawn changes stop old-world capture")
    controller.Pawn=pawn
    runtime.toggle(); runtime.toggle()
    check(logs[#logs]:find("reason=F5",1,true),"F5 stops without interfering with other mods' keys")
    return count
end
return M
