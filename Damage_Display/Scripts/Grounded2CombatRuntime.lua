local UE, Core, Config = require("Grounded2CombatUE"), require("Grounded2CombatCore"), require("Grounded2CombatConfig")
local UI = require("Grounded2CombatUI")
local M = {}
local state = {
    health_enabled = Config.HealthEnabled, damage_enabled = Config.DamageEnabled,
    queue = Core.queue(Config.MaxQueuedEvents), ui = UI.new(),
    hooks = {}, callbacks = 0, accepted = 0, elapsed = 0, next_discovery = 0,
    next_health = 0, next_overlay = 0, next_status = 0,
    controller = nil, controller_id = nil, world = nil, world_id = nil,
}

local function clear_context(reason)
    if state.controller_id ~= nil then
        UE.log("CONTEXT_CLEARED reason=" .. tostring(reason)
            .. " controller_id=" .. tostring(state.controller_id) .. " world_id=" .. tostring(state.world_id))
    end
    state.ui:clear()
    state.queue.events = {}
    state.controller, state.controller_id, state.world, state.world_id = nil, nil, nil, nil
    state.next_health, state.next_overlay = 0, 0
end

local function observe(indices, context, ...)
    if not state.damage_enabled or not UE.live(state.controller) then return end
    state.callbacks = state.callbacks + 1
    local args = {...}
    local ok, err = pcall(function()
        local damage = UE.unwrap(args[indices.Damage])
        if not Core.accept_damage(damage, Config.MinimumDamage) then return end
        local component = UE.unwrap(context)
        if not UE.live(component) then return end
        local owner = UE.call(component, "/Script/Engine.ActorComponent:GetOwner")
        if not UE.live(owner) or not UE.is_a(owner, "/Script/Maine.SurvivalCreature") then return end
        local _, world_id = UE.world(owner)
        if world_id ~= state.world_id then return end
        local position, anchor
        if Config.DamageAnchor == "health_bar" then
            anchor = state.ui:capture_damage(owner, component, state.controller)
            if not anchor then return end
        else
            position = indices.HitLocation and Core.vector(UE.unwrap(args[indices.HitLocation])) or nil
            if not position or (position.X == 0 and position.Y == 0 and position.Z == 0) then
                position = Core.vector(UE.call(owner, "/Script/Engine.Actor:K2_GetActorLocation"))
            end
        end
        if Core.push(state.queue, {damage = damage, position = position, anchor = anchor, world = world_id}) then
            state.accepted = state.accepted + 1
            UE.once("first-damage", "FIRST_DAMAGE_RECEIVED amount=" .. Core.number(damage, 3))
        end
    end)
    if not ok then UE.once("observer-error", "DAMAGE_OBSERVER ERROR " .. tostring(err)) end
    -- No return: the hook must never override the game result.
end

local function ensure_hooks()
    for _, suffix in ipairs({
        "MulticastHandleEffectsWithDamageFlags",
        "MulticastHandleEffectsWithDamageFlagsAtOwnerLocation",
        "MulticastHandleEffectsWithDamageFlagsAndInflictStyleAtOwnerLocation",
    }) do
        local path = "/Script/Maine.HealthComponent:" .. suffix
        if not state.hooks[path] then
            local ok, err = pcall(function()
                local fn = assert(UE.find(path), "damage function not loaded")
                local fields, indices = UE.parameters(fn), {}
                for i, field in ipairs(fields) do indices[field.name] = i end
                assert(indices.Damage and fields[indices.Damage].kind == "FloatProperty", "unexpected damage signature")
                assert(not indices.ReturnValue, "unexpected return parameter")
                local pre, post = RegisterHook(path, function() end, function(context, ...)
                    observe(indices, context, ...)
                end)
                state.hooks[path] = { pre = pre, post = post }
                UE.log("DAMAGE_HOOK_READY " .. suffix)
            end)
            if not ok then UE.once("hook:" .. suffix, "DAMAGE_HOOK ERROR " .. suffix .. ": " .. tostring(err)) end
        end
    end
end

local function discover()
    local controller, world, world_id = UE.local_player()
    local controller_id = UE.address(controller)
    if controller then assert(controller_id, "local controller address is not readable") end
    if state.controller_id and controller_id == state.controller_id and world_id == state.world_id then
        -- Diagnostic only; raw wrapper equality is never used as a lifecycle gate.
        UE.once("wrapper-identity", "IDENTITY_CHECK controller_raw_equal=" .. tostring(controller == state.controller)
            .. " world_raw_equal=" .. tostring(world == state.world)
            .. " controller_address_equal=" .. tostring(UE.same(controller, state.controller))
            .. " world_address_equal=" .. tostring(UE.same(world, state.world)))
    end
    if controller_id ~= state.controller_id or world_id ~= state.world_id then
        clear_context("discovery_identity_changed")
        state.controller, state.world, state.world_id = controller, world, world_id
        state.controller_id = controller_id
        if controller then
            UE.log("LOCAL_PLAYER_READY " .. UE.name(controller)
                .. " controller_id=" .. tostring(controller_id) .. " world_id=" .. tostring(world_id))
        end
    end
    if not controller then return end
    if state.health_enabled or (state.damage_enabled and Config.DamageAnchor == "health_bar") then
        local ok, err = pcall(function() state.ui:discover(controller, world) end)
        if not ok then UE.once("discovery-error", "WIDGET_DISCOVERY ERROR " .. tostring(err)) end
    end
    if state.damage_enabled then ensure_hooks() end
