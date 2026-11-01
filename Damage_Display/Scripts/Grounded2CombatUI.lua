local UE, Core, Config = require("Grounded2CombatUE"), require("Grounded2CombatCore"), require("Grounded2CombatConfig")
local M = {}
local VISIBLE, HIDDEN, NO_HIT_TEST = 0, 2, 3
local serial = 0

function M.new()
    return setmetatable({ records = {}, nodes = {}, random = Core.random(os.time()) }, { __index = M })
end

local function text_string(label)
    return label:GetText():ToString()
end

local function restore(record)
    if UE.live(record.label) and record.rendered and text_string(record.label) == record.rendered then
        record.label:SetText(FText(record.base))
    end
    record.rendered = nil
end

function M:clear_health()
    for _, record in pairs(self.records) do pcall(restore, record) end
    -- Retain bar discovery for damage anchoring even when F8 hides HP numbers.
end

function M:hide_damage()
    for _, node in ipairs(self.nodes) do
        if node.started ~= nil and UE.live(node.text) then node.text:SetVisibility(HIDDEN) end
        node.started, node.visible = nil, false
    end
end

function M:has_damage()
    for _, node in ipairs(self.nodes) do
        if node.started ~= nil then return true end
    end
    return false
end

function M:clear()
    self:clear_health()
    self.records = {}
    if UE.live(self.widget) then pcall(function() self.widget:RemoveFromParent() end) end
    self.widget, self.canvas, self.nodes = nil, nil, {}
end

function M:capture_damage(owner, component, controller)
    for _, record in pairs(self.records) do
        local widget = record.widget
        if UE.live(widget) and UE.member(widget, "bShowing") ~= false
            and UE.same(UE.member(widget, "TargetActor"), owner)
            and UE.same(UE.member(widget, "HealthComponent"), component) then
            local ok, point = pcall(UE.bar_anchor, controller, UE.member(widget, "HealthBar"))
            if not ok then
                UE.once("hud-anchor-error", "HUD_ANCHOR ERROR " .. tostring(point))
                return nil
            end
            if point then point.Y = point.Y + math.max(0, Config.DamageBarOffsetY) end
            return point
        end
    end
    UE.once("hud-unmatched", "HUD_DAMAGE_SKIPPED no visible bar for this victim; no world-position fallback")
end

