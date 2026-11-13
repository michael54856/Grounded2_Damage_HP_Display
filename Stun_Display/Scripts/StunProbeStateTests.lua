local Core,State,M = require("StunProbeCore"),require("StunProbeState"),{}
function M.run(check)
    -- Intentionally nonstandard values prove we never assume 0/1/2.
    local rows = {{name="EStunState::None",value=42},{name="EStunState::Stunned",value=7},
        {name="EStunState::StunCooldown",value=19},{name="EStunState::MAX",value=99}}
    local info = assert(State.enum_info("/Script/Test.FakeStunState",rows,32))
    check(info.names[42] == "EStunState::None" and info.names[7] == "EStunState::Stunned",
        "state mapping uses reflected enum values, not ordinals")
    check(info.rows[1].value == 7 and rows[1].value == 42,"enum sorting does not mutate input metadata")
    check(not State.enum_info("x",{},32) and not State.enum_info("x",rows,2)
        and not State.enum_info("x",nil,32),"missing/oversized enum definitions fail closed")
    check(not State.enum_info("x",{{name="a",value=1},{name="b",value=1}},32)
        and not State.enum_info("x",{{name="a",value=1},{name="a",value=2}},32),"ambiguous enum metadata is never guessed")
    check(not State.enum_info("x",{{name="a",value=1.5}},32)
        and not State.enum_info("x",{{name="a",value=0/0}},32)
        and not State.enum_info("x",{false},32),"invalid enum values are rejected")
    local enum_fields = {{key="ReturnValue",kind="EnumProperty",enum_info=info}}
    check(State.safe_getter(State.enum_getter_path,enum_fields)
        and State.safe_getter(State.bool_getter_path,{{key="ReturnValue",kind="BoolProperty"}}),"explicit typed state getters are allowed")
    check(not State.safe_getter(State.enum_getter_path,{{key="ReturnValue",kind="EnumProperty"}})
        and not State.safe_getter(State.enum_getter_path,{{key="ReturnValue",kind="ByteProperty",enum_info=info}}),
        "enum reads need verified metadata and the exact return type")
    check(not State.safe_getter(State.bool_getter_path,{{key="ReturnValue",kind="FloatProperty"}})
        and not State.safe_getter("/Script/Other.Component:GetStunState",enum_fields)
        and not State.safe_getter("/Script/Maine.ReactionComponent:BeginStun",enum_fields),"unrelated or mutating functions are excluded")
    check(not State.safe_getter(State.enum_getter_path,{{key="Reason",kind="IntProperty"},enum_fields[1]})
        and not State.safe_getter(State.enum_getter_path,nil),"state getter arguments are never guessed")
    local function observation(raw,stunned,metadata)
        return State.observe({["GetStunState()"]=raw,["IsStunned()"]=stunned},metadata or info)
    end
    check(observation(42,false).phase == "normal" and observation(7,true).phase == "stunned"
        and observation(19,false).phase == "cooldown","all three named states are decoded")
    check(State.describe(observation(42,false)):find("is_stunned=false",1,true)
        and observation(42,false).check == "agree","false is retained, never confused with unavailable")
    check(observation(7,false).phase == "unknown" and observation(7,false).check == "conflict"
        and observation(42,true).check == "conflict","contradictory state and IsStunned fail closed")
    check(observation(7,nil).phase == "stunned" and observation(7,nil).check == "enum_only",
        "known enum can be reported without pretending missing Boolean confirmation")
    check(observation(999,false).phase == "unknown" and observation(999,false).raw == 999
        and observation(999,false).check == "unknown_value","unknown values remain visible and unclassified")
    check(observation(99,false).phase == "unknown" and observation(99,false).check == "unknown_enum_name",
        "MAX/sentinel names are not treated as a gameplay state")
    check(observation(1.5,false).raw == nil and observation(nil,false).phase == "unknown"
        and State.observe({["IsStunned()"]=true},nil).phase == "unknown","missing data never becomes normal or zero")
    local event,record = State.event(nil,observation(42,false),0)
    check(event:find("STUN_STATE_INITIAL",1,true),"first state is labeled initial, not a fabricated transition")
    local unchanged,same_record = State.event(record,observation(42,false),1)
    check(unchanged == nil and same_record.time == 0,"repeated samples preserve original state-entry time")
    local transition,next_record = State.event(same_record,observation(7,true),3)
    check(transition:find("previous_state_seconds=3",1,true) and next_record.time == 3,
        "transition duration is measured between observed state entries")

    -- Full native adapter surface with fake reflection objects. Metadata-bound
    -- callable wrappers explode if accidentally executed; only find(path) works.
    local UE = require("StunProbeUE")
    local saved_find,saved_once = UE.find,UE.once
    local ok,err = pcall(function()
        UE.reset(); UE.once = function() end
        local raw,stunned,current = 19,false,25
        local enum = {IsValid=function() return true end,GetFullName=function() return "Enum /Script/Test.FakeStunState" end}
        function enum:ForEachName(callback)
            for _, row in ipairs(rows) do
                local text = row.name
                if callback({ToString=function() return text end},row.value) then break end
            end
        end
        local function property(key,kind,extra)
            local result = extra or {}
            result.GetFName = function() return {ToString=function() return key end} end
            result.GetFullName = function() return kind .. " /Script/Test.FakeReaction:" .. key end
            return result
        end
        local function fn(key,prop)
            return setmetatable({IsValid=function() return true end,
                GetFName=function() return {ToString=function() return key end} end,
                GetFullName=function() return "Function /Script/Maine.ReactionComponent:" .. key end,
                ForEachProperty=function(_,callback) callback(prop) end},
                {__call=function() error("class-bound metadata callable must not execute") end})
        end
        local funcs = {
            fn("GetMaxStun",property("ReturnValue","FloatProperty")),
            fn("GetStunState",property("ReturnValue","EnumProperty",{GetEnum=function() return enum end})),
            fn("IsStunned",property("ReturnValue","BoolProperty")),
        }
        local class = {IsValid=function() return true end,GetFullName=function() return "Class /Script/Test.FakeReaction" end,
            GetSuperStruct=function() return nil end,
            ForEachProperty=function(_,callback) callback(property("CurrentStunValue","FloatProperty")) end,
            ForEachFunction=function(_,callback) for _, method in ipairs(funcs) do if callback(method) then break end end end}
        local component = {IsValid=function() return true end,HasAnyFlags=function() return false end,
            GetClass=function() return class end,GetFullName=function() return "ReactionComponent /Test.FakeActor.ReactionComponent" end,
            GetPropertyValue=function(_,key) assert(key == "CurrentStunValue"); return current end}
        UE.find = function(path)
            local key = path:match(":([^:]+)$")
            assert(key == "GetStunState" or key == "IsStunned" or key == "GetMaxStun","unexpected native lookup")
            return function(context,...)
                assert(context == component and select("#",...) == 0,"state getter must use the live component with no extra arguments")
                if key == "GetStunState" then return raw elseif key == "IsStunned" then return stunned else return 75 end
            end
        end
        local schema = UE.schema(component)
        check(schema.state_enabled and schema.state_enum.names[19] == "EStunState::StunCooldown",
            "getter enum metadata is discovered from its actual return property")
        for _, getter in ipairs(schema.getters) do check(getter.fn == nil,"metadata-bound callable never escapes schema discovery") end
        local values = UE.values(component,schema)
        check(values["GetStunState()"] == 19 and values["IsStunned()"] == false and values.CurrentStunValue == 25,
            "native adapter preserves enum integers and false Boolean results")
        check(State.observe(values,schema.state_enum).phase == "cooldown","adapter values decode through the discovered mapping")
        raw,stunned = 7,true
        check(State.observe(UE.values(component,schema),schema.state_enum).phase == "stunned","same instance supports subsequent state changes")
        raw,stunned = 1.5,0
        values = UE.values(component,schema)
        check(values["GetStunState()"] == nil and values["IsStunned()"] == nil,
            "wrong native result types do not silently become state zero or false")
        local bad = {GetEnum=function() return nil end}
        check(UE.enum_info(bad) == nil,"missing enum definition refuses the enum getter instead of guessing")
    end)
    UE.find,UE.once = saved_find,saved_once
    UE.reset()
    if not ok then error(err) end

    -- Reader retains state observations even if a max of zero prevents a pair.
    local Reader = require("StunProbeReader")
    local actor,source = {},{}
    local fake_values = {CurrentStunValue=10,["GetMaxStun()"]=0,["GetStunState()"]=19,["IsStunned()"]=false}
    local fake = {live=function(object) return object ~= nil end,belongs=function(object,owner) return object == source and owner == actor end,
        values=function() return fake_values end}
    local binding = {object=source,id=10,path="Test.ReactionComponent",schema={state_enabled=true,state_enum=info}}
    local result = Reader.read(actor,{binding},fake,require("StunProbeConfig"))
    check(result.pair == nil and #result.states == 1 and result.states[1].observation.phase == "cooldown",
        "state diagnostics survive an unavailable current/max pair")
    fake_values["GetMaxStun()"] = 75
    result = Reader.read(actor,{binding},fake,require("StunProbeConfig"))
    check(Reader.describe(result):find("phase=cooldown",1,true),"normal sample log includes state interpretation")

    local now,raw,stunned,visible_state,provider_id = 0,42,false,true,10
    local controller,pawn,target,widget = {id=1,world=3},{id=2},{id=4},{}
    controller.Pawn = pawn
    local logs = {}
    local runtime_ue = {live=function(object) return object ~= nil end,reset=function() end,
        log=function(message) logs[#logs+1] = message end,once=function() end,
        local_player=function() return controller,pawn,3 end,time=function() return now end,
        world=function(object) return object == target and 3 or object.world end,
        same=function(a,b) return a == b end,member=function(object,key) return object[key] end,
        all=function() return {widget} end,target_from_widget=function() return target end,
        address=function(object) return object.id end,name=function() return "Fake" end}
    local runtime_reader = {build=function() return {} end,
        read=function()
            local observations = {}
            if visible_state then observations[1] = {id=provider_id,path="Test.Reaction",observation=observation(raw,stunned),values={}} end
            return {providers={},states=observations}
        end,describe=function() return "STUN_SAMPLE fake" end}
    local runtime = require("StunProbeRuntime").new(runtime_ue,require("StunProbeConfig"),runtime_reader)
    runtime.toggle(); runtime.update()
    now=1; runtime.update()
    now,raw,stunned=2,7,true; runtime.update()
    now,raw,stunned=3,19,false; runtime.update()
    now,raw,stunned=4,42,false; runtime.update()
    local initial,transitions = 0,0
    for _, message in ipairs(logs) do
        if message:find("STUN_STATE_INITIAL",1,true) then initial = initial + 1 end
        if message:find("STUN_STATE_TRANSITION",1,true) then transitions = transitions + 1 end
    end
    check(initial == 1 and transitions == 3,"runtime logs one initial state and a complete observed normal/stun/cooldown/normal cycle")
    local function has_since(index,marker)
        for i=index+1,#logs do if logs[i]:find(marker,1,true) then return true end end
        return false
    end
    visible_state,now=false,5; runtime.update()
    local before = #logs
    visible_state,now=true,6; runtime.update()
    check(has_since(before,"STUN_STATE_INITIAL") and not has_since(before,"STUN_STATE_TRANSITION"),
        "state continuity resets when provider observations disappear")
    before = #logs
    provider_id,now=11,7; runtime.update()
    check(has_since(before,"STUN_STATE_INITIAL") and not has_since(before,"STUN_STATE_TRANSITION"),
        "replacement provider starts its own state timeline")
    runtime.toggle(); runtime.toggle(); now=8; runtime.update()
    local new_initial = false
    for index=#logs,1,-1 do
        if logs[index]:find("STUN_STATE_INITIAL",1,true) then new_initial = true; break end
        if logs[index]:find("CAPTURE_BEGIN",1,true) then break end
    end
    check(new_initial,"new F6 capture never creates a transition from the previous recording")
end
return M
