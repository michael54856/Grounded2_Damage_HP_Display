-- Observe native HUD visibility without overriding any game return values.
-- Remote context is unwrapped synchronously; UObject inspection/UI work is
-- deferred to the game thread and multiple notifications share one flush.
local M = {}
function M.new(ue,register_hook,notify_new,execute,on_change)
    local events,hooks,pending,scheduled,prepared = {},{},{},false,false
    local function enqueue(widget)
        if #pending < 16 then pending[#pending+1] = widget end
        if scheduled then return end
        scheduled = true
        local ok,err = pcall(execute,function()
            local batch = pending
            pending,scheduled = {},false
            local success,problem = pcall(on_change,batch)
            if not success then ue.once("hud-event-update:" .. tostring(problem),"STUN_HUD_EVENT_ERROR " .. tostring(problem)) end
        end)
        if not ok then
            pending,scheduled = {},false
            ue.once("hud-event-queue:" .. tostring(err),"STUN_HUD_EVENT_ERROR " .. tostring(err))
        end
    end
    function events.prepare()
        if prepared then return end
        prepared = true
        for _,name in ipairs({"ShowBarNative","HideBarNative"}) do
            local path = "/Script/Maine.EnemyHealthWidget:" .. name
            local ok,err = pcall(function()
                local fn = assert(ue.find(path),"function unavailable")
                assert(#ue.parameters(fn) == 0,"unexpected signature")
                local pre,post = register_hook(path,function() end,function(context)
                    enqueue(ue.unwrap(context))
                    -- No return: preserve the engine's visibility behavior.
                end)
                assert(pre ~= nil and post ~= nil,"hook registration failed")
                hooks[#hooks+1] = {path=path,pre=pre,post=post}
                ue.log("STUN_HUD_EVENT_READY " .. path)
            end)
            if not ok then ue.once("hud-event:" .. path,"STUN_HUD_EVENT_UNAVAILABLE " .. path .. " " .. tostring(err)
                .. "; cached visibility polling remains active") end
        end
        if type(notify_new) == "function" then
            local ok,err = pcall(notify_new,"/Script/Maine.EnemyHealthWidget",function(widget) enqueue(widget) end)
            if not ok then ue.once("hud-create-event","STUN_HUD_EVENT_UNAVAILABLE new_object " .. tostring(err)) end
        end
    end
    return events
end
return M
