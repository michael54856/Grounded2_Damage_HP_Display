local Core,Reader,M = require("StunDisplayCore"),require("StunProbeReader"),{}
function M.new(ue,config,probe_config,ui,reader)
    reader = reader or Reader
    local runtime,state,idle_ticks,error_ticks = {},nil,0,0
    function runtime.clear()
        ui.clear()
        ue.reset()
        state = nil
    end
    local function context_valid()
        return ue.live(state.controller) and ue.live(state.pawn) and ue.world(state.controller) == state.world
            and ue.same(ue.member(state.controller,"Pawn"),state.pawn)
    end
    local function signal(widget)
        if not ue.live(widget) then return "invalid" end
        if ue.member(widget,"bShowing") ~= true then return "hidden" end
        return "show:" .. tostring(ue.address(ue.member(widget,"TargetActor")))
    end
    local function cache_widget(widget)
        if not ue.hud_widget(widget,state.controller,state.world) then return end
        local id = ue.address(widget)
        if not id then return end
        local count = 0
        for _ in pairs(state.widgets) do count = count + 1 end
        if state.widgets[id] or count < config.MaxCachedWidgets then
            state.widgets[id],state.signals[id] = widget,signal(widget)
        end
    end
    local function tick(candidates)
        if not config.Enabled then if state then runtime.clear() end; return end
        if state and not context_valid() then runtime.clear() end
        if not state then
            if type(candidates) == "table" then idle_ticks = 0 end
            if idle_ticks > 0 then idle_ticks = idle_ticks - 1; return end
            idle_ticks = math.max(0,math.ceil(config.DiscoveryInterval*1000/config.UpdateIntervalMs)-1)
            local controller,pawn,world = ue.local_player()
            if not controller then return end
            state = {controller=controller,pawn=pawn,world=world,records={},widgets={},signals={},
                next_discovery=0,followup_frames=0}
            idle_ticks = 0
        end
        if not state.prepared then ui.prepare(state.controller); state.prepared = true end
        local now = ue.time(state.controller)
        if state.last_time and now < state.last_time then runtime.clear(); return end
        state.last_time = now
        if now >= state.next_discovery then
            state.next_discovery = now + config.DiscoveryInterval
            state.widgets,state.signals = {},{}
            -- Include hidden widgets: visibility can change between global scans.
            for _,widget in ipairs(ue.all("EnemyHealthWidget")) do cache_widget(widget) end
            for id in pairs(state.records) do
                if not state.widgets[id] then state.records[id] = nil end
            end
        end
        if type(candidates) == "table" then
            for _,widget in ipairs(candidates) do cache_widget(widget) end
            if #candidates > 0 then state.followup_frames = config.AppearanceRetryFrames end
        end
        local entries,viewport,count = {},nil,0
        state.layout_pending = false
        for id,widget in pairs(state.widgets) do
            if count >= config.MaxBars then break end
            local actor = ue.target_from_widget(widget,state.controller,state.world)
            state.signals[id] = signal(widget)
            if actor and ue.live(ue.member(widget,"HealthBar")) then
                count = count + 1
                local record = state.records[id]
                -- Recycled HUD widget: bind its new actor immediately, not at the
                -- next global scan. Hidden records are retained for quick reuse.
                if not record or not ue.same(record.actor,actor) then
                    record = {actor=actor,providers=reader.build(actor,ue,probe_config),
                        next_rebuild=now+config.DiscoveryInterval}
                    state.records[id] = record
                    state.followup_frames = config.AppearanceRetryFrames
                end
                if not record.showing then state.followup_frames = config.AppearanceRetryFrames end
                record.showing = true
                local ok,entry = pcall(function()
                    if not ue.visible(widget) then state.layout_pending = true; return nil end
                    local result = reader.read(actor,record.providers,ue,probe_config)
                    local model = Core.model(result)
                    if not model and now >= record.next_rebuild then
                        record.next_rebuild = now + config.DiscoveryInterval
                        record.providers = reader.build(actor,ue,probe_config)
                        model = Core.model(reader.read(actor,record.providers,ue,probe_config))
                    end
                    if not model then
                        ue.once("stun-ui-unresolved:" .. tostring(ue.address(actor)),
                            "STUN_BAR_UNAVAILABLE no verified current/max/state for " .. ue.name(actor))
                        return nil
                    end
                    viewport = viewport or ue.viewport(state.controller)
                    if not viewport then return nil end
                    local rect = ue.bar_rect(state.controller,ue.member(widget,"HealthBar"),viewport,config)
                    if rect then return {model=model,rect=rect,key=tostring(id) .. ":" .. tostring(ue.address(actor))} end
                    state.layout_pending = true
                end)
                if ok and entry then entries[#entries+1] = entry
                elseif not ok then ue.once("stun-bar-read:" .. tostring(entry),"STUN_BAR_READ_ERROR " .. tostring(entry)) end
            elseif state.records[id] then
                state.records[id].showing = false
            end
        end
        if not state.layout_pending then state.followup_frames = 0 end
        ui.render(state.controller,entries,now)
    end
    function runtime.update(candidates)
        if error_ticks > 0 then
            -- Only the normal timer advances error backoff, not fast HUD events.
            if candidates == nil then error_ticks = error_ticks - 1 end
            return
        end
        local ok,err = pcall(tick,candidates)
        if not ok then
            ui.hide()
            error_ticks = math.ceil(config.ErrorRetrySeconds*1000/config.UpdateIntervalMs)
            ue.once("stun-ui:" .. tostring(err),"STUN_UI_ERROR " .. tostring(err))
        end
    end
    function runtime.animate()
        if not state or not config.Enabled or error_ticks > 0 or not ui.has_active() then return end
        local ok,err = pcall(function()
            if not ue.live(state.controller) then ui.hide(); return end
            ui.animate(ue.time(state.controller))
        end)
        if not ok then
            ui.hide()
            ue.once("stun-animation:" .. tostring(err),"STUN_ANIMATION_ERROR " .. tostring(err))
        end
    end
    function runtime.fast()
        if not state or not config.Enabled or error_ticks > 0 then return end
        local ok,err = pcall(function()
            if not context_valid() then runtime.clear(); return end
            local changed = false
            -- Inspect only cached local HUD flags; no global scans, stun reads or
            -- geometry calls on unchanged animation frames.
            for id,widget in pairs(state.widgets) do
                local next_signal = signal(widget)
                if state.signals[id] ~= next_signal then changed = true; state.signals[id] = next_signal end
            end
            if changed then
                state.followup_frames = config.AppearanceRetryFrames
                runtime.update({})
            elseif state.layout_pending and state.followup_frames > 0 then
                state.followup_frames = state.followup_frames - 1
                runtime.update({})
            end
            runtime.animate()
        end)
        if not ok then
            ui.hide()
            ue.once("stun-visibility:" .. tostring(err),"STUN_VISIBILITY_ERROR " .. tostring(err))
        end
    end
    return runtime
end
function M.start()
    local ue,config = require("StunDisplayUE"),require("StunDisplayConfig")
    local ui = require("StunDisplayUI").new(ue,config)
    M.active = M.new(ue,config,require("StunProbeConfig"),ui)
    M.events = require("StunDisplayEvents").new(ue,RegisterHook,NotifyOnNewObject,ExecuteInGameThread,
        function(widgets) M.active.update(widgets) end)
    M.events.prepare()
    M.loop = LoopInGameThreadWithDelay(config.UpdateIntervalMs,M.active.update)
    M.animation_loop = LoopInGameThreadWithDelay(config.AnimationIntervalMs,M.active.fast)
    ue.log("STUN_UI_LOADED version=0.3.3-alpha; auto_display=" .. tostring(config.Enabled)
        .. "; sample_ms=" .. config.UpdateIntervalMs .. "; animation_ms=" .. config.AnimationIntervalMs
        .. "; visibility=cached_flags_and_native_events; preload=true; F6=diagnostic_capture_only")
end
return M
