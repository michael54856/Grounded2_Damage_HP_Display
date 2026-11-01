-- Runs inside Lua before the runtime starts; no UE objects or hooks are involved.
local M, Core, UE = {}, require("Grounded2CombatCore"), require("Grounded2CombatUE")

local function geometry_tests(check)
    local bridge, post_hook, pre_hook, registrations, alive = nil, nil, nil, 0, false
    local widget, other = { id = 1 }, { id = 2 }
    local native = { type = function() return "UScriptStruct" end }
    local mode, callback_return = "normal", nil
    local fake = {
        find = function() return {} end,
        parameters = function() return { { name = "ReturnValue", kind = "StructProperty" } } end,
        unwrap = function(parameter) return parameter:get() end,
        same = function(a, b) return a and b and a.id == b.id end,
        log = function() end,
        call = function(context)
            if mode == "getter_error" then error("simulated getter failure") end
            alive = true
            if mode ~= "missing_post" then
                local function param(value) return { get = function() return value end } end
                post_hook(param(other), param(native)) -- unrelated calls must not consume the request
                pre_hook(param(context))
                callback_return = post_hook(param(context), param(mode == "flat_return" and {} or native))
            end
            alive = false
            return {} -- reproduces the lossy, reflection-only normal Lua return
        end,
    }
    bridge = require("Grounded2CombatGeometry").new(fake, function(_, pre, post)
        registrations, pre_hook, post_hook = registrations + 1, pre, post
        return 1, 2
    end)
    bridge.prepare()
    bridge.prepare()
    check(registrations == 1, "native geometry observation hook is installed only once")
    local consumed = 0
    local function anchor(geometry)
        assert(alive and geometry == native, "geometry must remain native and live during conversion")
        consumed = consumed + 1
        return Core.bar_point({ X = 200, Y = 16 }, 0.8, 0)
    end
    local result = bridge.read(widget, anchor)
    check(result.X == 160 and consumed == 1 and not alive,
        "native geometry is consumed before flattened return and unrelated widgets are ignored")
    check(callback_return == nil, "geometry observer never overrides the engine return value")
    post_hook({ get = function() return widget end }, { get = function() return native end })
    check(consumed == 1, "geometry observer does nothing outside an explicit request")
    for _, failure in ipairs({ "getter_error", "missing_post", "flat_return", "consumer_error", "nested_read" }) do
        mode = failure
        local ok = pcall(function()
            bridge.read(widget, function(geometry)
                if failure == "consumer_error" then error("simulated conversion failure") end
                if failure == "nested_read" then return bridge.read(widget, anchor) end
                return anchor(geometry)
            end)
        end)
        check(not ok, "geometry bridge rejects " .. failure)
        mode = "normal"
        check(bridge.read(widget, anchor).X == 160, "geometry request is cleared after " .. failure)
    end
end

