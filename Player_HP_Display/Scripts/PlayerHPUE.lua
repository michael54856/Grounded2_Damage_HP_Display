local M, cache, reported = {}, {}, {}
local Core = require("PlayerHPCore")
local geometry_bridge
function M.log(message) print("[Player_HP_Display] " .. tostring(message) .. "\n") end
function M.once(key, message)
    if not reported[key] then reported[key] = true; M.log(message) end
end
function M.valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end
function M.live(object)
    if not M.valid(object) then return false end
    local ok, bad = pcall(function() return object:HasAnyFlags(0x18030) end)
    return ok and not bad
end
function M.address(object)
    if not M.valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if ok and Core.finite(address) and address ~= 0 then return address end
end
function M.same(a, b)
    local first, second = M.address(a), M.address(b)
    return first ~= nil and second ~= nil and first == second
end
function M.find(path)
    if M.valid(cache[path]) then return cache[path] end
    local object = StaticFindObject(path)
    if M.valid(object) then cache[path] = object; return object end
end
function M.member(object, field)
    if not M.valid(object) then return nil end
    local ok, value = pcall(function() return object:GetPropertyValue(field) end)
    if ok then return value end
end
function M.name(object) return M.valid(object) and object:GetFullName() or "INVALID" end
function M.is_a(object, path)
    local class = M.find(path)
    return M.valid(object) and M.valid(class) and object:IsA(class)
end
function M.call(object, path, ...)
    assert(M.valid(object), "invalid context: " .. path)
    return assert(M.find(path), "missing function: " .. path)(object, ...)
end
function M.static(path, method, ...)
    local class = assert(M.find(path), "missing class: " .. path)
    return M.call(class:GetCDO(), path .. ":" .. method, ...)
end
function M.unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end
function M.parameters(fn)
    local fields = {}
    fn:ForEachProperty(function(property)
        fields[#fields + 1] = { name = property:GetFName():ToString(), kind = property:GetFullName():match("^(%S+)") }
    end)
    return fields
end
function M.all(class)
    local ok, objects = pcall(FindAllOf, class)
    return ok and objects or {}
end
function M.world(object)
    if not M.live(object) then return nil end
    local world = object:GetWorld()
    return M.live(world) and M.address(world) or nil
end
function M.local_player()
    for _, controller in ipairs(M.all("PlayerController")) do
        if M.live(controller) and M.is_a(M.member(controller, "Player"), "/Script/Engine.LocalPlayer") then
            local pawn = M.member(controller, "Pawn")
            if M.live(pawn) and M.is_a(pawn, "/Script/Maine.SurvivalCharacter") then
                local world = M.world(controller)
                if world then return controller, pawn, world end
            end
        end
    end
end
function M.health_component(pawn)
    local component = M.member(pawn, "HealthComponent")
    if not M.live(component) then
        local path = "/Script/Maine.SurvivalCharacter:GetHealthComponent"
        if M.find(path) then component = M.call(pawn, path) end
    end
    if M.live(component) and M.is_a(component, "/Script/Maine.HealthComponent")
        and M.same(M.call(component, "/Script/Engine.ActorComponent:GetOwner"), pawn) then return component end
end
function M.health(component)
    return M.call(component, "/Script/Maine.HealthComponent:GetCurrentHealth"),
        M.call(component, "/Script/Maine.HealthComponent:GetMaxHealth")
end
function M.time(controller)
    local now = M.static("/Script/Engine.GameplayStatics", "GetRealTimeSeconds", controller)
    assert(Core.finite(now), "real-time clock unavailable")
    return now
end
function M.owned_by(widget, controller)
    local object, visited = widget, {}
    for _ = 1, 16 do
        if not M.live(object) then break end
        local id = M.address(object)
        if not id or visited[id] then break end
        visited[id] = true
        local owning_player = "/Script/UMG.Widget:GetOwningPlayer"
        if M.is_a(object, "/Script/UMG.Widget") and M.find(owning_player) then
            local ok, owner = pcall(M.call, object, owning_player)
            if ok and M.live(owner) then return M.same(owner, controller) end
        end
        if M.is_a(object, "/Script/Maine.GameUserWidget") then
            local ok, owner = pcall(M.call, object, "/Script/Maine.GameUserWidget:GetOwningSurvivalPlayerController")
            if ok and M.same(owner, controller) then return true end
            if ok and M.live(owner) then return false end
        end
        object = object:GetOuter()
    end
    return false
end
function M.visible(widget)
    local object = widget
    local function shown(value)
        if not M.call(value, "/Script/UMG.Widget:IsVisible") then return false end
        local opacity = M.member(value, "RenderOpacity")
        return not Core.finite(opacity) or opacity > 0
    end
    local parent_complete = false
    for _ = 1, 24 do
        if not M.live(object) then parent_complete = true; break end
        if not shown(object) then return false end
        object = M.call(object, "/Script/UMG.Widget:GetParent")
    end
    if not parent_complete then return false end
    -- A WidgetTree root has no panel parent; also inspect owning UserWidgets
    -- so hiding the entire HUD/menu does not leave this separate overlay behind.
    object = widget
    for _ = 1, 16 do
        if not M.live(object) then return true end
        if M.is_a(object, "/Script/UMG.Widget") and not shown(object) then return false end
        object = object:GetOuter()
    end
    return false
end
function M.viewport(controller)
    local size = M.static("/Script/UMG.WidgetLayoutLibrary", "GetViewportSize", controller)
    local scale = M.static("/Script/UMG.WidgetLayoutLibrary", "GetViewportScale", controller)
    if not Core.finite(scale) or scale <= 0 then return nil end
    return Core.point({ X = size.X / scale, Y = size.Y / scale })
end
function M.rect(widget, controller)
    if not M.live(widget) or not M.visible(widget) then return nil end
    if not geometry_bridge then geometry_bridge = require("PlayerHPGeometry").new(M, RegisterHook) end
    return geometry_bridge.read(widget, function(geometry)
        local size = M.static("/Script/UMG.SlateBlueprintLibrary", "GetLocalSize", geometry)
        local center = Core.center(size)
        if not center then
            local extent = Core.point(size)
            M.once("zero-geometry:" .. tostring(M.address(widget)), "PLAYER_BAR_GEOMETRY_UNAVAILABLE width="
                .. tostring(extent and extent.X) .. " height=" .. tostring(extent and extent.Y) .. " widget=" .. M.name(widget))
            return nil
        end
        local function convert(point)
            local pixel, viewport = {}, {}
            M.static("/Script/UMG.SlateBlueprintLibrary", "LocalToViewport", controller, geometry, point, pixel, viewport)
            return Core.point(viewport)
        end
        local top, bottom, middle = convert({X=0,Y=0}), convert(size), convert(center)
        if not top or not bottom or not middle then return nil end
        return { X = middle.X, Y = middle.Y, width = math.abs(bottom.X - top.X), height = math.abs(bottom.Y - top.Y) }
    end)
end
return M
