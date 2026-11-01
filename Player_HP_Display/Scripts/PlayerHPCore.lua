local M = {}
function M.finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
function M.point(value)
    if value == nil then return nil end
    local ok, x, y = pcall(function() return value.X, value.Y end)
    if ok and M.finite(x) and M.finite(y) then return { X = x, Y = y } end
end
function M.health(current, maximum)
    if not M.finite(current) or not M.finite(maximum) or maximum <= 0 then return nil end
    current = math.max(0, math.min(current, maximum))
    return string.format("[%.0f / %.0f]", math.floor(current + 0.5), math.floor(maximum + 0.5))
end
function M.center(size)
    size = M.point(size)
    if not size or size.X <= 0 or size.Y <= 0 then return nil end
    return { X = size.X / 2, Y = size.Y / 2 }
end
function M.reset_health(tracker)
    tracker.current, tracker.maximum, tracker.identity, tracker.was_zero = nil, nil, nil, nil
end
function M.track_health(tracker, current, maximum, identity)
    if not M.health(current, maximum) or identity == nil then M.reset_health(tracker); return nil end
    -- Match the center label's integer rounding so fractional regeneration is
    -- eventually shown as +1, not discarded at every polling interval.
    local was_zero, is_zero = tracker.was_zero, current <= 0
    current = math.floor(math.max(0, math.min(current, maximum)) + 0.5)
    local previous, old_max, old_id = tracker.current, tracker.maximum, tracker.identity
    tracker.current, tracker.maximum, tracker.identity = current, maximum, identity
    tracker.was_zero = is_zero
    if previous == nil or old_id ~= identity or math.abs(old_max - maximum) > 0.0001 then return nil end
    if was_zero and not is_zero then return nil end -- no fake heal on respawn/reinitialization
    local delta = current - previous
    if delta ~= 0 then return delta end
end
function M.change_text(delta)
    if not M.finite(delta) or delta == 0 or delta ~= math.floor(delta) then return nil end
    return string.format("%s%.0f", delta > 0 and "+" or "-", math.abs(delta))
end
function M.popup_anchor(rect, config)
    return { X = rect.X + rect.width / 2 + config.PopupGap, Y = rect.Y + config.PopupOffsetY }
end
function M.popup_frame(age, config)
    if not M.finite(age) or age < 0 or age >= config.PopupLifetime or config.PopupLifetime <= 0 then return nil end
    local progress = age / config.PopupLifetime
    local fade_start = math.max(0, math.min(0.99, config.PopupFadeStart))
    local alpha = 1 - math.max(0, (progress - fade_start) / (1 - fade_start))
    -- Screen Y decreases upwards. Ease out without falling back onto the HUD.
    return { Y = -config.PopupRise * (1 - (1 - progress) ^ 2), alpha = alpha }
end
function M.health_score(name, hint)
    local path, field = tostring(name):lower(), tostring(hint or ""):lower()
    for _, excluded in ipairs({ "enemy", "building", "boss", "inventory", "ui_inv", "invhealth", "menu", "mount", "pethealth",
        "buggy", "tickdown", "healthtext", "healthicon", "healthpip", "healthpoolupgrade",
        "statuseffect", "cooldown", "timer", "regeneration", "waterbar", "hungerbar", "foodbar", "staminabar", "oxygenbar" }) do
        if path:find(excluded, 1, true) then return nil end
    end
    local text = path .. " " .. field
    if text:find("healthbar", 1, true) or text:find("health_bar", 1, true) then return 100 end
    if text:find("healthreadout", 1, true) then return 90 end
    if text:find("healthfill", 1, true) then return 80 end
    if text:find("healthholder", 1, true) then return 70 end
    if field == "health" or field == "hp" or field == "hpbar" then return 60 end
    if text:find("health", 1, true) then return 50 end
    return nil
end
function M.eligible(rect, viewport, config)
    if not rect or not viewport or not M.finite(rect.X) or not M.finite(rect.Y)
        or not M.finite(rect.width) or not M.finite(rect.height)
        or rect.width < config.MinimumBarWidth or rect.height <= 0
        or rect.width / rect.height < config.MinimumBarAspectRatio then return false end
    if rect.X < 0 or rect.X > viewport.X or rect.Y < 0 or rect.Y > viewport.Y then return false end
    return not config.RequireBottomLeft or (rect.X <= viewport.X / 2 and rect.Y >= viewport.Y / 2)
end
function M.choose(candidates)
    table.sort(candidates, function(a, b)
        if a.score == b.score then return a.key < b.key end
        return a.score > b.score
    end)
    local best = candidates[1]
    if not best then return nil, "no_candidate" end
    for i = 2, #candidates do
        local candidate = candidates[i]
        if best.score - candidate.score >= 10 then break end
        -- Duplicate references/overlaid fills of the same physical bar are OK.
        if math.abs(best.rect.X - candidate.rect.X) > 4 or math.abs(best.rect.Y - candidate.rect.Y) > 4
            or math.abs(best.rect.width - candidate.rect.width) > 8 then return nil, "ambiguous_candidates" end
    end
    return best
end
return M
