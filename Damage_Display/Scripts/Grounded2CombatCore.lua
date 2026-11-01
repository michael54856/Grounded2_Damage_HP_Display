-- Engine-independent presentation rules. Values are real damage notifications,
-- not HP differences: multiple notifications may legitimately share the same HP.
local M = {}

function M.finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function M.number(value, decimals)
    if not M.finite(value) then return nil end
    local precision = math.max(0, math.min(3, math.floor(decimals or 1)))
    if precision == 0 then
        value = value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
    end
    local text = string.format("%." .. precision .. "f", value)
    if precision > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
    if text == "-0" then text = "0" end
    return text
end

function M.health(current, maximum, decimals)
    if not M.finite(current) or not M.finite(maximum) or maximum <= 0 then return nil end
    current = math.max(0, math.min(current, maximum))
    return M.number(current, decimals) .. " / " .. M.number(maximum, decimals)
end

function M.accept_damage(value, minimum)
    return M.finite(value) and value > 0 and value >= (minimum or 1)
end

function M.damage(value, decimals, minimum)
    if not M.accept_damage(value, minimum) then return nil end
    return M.number(value, decimals or 0)
end

function M.vector(value)
    if value == nil then return nil end
    local ok, x, y, z = pcall(function() return value.X, value.Y, value.Z end)
    if ok and M.finite(x) and M.finite(y) and M.finite(z) then
        return { X = x, Y = y, Z = z }
    end
end

function M.point(value)
    if value == nil then return nil end
    local ok, x, y = pcall(function() return value.X, value.Y end)
    if ok and M.finite(x) and M.finite(y) then return { X = x, Y = y } end
end

-- Only horizontal fill modes are supported; never guess another layout.
function M.bar_point(size, percent, fill_type, padding)
    size = M.point(size)
    padding = M.point(padding) or { X = 0, Y = 0 }
    if not size or size.X <= 0 or size.Y <= 0 or not M.finite(percent) then return nil end
    if fill_type ~= 0 and fill_type ~= 1 then return nil end
    local inset = math.max(0, padding.X)
    local width = size.X - 2 * inset
    if width <= 0 then return nil end
    local ratio = math.max(0, math.min(1, percent))
    if fill_type == 1 then ratio = 1 - ratio end
    return { X = inset + width * ratio, Y = size.Y }
end

-- The physical top-right of the full native bar, independent of HP, fill
-- direction and progress-bar padding. Convert this point through native geometry.
function M.bar_right_point(size)
    size = M.point(size)
    if not size or size.X <= 0 or size.Y <= 0 then return nil end
    return { X = size.X, Y = 0 }
end

function M.queue(capacity)
    return { capacity = math.max(1, math.floor(capacity)), events = {}, dropped = 0 }
end

function M.push(queue, event)
    if not M.finite(event.damage) or event.damage <= 0 or event.world == nil then return false end
    local position = M.vector(event.position)
    local anchor = M.point(event.anchor)
    if not position and not anchor then return false end
    if #queue.events >= queue.capacity then
        table.remove(queue.events, 1)
        queue.dropped = queue.dropped + 1
    end
    -- Copy scalars: no hook parameter, remote struct or victim reference survives.
    queue.events[#queue.events + 1] = {
        damage = event.damage, position = position, anchor = anchor, world = event.world,
    }
    return true
end

function M.drain(queue, world)
    local result = {}
    for _, event in ipairs(queue.events) do
        if event.world == world then result[#result + 1] = event end
    end
    queue.events = {}
    return result
end

-- Sample randomness once per popup, never once per frame. Keep our PRNG local
-- to avoid reseeding or consuming the random stream of other Lua mods.
function M.random(seed)
    local state = math.max(1, math.floor(seed or 1) % 2147483647)
    return function()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
end

function M.trajectory(random, height, travel_min, travel_max)
    local direction = random() < 0.5 and -1 or 1
    return {
        x = direction * (travel_min + (travel_max - travel_min) * random()),
        height = height * (0.85 + 0.3 * random()),
    }
end

function M.downward_trajectory(random, angle_min, angle_max, distance_min, distance_max)
    assert(M.finite(angle_min) and M.finite(angle_max) and angle_min >= 30
        and angle_max > angle_min and angle_max < 90, "downward launch angles must satisfy 30 <= min < max < 90")
    assert(M.finite(distance_min) and M.finite(distance_max) and distance_min > 0
        and distance_max >= distance_min, "downward launch distance must be positive")
    local direction = random() < 0.5 and -1 or 1
    -- Use an open interval so a zero PRNG sample never launches at exactly 30 degrees.
    local sample = math.max(0.000001, math.min(0.999999, random()))
    local degrees = angle_min + (angle_max - angle_min) * sample
    local radians = math.rad(degrees)
    local distance = distance_min + (distance_max - distance_min) * random()
    return {
        downward = true, angle = degrees,
        x = direction * distance * math.sin(radians),
        y = distance * math.cos(radians),
    }
end

function M.rightward_trajectory(random, angle_min, angle_max, distance_min, distance_max)
    assert(M.finite(angle_min) and M.finite(angle_max) and angle_min > 0
        and angle_max >= angle_min and angle_max < 90, "rightward launch angles must satisfy 0 < min <= max < 90")
    assert(M.finite(distance_min) and M.finite(distance_max) and distance_min > 0
        and distance_max >= distance_min, "rightward launch distance must be positive")
    local sample = math.max(0, math.min(1, random()))
    local degrees = angle_min + (angle_max - angle_min) * sample
    local radians = math.rad(degrees)
    local distance = distance_min + (distance_max - distance_min) * random()
    return {
        downward = true, angle = degrees,
        x = distance * math.cos(radians),
        y = distance * math.sin(radians),
    }
end

function M.opacity(progress, fade_start, fade_power)
    fade_start, fade_power = fade_start or 0.8, fade_power or 3
    assert(M.finite(fade_start) and fade_start >= 0 and fade_start < 1, "fade start must be within [0, 1)")
    assert(M.finite(fade_power) and fade_power >= 1, "fade power must be at least one")
    if progress <= fade_start then return 1 end
    local fade = math.max(0, math.min(1, (progress - fade_start) / (1 - fade_start)))
    return 1 - fade ^ fade_power
end

function M.animation(age, lifetime, trajectory, fall_distance, fade_start, fade_power)
    if not M.finite(age) or lifetime <= 0 or age >= lifetime then return nil end
    local progress = math.max(0, age / lifetime)
    local alpha = M.opacity(progress, fade_start, fade_power)
    local y
    if trajectory.downward then
        -- Screen Y increases downward. Positive initial velocity and gravity
        -- guarantee that no part of a HUD popup's flight rises toward the bar.
        y = trajectory.y * progress + math.max(0, fall_distance or 0) * progress ^ 2
    else
        -- Preserve the legacy world-space arc for the optional world mode.
        y = -4 * trajectory.height * progress * (1 - progress) + (fall_distance or 0) * progress ^ 2
    end
    return {
        x = trajectory.x * progress,
        y = y,
        alpha = math.max(0, math.min(1, alpha)),
    }
end

return M
