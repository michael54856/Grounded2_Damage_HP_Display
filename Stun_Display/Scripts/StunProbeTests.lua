-- Pure/fake UE tests only. No real hooks, timers, native function calls or UI.
local Core, Reader, M = require("StunProbeCore"),require("StunProbeReader"),{}
function M.run()
    local count = 0
    local function check(value,message)
        assert(value,"Stun_Display self-test: " .. message)
        count = count + 1
    end
    check(Core.finite(0) and not Core.finite(0/0) and not Core.finite(math.huge),"finite numeric samples only")
    check(Core.number(12.125) == "12.125" and Core.number(0) == "0" and Core.number(nil) == "unavailable",
        "fractional stun is retained, not rounded to an integer")
    check(Core.related("CurrentStunValue") and Core.related("StaggerThreshold") and not Core.related("Health"),
        "related metadata filter")
    check(Core.scalar_kind("FloatProperty") and not Core.scalar_kind("StructProperty")
        and Core.object_kind("ObjectPtrProperty") and not Core.object_kind("ArrayProperty"),"unsupported raw memory is excluded")
    local scalar_return = {{key="ReturnValue",kind="FloatProperty"}}
    check(Core.safe_getter("GetMaxStun",scalar_return),"explicit zero-input getter is accepted")
    check(not Core.safe_getter("BeginStun",scalar_return) and not Core.safe_getter("TryStun",scalar_return)
        and not Core.safe_getter("EndStun",{}),"stun-changing functions are never invoked")
    check(not Core.safe_getter("GetMaxStun",{{key="Reason",kind="EnumProperty"},{key="ReturnValue",kind="FloatProperty"}}),
        "getters requiring inputs are not guessed")
    check(not Core.safe_getter("GetMaxStun",{{key="ReturnValue",kind="StructProperty"}}),"nonscalar returns are not called")
    check(not Core.safe_getter("GetStunState",{{key="ReturnValue",kind="EnumProperty"}})
        and not Core.safe_field("StunState","EnumProperty"),"generic numeric path excludes direct enum fields; typed state getters are separate")
    check(Core.safe_field("CurrentStunValue","FloatProperty") and not Core.safe_field("HitStun","IntProperty"),
        "only known current/max/decay floating fields are sampled")
    check(Core.function_path("Function /Script/Maine.ReactionComponent:GetMaxStun")
        == "/Script/Maine.ReactionComponent:GetMaxStun", "normalize reflection names for unbound lookup")
    local provider = {id=1,path="Creature.Combat",values={CurrentStunValue=25,MaxStunValue=80,["GetMaxStun()"]=100,["GetStunRatio()"]=0.25}}
    local pair = Core.pair(provider)
    check(pair.current == 25 and pair.maximum == 100 and pair.maximum_key == "GetMaxStun()",
        "runtime max getter takes priority over a potentially unmodified base field")
    check(pair.status == "getter_pair_observed" and pair.score == 20,"observations are not labeled semantically verified")
    local base = {id=2,path="Creature.Base",values={CurrentStunValue=10,MaxStunValue=80}}
    check(Core.pair(base).status == "field_pair_unverified","field-only maximum is explicitly unverified")
    check(Core.pair({values={["GetStunRatio()"]=0.25,["GetMaxStun()"]=100}}) == nil,
        "ratio is never multiplied to fabricate an allegedly direct current value")
    check(Core.pair({values={CurrentStunValue=10,MaxStunValue=100,["GetMaxStun()"]=0}}) == nil,
        "zero effective maximum cannot silently fall back to base threshold")
    check(Core.pair({values={CurrentStunValue=-1,MaxStunValue=100}}) == nil
        and Core.pair({values={CurrentStunValue=10,MaxStunValue=0}}) == nil,"invalid samples fail closed")
    check(Core.pair({values={CurrentStunValue=120,MaxStunValue=100}}).current == 120,
        "above-threshold raw observations are retained instead of concealed by clamping")
    local config = require("StunProbeConfig")
    local selected,reason = Core.select({base,provider},config)
    check(selected.provider == provider and reason == nil,"unique effective-getter source wins")
    selected,reason = Core.select({provider,{id=3,path="Creature.Other",values=provider.values}},config)
    check(selected == nil and reason == "multiple_providers","equally plausible sources remain unresolved")
    selected,reason = Core.select({},config)
    check(selected == nil and reason == "no_direct_current_max_pair","missing direct data is not treated as zero")
    check(Core.select({base,provider},{PreferredProviderPathContains="base"}).provider == base,
        "manual provider path filter is case-insensitive")
    check(Core.ratio_relation(25,100,0.25) == "direct" and Core.ratio_relation(25,100,0.75) == "inverse"
        and Core.ratio_relation(50,100,0.5) == "direct_or_inverse", "accumulation versus remaining-value convention is checked")
    check(Core.ratio_relation(25,100,0.4) == "mismatch" and Core.ratio_relation(25,0,0.25) == "unavailable",
        "ratio discrepancies are not hidden")
    check(Core.values_text({Z=true,A=1.25}) == "A=1.25 Z=true","raw values have stable, readable ordering")
    check(Core.should_report(nil,"a",0,2) and not Core.should_report({fingerprint="a",time=0},"a",1,2)
        and Core.should_report({fingerprint="a",time=0},"b",1,2)
        and Core.should_report({fingerprint="a",time=0},"a",2,2),"changes plus heartbeat, not unlimited identical log spam")

    local actor = {id=10,fields={},schema={fields={},getters={},references={"Combat"}}}
    local combat = {id=11,owner=actor,fields={},schema={fields={{key="CurrentStunValue"}},getters={},references={"OwnerCycle"}},values=provider.values}
    actor.fields.Combat,combat.fields.OwnerCycle = combat,actor
    local foreign = {id=12,owner={id=99},schema=combat.schema,values=provider.values}
    local errors = {}
    local function live(object) return type(object) == "table" and not object.dead end
    local fake = {
        live=live,address=function(object) return object.id end,name=function(object) return "Fake_" .. object.id end,
        belongs=function(object,root) return object == root or object.owner == root end,
        member=function(object,key) return object.fields[key] end,
        components=function() return {combat,combat,foreign} end,
        schema=function(object) return object.schema end,
        values=function(object) return object.values end,
        once=function(_,message) errors[#errors+1] = message end,
    }
    local bindings = Reader.build(actor,fake,config)
    check(#bindings == 1 and bindings[1].object == combat,"provider traversal deduplicates cycles and rejects foreign owners")
    local result = Reader.read(actor,bindings,fake,config)
    check(result.pair.current == 25 and result.pair.maximum == 100,"direct runtime values flow through the reader")
    local description = Reader.describe(result)
    check(description:find("current=25 max=100",1,true) and description:find("ratio_relation=direct",1,true),
        "diagnostics identify the pair and cross-check the ratio")
    combat.owner = foreign
    check(Reader.read(actor,bindings,fake,config).pair == nil,"owner changes invalidate an existing binding")
    combat.owner,combat.dead = actor,true
    check(Reader.read(actor,bindings,fake,config).pair == nil,"destroyed providers are never read")
    combat.dead = false
    fake.components = function() error("fake unavailable enumeration") end
    check(#Reader.build(actor,fake,config) == 1,"reflected references still work if component enumeration is unavailable")

    local Native = require("StunProbeUE")
    local function wrapper(id) return {IsValid=function() return true end,GetAddress=function() return id end} end
    check(Native.same(wrapper(123),wrapper(123)) and not Native.same(wrapper(123),wrapper(124)),
        "native identity, never raw Lua userdata identity")
    check(not Native.same(wrapper(0),wrapper(0)) and not Native.same(nil,nil),"invalid identities cannot establish ownership")
    -- Regression at the native adapter boundary, not just injected runtime tests.
    local saved_find,saved_member,saved_parameters,saved_once = Native.find,Native.member,Native.parameters,Native.once
    local adapter_ok,adapter_error = pcall(function()
        local component,actor_context,component_class = wrapper(500),wrapper(501),wrapper(502)
        local called,enumerated,enumeration_return = false,false,nil
        local max_path = "/Script/Maine.ReactionComponent:GetMaxStun"
        Native.once = function() end
        Native.member = function(object,key)
            assert(object == component and key == "CurrentStunValue")
            return 12.5
        end
        Native.find = function(path)
            if path == max_path then
                return function(context,...)
                    assert(context == component and select("#",...) == 0,"getter must receive live component, not class")
                    called = true; return 100
                end
            elseif path == "/Script/Engine.Actor:K2_GetComponentsByClass" then
                return function(context,...)
                    assert(context == actor_context and select("#",...) == 1,"component enumeration must have exactly one native input")
                    assert((...) == component_class)
                    enumerated = true
                    return enumeration_return
                end
            elseif path == "/Script/Engine.ActorComponent" then return component_class end
            error("unexpected native lookup: " .. tostring(path))
        end
        Native.parameters = function() return {
            {key="ComponentClass",kind="ClassProperty"},{key="ReturnValue",kind="ArrayProperty"},
        } end
        local values = Native.values(component,{fields={{key="CurrentStunValue"}},getters={{key="GetMaxStun",path=max_path,
            fn=function() error("class-bound metadata wrapper must never execute") end}}})
        check(called and values.CurrentStunValue == 12.5 and values["GetMaxStun()"] == 100,
            "adapter ignores class-bound metadata callable and uses explicit instance context")
        enumeration_return = {ForEach=function(_,callback) callback(1,{get=function() return component end}) end}
        local listed = Native.components(actor_context)
        check(enumerated and #listed == 1 and listed[1] == component,
            "assert message cannot leak into component getter parameters")
        enumeration_return = {{get=function() return component end}}
        listed = Native.components(actor_context)
        check(#listed == 1 and listed[1] == component,
            "actual UE4SS 1176-style Lua array return works without a ForEach method")
        local valid_second = wrapper(503)
        local plain = {component,{get=function() return valid_second end}}
        local list,format,limited,examined = Native.component_list(plain,64)
        check(#list == 2 and list[1] == component and list[2] == valid_second and format == "lua_table"
            and not limited and examined == 2, "Lua tables accept both direct UObject and wrapped elements")
        check(plain[1] == component and type(plain[2].get) == "function", "enumeration never mutates the original return table")
        list,format,limited,examined = Native.component_list({},64)
        check(#list == 0 and format == "lua_table" and not limited and examined == 0, "empty Lua array is a successful empty enumeration")
        list,format,limited,examined = Native.component_list({false,wrapper(0),{get=function() error("invalid element") end},component},4)
        check(#list == 1 and list[1] == component and examined == 4 and not limited, "invalid elements are skipped but still count toward the scan budget")
        list,format,limited,examined = Native.component_list({component,component,component},2)
        check(#list == 2 and limited and examined == 2, "Lua array enumeration is bounded")
        list,format,limited = Native.component_list({component,component},2)
        check(#list == 2 and not limited, "exactly full Lua array is not incorrectly labeled truncated")
        local touched = 0
        list,format,limited,examined = Native.component_list({ForEach=function(_,callback)
            for index=1,4 do
                if callback(index,{get=function() touched = touched + 1; return component end}) then break end
            end
        end},2)
        check(#list == 2 and format == "tarray" and limited and examined == 2 and touched == 2,
            "native TArray retains wrapper support and stops before unwrapping beyond the budget")
        list,format,limited,examined = Native.component_list({ForEach=function() end},2)
        check(#list == 0 and format == "tarray" and not limited and examined == 0, "empty native TArray is supported")
        check(not pcall(Native.component_list,nil,64) and not pcall(Native.component_list,42,64),
            "unexpected return types fail explicitly instead of being silently treated as empty")
        check(not pcall(Native.component_list,{[0]=component},64)
            and not pcall(Native.component_list,{unexpected=true},64), "unsupported table shapes are not guessed")
        check(not pcall(Native.component_list,{},0), "invalid enumeration budgets fail before iteration")
    end)
    Native.find,Native.member,Native.parameters,Native.once = saved_find,saved_member,saved_parameters,saved_once
    if not adapter_ok then error(adapter_error) end

    local log,now,builds,reads,enumerations = {},0,0,0,0
    local pawn,controller,widget = {id=20},{id=21,world=30},{id=22}
    controller.Pawn = pawn
    actor.world = 30
    local function runtime_log(message) log[#log+1] = message end
    local runtime_ue = {
        live=live,reset=function() end,log=runtime_log,once=function(_,message) runtime_log(message) end,
        local_player=function() return controller,pawn,30 end,
        time=function() return now end,
        world=function(object) return object.world end,
        member=function(object,key) return object[key] end,
        same=function(a,b) return live(a) and live(b) and a.id == b.id end,
        all=function() enumerations = enumerations + 1; return {widget} end,
        target_from_widget=function() return actor end,
        address=function(object) return object.id end,
        name=function(object) return "Fake_" .. object.id end,
    }
    local runtime_reader = {
        build=function() builds = builds + 1; return {} end,
        read=function() reads = reads + 1; return {providers={}} end,
        describe=function() return "STUN_UNRESOLVED fake" end,
    }
    local runtime = require("StunProbeRuntime").new(runtime_ue,config,runtime_reader)
    runtime.update()
    check(reads == 0 and enumerations == 0,"idle probe does no object searches or monster reads")
    runtime.toggle(); runtime.update()
    check(builds == 1 and reads == 1 and enumerations == 1,"capture starts with one bounded target")
    now = 0.1; runtime.update()
    check(reads == 2 and builds == 1 and enumerations == 1,"sampling does not rediscover global objects every tick")
    now = 1.1; runtime.update()
    check(builds == 1 and enumerations == 2,"repeated HUD references do not recreate provider bindings")
    runtime_ue.target_from_widget = function() return nil end
    now = 2.2; runtime.update()
    check(reads == 4,"pinned target remains readable for decay after its HUD target disappears")
    now = config.CaptureSeconds; runtime.update()
    local before_reads = reads
    runtime.update()
    check(reads == before_reads and log[#log]:find("reason=timeout",1,true),"capture times out and returns idle")
    runtime.toggle(); now = now + 0.1
    controller.Pawn = {id=99}; runtime.update()
    check(log[#log]:find("reason=local_context_changed",1,true),"pawn transitions stop capture")
    controller.Pawn = pawn
    runtime.toggle(); runtime.toggle()
    check(log[#log]:find("reason=F6",1,true),"F6 stops the current recording")
    runtime.toggle()
    runtime_ue.target_from_widget = function() return actor end
    runtime_reader.read = function() error("simulated read failure") end
    runtime.update()
    check(log[#log]:find("reason=read_error",1,true),"read failures terminate capture safely")
    require("StunProbeStateTests").run(check)
    return count
end
return M
