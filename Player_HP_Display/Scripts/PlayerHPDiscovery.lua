local Core = require("PlayerHPCore")
local M = {}
function M.new(ue, config)
    local discovery = {}
    function discovery.find(controller, world, viewport)
        local candidates, by_id, seen_roots = {}, {}, {}
        local scanned = 0
        local function add(widget, hint)
            if not ue.live(widget) or not ue.is_a(widget, "/Script/UMG.Widget")
                or ue.is_a(widget, "/Script/UMG.TextBlock") or ue.world(widget) ~= world then return end
            local name = ue.name(widget)
            local score = Core.health_score(name, hint)
            if not score or not ue.owned_by(widget, controller) then return end
            local override = config.TargetWidgetPathContains
            if override and not name:lower():find(override:lower(), 1, true) then return end
            local key = ue.address(widget)
            if not key then return end
            if by_id[key] and by_id[key].score >= score then return end
            ue.once("health-widget:" .. key, "HEALTH_WIDGET hint=" .. tostring(hint) .. " widget=" .. name)
            local ok, rect = pcall(ue.rect, widget, controller)
            if not ok then ue.once("rect:" .. key, "CANDIDATE_GEOMETRY ERROR " .. tostring(rect)); return end
            if not Core.eligible(rect, viewport, config) then
                if rect then
                    ue.once("layout:" .. key, string.format("HEALTH_WIDGET_LAYOUT_REJECTED x=%.1f y=%.1f width=%.1f height=%.1f widget=%s",
                        rect.X, rect.Y, rect.width, rect.height, name))
                end
                return
            end
            ue.once("candidate:" .. key, string.format("CANDIDATE score=%d x=%.1f y=%.1f width=%.1f height=%.1f hint=%s widget=%s",
                score, rect.X, rect.Y, rect.width, rect.height, tostring(hint), name))
            local candidate = { key = key, widget = widget, rect = rect, score = score }
            if by_id[key] then
                for i, previous in ipairs(candidates) do if previous.key == key then candidates[i] = candidate; break end end
            else
                candidates[#candidates + 1] = candidate
            end
            by_id[key] = candidate
        end
        local function inspect(root)
            local key = ue.address(root)
            if not key or seen_roots[key] or not ue.live(root) or ue.world(root) ~= world
                or not ue.is_a(root, "/Script/UMG.Widget") or not ue.owned_by(root, controller) then return end
            seen_roots[key] = true
            ue.once("root:" .. key, "LOCAL_HUD_ROOT " .. ue.name(root))
            local class, visited, count = root:GetClass(), {}, 0
            for _ = 1, 4 do
                if not ue.valid(class) then break end
                class:ForEachProperty(function(property)
                    if count >= 96 then return true end
                    local field = property:GetFName():ToString()
                    local kind = property:GetFullName():match("^(%S+)")
                    if not visited[field] and (kind == "ObjectProperty" or kind == "ObjectPtrProperty") then
                        visited[field], count = true, count + 1
                        local lower = field:lower()
                        if lower:find("health", 1, true) or lower:find("hp", 1, true) or lower:find("vital", 1, true) then
                            local value = ue.member(root, field)
                            ue.once("field:" .. key .. ":" .. field, "HUD_FIELD " .. field .. " => " .. ue.name(value))
                            add(value, field)
                        end
                    end
                end)
                class = class:GetSuperStruct()
            end
        end
        for _, source in ipairs({
            { "ProgressBar", nil }, { "HealthReadoutWidget", "HealthReadoutWidget" },
            { "UI_HealthFill_C", "HealthFill" },
        }) do
            for _, widget in ipairs(ue.all(source[1])) do scanned = scanned + 1; add(widget, source[2]) end
        end
        for _, source in ipairs({ "PlayerStatusWidget", "HUDWidget", "GameUI" }) do
            for _, root in ipairs(ue.all(source)) do scanned = scanned + 1; inspect(root) end
        end
        local selected, reason = Core.choose(candidates)
        if selected then
            ue.once("selected:" .. selected.key, "PLAYER_BAR_READY " .. ue.name(selected.widget))
            return selected
        end
        ue.once("selection:" .. tostring(reason), "WAITING_FOR_PLAYER_HEALTH_BAR reason=" .. tostring(reason)
            .. " scanned=" .. scanned .. " eligible=" .. #candidates)
        return nil
    end
    return discovery
end
return M
