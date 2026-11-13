-- FGeometry has opaque native fields. Consume the native return synchronously;
-- never pass its flattened Lua table back into Slate or change the return value.
local M,PATH = {},"/Script/UMG.Widget:GetCachedGeometry"
function M.new(ue,register_hook)
    local bridge,hooks,pending = {},nil,nil
    function bridge.prepare()
        if hooks then return end
        local fields = ue.parameters(assert(ue.find(PATH),"GetCachedGeometry unavailable"))
        assert(#fields == 1 and fields[1].key == "ReturnValue" and fields[1].kind == "StructProperty",
            "unexpected GetCachedGeometry signature")
        local pre,post = register_hook(PATH,function() end,function(context,native_return)
            local request = pending
            if not request or request.busy or request.finished or not ue.same(ue.unwrap(context),request.widget) then return end
            request.busy = true
            request.ok,request.result = pcall(function()
                local geometry = ue.unwrap(native_return)
                assert(geometry and geometry:type() == "UScriptStruct","native FGeometry wrapper unavailable")
                return request.consume(geometry)
            end)
            request.busy,request.finished = false,true
        end)
        assert(pre ~= nil and post ~= nil,"geometry hook registration failed")
        hooks = {pre=pre,post=post}
        ue.log("CHILL_GEOMETRY_READY source=native_return")
    end
    function bridge.read(widget,consume)
        bridge.prepare()
        assert(not pending,"nested chill geometry read")
        local request = {widget=widget,consume=consume}
        pending = request
        local ok,err = pcall(ue.call,widget,PATH)
        pending = nil
        if not ok then error(err) end
        assert(request.finished,"native geometry return not observed")
        if not request.ok then error(request.result) end
        return request.result
    end
    return bridge
end
return M