function M:discover(controller, world)
    if Config.DamageAnchor == "health_bar" then
        local ok, err = pcall(UE.prepare_bar_geometry)
        if not ok then UE.once("geometry-setup", "HUD_GEOMETRY_BRIDGE ERROR " .. tostring(err)) end
    end
    local previous, discovered = self.records, {}
    local candidates = FindAllOf("EnemyHealthWidget") or {}
    local counts = { live = 0, world = 0, owner = 0, label = 0, accepted = 0 }
    for _, widget in ipairs(candidates) do
        if UE.live(widget) then counts.live = counts.live + 1 end
        if UE.live(widget) and UE.same(widget:GetWorld(), world) then
            counts.world = counts.world + 1
            -- This exact reflected getter was captured from the live game's schema.
            -- GetOwningPlayer is not reflected on /Script/UMG.UserWidget in this build.
            local owner_ok, owner = pcall(UE.call, widget,
                "/Script/Maine.GameUserWidget:GetOwningSurvivalPlayerController")
            if not owner_ok then
                UE.once("widget-owner-error", "WIDGET_OWNER ERROR " .. tostring(owner))
                owner = nil
            end
            local label = UE.member(widget, "EnemyName")
            if UE.same(owner, controller) then counts.owner = counts.owner + 1 end
            if UE.live(label) then counts.label = counts.label + 1 end
            if UE.same(owner, controller) and UE.live(label) then
                local key = UE.address(widget)
                assert(key, "health widget has no readable identity")
                local record = previous[key]
                if record and not UE.same(record.label, label) then pcall(restore, record); record = nil end
                record = record or { widget = widget, label = label }
                discovered[key] = record
                counts.accepted = counts.accepted + 1
                UE.once("live-health-widget", "LIVE_HEALTH_WIDGET " .. UE.name(widget))
            end
        end
    end
    for key, record in pairs(previous) do
        if not discovered[key] then pcall(restore, record) end
    end
    self.records = discovered
    local summary = string.format("WIDGET_SCAN total=%d live=%d world_match=%d owner_match=%d label_valid=%d accepted=%d",
        #candidates, counts.live, counts.world, counts.owner, counts.label, counts.accepted)
    if summary ~= self.scan_summary then UE.log(summary); self.scan_summary = summary end
end

function M:health()
    for _, record in pairs(self.records) do
        local ok, err = pcall(function()
            if not UE.live(record.widget) or not UE.live(record.label) then return end
            local target = UE.member(record.widget, "TargetActor")
            local component = UE.member(record.widget, "HealthComponent")
            if UE.member(record.widget, "bShowing") == false
                or not UE.live(target) or not UE.is_a(target, "/Script/Maine.SurvivalCreature")
                or not UE.live(component) then
                restore(record)
                return
            end
            local component_owner = UE.call(component, "/Script/Engine.ActorComponent:GetOwner")
            if not UE.same(component_owner, target) then restore(record); return end
            local current, maximum = UE.hp(component)
            local value = Core.health(current, maximum, Config.HealthDecimals)
            if not value then restore(record); return end
            local existing = text_string(record.label)
            if existing ~= record.rendered then record.base = existing end
            local wanted = record.base .. "  [" .. value .. "]"
            if wanted ~= existing then record.label:SetText(FText(wanted)) end
            record.rendered = wanted
            UE.once("hp-visible", "HP_TEXT_READY " .. value)
        end)
        if not ok then UE.once("health-error", "HEALTH_UI ERROR " .. tostring(err)) end
    end
end

function M:ensure_overlay(controller)
    if UE.live(self.widget) and UE.live(self.canvas) then return true end
    serial = serial + 1
    local ok, err = pcall(function()
        local widget_class = assert(UE.find("/Script/UMG.UserWidget"), "UserWidget class missing")
        local tree_class = assert(UE.find("/Script/UMG.WidgetTree"), "WidgetTree class missing")
        local canvas_class = assert(UE.find("/Script/UMG.CanvasPanel"), "CanvasPanel class missing")
        local text_class = assert(UE.find("/Script/UMG.TextBlock"), "TextBlock class missing")
        local widget = StaticConstructObject(widget_class, controller, FName("G2CombatHUD_" .. serial))
        assert(UE.valid(widget), "cannot construct overlay")
        self.widget = widget
        local tree = StaticConstructObject(tree_class, widget, FName("G2CombatTree_" .. serial))
        assert(UE.valid(tree), "cannot construct widget tree")
        widget.WidgetTree = tree
        local canvas = StaticConstructObject(canvas_class, tree, FName("G2CombatCanvas_" .. serial))
        assert(UE.valid(canvas), "cannot construct canvas")
        tree.RootWidget = canvas
        self.canvas = canvas
        widget:SetOwningPlayer(controller)
        widget:SetVisibility(NO_HIT_TEST)
        canvas:SetVisibility(NO_HIT_TEST)

        for i = 1, Config.MaxPopups do
            local text = StaticConstructObject(text_class, tree, FName("G2Damage_" .. serial .. "_" .. i))
            assert(UE.valid(text), "cannot construct damage text")
            local slot = canvas:AddChildToCanvas(text)
            assert(UE.valid(slot), "cannot attach damage text")
            slot:SetAutoSize(true)
            slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
            slot:SetAlignment({ X = 0.5, Y = 0.5 })
            slot:SetZOrder(10)
            local font = text.Font
            for _, record in pairs(self.records) do
                if UE.live(record.label) then
                    local candidate = UE.member(record.label, "Font")
                    if candidate then text:SetFont(candidate); font = text.Font; break end
                end
            end
            font.Size = Config.DamageFontSize
            text:SetFont(font)
            text:SetColorAndOpacity({ SpecifiedColor = Config.DamageColor, ColorUseRule = 0 })
            text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 })
            text:SetShadowOffset({ X = 1.5, Y = 1.5 })
            text:SetVisibility(HIDDEN)
            self.nodes[i] = { text = text, slot = slot }
        end
        widget:AddToViewport(100)
    end)
    if not ok then
        if UE.live(self.widget) then pcall(function() self.widget:RemoveFromParent() end) end
        self.widget, self.canvas, self.nodes = nil, nil, {}
        UE.once("overlay-error", "OVERLAY ERROR " .. tostring(err))
        return false
    end
    UE.log("OVERLAY_READY pool=" .. #self.nodes)
    return true
end

function M:viewport(controller)
    local size = UE.static("/Script/UMG.WidgetLayoutLibrary", "GetViewportSize", controller)
    local scale = UE.static("/Script/UMG.WidgetLayoutLibrary", "GetViewportScale", controller)
    if not Core.finite(scale) or scale <= 0 then return nil end
    local x, y = size.X / scale, size.Y / scale
    if Core.finite(x) and Core.finite(y) and x > 0 and y > 0 then return { X = x, Y = y } end
end

function M:show(event, now, controller, viewport)
    local text = Core.damage(event.damage, Config.DamageDecimals, Config.MinimumDamage)
    if not text then return end
    local anchor = Core.point(event.anchor)
    if not anchor then
        local x = UE.project(controller, event.position, viewport)
        if x == nil then return end -- legacy world mode: off screen or behind camera
    end
    local node
    for _, candidate in ipairs(self.nodes) do
        if candidate.started == nil then node = candidate; break end
    end
    if not node then
        for _, candidate in ipairs(self.nodes) do
            if not node or candidate.started < node.started then node = candidate end
        end
    end
    if not node then return end
    node.position, node.anchor, node.started = event.position, anchor, now
    if anchor then
        node.trajectory = Core.rightward_trajectory(self.random, Config.DamageAngleMin, Config.DamageAngleMax,
            Config.DamageTravelMin, Config.DamageTravelMax)
    else
        node.trajectory = Core.trajectory(self.random, Config.DamageArcHeight, Config.DamageTravelMin, Config.DamageTravelMax)
    end
    -- HUD text starts at the bar's top-right, extending to the right and downward.
    node.slot:SetAlignment({ X = anchor and 0 or 0.5, Y = anchor and 0 or 0.5 })
    node.text:SetText(FText(text))
    node.text:SetRenderOpacity(1)
    node.opacity = 1
    node.text:SetVisibility(VISIBLE)
    node.visible = true
    UE.once("popup-visible", "DAMAGE_POP_READY amount=" .. Core.number(event.damage, 3))
end

function M:animate(now, controller, viewport)
    for _, node in ipairs(self.nodes) do
        if node.started ~= nil then
            local frame = Core.animation(now - node.started, Config.DamageLifetime, node.trajectory,
                node.anchor and Config.DamageFallDistance or 0, Config.DamageFadeStart, Config.DamageFadePower)
            if not frame or not UE.live(node.text) or not UE.live(node.slot) then
                if UE.live(node.text) then node.text:SetVisibility(HIDDEN) end
                node.started, node.visible = nil, false
            else
                local x, y
                if node.anchor then
                    x, y = node.anchor.X, node.anchor.Y
                else
                    x, y = UE.project(controller, node.position, viewport)
                    if y then y = y - 20 end
                end
                if x then
                    node.slot:SetPosition({ X = x + frame.x, Y = y + frame.y })
                    if node.opacity ~= frame.alpha then
                        node.text:SetRenderOpacity(frame.alpha)
                        node.opacity = frame.alpha
                    end
                    if not node.visible then node.text:SetVisibility(VISIBLE); node.visible = true end
                else
                    if node.visible then node.text:SetVisibility(HIDDEN); node.visible = false end
                end
            end
        end
    end
end

return M
