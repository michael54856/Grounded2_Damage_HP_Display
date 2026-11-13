-- Test only fake native events/queues; never register real hooks here.
local M = {}
function M.run(check)
    local hooks,queue,batches,created,registrations,notifications = {},{},{},nil,0,0
    local ue = {find=function(path) return {path=path} end,parameters=function() return {} end,
        unwrap=function(value) return value:get() end,once=function() end,log=function() end}
    local events = require("StunDisplayEvents").new(ue,function(path,_,post)
        hooks[path]=post; registrations=registrations+1; return registrations*2,registrations*2+1
    end,function(path,callback)
        check(path == "/Script/Maine.EnemyHealthWidget","new-object subscription is restricted to enemy HUD widgets")
        notifications=notifications+1; created=callback
    end,function(callback) queue[#queue+1]=callback end,function(batch) batches[#batches+1]=batch end)
    events.prepare(); events.prepare()
    check(registrations == 2 and notifications == 1,"visibility observers are installed once per mod state")
    local widget,another = {},{}
    local show = hooks["/Script/Maine.EnemyHealthWidget:ShowBarNative"]
    local hide = hooks["/Script/Maine.EnemyHealthWidget:HideBarNative"]
    check(select("#",show({get=function() return widget end})) == 0,"HUD observer does not override native return values")
    hide({get=function() return widget end}); created(another)
    check(#queue == 1 and #batches == 0,"native notifications defer work and share one game-thread queue flush")
    queue[1]()
    check(#batches == 1 and #batches[1] == 3 and batches[1][1] == widget and batches[1][3] == another,
        "unwrapped contexts survive until deferred processing without retaining remote parameter buffers")
    created(widget)
    check(#queue == 2,"notifications after a flush can schedule the next update")
    queue[2]()
    local rejected = 0
    local invalid = require("StunDisplayEvents").new({find=ue.find,
        parameters=function() return {{key="Reason",kind="IntProperty"}} end,once=function() end,log=function() end},
        function() rejected=rejected+1 end,nil,function() end,function() end)
    invalid.prepare()
    check(rejected == 0,"changed native visibility signatures are not hooked; polling can remain active")
end
return M
