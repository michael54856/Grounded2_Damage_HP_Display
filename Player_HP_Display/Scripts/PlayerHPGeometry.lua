-- Same native-return preservation approach already tested in the combat HUD.
-- This module has its own state, names and hooks; no other mod is required.
local M = {}
local PATH = "/Script/UMG.Widget:GetCachedGeometry"
function M.new(ue, register)
    local bridge, hooks, pending = {}, nil, nil
    function bridge.prepare()
        if hooks then return end
        local fields = ue.parameters(assert(ue.find(PATH), "GetCachedGeometry missing"))
        assert(#fields == 1 and fields[1].name == "ReturnValue" and fields[1].kind == "StructProperty",
            "unexpected native geometry getter signature")
        local pre, post = register(PATH, function() end, function(context, native_return)
            local request = pending
            if not request or request.busy or request.finished then return end
            if not ue.same(ue.unwrap(context), request.widget) then return end
            request.busy = true
            request.ok, request.value = pcall(function()
                local geometry = ue.unwrap(native_return)
                assert(geometry and geometry:type() == "UScriptStruct", "native FGeometry wrapper unavailable")
                return request.consume(geometry)
            end)
            request.busy, request.finished = false, true
            -- Never return a replacement for the engine's value.
        end)
        assert(pre ~= nil and post ~= nil, "native geometry hook registration failed")
        hooks = { pre, post }
        ue.log("GEOMETRY_BRIDGE_READY source=native_return")
    end
    function bridge.read(widget, consume)
        bridge.prepare()
        assert(not pending, "nested geometry read")
        local request = { widget = widget, consume = consume }
        pending = request
        local ok, err = pcall(ue.call, widget, PATH)
        pending = nil
        if not ok then error(err) end
        assert(request.finished, "native geometry return was not observed")
        if not request.ok then error(request.value) end
        return request.value -- scalars only, consumed before native return expires
    end
    return bridge
end
return M
