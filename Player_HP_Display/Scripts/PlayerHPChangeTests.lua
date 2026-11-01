-- Fake UE/UMG only: never registers a real hook or starts a real timer.
local M, Core = {}, require("PlayerHPCore")
function M.run(check)
    local defaults = require("PlayerHPConfig")
    local tracker = {}
    check(Core.track_health(tracker, 100, 100, 1) == nil, "initial health establishes a baseline without a heal popup")
    check(Core.track_health(tracker, 88, 100, 1) == -12, "damage is negative")
    check(Core.track_health(tracker, 98, 100, 1) == 10, "healing is positive")
    check(Core.track_health(tracker, 98, 100, 1) == nil, "unchanged HP never spawns zero text")
    check(Core.change_text(10) == "+10" and Core.change_text(-12) == "-12", "signed integer formatting")
    check(Core.change_text(0) == nil and Core.change_text(0/0) == nil and Core.change_text(1.2) == nil,
        "invalid and noninteger change values cannot create labels")
    check(Core.track_health(tracker, 120, 120, 1) == nil, "max-HP changes do not look like healing")
    check(Core.track_health(tracker, 20, 120, 2) == nil, "replacement health component starts fresh")
    check(Core.track_health(tracker, nil, 120, 2) == nil
        and Core.track_health(tracker, 50, 120, 2) == nil, "invalid samples break continuity")
    check(Core.track_health(tracker, 0, 120, 2) == -50
        and Core.track_health(tracker, 120, 120, 2) == nil, "death can show damage but respawn is not fake healing")
    Core.reset_health(tracker)
    check(Core.track_health(tracker, 50, 100, 2) == nil, "explicit context reset establishes a new baseline")
    check(Core.track_health(tracker, 50.2, 100, 2) == nil
        and Core.track_health(tracker, 50.4, 100, 2) == nil
        and Core.track_health(tracker, 50.6, 100, 2) == 1, "fractional regeneration follows accumulated integer HP")
    check(Core.track_health(tracker, 50.8, 100, 2) == nil
        and Core.track_health(tracker, 51, 100, 2) == nil, "fractional healing is not counted repeatedly")
    Core.reset_health(tracker)
    check(Core.track_health(tracker, 0.2, 100, 2) == nil
        and Core.track_health(tracker, 0.6, 100, 2) == 1, "low nonzero health is not mistaken for a respawn")
    local rect = {X=100,Y=650,width=160,height=20}
    local anchor = Core.popup_anchor(rect, defaults)
    check(anchor.X == 180 + defaults.PopupGap and anchor.Y == 650 + defaults.PopupOffsetY,
        "popup begins outside the full bar right edge at its vertical center")
    local start = Core.popup_frame(0, defaults)
    local early = Core.popup_frame(defaults.PopupLifetime * 0.2, defaults)
    local late = Core.popup_frame(defaults.PopupLifetime * 0.8, defaults)
    check(start.Y == 0 and start.alpha == 1, "popup starts opaque at the anchor")
    check(early.Y < 0 and late.Y < early.Y and late.Y >= -defaults.PopupRise, "popup always moves up and never falls onto the bar")
    check(early.alpha == 1 and late.alpha > 0 and late.alpha < 1, "popup fades after the short initial phase")
    check(Core.popup_frame(defaults.PopupLifetime, defaults) == nil
        and Core.popup_frame(-1, defaults) == nil, "expired or reversed clocks cannot retain a popup")

    -- Exercise actual runtime transitions with dependency-injected fake objects.
    local config = {}
    for key, value in pairs(defaults) do config[key] = value end
    local pawn, component = {id=2}, {id=3}
    local controller, widget = {id=1,world=10,Pawn=pawn}, {id=4}
    local current, maximum, now, hidden, fail_health = 100, 100, 0, false, false
    local changes, errors, scans, reads, animations, active = {}, {}, 0, 0, 0, false
    local rendered
    local function live(object) return type(object) == "table" and not object.destroyed end
    local ui = {
        clear = function() active = false end,
        clear_changes = function() active = false end,
        hide = function() active = false end,
        show = function(_, value) rendered = value end,
        popup = function(_, delta, _, time) changes[#changes+1] = {delta=delta,time=time}; active = true end,
        has_changes = function() return active end,
        animate = function() animations = animations + 1 end,
    }
    local ue = {
        live=live, name=function() return "fake" end, log=function() end,
        once=function(_, message) if message:find("ERROR", 1, true) then errors[#errors+1] = message end end,
        local_player=function() return controller, pawn, 10 end,
        world=function(object) return object.world end,
        same=function(a,b) return live(a) and live(b) and a.id == b.id end,
        member=function(object, field) return object[field] end,
        address=function(object) return object.id end,
        health_component=function() return component end,
        health=function()
            reads = reads + 1
            if fail_health then error("simulated read failure") end
            return current, maximum
        end,
        viewport=function() return {X=1000,Y=800} end,
        owned_by=function() return true end,
        rect=function() if not hidden then return rect end end,
        time=function() return now end,
    }
    local discovery = {find=function() scans = scans + 1; return {widget=widget} end}
    local runtime = require("PlayerHPRuntime").new(ue, config, ui, discovery)
    local function step(value, max)
        current, maximum, now = value, max or maximum, now + 0.1
        runtime.update()
    end
    step(100)
    check(rendered == "[100 / 100]" and #changes == 0, "runtime preserves the centered HP label without initial popup")
    step(88); step(98)
    check(#changes == 2 and changes[1].delta == -12 and changes[2].delta == 10, "runtime sends both signed changes to UI")
    local prior_reads, prior_scans = reads, scans
    now = now + 0.017; runtime.animate()
    check(animations == 1 and reads == prior_reads and scans == prior_scans, "animation does not poll health or rediscover widgets")
    step(98)
    check(#changes == 2, "runtime does not repeat the last delta")
    step(110,120)
    check(#changes == 2, "runtime ignores maximum HP reconfiguration")
    hidden = true; step(90)
    hidden = false; step(90)
    check(#changes == 2 and not active, "hidden HUD discards changes rather than replaying them")
    step(95)
    check(changes[#changes].delta == 5, "visible healing resumes from the most recent sample")
    local before = #changes
    component = {id=30}; step(120)
    check(#changes == before, "runtime component replacement never generates fake healing")
    step(nil); step(100)
    check(#changes == before, "runtime recovery from unavailable health resets the baseline")
    step(90)
    fail_health = true; step(80); fail_health = false; step(80)
    check(#errors == 1 and #changes == before + 1, "read errors clear the UI and cannot create catch-up damage")
    step(70)
    pawn = {id=20}; controller.Pawn = pawn
    runtime.animate()
    check(not active, "animation clears immediately on pawn identity change")
    step(70); step(100)
    check(changes[#changes].delta == -10, "new pawn starts from a fresh health baseline")
    before = #changes
    config.PopupEnabled = false; step(90)
    check(#changes == before and rendered == "[90 / 120]", "popup toggle never disables the main HP label")
    config.Enabled = false
    prior_reads = reads; step(80)
    check(reads == prior_reads and not active, "disabled mod does not poll health or retain animations")

    -- Exercise real UI pooling/animation code, but replace all UMG constructors.
    local globals = {FName=_G.FName,FText=_G.FText,StaticConstructObject=_G.StaticConstructObject}
    local ok, err = pcall(function()
        local created, removed = 0, false
        local function label()
            local text = {Font={}}
            function text:SetFont(font) self.Font = font end
            function text:SetText(value) self.value = value end
            function text:SetColorAndOpacity(value) self.color = value.SpecifiedColor end
            function text:SetRenderOpacity(value) self.opacity = value end
            function text:SetVisibility(value) self.visibility = value end
            function text:SetShadowColorAndOpacity() end
            function text:SetShadowOffset() end
            return text
        end
        local function slot()
            local result = {}
            function result:SetAutoSize() end
            function result:SetAnchors() end
            function result:SetAlignment(value) self.alignment = value end
            function result:SetPosition(value) self.position = {X=value.X,Y=value.Y} end
            return result
        end
        _G.FName, _G.FText = function(value) return value end, function(value) return value end
        _G.StaticConstructObject = function() created = created + 1; return label() end
        config.PopupEnabled, config.MaxPopups = true, 2
        local fake_ui = require("PlayerHPUI").new({
            live=live, valid=live, find=function(path) return path end, once=function() end,
        }, config)
        fake_ui.widget = {SetVisibility=function() end,RemoveFromParent=function() removed = true end}
        fake_ui.text, fake_ui.slot = label(), slot()
        fake_ui.canvas = {GetOuter=function() return {} end,AddChildToCanvas=function() return slot() end}
        fake_ui.popup(controller, 10, rect, 1)
        local first_node = fake_ui.nodes[1]
        check(created == 1 and first_node.text.value == "+10" and first_node.text.color == config.HealColor,
            "UI constructs a green positive label")
        check(first_node.slot.position.X == 192 and first_node.slot.alignment.X == 0,
            "entire popup stays to the right of the bar")
        fake_ui.popup(controller, -12, rect, 1.1)
        check(fake_ui.nodes[2].text.value == "-12" and fake_ui.nodes[2].text.color == config.DamageColor,
            "UI constructs a red negative label")
        fake_ui.animate(1.6)
        check(first_node.slot.position.Y < 650 and first_node.text.opacity < 1, "UI applies upward motion and fading")
        fake_ui.popup(controller, -5, rect, 1.7)
        check(created == 2 and #fake_ui.nodes == 2 and first_node.text.value == "-5" and first_node.text.opacity == 1,
            "bounded pool reuses the oldest label and resets its opacity")
        fake_ui.animate(3)
        check(not fake_ui.has_changes() and first_node.text.visibility == 2, "expired labels are hidden and reusable")
        fake_ui.popup(controller, 1, rect, 3.1); fake_ui.hide()
        check(not fake_ui.has_changes(), "hiding HUD clears every active popup")
        fake_ui.clear()
        check(removed and #fake_ui.nodes == 0, "context cleanup removes overlay and resets popup pool")
    end)
    _G.FName, _G.FText, _G.StaticConstructObject = globals.FName, globals.FText, globals.StaticConstructObject
    if not ok then error(err) end
end
return M
