-- All UObject/UMG objects below are fakes; no native getters or UI writes.
local M = {}
function M.run()
    local checks = 0
    local function check(value,message) assert(value,"UI probe self-test: " .. message); checks=checks+1 end
    local config = {MaxUIClasses=32,MaxUIClassDepth=4,MaxUIFields=128,MaxUIFunctions=96,
        MaxUINodes=48,MaxUIDepth=7,MaxUIChildren=32,MaxUIWidgets=2,UIHeartbeatSeconds=5}
    local function property(key,kind,struct)
        return {GetFName=function() return {ToString=function() return key end} end,
            GetFullName=function() return kind .. " /Test.Widget:" .. key end,
            GetStruct=function() return {GetFullName=function() return struct end} end}
    end
    local function class(name,properties,functions)
        return {name=name,GetSuperStruct=function() return nil end,
            ForEachProperty=function(_,callback) for _,p in ipairs(properties or {}) do if callback(p) then break end end end,
            ForEachFunction=function(_,callback) for _,fn in ipairs(functions or {}) do if callback(fn) then break end end end}
    end
    local metadata_calls = 0
    local fn = setmetatable({name="Function /Test.StatusRow:RefreshItems",GetFName=function()
        return {ToString=function() return "RefreshItems" end} end},
        {__call=function() metadata_calls=metadata_calls+1; error("UI metadata function must not execute") end})
    local actor,controller = {id=99},{id=98}
    local hud = {id=1,name="UI_EnemyHealth_C /Test.HUD",user=true,children={}}
    local row = {id=2,name="UI_StatusEffectTimerRow_C /Test.HUD.Row",user=true,owner=hud}
    local panel = {id=3,name="HorizontalBox /Test.HUD.Row.Box",panel=true,owner=hud,children={}}
    -- Dynamic status entries can have PlayerController as outer, while still
    -- being canonical panel children. Reflected foreign pointers are rejected.
    local item = {id=4,name="UI_StatusEffectTimer_C /Test.DynamicIcon",owner=controller}
    local foreign = {id=5,name="UI_Foreign /Test.OtherPlayer",owner=controller}
    hud.class = class("Class Test.HUD",{property("UI_StatusEffectTimerRow","ObjectProperty"),property("StatusOtherPlayer","ObjectProperty")})
    row.class = class("Class Test.Row",{}, {fn})
    panel.class = class("Class Test.Panel")
    item.class = class("Class Test.Item",{property("StatusEffectRowHandle","StructProperty","ScriptStruct /Script/Engine.DataTableRowHandle"),
        property("RemainingDuration","FloatProperty"),property("Brush","StructProperty","ScriptStruct /Script/SlateCore.SlateBrush")})
    foreign.class = class("Class Test.Foreign")
    for _,object in ipairs({hud,row,panel,item,foreign}) do object.GetClass=function(self) return self.class end end
    hud.UI_StatusEffectTimerRow,hud.StatusOtherPlayer = row,foreign
    row.WidgetTree = {RootWidget=panel}
    panel.children = {item}
    item.StatusEffectRowHandle = {RowName={ToString=function() return "Chilling_Test" end},DataTable={name="DataTable Test.Effects"}}
    item.RemainingDuration = 3
    item.Brush = {ResourceObject={name="Texture2D Test.ChillIcon"}}
    local logs,calls,signature_ok,visible,extra,child_count = {},{},true,true,false,nil
    local function log(value) logs[#logs+1]=value end
    local ue = {
        valid=function(object) return object ~= nil end,live=function(object) return object ~= nil end,
        name=function(object) return object and object.name or "INVALID" end,
        member=function(object,key) if object then return object[key] end end,
        same=function(a,b) return a == b end,address=function(object) return object and object.id end,
        world=function() return 7 end,unwrap=function(object) return object end,
        belongs=function(object,owner) return object.owner == owner end,
        is_a=function(object,path)
            if not object then return false end
            if path == "/Script/UMG.Widget" then return object.GetClass ~= nil end
            if path == "/Script/UMG.UserWidget" then return object.user == true end
            if path == "/Script/UMG.PanelWidget" then return object.panel == true end
        end,
        all=function() return extra and {hud,foreign} or {hud} end,
        target_from_widget=function(object,owner,world)
            if visible and object == hud and owner == controller and world == 7 then return actor end
        end,
        log=log,once=function(_,value) log(value) end,find=function(path) return {path=path} end,
        parameters=function(method)
            if not signature_ok then return {} end
            if method.path and method.path:find("GetChildrenCount",1,true) then return {{key="ReturnValue",kind="IntProperty"}} end
            if method.path then return {{key="Index",kind="IntProperty"},{key="ReturnValue",kind="ObjectProperty"}} end
            return {}
        end,
        call=function(object,path,...)
            check(object == panel,"native child getters use the actual live panel context")
            if path:find("GetChildrenCount",1,true) then
                check(select("#",...) == 0,"count getter gets no extra parameters")
                calls[#calls+1]="count"; return child_count or #object.children
            end
            check(select("#",...) == 1,"child getter gets exactly one index")
            local index = ...
            calls[#calls+1]=index
            return object.children[index+1]
        end,
    }
    local probe = require("ElementAccumulationUIProbe").new(ue,config)
    local targets = {[99]={actor=actor}}
    probe.scan(controller,7,targets,0)
    local function contains(marker,start)
        for i=(start or 0)+1,#logs do if logs[i]:find(marker,1,true) then return true end end
        return false
    end
    check(contains("UI_SNAPSHOT") and contains("UI_StatusEffectTimerRow_C"),"live status row is reached through its reflected HUD field")
    check(contains("UI_NODE id=4") and not contains("UI_NODE id=5"),"canonical dynamic panel children are accepted while foreign references are not traversed")
    check(calls[2] == 0,"native child indices are zero based")
    check(contains("row=Chilling_Test") and contains("RemainingDuration"),"copied row names and duration data can identify the status icon")
    check(contains("UI_BRUSH") and contains("Test.ChillIcon"),"typed brush metadata can identify the original icon texture without changing it")
    check(metadata_calls == 0 and contains("invoke=false"),"UI update/refresh functions are inspected but never called")
    local before=#logs
    probe.scan(controller,7,targets,1)
    check(not contains("UI_SNAPSHOT",before),"unchanged structure does not flood output before heartbeat")
    item.RemainingDuration=2
    before=#logs; probe.scan(controller,7,targets,2)
    check(contains("UI_SNAPSHOT",before),"status data changes produce a new snapshot")
    visible=false; before=#logs; probe.scan(controller,7,targets,3)
    check(contains("UI_TARGET_NOT_VISIBLE",before),"hidden or recycled HUDs drop old snapshot continuity")
    visible=true; before=#logs; probe.scan(controller,7,{[100]={actor={id=100}}},4)
    check(not contains("UI_SNAPSHOT",before),"a different current target cannot be matched to the pinned monster")
    signature_ok=false; probe.reset(); calls={}; before=#logs
    probe.scan(controller,7,targets,5)
    check(#calls == 0 and contains("UI_API_UNAVAILABLE",before),"unexpected native signatures disable child calls")
    signature_ok=true; probe.reset(); child_count=1000; calls={}; before=#logs
    probe.scan(controller,7,targets,6)
    check(#calls == config.MaxUIChildren+1 and contains("limited=true",before),"child enumeration is bounded even for large native counts")
    local now,reads,ui_scans,resets,fail_ui,scope_ok = 0,0,0,0,false,false
    local pawn = {}
    controller.Pawn = pawn
    local values = {CurrentBodyTemperature=0,MaxChill=-100,["GetCurrentBodyTemperatureState()"]=2,["IsFrozen()"]=false}
    local integration_logs = {}
    local runtime_ue = {live=function(object) return object ~= nil end,reset=function() end,
        local_player=function() return controller,pawn,7 end,world=function() return 7 end,
        same=ue.same,member=ue.member,address=ue.address,time=function() return now end,
        all=function() return {hud} end,target_from_widget=function() return actor end,
        name=function() return "FakeCreature" end,log=function(message) integration_logs[#integration_logs+1]=message end,
        once=function(_,message) integration_logs[#integration_logs+1]=message end}
    local runtime_config = {CaptureSeconds=600,SampleIntervalMs=100,DiscoveryInterval=1,ProviderRefreshInterval=2,
        HeartbeatSeconds=2,MaxTargets=1,UIProbeInterval=0.25}
    local ui_probe = {reset=function() resets=resets+1 end,
        scan=function(_,world,pinned)
            ui_scans=ui_scans+1
            scope_ok = world == 7 and pinned and pinned[99] and pinned[99].actor == actor
            if fail_ui then error("fake UI unavailable") end
        end}
    local runtime = require("ElementAccumulationRuntime").new(runtime_ue,runtime_config,
        {build=function() return {} end,read=function() reads=reads+1; return {{id=10,path="Fake.Temp",values=values}} end},ui_probe)
    runtime.update()
    check(ui_scans == 0 and reads == 0,"UI diagnostics are idle until F5 capture starts")
    runtime.toggle(); runtime.update()
    now=0.1; runtime.update()
    check(ui_scans == 1 and reads == 2 and resets == 1 and scope_ok,
        "UI inspection receives the pinned monster/world, has its own cadence and resets per capture")
    values["GetCurrentBodyTemperatureState()"],values["IsFrozen()"],now=0,true,0.2; runtime.update()
    check(ui_scans == 2,"freeze transitions trigger UI inspection without waiting for the interval")
    fail_ui=true
    values["GetCurrentBodyTemperatureState()"],values["IsFrozen()"],now=1,false,0.3; runtime.update()
    local before_reads=reads
    now=0.4; runtime.update(); runtime.toggle()
    check(reads == before_reads+1 and integration_logs[#integration_logs]:find("reason=F5",1,true),
        "UI inspection errors do not stop otherwise valid cold sampling")
    return checks
end
return M
