-- Pure Lua/fake UE tests only. No real hooks, UI, memory edits or gameplay calls.
local M, Core = {}, require("PlayerHPCore")
function M.run()
    local count = 0
    local function check(value, message)
        assert(value, "Player_HP_Display self-test: " .. message)
        count = count + 1
    end
    check(Core.health(80, 100) == "[80 / 100]", "requested bracketed HP format")
    check(Core.health(80.6, 100.4) == "[81 / 100]" and Core.health(2.5, 100) == "[3 / 100]", "integer half-up display")
    check(Core.health(-5, 100) == "[0 / 100]" and Core.health(120, 100) == "[100 / 100]", "display clamping")
    check(Core.health(0, 0) == nil and Core.health(0/0, 100) == nil and Core.health(10, math.huge) == nil,
        "uninitialized and non-finite health is hidden")
    local center = Core.center({ X = 240, Y = 20 })
    check(center.X == 120 and center.Y == 10, "position is the full bar center, not its fill tip")
    check(Core.center({X=0,Y=20}) == nil and Core.center({X=240,Y=0}) == nil, "zero-size geometry is hidden")
    check(Core.health_score("UI_HUD.PlayerVitals.HealthBar") == 100, "explicit player health bar is preferred")
    check(Core.health_score("UI_HUD.UI_EnemyHealth.HealthBar") == nil
        and Core.health_score("UI_Inventory.HealthBar") == nil
        and Core.health_score("UI_HUD.MountHealthBar") == nil, "enemy, inventory and mount bars are excluded")
    check(Core.health_score("UI_HUD.WaterBar") == nil and Core.health_score("UI_HUD.HungerBar") == nil,
        "water and food are not health bars")
    local config = { RequireBottomLeft = true, MinimumBarWidth = 30, MinimumBarAspectRatio = 1.5 }
    local viewport = { X = 1000, Y = 800 }
    local rect = { X = 100, Y = 650, width = 160, height = 20 }
    check(Core.eligible(rect, viewport, config), "bottom-left horizontal bar is eligible")
    check(not Core.eligible({X=900,Y=650,width=160,height=20}, viewport, config)
        and not Core.eligible({X=100,Y=100,width=160,height=20}, viewport, config), "other HUD corners are rejected")
    check(not Core.eligible({X=100,Y=650,width=10,height=20}, viewport, config)
        and not Core.eligible({X=100,Y=650,width=100,height=0}, viewport, config), "slivers and zero-height bars are rejected")
    local defaults = require("PlayerHPConfig")
    check(defaults.RequireBottomLeft == true and defaults.RequireBottomRight == nil,
        "default config must not restore the erroneous bottom-right restriction")
    check(Core.eligible({X=345.3,Y=1026,width=322.1,height=12}, {X=1920,Y=1080}, defaults),
        "runtime-observed player bar passes the shipped defaults")
    local first = { key = 1, score = 100, rect = rect }
    local same = { key = 2, score = 100, rect = {X=101,Y=650,width=160,height=20} }
    local other = { key = 3, score = 100, rect = {X=300,Y=650,width=160,height=20} }
    check(Core.choose({first, same}) == first, "duplicate geometry references do not create ambiguity")
    local selected, reason = Core.choose({first, other})
    check(selected == nil and reason == "ambiguous_candidates", "distinct equally plausible bars fail closed")
    check(Core.choose({first, {key=3,score=80,rect=other.rect}}) == first, "stronger health binding wins")
    local bar = { id=1, name="UI_HUD.PlayerVitals.HealthBar", rect=rect, owner=true, world=10 }
    local foreign = {id=2,name=bar.name,rect=rect,owner=false,world=10}
    local enemy = {id=3,name="UI_HUD.UI_EnemyHealth.HealthBar",rect=rect,owner=true,world=10}
    local food = {id=4,name="UI_HUD.FoodBar",rect=rect,owner=true,world=10}
    local objects = {bar, foreign, enemy, food}
    local fake = {
        live = function(object) return type(object) == "table" and not object.destroyed end,
        valid = function(object) return type(object) == "table" end,
        is_a = function(_, path) return path == "/Script/UMG.Widget" end,
        world = function(object) return object.world end,
        name = function(object) return object and object.name or "INVALID" end,
        address = function(object) return object.id end,
        owned_by = function(object) return object.owner end,
        rect = function(object) return object.rect end,
        all = function(class) return class == "ProgressBar" and objects or {} end,
        once = function() end,
    }
    local discovery = require("PlayerHPDiscovery").new(fake, config)
    check(discovery.find({}, 10, viewport).widget == bar, "discovery selects only a local owned health bar")
    bar.world = 11
    check(discovery.find({}, 10, viewport) == nil, "other-world widgets never show local HP")
    bar.world, bar.destroyed = 10, true
    check(discovery.find({}, 10, viewport) == nil, "destroyed widgets are not used")
    bar.destroyed = false
    config.TargetWidgetPathContains = "NoSuchWidget"
    check(discovery.find({}, 10, viewport) == nil, "manual path filter cannot choose another widget")
    config.TargetWidgetPathContains = nil
    local actual_path = "UI_HUD_C_1.WidgetTree_2.WBP_PlayerVitals_Augusta.WidgetTree_3."
        .. "WBP_PlayerInfo.WidgetTree_4.WBP_Health.WidgetTree_5.UI_HealthFill_Horizontal"
    local player_fill = {id=5,name=actual_path,rect=rect,owner=true,world=10}
    local nameplate = {id=6,name="WBP_PlayerNameplate_C_1.WidgetTree_2.WBP_HealthBar."
        .. "WidgetTree_3.UI_HealthFill_Horizontal",rect=rect,owner=true,world=10}
    objects = {player_fill, nameplate}
    check(require("PlayerHPDiscovery").new(fake, defaults).find({}, 10, viewport).widget == player_fill,
        "shipped defaults select the observed player vitals path, not overhead health bars")
    objects = {nameplate}
    check(require("PlayerHPDiscovery").new(fake, defaults).find({}, 10, viewport) == nil,
        "overhead nameplate cannot be selected even with local ownership and bottom-left geometry")
    local post, registrations, alive, consume_error = nil, 0, false, false
    local native = { type = function() return "UScriptStruct" end }
    local geometry_ue = {
        find = function() return {} end,
        parameters = function() return {{name="ReturnValue",kind="StructProperty"}} end,
        unwrap = function(parameter) return parameter:get() end,
        same = function(a,b) return a == b end,
        log = function() end,
        call = function(widget)
            alive = true
            local result = post({get=function() return widget end}, {get=function() return native end})
            assert(result == nil, "geometry hook must not override the original return")
            alive = false
            return {} -- regular Lua return loses FGeometry's opaque fields
        end,
    }
    local bridge = require("PlayerHPGeometry").new(geometry_ue, function(_, _, callback)
        registrations, post = registrations + 1, callback
        return 1, 2
    end)
    local function consume(geometry)
        assert(alive and geometry == native, "native geometry must be consumed while alive")
        if consume_error then error("simulated geometry conversion failure") end
        return Core.center({X=240,Y=20})
    end
    bridge.prepare(); bridge.prepare()
    check(registrations == 1, "only this mod's geometry hook is installed once")
    local position = bridge.read(bar, consume)
    check(position.X == 120 and position.Y == 10 and not alive, "native geometry is converted before flattening")
    consume_error = true
    check(not pcall(bridge.read, bar, consume), "geometry conversion errors propagate safely")
    consume_error = false
    check(bridge.read(bar, consume).X == 120, "failed geometry conversion leaves no stale pending request")
    local UE = require("PlayerHPUE")
    local function wrapper(id)
        return { IsValid=function() return true end, GetAddress=function() return id end }
    end
    check(UE.same(wrapper(100), wrapper(100)) and not UE.same(wrapper(100), wrapper(101)),
        "ownership uses native addresses, not raw Lua wrapper identity")
    check(not UE.same(wrapper(0), wrapper(0)) and not UE.same(nil, nil), "invalid identities never count as local ownership")
    require("PlayerHPChangeTests").run(check)
    return count
end
return M