function M.run()
    local count = 0
    local function check(condition, message)
        assert(condition, "Combat HUD self-test: " .. message)
        count = count + 1
    end
    check(Core.health(1769.755, 1920, 0) == "1770 / 1920", "integer host HP")
    check(Core.health(1769.2, 1920, 0) == "1769 / 1920", "integer HP rounds down below midpoint")
    check(Core.health(0, 0, 1) == nil, "uninitialized component is hidden")
    check(Core.health(-4, 1920, 1) == "0 / 1920", "lethal HP display")
    check(Core.health(0/0, 1920, 1) == nil, "NaN HP is rejected")
    check(Core.damage(0, 1) == nil and Core.damage(-150, 1) == nil, "zero and heal are not damage")
    check(Core.damage(0.001, 0) == nil and Core.damage(0.9999, 0) == nil,
        "raw damage below one is filtered before rounding")
    check(Core.damage(1, 0) == "1" and Core.damage(1.6, 0) == "2" and Core.damage(2.5, 0) == "3",
        "integer damage uses half-up rounding and inclusive threshold")
    check(Core.damage(math.huge, 0) == nil and Core.damage(0/0, 0) == nil, "non-finite damage is hidden")
    local queue = Core.queue(2)
    local position = { X = 1, Y = 2, Z = 3 }
    Core.push(queue, { damage = 6.0547494888306, position = position, world = 10 })
    Core.push(queue, { damage = 43.875, position = position, world = 10 })
    position.X = 100
    local events = Core.drain(queue, 10)
    check(#events == 2 and math.abs(events[1].damage + events[2].damage - 49.9297494888306) < 0.00001,
        "distinct damage components are preserved")
    check(events[1].position.X == 1, "hit position is copied")
    for i = 1, 3 do Core.push(queue, { damage = i, position = position, world = 10 }) end
    check(#queue.events == 2 and queue.dropped == 1, "queue is bounded")
    check(#Core.drain(queue, 11) == 0 and #queue.events == 0, "world transition discards old hits")
    check(not Core.push(queue, { damage = math.huge, position = position, world = 10 }), "invalid damage")
    check(not Core.push(queue, { damage = 2, position = {X=1,Y=2}, world = 10 }), "invalid hit position")
    local right, left = { x = 90, height = 70 }, { x = -90, height = 70 }
    check(Core.animation(0, 1, right).alpha == 1 and Core.animation(0, 1, right).x == 0,
        "new popup is visible at the hit")
    local frame = Core.animation(0.9, 1, right)
    check(frame.alpha > 0 and frame.alpha < 1 and frame.x > 0 and frame.y < 0, "popup arcs and fades")
    check(Core.animation(0.5, 1, right).y == -70, "arc apex matches launch height")
    check(Core.animation(0.75, 1, right).y > Core.animation(0.5, 1, right).y,
        "popup falls after the apex")
    check(Core.animation(0.5, 1, right).x == -Core.animation(0.5, 1, left).x,
        "left and right trajectories are mirrored")
    check(Core.animation(1, 1, right) == nil, "expired popup is removed")
    check(Core.animation(-1, 1, right).x == 0 and Core.animation(0, 0, right) == nil,
        "negative age and invalid lifetime are safe")
    local random, seen_left, seen_right = Core.random(12345), false, false
    for _ = 1, 32 do
        local trajectory = Core.trajectory(random, 70, 55, 110)
        seen_left, seen_right = seen_left or trajectory.x < 0, seen_right or trajectory.x > 0
        assert(math.abs(trajectory.x) >= 55 and math.abs(trajectory.x) <= 110, "travel bounds")
        assert(trajectory.height >= 59.5 and trajectory.height <= 80.5, "arc height bounds")
    end
    check(seen_left and seen_right, "seeded local randomness produces both directions within bounds")
    local size = { X = 200, Y = 16 }
    check(Core.bar_point(size, 0.8, 0).X == 160, "80 percent starts at 80 percent of the HUD bar")
    check(Core.bar_point(size, 0.8, 0).Y == 16, "HUD popup origin uses the native bar bottom edge")
    check(math.abs(Core.bar_point(size, 0.8, 1).X - 40) < 0.00001, "right-to-left HUD fill")
    check(Core.bar_point(size, 0, 0).X == 0 and Core.bar_point(size, 1, 0).X == 200,
        "empty and full bars use the two ends")
    check(Core.bar_point(size, 2, 0).X == 200 and Core.bar_point(size, -1, 0).X == 0,
        "HUD ratio is clamped without rounding HP first")
    check(math.abs(Core.bar_point(size, 0.8, 0, { X = 4, Y = 0 }).X - 157.6) < 0.00001,
        "native progress bar border padding is respected")
    check(Core.bar_point({X=0,Y=16}, 0.8, 0) == nil and Core.bar_point(size, 0.8, 2) == nil
        and Core.bar_point(size, 0/0, 0) == nil, "unlaid-out or unsupported bars are rejected")
    local anchor = { X = 800, Y = 100 }
    check(Core.push(queue, { damage = 2, anchor = anchor, world = 10 }), "HUD damage needs no world position")
    anchor.X = 900
    local hud_events = Core.drain(queue, 10)
    check(hud_events[1].anchor.X == 800 and hud_events[1].position == nil, "HUD origin is copied and locked at hit time")
    check(not Core.push(queue, { damage = 2, anchor = {X=0/0,Y=100}, world = 10 }), "invalid HUD coordinates are rejected")
    local falling = Core.animation(0.95, 1, right, 100)
    check(falling.y > 0 and falling.x > 0, "legacy arc supports an optional falling offset")
    local down_left = Core.downward_trajectory(function() return 0 end, 30, 80, 55, 110)
    local down_right = Core.downward_trajectory(function() return 1 end, 30, 80, 55, 110)
    check(down_left.x < 0 and down_right.x > 0 and down_left.y > 0 and down_right.y > 0,
        "both randomized launch directions point downward")
    check(down_left.angle > 30 and down_right.angle < 80,
        "extreme PRNG samples stay strictly above 30 and below 80 degrees")
    local downward_random, left_seen, right_seen = Core.random(24680), false, false
    for _ = 1, 128 do
        local trajectory = Core.downward_trajectory(downward_random, 30, 80, 55, 110)
        left_seen, right_seen = left_seen or trajectory.x < 0, right_seen or trajectory.x > 0
        local ratio = math.abs(trajectory.x) / trajectory.y
        assert(ratio > math.tan(math.rad(30)) and ratio < math.tan(math.rad(80)), "actual velocity angle bounds")
        local previous_y = 0
        for i = 0, 99 do
            local downward_frame = Core.animation(i / 100, 1, trajectory, 100)
            assert(downward_frame.y >= previous_y and downward_frame.y >= 0, "HUD flight never rises")
            previous_y = downward_frame.y
        end
    end
    check(left_seen and right_seen, "random HUD launches cover both sides within actual velocity angle bounds")
    check(Core.animation(0, 1, down_left, 100).y == 0
        and Core.animation(0.8, 1, down_left, 100).alpha > 0
        and Core.animation(1, 1, down_left, 100) == nil, "downward popup keeps origin, fade and expiry rules")
    check(Core.animation(0.8, 1, down_left, -100).y > 0, "negative configured gravity cannot reverse HUD motion")
    check(not pcall(Core.downward_trajectory, downward_random, 29, 80, 55, 110)
        and not pcall(Core.downward_trajectory, downward_random, 30, 90, 55, 110), "unsafe launch angles are rejected")
    local right_edge = Core.bar_right_point({ X = 200, Y = 16 })
    check(right_edge.X == 200 and right_edge.Y == 0, "fixed HUD origin uses the full bar top-right")
    check(Core.bar_right_point({X=200,Y=64}).Y == 0, "top-right origin does not include bar height or old lower gap")
    check(Core.bar_right_point({X=0,Y=16}) == nil and Core.bar_right_point({X=200,Y=0}) == nil
        and Core.bar_right_point({X=0/0,Y=16}) == nil, "fixed HUD origin rejects invalid geometry")
    for _, hp in ipairs({ 0, 0.1, 0.8, 1 }) do
        local independent = Core.bar_right_point({ X = 200, Y = 16, Percent = hp, BarFillType = 1 })
        assert(independent.X == 200 and independent.Y == 0, "HUD top-right must not track health or fill direction")
    end
    check(true, "fixed right-edge anchor is independent of percentage and fill direction")
    local shallow = Core.rightward_trajectory(function() return 0 end, 15, 80, 55, 110)
    local steep = Core.rightward_trajectory(function() return 1 end, 15, 80, 55, 110)
    check(math.abs(shallow.y / shallow.x - math.tan(math.rad(15))) < 0.00001
        and math.abs(steep.y / steep.x - math.tan(math.rad(80))) < 0.00001,
        "15-80 degree range is measured below rightward horizontal, not downward vertical")
    local rightward_random = Core.random(34567)
    for _ = 1, 128 do
        local trajectory = Core.rightward_trajectory(rightward_random, 15, 80, 55, 110)
        assert(trajectory.x > 0 and trajectory.y > 0, "HUD launches must always point right and down")
        local slope = trajectory.y / trajectory.x
        assert(slope >= math.tan(math.rad(15)) - 0.00001 and slope <= math.tan(math.rad(80)) + 0.00001,
            "random launch slope is within horizontal angle bounds")
        local previous_x, previous_y = 0, 0
        for i = 0, 99 do
            local sample = Core.animation(i / 100, 1, trajectory, 100)
            assert(sample.x >= previous_x and sample.y >= previous_y, "HUD animation never moves left or up")
            previous_x, previous_y = sample.x, sample.y
        end
    end
    check(true, "random rightward trajectories stay within angle bounds and move monotonically right/down")
    check(not pcall(Core.rightward_trajectory, rightward_random, -15, 80, 55, 110)
        and not pcall(Core.rightward_trajectory, rightward_random, 15, 90, 55, 110), "upward or vertical launch bounds are rejected")
    check(Core.opacity(0, 0.8, 3) == 1 and Core.opacity(0.79, 0.8, 3) == 1
        and Core.opacity(0.8, 0.8, 3) == 1, "damage remains fully opaque throughout the hold period")
    check(math.abs(Core.opacity(0.9, 0.8, 3) - 0.875) < 0.00001,
        "final fade is cubic rather than linear")
    check(Core.opacity(0.8) - Core.opacity(0.85) < Core.opacity(0.9) - Core.opacity(0.95),
        "opacity decreases faster near the end of the fade")
    local previous_alpha = 1
    for i = 0, 100 do
        local alpha = Core.opacity(i / 100)
        assert(alpha >= 0 and alpha <= previous_alpha and alpha <= 1, "opacity stays bounded and never flashes back")
        previous_alpha = alpha
    end
    check(Core.opacity(1) == 0 and Core.opacity(2) == 0, "fade reaches and clamps to zero")
    check(Core.animation(1.2, 1.6, shallow, 100, 0.8, 3).alpha == 1
        and Core.animation(1.59, 1.6, shallow, 100, 0.8, 3) ~= nil
        and Core.animation(1.6, 1.6, shallow, 100, 0.8, 3) == nil,
        "extended lifetime holds visibility then removes the popup at 1.6 seconds")
    check(Core.animation(0.87, 1.1, shallow, 100, 0.8, 3).alpha == 1
        and Core.animation(1.09, 1.1, shallow, 100, 0.8, 3) ~= nil
        and Core.animation(1.1, 1.1, shallow, 100, 0.8, 3) == nil,
        "restored 1.1 second lifetime retains opaque hold, late fade and exact expiry")
    check(Core.opacity(0.55, 0.55, 1) == 1 and math.abs(Core.opacity(0.8, 0.55, 1) - 4/9) < 0.00001,
        "right-bar variant restores the original earlier linear fade")
    check(Core.animation(0.7, 1.1, shallow, 100, 0.55, 1).alpha < 1
        and Core.animation(1.09, 1.1, shallow, 100, 0.55, 1) ~= nil
        and Core.animation(1.1, 1.1, shallow, 100, 0.55, 1) == nil,
        "right-bar variant keeps 1.1 seconds with an earlier fade and exact expiry")
    local function wrapper(address, is_valid)
        return {
            GetAddress = function() return address end,
            IsValid = function() return is_valid ~= false end,
        }
    end
    local controller, new_controller_wrapper = wrapper(1001), wrapper(1001)
    local world, new_world_wrapper = wrapper(2001), wrapper(2001)
    check(controller ~= new_controller_wrapper and UE.same(controller, new_controller_wrapper),
        "different wrappers for one controller must retain context")
    check(world ~= new_world_wrapper and UE.same(world, new_world_wrapper),
        "different wrappers for one world must not clear the damage queue")
    check(not UE.same(world, wrapper(2002)), "a real world transition is detected")
    check(not UE.same(world, wrapper(2001, false)), "invalid wrapper is not a live identity")
    check(not UE.same(wrapper(0), wrapper(0)), "null pointers are not objects")
    check(UE.same(nil, nil) and not UE.same(controller, nil), "absent controller handling")
    local ui = require("Grounded2CombatUI").new()
    local record = {} -- no label means no UObject calls during restoration
    ui.records.enemy = record
    ui.nodes = { { started = 0 } }
    ui:clear_health()
    check(ui.records.enemy == record and ui:has_damage(), "real F8 cleanup retains bar discovery and active damage")
    geometry_tests(check)
    count = count + require("Grounded2CombatRuntimeTests").run()
    return count
end
return M
