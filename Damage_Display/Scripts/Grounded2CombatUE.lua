local M, cache, reported = {}, {}, {}
local Core = require("Grounded2CombatCore")
local geometry_bridge

function M.log(message) print("[Grounded2CombatHUD] " .. tostring(message) .. "\n") end
function M.once(key, message)
    if not reported[key] then reported[key] = true; M.log(message) end
end
function M.valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end
function M.address(object)
    if not M.valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if ok and Core.finite(address) and address ~= 0 then return address end
end
function M.same(first, second)
    if first == nil or second == nil then return first == nil and second == nil end
    local first_address, second_address = M.address(first), M.address(second)
    return first_address ~= nil and second_address ~= nil and first_address == second_address
end
function M.live(object)
    if not M.valid(object) then return false end
    local ok, bad = pcall(function() return object:HasAnyFlags(0x18030) end)
    return ok and not bad -- CDO, archetype, beginning/finished destruction
end
function M.find(path)
    if M.valid(cache[path]) then return cache[path] end
    local object = StaticFindObject(path)
    if M.valid(object) then cache[path] = object; return object end
end
function M.member(object, key)
    if not M.valid(object) then return nil end
    local ok, value = pcall(function() return object:GetPropertyValue(key) end)
    if ok then return value end
end
function M.is_a(object, path)
    local class = M.find(path)
    return M.valid(object) and M.valid(class) and object:IsA(class)
end
function M.name(object)
    return M.valid(object) and object:GetFullName() or "INVALID"
end
function M.call(object, path, ...)
    assert(M.valid(object), "invalid context for " .. path)
    local fn = assert(M.find(path), "missing UFunction " .. path)
    return fn(object, ...)
end
function M.static(class_path, method, ...)
    local class = assert(M.find(class_path), "missing class " .. class_path)
    return M.call(class:GetCDO(), class_path .. ":" .. method, ...)
end
function M.hp(component)
    if not M.live(component) then return nil end
    local current = M.call(component, "/Script/Maine.HealthComponent:GetCurrentHealth")
    local maximum = M.call(component, "/Script/Maine.HealthComponent:GetMaxHealth")
    if Core.finite(current) and Core.finite(maximum) and maximum > 0 then return current, maximum end
end
function M.world(object)
    if not M.live(object) then return nil end
    local world = object:GetWorld()
    if M.live(world) then
        local id = assert(M.address(world), "world address is not readable")
        return world, id
    end
end
function M.local_player()
    for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
        if M.live(controller) and M.is_a(M.member(controller, "Player"), "/Script/Engine.LocalPlayer") then
            local pawn = M.member(controller, "Pawn")
            if M.live(pawn) and M.is_a(pawn, "/Script/Maine.SurvivalCharacter") then
                local world, id = M.world(controller)
                if world then return controller, world, id end
            end
        end
    end
end
function M.unwrap(parameter)
    if parameter == nil then return nil end
    local ok, value = pcall(function() return parameter:get() end)
    return ok and value or parameter
end
function M.parameters(fn)
    local result = {}
    fn:ForEachProperty(function(property)
        result[#result + 1] = { name = property:GetFName():ToString(), kind = property:GetFullName():match("^(%S+)") }
    end)
    return result
end
function M.project(controller, position, viewport)
    local screen = {}
    local projected = M.static("/Script/UMG.WidgetLayoutLibrary", "ProjectWorldLocationToWidgetPosition",
        controller, position, screen, false)
    if not projected or not Core.finite(screen.X) or not Core.finite(screen.Y) then return nil end
    if screen.X < 0 or screen.Y < 0 or screen.X > viewport.X or screen.Y > viewport.Y then return nil end
    return screen.X, screen.Y
end

function M.prepare_bar_geometry()
    if not geometry_bridge then
        geometry_bridge = require("Grounded2CombatGeometry").new(M, RegisterHook)
    end
    geometry_bridge.prepare()
end

-- Return viewport widget units, not desktop pixels. Do not round-trip native
-- FGeometry through a Lua return table: opaque fields would be lost.
function M.bar_anchor(controller, bar)
    assert(M.live(bar), "native HealthBar is unavailable")
    assert(M.is_a(bar, "/Script/UMG.ProgressBar"), "unsupported native HealthBar class: " .. M.name(bar))
    if not M.call(bar, "/Script/UMG.Widget:IsVisible") then return nil end
    M.prepare_bar_geometry()
    return geometry_bridge.read(bar, function(geometry)
        local size = M.static("/Script/UMG.SlateBlueprintLibrary", "GetLocalSize", geometry)
        local extent = Core.point(size)
        local local_point = Core.bar_right_point(size)
        if not local_point then
            M.once("bar-layout", "HUD_BAR_LAYOUT_UNAVAILABLE edge=top_right width=" .. tostring(extent and extent.X)
                .. " height=" .. tostring(extent and extent.Y) .. " source=native_return bar=" .. M.name(bar))
            return nil
        end
        local pixel, viewport = {}, {}
        M.static("/Script/UMG.SlateBlueprintLibrary", "LocalToViewport", controller,
            geometry, local_point, pixel, viewport)
        local point = Core.point(viewport)
        if point then
            M.once("bar-anchor", "HUD_ANCHOR_READY edge=top_right"
                .. " x=" .. Core.number(point.X, 1) .. " y=" .. Core.number(point.Y, 1)
                .. " width=" .. Core.number(extent.X, 1) .. " height=" .. Core.number(extent.Y, 1)
                .. " source=native_return bar=" .. M.name(bar))
        else
            M.once("bar-conversion", "HUD_ANCHOR ERROR invalid native viewport coordinates")
        end
        return point -- copy of scalars; never retain the native struct
    end)
end
return M
