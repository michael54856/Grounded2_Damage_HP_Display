-- One sampling/render transaction for every visible effect. This makes row
-- compaction atomic rather than letting independent effect loops compete.
local Order,DefaultReader,M=require("ElementDisplayOrder"),require("ElementAccumulationReader"),{}
function M.new(ue,config,probe_config,effects)
    local runtime,state,idle_ticks={},nil,0
    local by_id={}
    for _,effect in ipairs(effects) do
        assert(not by_id[effect.id],"duplicate effect id " .. effect.id)
        by_id[effect.id]=effect
    end
    local function hide(effect)
        pcall(effect.ui.hide)
    end
    function runtime.clear()
        for _,effect in ipairs(effects) do
            pcall(effect.ui.clear)
            if effect.ue ~= ue and effect.ue.reset then effect.ue.reset() end
        end
        ue.reset()
        if ue.reset_layout then ue.reset_layout() end
        state=nil
    end
    local function context_valid()
        return ue.live(state.controller) and ue.live(state.pawn) and ue.world(state.controller) == state.world
            and ue.same(ue.member(state.controller,"Pawn"),state.pawn)
    end
    local function cache_widget(widget)
        if not ue.hud_widget(widget,state.controller,state.world) then return end
        local id=ue.address(widget)
        if not id then return end
        local count=0; for _ in pairs(state.widgets) do count=count+1 end
        if state.widgets[id] or count < config.MaxCachedWidgets then state.widgets[id]=widget end
    end
    local function read_effect(effect,target,now)
        local reader=effect.reader or DefaultReader
        local source=target.sources[effect.id]
        if not source then
            source={providers=reader.build(target.actor,effect.ue,probe_config),next_rebuild=now+config.DiscoveryInterval}
            target.sources[effect.id]=source
        end
        local model,reason=effect.core.model(reader.read(target.actor,source.providers,effect.ue,probe_config),effect.config)
        if not model and not effect.core.inactive(reason) and now >= source.next_rebuild then
            source.next_rebuild=now+config.DiscoveryInterval
            source.providers=reader.build(target.actor,effect.ue,probe_config)
            model,reason=effect.core.model(reader.read(target.actor,source.providers,effect.ue,probe_config),effect.config)
        end
        if not model and not effect.core.inactive(reason) then
            effect.ue.once(effect.id .. "-unavailable:" .. tostring(ue.address(target.actor)) .. ":" .. tostring(reason),
                effect.tag .. "_BAR_UNAVAILABLE reason=" .. tostring(reason) .. " actor=" .. ue.name(target.actor))
        end
        return model
    end
    local function sample_target(target,now)
        local models,active={},{}
        for _,effect in ipairs(effects) do
            local status=state.effects[effect.id]
            if effect.config.Enabled and status.prepared and now >= status.retry_at then
                local ok,model=pcall(read_effect,effect,target,now)
                if ok and model then models[effect.id]=model; active[#active+1]=effect.id
                elseif not ok then
                    effect.ue.once(effect.id .. "-read:" .. tostring(model),effect.tag .. "_BAR_READ_ERROR " .. tostring(model))
                end
            end
        end
        target.order=Order.update(target.order,active,config.MaxEffectRows)
        return models
    end
    local function prune_targets(seen)
        local count=0
        for _ in pairs(state.targets) do count=count+1 end
        local limit=math.max(config.MaxBars,config.MaxCachedTargets or config.MaxCachedWidgets)
        while count > limit do
            local oldest_id,oldest
            for id,target in pairs(state.targets) do
                if not seen[id] and (not oldest or target.last_seen < oldest) then oldest_id,oldest=id,target.last_seen end
            end
            if not oldest_id then break end
            state.targets[oldest_id]=nil; count=count-1
        end
    end
    local function tick(candidates)
        local enabled=false
        for _,effect in ipairs(effects) do if effect.config.Enabled then enabled=true; break end end
        if not enabled then if state then runtime.clear() end; return end
        if state and not context_valid() then runtime.clear() end
        if not state then
            if type(candidates) == "table" then idle_ticks=0 end
            if idle_ticks > 0 then idle_ticks=idle_ticks-1; return end
            idle_ticks=math.max(0,math.ceil(config.DiscoveryInterval*1000/config.UpdateIntervalMs)-1)
            local controller,pawn,world=ue.local_player()
            if not controller then return end
            state={controller=controller,pawn=pawn,world=world,widgets={},targets={},effects={},next_discovery=0}
            for _,effect in ipairs(effects) do state.effects[effect.id]={prepared=false,retry_at=0} end
            idle_ticks=0
        end
        local now=ue.time(state.controller)
        if state.last_time and now < state.last_time then runtime.clear(); return end
        state.last_time=now
        for _,effect in ipairs(effects) do
            local status=state.effects[effect.id]
            if effect.config.Enabled and not status.prepared and now >= status.retry_at then
                local ok,err=pcall(effect.ui.prepare,state.controller)
                if ok then status.prepared=true
                else
                    status.retry_at=now+config.ErrorRetrySeconds
                    hide(effect)
                    effect.ue.once(effect.id .. "-prepare:" .. tostring(err),effect.tag .. "_UI_ERROR " .. tostring(err))
                end
            end
        end
        if now >= state.next_discovery then
            state.next_discovery=now+config.DiscoveryInterval
            state.widgets={}
            for _,widget in ipairs(ue.all("EnemyHealthWidget")) do cache_widget(widget) end
            for id,target in pairs(state.targets) do
                if not ue.live(target.actor) or ue.world(target.actor) ~= state.world then state.targets[id]=nil end
            end
        end
        if type(candidates) == "table" then for _,widget in ipairs(candidates) do cache_widget(widget) end end
        local entries,ids,sampled,seen,viewport,count={},{},{},{},nil,0
        for _,effect in ipairs(effects) do entries[effect.id]={} end
        for id in pairs(state.widgets) do ids[#ids+1]=id end
        table.sort(ids)
        for _,hud_id in ipairs(ids) do
            if count >= config.MaxBars then break end
            local widget=state.widgets[hud_id]
            local actor=ue.target_from_widget(widget,state.controller,state.world)
            local actor_id=actor and ue.address(actor)
            if actor_id then
                count=count+1
                seen[actor_id]=true
                local target=state.targets[actor_id]
                if not target or not ue.same(target.actor,actor) then
                    target={actor=actor,sources={},order={}}
                    state.targets[actor_id]=target
                end
                target.last_seen=now
                local models=sampled[actor_id]
                if not models then models=sample_target(target,now); sampled[actor_id]=models end
                local bar=ue.member(widget,"HealthBar")
                if #target.order > 0 and ue.live(bar) and ue.is_a(bar,"/Script/UMG.ProgressBar")
                    and ue.visible(widget) and ue.visible(bar) then
                    viewport=viewport or ue.viewport(state.controller)
                    local ok,health=pcall(ue.widget_rect,bar,state.controller)
                    if ok and health and viewport then
                        for row,id in ipairs(target.order) do
                            local effect=by_id[id]
                            local rect=effect.core.rect(health,viewport,effect.config,row)
                            if rect then entries[id][#entries[id]+1]={model=models[id],rect=rect,
                                key=tostring(hud_id) .. ":" .. tostring(actor_id) .. ":" .. id} end
                        end
                    elseif not ok then ue.once("element-geometry:" .. tostring(health),"ELEMENT_LAYOUT_ERROR " .. tostring(health)) end
                end
            end
        end
        prune_targets(seen)
        for _,effect in ipairs(effects) do
            local status=state.effects[effect.id]
            if effect.config.Enabled and status.prepared and now >= status.retry_at then
                local ok,err=pcall(effect.ui.render,state.controller,entries[effect.id],now)
                if not ok then
                    status.retry_at=now+config.ErrorRetrySeconds
                    hide(effect)
                    effect.ue.once(effect.id .. "-render:" .. tostring(err),effect.tag .. "_UI_ERROR " .. tostring(err))
                end
            else hide(effect) end
        end
    end
    function runtime.update(candidates)
        local ok,err=pcall(tick,candidates)
        if not ok then
            for _,effect in ipairs(effects) do hide(effect) end
            ue.once("element-ui:" .. tostring(err),"ELEMENT_UI_ERROR " .. tostring(err))
        end
    end
    return runtime
end
function M.start(ready)
    local ue,config=require("ChillDisplayUE"),require("ChillDisplayConfig")
    local effects={}
    if ready.CHILL then
        effects[#effects+1]={id="ice",tag="CHILL",ue=ue,config=config,core=require("ChillDisplayCore"),
            ui=require("ChillDisplayUI").new(ue,config)}
    end
    if ready.SOUR then
        local sour_ue,sour_config=require("SourDisplayUE").new(),require("SourDisplayConfig")
        effects[#effects+1]={id="sour",tag="SOUR",ue=sour_ue,config=sour_config,core=require("SourDisplayCore"),
            ui=require("ChillDisplayUI").new(sour_ue,sour_config,{Tag="SOUR",WidgetPrefix="G2Sour",IconFile="sour_icon.png",
                Phases={"sour"},Colors={sour=sour_config.SourColor}})}
    end
    if ready.SPICY then
        local spicy_ue,spicy_config=require("SpicyDisplayUE").new(),require("SpicyDisplayConfig")
        effects[#effects+1]={id="spicy",tag="SPICY",ue=spicy_ue,config=spicy_config,core=require("SpicyDisplayCore"),
            maximum_source="native_MaxSizzle",
            ui=require("ChillDisplayUI").new(spicy_ue,spicy_config,{Tag="SPICY",WidgetPrefix="G2Spicy",IconFile="spicy_icon.png",
                Phases={"spicy"},Colors={spicy=spicy_config.SpicyColor}})}
    end
    if ready.POISON then
        local poison_ue,poison_config=require("PoisonDisplayUE").new(),require("PoisonDisplayConfig")
        effects[#effects+1]={id="poison",tag="POISON",ue=poison_ue,config=poison_config,core=require("PoisonDisplayCore"),
            ui=require("ChillDisplayUI").new(poison_ue,poison_config,{Tag="POISON",WidgetPrefix="G2Poison",IconFile="poison_icon.png",
                Phases={"poison"},Colors={poison=poison_config.PoisonColor}})}
    end
    if ready.WOOZY then
        local woozy_ue,woozy_config=require("WoozyDisplayUE").new(),require("WoozyDisplayConfig")
        effects[#effects+1]={id="woozy",tag="WOOZY",ue=woozy_ue,config=woozy_config,core=require("WoozyDisplayCore"),
            ui=require("ChillDisplayUI").new(woozy_ue,woozy_config,{Tag="WOOZY",WidgetPrefix="G2Woozy",IconFile="dizzy_icon.png",
                Phases={"woozy"},Colors={woozy=woozy_config.WoozyColor}})}
    end
    if #effects == 0 then return end
    M.active=M.new(ue,config,require("ElementAccumulationConfig"),effects)
    M.events=require("ChillDisplayEvents").new(ue,RegisterHook,NotifyOnNewObject,ExecuteInGameThread,
        function(widgets) M.active.update(widgets) end,"ELEMENT")
    M.events.prepare()
    M.loop=LoopInGameThreadWithDelay(config.UpdateIntervalMs,M.active.update)
    for _,effect in ipairs(effects) do
        local reference=effect.config.ReferenceMaximum
        ue.log(effect.tag .. "_UI_LOADED version=0.7.0-alpha; sample_ms=" .. config.UpdateIntervalMs
            .. "; ordering=activation_order" .. (reference and "; reference_max=" .. reference
                .. "; max_source=configured_observed_reference" or effect.maximum_source
                and "; max_source=" .. effect.maximum_source or ""))
    end
    ue.log("ELEMENT_UI_LOADED version=0.7.0-alpha; effects=" .. #effects .. "; sample_ms=" .. config.UpdateIntervalMs
        .. "; ordering=per_target_activation; compact=true; rows=" .. config.MaxEffectRows)
end
return M
