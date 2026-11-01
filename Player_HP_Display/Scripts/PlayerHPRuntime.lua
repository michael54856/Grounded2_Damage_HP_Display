local Core = require("PlayerHPCore")
local M = {}
-- Dependencies can be replaced with fake objects for startup regression tests.
function M.new(ue, config, ui, discovery)
    local runtime = {}
    local state = { elapsed = 0, next_discovery = 0, next_player_scan = 0, tracker = {} }
    local function clear()
        ui.clear()
        Core.reset_health(state.tracker)
        state.controller, state.pawn, state.world, state.component, state.bar = nil, nil, nil, nil, nil
        state.component_id, state.next_discovery = nil, 0
    end
    local function tick()
        state.elapsed = state.elapsed + config.UpdateIntervalMs / 1000
        if not config.Enabled then Core.reset_health(state.tracker); ui.hide(); return end
        if not ue.live(state.controller) or not ue.live(state.pawn) then
            if state.elapsed < state.next_player_scan then ui.hide(); return end
            state.next_player_scan = state.elapsed + config.DiscoveryInterval
            local controller, pawn, world = ue.local_player()
            if not controller then clear(); return end
            clear()
            state.controller, state.pawn, state.world = controller, pawn, world
            ue.log("LOCAL_PLAYER_READY controller=" .. ue.name(controller) .. " pawn=" .. ue.name(pawn))
        end
        if ue.world(state.controller) ~= state.world or not ue.same(ue.member(state.controller, "Pawn"), state.pawn) then clear(); return end
        state.component = ue.health_component(state.pawn)
        if not state.component then
            Core.reset_health(state.tracker)
            ui.hide(); ue.once("component", "WAITING_FOR_LOCAL_HEALTH_COMPONENT"); return
        end
        local identity = ue.address(state.component)
        if identity ~= state.component_id then ui.clear_changes(); state.component_id = identity end
        local current, maximum = ue.health(state.component)
        local delta = Core.track_health(state.tracker, current, maximum, identity)
        local value = Core.health(current, maximum)
        if not value then ui.hide(); return end
        -- Sample even while the HUD is hidden; do not queue changes to replay later.
        local viewport = ue.viewport(state.controller)
        if not viewport or viewport.X <= 0 or viewport.Y <= 0 then ui.hide(); return end
        if state.elapsed >= state.next_discovery then
            state.next_discovery = state.elapsed + config.DiscoveryInterval
            state.bar = discovery.find(state.controller, state.world, viewport)
        end
        if not state.bar or not ue.live(state.bar.widget) or not ue.owned_by(state.bar.widget, state.controller) then ui.hide(); return end
        local rect = ue.rect(state.bar.widget, state.controller)
        if not Core.eligible(rect, viewport, config) then ui.hide(); return end
        ui.show(state.controller, value, rect)
        if delta and config.PopupEnabled then ui.popup(state.controller, delta, rect, ue.time(state.controller)) end
    end
    function runtime.update()
        local ok, err = pcall(tick)
        if not ok then
            pcall(ui.clear)
            Core.reset_health(state.tracker)
            state.bar, state.next_discovery = nil, 0
            ue.once("update:" .. tostring(err), "UPDATE ERROR " .. tostring(err))
        end
    end
    function runtime.animate()
        if not ui.has_changes() then return end
        local ok, err = pcall(function()
            if not config.Enabled or not config.PopupEnabled or not ue.live(state.controller)
                or not ue.live(state.pawn) or ue.world(state.controller) ~= state.world
                or not ue.same(ue.member(state.controller, "Pawn"), state.pawn) then ui.clear_changes(); return end
            ui.animate(ue.time(state.controller))
        end)
        if not ok then
            pcall(ui.clear_changes)
            ue.once("animation:" .. tostring(err), "ANIMATION ERROR " .. tostring(err))
        end
    end
    function runtime.start()
        assert(type(LoopInGameThreadWithDelay) == "function", "official UE4SS delayed-action API is required")
        state.loop = LoopInGameThreadWithDelay(config.UpdateIntervalMs, runtime.update)
        state.animation_loop = LoopInGameThreadWithDelay(config.AnimationIntervalMs, runtime.animate)
        ue.log("LOADED version=0.2.0-alpha enabled=" .. tostring(config.Enabled)
            .. "; player_bar=bottom_left; signed_hp_changes=true; no F7/F8 keybinds")
    end
    return runtime
end
function M.start()
    local ue, config = require("PlayerHPUE"), require("PlayerHPConfig")
    M.active = M.new(ue, config, require("PlayerHPUI").new(ue, config), require("PlayerHPDiscovery").new(ue, config))
    M.active.start()
end
return M
