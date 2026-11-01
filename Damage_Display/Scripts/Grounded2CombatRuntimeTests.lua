-- Isolated runtime regression tests: all UE APIs, timers, UI and hooks are fakes.
-- Restore every global/module even if an assertion fails; never touch real hooks.
local M = {}
function M.run()
    local count = 0
    local function check(condition, message)
        assert(condition, "Combat HUD runtime self-test: " .. message)
        count = count + 1
    end
    local module_names = { "Grounded2CombatUE", "Grounded2CombatUI", "Grounded2CombatConfig", "Grounded2CombatRuntime" }
    local global_names = { "RegisterKeyBind", "ExecuteInGameThread", "RegisterHook", "Key",
        "LoopInGameThreadWithDelay", "LoopInGameThreadAfterFrames", "EngineTickAvailable" }
    local modules, globals = {}, {}
    for _, name in ipairs(module_names) do modules[name] = package.loaded[name] end
    for _, name in ipairs(global_names) do globals[name] = _G[name] end
    local ok, err = pcall(function()
      for _, anchor_mode in ipairs({ "world", "health_bar" }) do
        for _, frame_available in ipairs({ true, false }) do
            local keys, timers, hooks, errors = {}, {}, {}, {}
            local world, controller = { id = 20 }, { id = 10, Pawn = {} }
            local anchor, bar_visible, viewport_queries, world_locations = { X = 800, Y = 100 }, true, 0, 0
            local real_time, clock_reads, ui = 0, 0, { records = {}, health_calls = 0,
                clear_health_calls = 0, shows = 0, animations = 0, active = false, clears = 0 }
            function ui:discover() self.records = { enemy = {} } end
            function ui:capture_damage() if bar_visible then return anchor end end
            function ui:health() self.health_calls = self.health_calls + 1 end
            function ui:clear_health() self.clear_health_calls = self.clear_health_calls + 1; self.records = {} end
            function ui:hide_damage() self.active = false end
            function ui:has_damage() return self.active end
            function ui:clear() self.clears = self.clears + 1; self.records = {}; self.active = false; self.widget = nil end
            function ui:ensure_overlay() self.widget = {}; return true end
            function ui:viewport() viewport_queries = viewport_queries + 1; return { X = 1920, Y = 1080 } end
            function ui:show(event)
                self.shows = self.shows + 1; self.last_damage = event.damage
                self.last_anchor = event.anchor; self.active = true
            end
            function ui:animate() self.animations = self.animations + 1 end
            local fake = {
                live = function(object) return type(object) == "table" end,
                member = function(object, name) return object[name] end,
                address = function(object) return object and object.id end,
                same = function(a, b) return a == b end,
                world = function() return world, world.id end,
                local_player = function() return controller, world, world.id end,
                find = function() return {} end,
                parameters = function() return { {name = "Damage", kind = "FloatProperty"} } end,
                unwrap = function(value) return value end,
                is_a = function() return true end,
                name = function() return "fake" end,
                call = function(_, path)
                    if path:find("GetOwner", 1, true) then return {} end
                    world_locations = world_locations + 1
                    return { X = 10, Y = 20, Z = 30 }
                end,
                static = function() clock_reads = clock_reads + 1; return real_time end,
                log = function() end,
                once = function(_, message)
                    if message:find("ERROR", 1, true) then errors[#errors + 1] = message end
                end,
            }
            package.loaded.Grounded2CombatUE = fake
            package.loaded.Grounded2CombatUI = { new = function() return ui end }
            -- Do not depend on the user's startup switches or tuning values.
            package.loaded.Grounded2CombatConfig = {
                HealthEnabled = true, DamageEnabled = true, MaxQueuedEvents = 128,
                DamageAnchor = anchor_mode,
                DamageDecimals = 0, MinimumDamage = 1, MaintenanceIntervalMs = 100,
                HealthInterval = 0.1, DiscoveryInterval = 1, PreferFrameUpdates = true, FrameIntervalMs = 8,
            }
            package.loaded.Grounded2CombatRuntime = nil
            _G.Key = { F7 = 7, F8 = 8 }
            _G.EngineTickAvailable = frame_available
            _G.RegisterKeyBind = function(key, callback) keys[key] = callback end
            _G.ExecuteInGameThread = function(callback) callback() end
            _G.RegisterHook = function(_, _, post) hooks[#hooks + 1] = post; return 1, 2 end
            _G.LoopInGameThreadWithDelay = function(ms, callback) timers[ms] = callback; return ms end
            local frame_callback
            _G.LoopInGameThreadAfterFrames = function(frames, callback)
                check(frames == 1, "animation is scheduled every engine frame")
                frame_callback = callback
                return 999
            end
            require("Grounded2CombatRuntime").start()
            local config = require("Grounded2CombatConfig")
            local maintain = timers[config.MaintenanceIntervalMs]
            local animate = frame_callback or timers[config.FrameIntervalMs]
            check(type(maintain) == "function" and type(animate) == "function", "separate maintenance and animation drivers")
            check((frame_callback ~= nil) == frame_available, "timer fallback when EngineTick is unavailable")
            local function step(callback)
                real_time = real_time + 0.02
                callback()
                assert(#errors == 0, table.concat(errors, "\n"))
            end
            step(maintain)
            check(#hooks == 3 and ui.health_calls == 1, "startup observes damage and updates HP")
            step(animate)
            check(clock_reads == 0, "idle animation skips engine queries")
            hooks[1]({}, 0.999)
            step(animate)
            check(ui.shows == 0 and clock_reads == 0, "sub-one damage is rejected before queue and projection")
            hooks[1]({}, 1.6)
            anchor.X = 900
            step(animate)
            check(ui.shows == 1 and ui.last_damage == 1.6, "accepted damage preserves original precision internally")
            if anchor_mode == "health_bar" then
                check(ui.last_anchor.X == 800 and viewport_queries == 0 and world_locations == 0,
                    "HUD mode locks hit-time coordinates without world location or projection viewport work")
                bar_visible = false
                hooks[1]({}, 5)
                step(animate)
                check(ui.shows == 1, "damage without a matching visible HUD bar is not misattributed")
                bar_visible = true
            end
            keys[8]()
            local before_health, before_shows = ui.health_calls, ui.shows
            check(ui.clear_health_calls == 1 and ui.active, "F8 restores names without clearing popups")
            step(maintain)
            hooks[1]({}, 4)
            step(animate)
            check(ui.health_calls == before_health and ui.shows == before_shows + 1, "F8 off leaves damage enabled")
            if anchor_mode == "health_bar" then
                check(next(ui.records) ~= nil, "HUD bars are rediscovered with HP text disabled")
            end
            keys[8]()
            step(maintain)
            check(ui.health_calls == before_health + 1, "F8 on resumes HP updates")
            hooks[1]({}, 7) -- queued, but not rendered before disabling
            keys[7]()
            before_shows = ui.shows
            step(animate)
            check(not ui.active and ui.shows == before_shows, "F7 immediately hides popups and clears queued hits")
            before_health = ui.health_calls
            step(maintain)
            check(ui.health_calls == before_health + 1, "F7 off leaves HP enabled")
            hooks[1]({}, 8) -- must not be recorded while damage is disabled
            keys[7]()
            step(animate)
            check(ui.shows == before_shows, "F7 on never replays disabled or discarded hits")
            hooks[1]({}, 9)
            step(animate)
            check(ui.shows == before_shows + 1, "F7 on resumes new damage")
            local clears = ui.clears
            world.id = 21
            hooks[1]({}, 10)
            step(animate)
            check(ui.clears == clears + 1 and not ui.active, "world changes clear old UI and damage")
        end
      end
    end)
    for _, name in ipairs(module_names) do package.loaded[name] = modules[name] end
    for _, name in ipairs(global_names) do _G[name] = globals[name] end
    if not ok then error(err) end
    return count
end
return M
