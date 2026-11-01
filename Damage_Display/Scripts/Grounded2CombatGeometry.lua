-- Preserve opaque FGeometry while it is still a native return parameter.
-- On UE4SS 1ba38db4 normal struct return values become reflected Lua tables;
-- FGeometry's non-reflected fields do not survive that round trip.
local M = {}
local PATH = "/Script/UMG.Widget:GetCachedGeometry"

-- Dependencies are injected so regression tests never install real hooks.
function M.new(ue, register_hook)
    local bridge, hooks, pending = {}, nil, nil

    function bridge.prepare()
        if hooks then return end
        local fn = assert(ue.find(PATH), "GetCachedGeometry is unavailable")
        local fields = ue.parameters(fn)
        assert(#fields == 1 and fields[1].name == "ReturnValue" and fields[1].kind == "StructProperty",
            "unexpected GetCachedGeometry signature")
        local pre, post = register_hook(PATH, function() end, function(context, native_return)
            local request = pending
            if not request or request.busy or request.finished then return end
            -- Do not inspect or change other widgets' GetCachedGeometry calls.
            if not ue.same(ue.unwrap(context), request.widget) then return end
            request.busy = true
            request.ok, request.result = pcall(function()
                -- This pinned UE4SS build supplies the original return as the
                -- second POST-hook argument, before any ordinary parameters.
                local geometry = ue.unwrap(native_return)
                assert(geometry and geometry:type() == "UScriptStruct", "native FGeometry wrapper is unavailable")
                return request.consume(geometry)
            end)
            request.busy, request.finished = false, true
            -- No return value: never override the engine's geometry.
        end)
        assert(pre ~= nil and post ~= nil, "geometry observation hook registration failed")
        hooks = { pre = pre, post = post }
        ue.log("HUD_GEOMETRY_BRIDGE_READY source=native_return")
    end

    function bridge.read(widget, consume)
        bridge.prepare()
        assert(not pending, "nested geometry read is not supported")
        local request = { widget = widget, consume = consume }
        pending = request
        -- Ignore the flattened Lua return. Consume the native structure only
        -- inside the synchronous post callback, before the return buffer dies.
        local ok, err = pcall(ue.call, widget, PATH)
        pending = nil
        if not ok then error(err) end
        assert(request.finished, "native geometry return was not observed")
        if not request.ok then error(request.result) end
        return request.result
    end

    return bridge
end
return M
