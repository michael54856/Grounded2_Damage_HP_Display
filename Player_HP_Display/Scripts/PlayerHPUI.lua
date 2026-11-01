local M, serial = {}, 0
local Core = require("PlayerHPCore")
function M.new(ue, config)
    local ui = { nodes = {} }
    function ui.clear_changes()
        for _, node in ipairs(ui.nodes) do
            if ue.live(node.text) then node.text:SetVisibility(2) end
            node.started = nil
        end
    end
    function ui.hide()
        if ue.live(ui.widget) then ui.widget:SetVisibility(2) end
        ui.clear_changes()
    end
    function ui.clear()
        if ue.live(ui.widget) then pcall(function() ui.widget:RemoveFromParent() end) end
        ui.widget, ui.canvas, ui.text, ui.slot, ui.rendered, ui.font_size = nil, nil, nil, nil, nil, nil
        ui.nodes = {}
    end
    local function construct(path, outer, name)
        local object = StaticConstructObject(assert(ue.find(path), "missing class: " .. path), outer, FName(name .. serial))
        assert(ue.valid(object), "failed to construct " .. name)
        return object
    end
    local function ensure(controller)
        if ue.live(ui.widget) and ue.live(ui.canvas) and ue.live(ui.text) and ue.live(ui.slot) then return end
        ui.clear()
        serial = serial + 1
        ui.widget = construct("/Script/UMG.UserWidget", controller, "PlayerHPOverlay_")
        local tree = construct("/Script/UMG.WidgetTree", ui.widget, "PlayerHPTree_")
        ui.widget.WidgetTree = tree
        ui.canvas = construct("/Script/UMG.CanvasPanel", tree, "PlayerHPCanvas_")
        tree.RootWidget = ui.canvas
        ui.widget:SetOwningPlayer(controller)
        ui.canvas:SetVisibility(3)
        ui.text = construct("/Script/UMG.TextBlock", tree, "PlayerHPValue_")
        ui.slot = ui.canvas:AddChildToCanvas(ui.text)
        assert(ue.live(ui.slot), "failed to attach HP text")
        ui.slot:SetAutoSize(true)
        ui.slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
        ui.slot:SetAlignment({X=0.5,Y=0.5})
        ui.text:SetVisibility(3)
        ui.text:SetColorAndOpacity({ SpecifiedColor = config.Color, ColorUseRule = 0 })
        ui.text:SetShadowColorAndOpacity({R=0,G=0,B=0,A=1})
        ui.text:SetShadowOffset({X=1,Y=1})
        ui.widget:SetVisibility(2)
        ui.widget:AddToViewport(110)
        ue.log("OVERLAY_READY")
    end
    function ui.show(controller, value, rect)
        ensure(controller)
        local font_size = config.FontSize
        if config.FitFontToBarHeight then
            font_size = math.max(config.MinimumFontSize, math.min(font_size, math.floor(rect.height * 0.8)))
        end
        if font_size ~= ui.font_size then
            local font = ui.text.Font
            font.Size = font_size
            ui.text:SetFont(font)
            ui.font_size = font_size
        end
        if value ~= ui.rendered then ui.text:SetText(FText(value)); ui.rendered = value end
        ui.slot:SetPosition({X=rect.X + config.OffsetX,Y=rect.Y + config.OffsetY})
        ui.widget:SetVisibility(3) -- HitTestInvisible, never consume gameplay input
        ue.once("visible", "HP_TEXT_READY " .. value)
    end
    function ui.has_changes()
        for _, node in ipairs(ui.nodes) do if node.started ~= nil then return true end end
        return false
    end
    function ui.popup(controller, delta, rect, now)
        local value = Core.change_text(delta)
        if not config.PopupEnabled or not value then return end
        ensure(controller)
        local node
        for _, candidate in ipairs(ui.nodes) do
            if candidate.started == nil then node = candidate; break end
        end
        if not node and #ui.nodes < config.MaxPopups then
            local text = construct("/Script/UMG.TextBlock", ui.canvas:GetOuter(), "PlayerHPChange_" .. (#ui.nodes + 1) .. "_")
            local slot = ui.canvas:AddChildToCanvas(text)
            assert(ue.live(slot), "failed to attach HP change text")
            slot:SetAutoSize(true)
            slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
            slot:SetAlignment({X=0,Y=0.5}) -- left edge stays outside the bar
            local font = text.Font
            font.Size = config.PopupFontSize
            text:SetFont(font)
            text:SetShadowColorAndOpacity({R=0,G=0,B=0,A=1})
            text:SetShadowOffset({X=1,Y=1})
            node = { text = text, slot = slot }
            ui.nodes[#ui.nodes + 1] = node
        end
        if not node then
            -- Reuse the oldest label rather than allocating unbounded widgets.
            for _, candidate in ipairs(ui.nodes) do
                if not node or candidate.started < node.started then node = candidate end
            end
        end
        if not node then return end
        node.anchor, node.started = Core.popup_anchor(rect, config), now
        node.text:SetText(FText(value))
        node.text:SetColorAndOpacity({ SpecifiedColor = delta > 0 and config.HealColor or config.DamageColor, ColorUseRule = 0 })
        node.text:SetRenderOpacity(1)
        node.slot:SetPosition(node.anchor)
        node.text:SetVisibility(3)
        ue.once("first-change", "HP_CHANGE_READY " .. value)
    end
    function ui.animate(now)
        for _, node in ipairs(ui.nodes) do
            if node.started ~= nil then
                local frame = Core.popup_frame(now - node.started, config)
                if frame and ue.live(node.text) and ue.live(node.slot) then
                    node.slot:SetPosition({X=node.anchor.X,Y=node.anchor.Y + frame.Y})
                    node.text:SetRenderOpacity(frame.alpha)
                else
                    if ue.live(node.text) then node.text:SetVisibility(2) end
                    node.started = nil
                end
            end
        end
    end
    return ui
end
return M
