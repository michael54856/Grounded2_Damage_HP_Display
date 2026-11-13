local Core,Reader,M=require("SourProbeCore"),require("ElementAccumulationReader"),{}
function M.new(ue,config,reader)
    reader=reader or Reader
    local runtime,state={},{active=false}
    function runtime.stop(reason)
        if not state.active then return end
        ue.log("SOUR_CAPTURE_END reason=" .. reason .. " samples=" .. state.samples .. " changes=" .. state.changes)
        state={active=false}
    end
    function runtime.toggle()
        if state.active then runtime.stop("F5"); return end
        local controller,pawn,world=ue.local_player()
        if not controller then ue.log("SOUR_CAPTURE_NOT_STARTED enter a playable world and press F5"); return end
        ue.reset()
        local now=ue.time(controller)
        state={active=true,controller=controller,pawn=pawn,world=world,start=now,last_time=now,
            next_discovery=now,target=nil,levels={},peaks={},samples=0,changes=0}
        ue.log("SOUR_CAPTURE_BEGIN seconds=" .. config.CaptureSeconds .. " interval_ms=" .. config.SampleIntervalMs
            .. "; F5=stop; target=pinned_first_local_enemy_hud; no assumed max; properties_only=true")
    end
    local function tick()
        if not state.active then return end
        if not ue.live(state.controller) or not ue.live(state.pawn) or ue.world(state.controller) ~= state.world
            or not ue.same(ue.member(state.controller,"Pawn"),state.pawn) then runtime.stop("local_context_changed"); return end
        local now=ue.time(state.controller)
        if now < state.last_time then runtime.stop("clock_reversed"); return end
        state.last_time=now
        if now-state.start >= config.CaptureSeconds then runtime.stop("timeout"); return end
        if state.target and (not ue.live(state.target.actor) or ue.world(state.target.actor) ~= state.world) then
            runtime.stop("target_unavailable"); return
        end
        if not state.target and now >= state.next_discovery then
            state.next_discovery=now+config.DiscoveryInterval
            for _,widget in ipairs(ue.all("EnemyHealthWidget")) do
                local actor=ue.target_from_widget(widget,state.controller,state.world)
                if actor then
                    state.target={actor=actor,id=ue.address(actor),providers=reader.build(actor,ue,config),
                        next_refresh=now+config.ProviderRefreshInterval}
                    ue.log("SOUR_TARGET_READY target_id=" .. tostring(state.target.id) .. " actor=" .. ue.name(actor))
                    break
                end
            end
            if not state.target then ue.once("no-target","SOUR_WAITING_FOR_TARGET show the intended monster's native health bar") end
        end
        local target=state.target
        if not target then return end
        if now >= target.next_refresh then
            target.next_refresh=now+config.ProviderRefreshInterval
            target.providers=reader.build(target.actor,ue,config)
        end
        local samples=reader.read(target.actor,target.providers,ue)
        local lines,transitions,current_sources={},{},0
        for _,provider in ipairs(samples) do
            lines[#lines+1]=Core.describe(provider)
            lines[#lines+1]="SOUR_VALUES provider_id=" .. provider.id .. " source=" .. provider.path
                .. " " .. Core.values_text(provider.values)
            local value=provider.values.CurrentCorrosionLevel
            if Core.finite(value) then
                current_sources=current_sources+1
                local previous=state.levels[provider.id]
                local peak=math.max(state.peaks[provider.id] or value,value)
                state.peaks[provider.id]=peak
                if previous ~= nil and previous ~= value then
                    transitions[#transitions+1]="SOUR_LEVEL_CHANGE provider_id=" .. provider.id
                        .. " direction=" .. (value > previous and "rise" or "fall")
                        .. " previous=" .. Core.number(previous) .. " current=" .. Core.number(value)
                        .. " observed_peak=" .. Core.number(peak) .. " interpretation=unverified"
                end
                state.levels[provider.id]=value
            end
        end
        if current_sources == 0 then
            ue.once("unresolved:" .. tostring(target.id),"SOUR_UNRESOLVED no direct CurrentCorrosionLevel yet; schema/other fields retained")
        elseif current_sources > 1 then
            ue.once("ambiguous:" .. tostring(target.id),"SOUR_MULTIPLE_SOURCES count=" .. current_sources .. "; values remain separate")
        end
        table.sort(lines)
        local fingerprint=table.concat(lines,"\n")
        if Core.should_report(state.report,fingerprint,now,config.HeartbeatSeconds) then
            if state.report and state.report.fingerprint ~= fingerprint then state.changes=state.changes+1 end
            ue.log("SOUR_SNAPSHOT target_id=" .. tostring(target.id) .. " elapsed=" .. Core.number(now-state.start)
                .. " providers=" .. #samples .. " current_sources=" .. current_sources)
            for _,line in ipairs(lines) do ue.log(line .. " target_id=" .. tostring(target.id)
                .. " elapsed=" .. Core.number(now-state.start)) end
            state.report={fingerprint=fingerprint,time=now}
        end
        for _,line in ipairs(transitions) do ue.log(line .. " target_id=" .. tostring(target.id)
            .. " elapsed=" .. Core.number(now-state.start)) end
        state.samples=state.samples+1
    end
    function runtime.update()
        local ok,err=pcall(tick)
        if not ok then ue.log("SOUR_CAPTURE_ERROR " .. tostring(err)); runtime.stop("read_error") end
    end
    return runtime
end
function M.start()
    assert(type(LoopInGameThreadWithDelay) == "function" and type(ExecuteInGameThread) == "function",
        "official UE4SS game-thread APIs are required")
    local config=require("ElementAccumulationConfig")
    assert(config.Effect == "Sour","Sour probe requires Effect=Sour")
    local ue=require("SourProbeUE").new(nil,config)
    M.active=M.new(ue,config)
    RegisterKeyBind(Key.F5,function()
        ExecuteInGameThread(function()
            local ok,err=pcall(M.active.toggle)
            if not ok then ue.log("SOUR_TOGGLE_ERROR " .. tostring(err)); M.active.stop("toggle_error") end
        end)
    end)
    M.loop=LoopInGameThreadWithDelay(config.SampleIntervalMs,M.active.update)
    ue.log("SOUR_PROBE_LOADED version=0.3.1-probe; F5=start/stop " .. config.CaptureSeconds
        .. "s; properties_only=true; cold_overlay_preserved=true")
end
return M
