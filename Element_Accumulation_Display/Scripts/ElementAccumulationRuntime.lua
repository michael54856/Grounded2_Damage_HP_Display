local Core,Reader,M = require("ElementAccumulationCore"),require("ElementAccumulationReader"),{}
function M.new(ue,config,reader,ui_probe)
    reader = reader or Reader
    local runtime,state = {},{active=false}
    function runtime.stop(reason)
        if not state.active then return end
        ue.log("CAPTURE_END effect=Chill reason=" .. reason .. " samples=" .. state.samples .. " changes=" .. state.changes)
        state = {active=false}
    end
    function runtime.toggle()
        if state.active then runtime.stop("F5"); return end
        local controller,pawn,world = ue.local_player()
        if not controller then ue.log("CAPTURE_NOT_STARTED enter a playable world and press F5"); return end
        ue.reset()
        if ui_probe then ui_probe.reset() end
        local now = ue.time(controller)
        state = {active=true,controller=controller,pawn=pawn,world=world,start=now,last_time=now,
            next_discovery=now,next_ui=now,targets={},reports={},samples=0,changes=0}
        ue.log("CAPTURE_BEGIN effect=Chill seconds=" .. config.CaptureSeconds .. " interval_ms=" .. config.SampleIntervalMs
            .. "; F5=stop; raw temperature/threshold semantics remain unverified; no assumed max=100")
    end
    local function tick()
        if not state.active then return end
        if not ue.live(state.controller) or not ue.live(state.pawn) or ue.world(state.controller) ~= state.world
            or not ue.same(ue.member(state.controller,"Pawn"),state.pawn) then runtime.stop("local_context_changed"); return end
        local now = ue.time(state.controller)
        if now < state.last_time then runtime.stop("clock_reversed"); return end
        state.last_time = now
        if now-state.start >= config.CaptureSeconds then runtime.stop("timeout"); return end
        for id,target in pairs(state.targets) do
            if not ue.live(target.actor) or ue.world(target.actor) ~= state.world then
                ue.log("TARGET_REMOVED id=" .. id)
                state.targets[id],state.reports[id] = nil,nil
            end
        end
        if now >= state.next_discovery then
            state.next_discovery = now + config.DiscoveryInterval
            local count = 0
            for _ in pairs(state.targets) do count = count + 1 end
            for _,widget in ipairs(ue.all("EnemyHealthWidget")) do
                if count >= config.MaxTargets then break end
                local actor = ue.target_from_widget(widget,state.controller,state.world)
                local id = actor and ue.address(actor)
                if id and not state.targets[id] then
                    state.targets[id] = {actor=actor,providers=reader.build(actor,ue,config),next_refresh=now+config.ProviderRefreshInterval}
                    count = count + 1
                    ue.log("TARGET_READY effect=Chill id=" .. id .. " actor=" .. ue.name(actor))
                end
            end
            if count == 0 then ue.once("no-target","WAITING_FOR_TARGET show a monster's native health bar; no random world target") end
        end
        for id,target in pairs(state.targets) do
            if now >= target.next_refresh then
                target.next_refresh = now + config.ProviderRefreshInterval
                target.providers = reader.build(target.actor,ue,config)
            end
            local samples = reader.read(target.actor,target.providers,ue)
            local next_states,raw = {},{}
            for _,provider in ipairs(samples) do
                raw[#raw+1] = "source=" .. provider.path .. " " .. Core.values_text(provider.values)
                if provider.values["GetCurrentBodyTemperatureState()"] ~= nil
                    or type(provider.values["IsFrozen()"]) == "boolean" or type(provider.values.bIsFrozen) == "boolean" then
                    local fingerprint = Core.state(provider)
                    local previous = target.states and target.states[provider.id]
                    local record = previous
                    if not previous or previous.fingerprint ~= fingerprint then
                        state.ui_dirty = true
                        record = {fingerprint=fingerprint,time=now}
                        ue.log((previous and "CHILL_STATE_TRANSITION previous={" .. previous.fingerprint
                            .. "} previous_state_seconds=" .. Core.number(now-previous.time) or "CHILL_STATE_INITIAL")
                            .. " " .. fingerprint .. " target_id=" .. id .. " provider_id=" .. provider.id
                            .. " elapsed=" .. Core.number(now-state.start) .. " source=" .. provider.path)
                    end
                    next_states[provider.id] = record
                end
            end
            target.states = next_states
            table.sort(raw)
            local description = Core.describe(samples)
            local fingerprint = description .. "\n" .. table.concat(raw,"\n")
            if Core.should_report(state.reports[id],fingerprint,now,config.HeartbeatSeconds) then
                if state.reports[id] and state.reports[id].fingerprint ~= fingerprint then state.changes = state.changes + 1 end
                ue.log(description .. " target_id=" .. id .. " elapsed=" .. Core.number(now-state.start))
                for _,line in ipairs(raw) do ue.log("CHILL_VALUES target_id=" .. id .. " " .. line) end
                state.reports[id] = {fingerprint=fingerprint,time=now}
            end
            state.samples = state.samples + 1
        end
        if ui_probe and next(state.targets) ~= nil and (state.ui_dirty or now >= state.next_ui) then
            state.ui_dirty = false
            state.next_ui = now + config.UIProbeInterval
            local ok,err = pcall(ui_probe.scan,state.controller,state.world,state.targets,now-state.start)
            if not ok then ue.once("ui-scan:" .. tostring(err),"UI_PROBE_ERROR " .. tostring(err)) end
        end
    end
    function runtime.update()
        local ok,err = pcall(tick)
        if not ok then ue.log("CAPTURE_ERROR " .. tostring(err)); runtime.stop("read_error") end
    end
    return runtime
end
function M.start(ui_tests_ok)
    assert(type(LoopInGameThreadWithDelay) == "function" and type(ExecuteInGameThread) == "function",
        "official UE4SS game-thread APIs are required")
    local ue,config = require("ElementAccumulationUE"),require("ElementAccumulationConfig")
    assert(config.Effect == "Chill","this diagnostic build supports Chill only")
    local ui_enabled = config.UIProbeEnabled and ui_tests_ok ~= false
    local ui_probe = ui_enabled and require("ElementAccumulationUIProbe").new(ue,config) or nil
    M.active = M.new(ue,config,nil,ui_probe)
    RegisterKeyBind(Key.F5,function()
        ExecuteInGameThread(function()
            local ok,err = pcall(M.active.toggle)
            if not ok then ue.log("TOGGLE_ERROR " .. tostring(err)); M.active.stop("toggle_error") end
        end)
    end)
    M.loop = LoopInGameThreadWithDelay(config.SampleIntervalMs,M.active.update)
    ue.log("LOADED version=0.3.0-alpha; effect=Chill; F5=start/stop " .. config.CaptureSeconds
        .. "s capture; native_status_ui_probe=" .. tostring(ui_enabled)
        .. "; independent cold overlay; no gameplay setters; no Stun_Display dependency")
end
return M
