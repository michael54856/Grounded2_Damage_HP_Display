local Core, Reader, M = require("StunProbeCore"),require("StunProbeReader"),{}
local State = require("StunProbeState")
function M.new(ue,config,reader)
    reader = reader or Reader
    local runtime, state = {}, {active=false}
    function runtime.stop(reason)
        if not state.active then return end
        ue.log("CAPTURE_END reason=" .. tostring(reason) .. " samples=" .. state.samples
            .. " changes=" .. state.changes .. "; scalar observations are not yet a verified stun-bar contract")
        state = {active=false}
    end
    function runtime.toggle()
        if state.active then runtime.stop("F6"); return end
        local controller,pawn,world = ue.local_player()
        if not controller then ue.log("CAPTURE_NOT_STARTED enter a playable world, show a monster health bar, then press F6"); return end
        ue.reset()
        local now = ue.time(controller)
        state = {active=true,controller=controller,pawn=pawn,world=world,start=now,next_discovery=now,
            targets={},reports={},samples=0,changes=0}
        ue.log("CAPTURE_BEGIN seconds=" .. config.CaptureSeconds .. " interval_ms=" .. config.SampleIntervalMs
            .. "; F6=stop; target discovery is local HUD only; no gameplay setters or damage hooks")
    end
    local function tick()
        if not state.active then return end
        if not ue.live(state.controller) or not ue.live(state.pawn) or ue.world(state.controller) ~= state.world
            or not ue.same(ue.member(state.controller,"Pawn"),state.pawn) then runtime.stop("local_context_changed"); return end
        local now = ue.time(state.controller)
        if now < state.start then runtime.stop("clock_reversed"); return end
        if now - state.start >= config.CaptureSeconds then runtime.stop("timeout"); return end
        for id, target in pairs(state.targets) do
            if not ue.live(target.actor) or ue.world(target.actor) ~= state.world then
                ue.log("TARGET_REMOVED id=" .. id)
                state.targets[id],state.reports[id] = nil,nil
            end
        end
        if now >= state.next_discovery then
            state.next_discovery = now + config.DiscoveryInterval
            local count = 0
            for _ in pairs(state.targets) do count = count + 1 end
            for _, widget in ipairs(ue.all("EnemyHealthWidget")) do
                if count >= config.MaxTargets then break end
                local actor = ue.target_from_widget(widget,state.controller,state.world)
                local id = actor and ue.address(actor)
                if id and not state.targets[id] then
                    state.targets[id] = {actor=actor,providers=reader.build(actor,ue,config)}
                    count = count + 1
                    ue.log("TARGET_READY id=" .. id .. " actor=" .. ue.name(actor))
                end
            end
            if count == 0 then ue.once("no-target","WAITING_FOR_TARGET show a monster's native health bar; no random loaded-creature fallback") end
        end
        for id,target in pairs(state.targets) do
            local result = reader.read(target.actor,target.providers,ue,config)
            local next_states = {}
            for _, observed in ipairs(result.states or {}) do
                local previous = target.states and target.states[observed.id]
                local event,record = State.event(previous,observed.observation,now)
                next_states[observed.id] = record
                if event then
                    ue.log(event .. " target_id=" .. id .. " provider_id=" .. observed.id
                        .. " elapsed=" .. Core.number(now - state.start)
                        .. " current=" .. Core.number(observed.values.CurrentStunValue)
                        .. " max=" .. Core.number(observed.values["GetMaxStun()"])
                        .. " ratio=" .. Core.number(observed.values["GetStunRatio()"])
                        .. " source=" .. observed.path)
                end
            end
            -- No state observations -> forget continuity; never replay a stale
            -- state transition if its provider disappears or changes owner.
            target.states = next_states
            local description = reader.describe(result)
            local raw = {}
            for _, provider in ipairs(result.providers) do
                raw[#raw+1] = "source=" .. provider.path .. " " .. Core.values_text(provider.values)
            end
            local fingerprint = description .. "\n" .. table.concat(raw,"\n")
            if Core.should_report(state.reports[id],fingerprint,now,config.HeartbeatSeconds) then
                if state.reports[id] and state.reports[id].fingerprint ~= fingerprint then state.changes = state.changes + 1 end
                ue.log(description .. " target_id=" .. id .. " elapsed=" .. Core.number(now - state.start))
                for _, values in ipairs(raw) do ue.log("STUN_VALUES target_id=" .. id .. " " .. values) end
                state.reports[id] = {fingerprint=fingerprint,time=now}
            end
            state.samples = state.samples + 1
        end
    end
    function runtime.update()
        local ok,err = pcall(tick)
        if not ok then ue.log("CAPTURE_ERROR " .. tostring(err)); runtime.stop("read_error") end
    end
    return runtime
end
function M.start()
    assert(type(LoopInGameThreadWithDelay) == "function" and type(ExecuteInGameThread) == "function",
        "official UE4SS game-thread timer APIs are required")
    local ue, config = require("StunProbeUE"),require("StunProbeConfig")
    M.active = M.new(ue,config)
    RegisterKeyBind(Key.F6,function()
        ExecuteInGameThread(function()
            local ok,err = pcall(M.active.toggle)
            if not ok then ue.log("TOGGLE_ERROR " .. tostring(err)); M.active.stop("toggle_error") end
        end)
    end)
    M.loop = LoopInGameThreadWithDelay(config.SampleIntervalMs,M.active.update)
    ue.log("LOADED version=0.3.3-alpha; F6=start/stop " .. config.CaptureSeconds .. "s stun capture; component_arrays=table_or_tarray; unbound_getters=true; state_getters=enum_and_bool; UI=auto")
end
return M