end

local function live_context()
    local controller = state.controller
    if not UE.live(controller) or not UE.live(UE.member(controller, "Pawn")) then
        if state.controller_id ~= nil then clear_context("controller_or_pawn_unavailable") end
        return nil
    end
    local _, world_id = UE.world(controller)
    if world_id ~= state.world_id then
        clear_context("world_id_changed new_world_id=" .. tostring(world_id))
        return nil
    end
    return controller, world_id
end

local function maintain()
    -- Discovery/HP work is deliberately separate from the per-frame animation.
    state.elapsed = state.elapsed + Config.MaintenanceIntervalMs / 1000
    if not state.health_enabled and not state.damage_enabled then return end
    if state.elapsed >= state.next_discovery then
        state.next_discovery = state.elapsed + Config.DiscoveryInterval
        discover()
    end
    if not live_context() then return end

    if state.elapsed >= state.next_status then
        state.next_status = state.elapsed + 10
        local widgets = 0
        for _ in pairs(state.ui.records) do widgets = widgets + 1 end
        UE.log("STATUS widgets=" .. widgets .. " callbacks=" .. state.callbacks
            .. " accepted=" .. state.accepted .. " queued=" .. #state.queue.events
            .. " overlay=" .. tostring(UE.live(state.ui.widget))
            .. " health=" .. tostring(state.health_enabled) .. " damage=" .. tostring(state.damage_enabled))
    end

    if state.health_enabled and state.elapsed >= state.next_health then
        state.next_health = state.elapsed + Config.HealthInterval
        state.ui:health()
    end
end

local function animate()
    -- No viewport query, world projection or real-time lookup while idle.
    if not state.damage_enabled or (#state.queue.events == 0 and not state.ui:has_damage()) then return end
    local controller, world_id = live_context()
    if not controller then return end
    local now = UE.static("/Script/Engine.GameplayStatics", "GetRealTimeSeconds", controller)
    if not Core.finite(now) then return end
    if not UE.live(state.ui.widget) then
        if #state.queue.events == 0 then return end
        if state.elapsed < state.next_overlay then state.queue.events = {}; return end
    end
    if not state.ui:ensure_overlay(controller) then
        state.next_overlay = state.elapsed + 5
        state.queue.events = {}
        return
    end
    local viewport
    if Config.DamageAnchor ~= "health_bar" then
        viewport = state.ui:viewport(controller)
        if not viewport then state.queue.events = {}; return end
    end
    if #state.queue.events > 0 then
        for _, event in ipairs(Core.drain(state.queue, world_id)) do state.ui:show(event, now, controller, viewport) end
    end
    state.ui:animate(now, controller, viewport)
end

function M.start()
    assert(type(LoopInGameThreadWithDelay) == "function", "this build needs the UE4SS delayed-action API")
    RegisterKeyBind(Key.F8, function()
        ExecuteInGameThread(function()
            state.health_enabled = not state.health_enabled
            if not state.health_enabled then state.ui:clear_health() end
            state.next_discovery, state.next_health = 0, 0
            UE.log("HEALTH_DISPLAY " .. (state.health_enabled and "ON" or "OFF"))
        end)
    end)
    RegisterKeyBind(Key.F7, function()
        ExecuteInGameThread(function()
            state.damage_enabled = not state.damage_enabled
            if not state.damage_enabled then
                state.queue.events = {}
                state.ui:hide_damage()
            end
            state.next_discovery, state.next_overlay = 0, 0
            UE.log("DAMAGE_DISPLAY " .. (state.damage_enabled and "ON" or "OFF") .. " callbacks=" .. state.callbacks
                .. " accepted=" .. state.accepted .. " dropped=" .. state.queue.dropped)
        end)
    end)
    local function guarded(callback, key)
        return function()
            local ok, err = pcall(callback)
            if not ok then UE.once(key, "UPDATE ERROR " .. key .. " " .. tostring(err)) end
        end
    end
    state.maintenance_loop = LoopInGameThreadWithDelay(Config.MaintenanceIntervalMs, guarded(maintain, "maintenance"))
    local frame_mode = false
    if Config.PreferFrameUpdates and EngineTickAvailable and type(LoopInGameThreadAfterFrames) == "function" then
        local ok, handle = pcall(LoopInGameThreadAfterFrames, 1, guarded(animate, "animation"))
        if ok and handle ~= nil and handle ~= false then state.animation_loop, frame_mode = handle, true end
    end
    if not frame_mode then
        state.animation_loop = LoopInGameThreadWithDelay(Config.FrameIntervalMs, guarded(animate, "animation"))
    end
    UE.log("ANIMATION_DRIVER " .. (frame_mode and "engine_frame" or ("timer_" .. Config.FrameIntervalMs .. "ms")))
    UE.log("LOADED version=0.6.3-right-alpha health=" .. tostring(state.health_enabled)
        .. " damage=" .. tostring(state.damage_enabled) .. " anchor=" .. tostring(Config.DamageAnchor)
        .. "; F8=health F7=damage")
end

return M
