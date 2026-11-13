local Order,Layout,M=require("ElementDisplayOrder"),require("ChillDisplayCore"),{}
function M.run()
    local checks=0
    local function check(value,message) assert(value,"Element dynamic display self-test: " .. message); checks=checks+1 end
    local function order_is(value,wanted) return table.concat(value,",") == wanted end
    local order=Order.update({}, {"sour"},5)
    check(order_is(order,"sour"),"sour can be first")
    order=Order.update(order,{"ice","sour"},5)
    check(order_is(order,"sour,ice"),"new ice appends rather than taking the first slot")
    order=Order.update(order,{"ice","sour","poison"},5)
    order=Order.update(order,{"sour","poison"},5)
    check(order_is(order,"sour,poison"),"removing a middle item closes its gap")
    order=Order.update(order,{"ice","sour","poison"},5)
    check(order_is(order,"sour,poison,ice"),"a reappearing effect appends to the current bottom")
    check(order_is(Order.update(order,{},5),""),"all effects can disappear")
    check(order_is(Order.update({}, {"ice","ice","sour"},5),"ice,sour"),"duplicate inputs do not create extra slots")
    check(#Order.update({}, {"a","b","c","d","e","f"},5) == 5,"column remains bounded to five effects")

    local config={UpdateIntervalMs=16,DiscoveryInterval=1,ErrorRetrySeconds=2,MaxBars=2,
        MaxCachedWidgets=8,MaxCachedTargets=3,MaxEffectRows=5,BarWidth=120,HeightScale=1,
        IconHeightScale=2,IconAspectRatio=1,IconGap=-4,FillInsetHeightScale=0,
        ColumnGap=12,ColumnRowGap=4,OffsetX=0,OffsetY=0}
    local now,available=0,true
    local controller,pawn={id=1,world=9},{id=2}
    controller.Pawn=pawn
    local a,b,c,d={id=11,world=9},{id=12,world=9},{id=13,world=9},{id=14,world=9}
    local bar={kind="bar"}
    local hud={id=100,actor=a,showing=true,bar=bar}
    local second={id=101,actor=b,showing=true,bar=bar}
    local widgets={hud}
    local levels={[11]={sour=25},[12]={ice=20},[13]={sour=10},[14]={}}
    local reads,builds,latest,clears,adapter_resets,fail={},{},{},{},{},{}
    local scans,geometry,base_resets=0,0,0
    local ue={
        live=function(value) return value ~= nil and not value.dead end,
        same=function(first,other) return first == other end,
        world=function(value) return value.world or 9 end,address=function(value) return value and value.id end,
        local_player=function() if available then return controller,pawn,9 end end,
        member=function(value,key)
            if key == "HealthBar" then return value.bar end
            return value[key]
        end,
        hud_widget=function(value) return not value.foreign end,
        target_from_widget=function(value) if value.showing and not value.foreign and not value.actor.dead then return value.actor end end,
        all=function(kind) check(kind == "EnemyHealthWidget","discovery remains scoped to native monster HUDs"); scans=scans+1; return widgets end,
        time=function() return now end,
        visible=function(value) return value.showing ~= false end,
        is_a=function(value,path) return value.kind == "bar" and path == "/Script/UMG.ProgressBar" end,
        viewport=function() return {X=1920,Y=1080} end,
        widget_rect=function() geometry=geometry+1; return {X=300,Y=50,width=400,height=20} end,
        reset=function() base_resets=base_resets+1 end,name=function() return "FixtureCreature" end,
        once=function() end,
    }
    local effects={}
    for _,id in ipairs({"ice","sour","poison","spicy","fifth"}) do
        local key=id
        local effect_config=setmetatable({Enabled=true},{__index=config})
        local adapter=key == "ice" and ue or {once=function() end,
            reset=function() adapter_resets[key]=(adapter_resets[key] or 0)+1 end}
        effects[#effects+1]={id=key,tag=key:upper(),config=effect_config,ue=adapter,
            core={inactive=function(reason) return reason == "inactive" end,
                model=function(samples)
                    local value=samples[1].value
                    if value <= 0 then return nil,"inactive" end
                    return {current=value,maximum=100,fraction=value/100,phase=key}
                end,
                rect=Layout.rect},
            reader={build=function(actor) builds[actor.id]=(builds[actor.id] or 0)+1; return {actor=actor} end,
                read=function(actor,providers)
                    check(actor == providers.actor,"cached source remains bound to its actor")
                    reads[key]=(reads[key] or 0)+1
                    if fail[key] then error("fixture effect read failure") end
                    return {{value=levels[actor.id][key] or 0}}
                end},
            ui={prepare=function() end,hide=function() latest[key]={} end,
                clear=function() clears[key]=(clears[key] or 0)+1; latest[key]={} end,
                render=function(_,entries) latest[key]=entries end}}
    end
    local runtime=require("ElementDisplayRuntime").new(ue,config,{},effects)
    local function step(candidates) now=now+0.016; runtime.update(candidates) end
    local function row(id,index) return latest[id][index or 1] and latest[id][index or 1].rect.row end
    step()
    check(row("sour") == 1 and #latest.ice == 0,"sour-first native sample occupies row one")
    local sour_key=latest.sour[1].key
    local before_geometry=geometry
    levels[11].ice=35; step()
    check(row("sour") == 1 and row("ice") == 2,"later ice occupies row two")
    check(geometry-before_geometry == 1,"two effects share one native health geometry read per HUD")
    levels[11].poison=10; step()
    check(row("poison") == 3,"a third effect appends below existing active effects")
    levels[11].ice=0; step()
    check(#latest.ice == 0 and row("poison") == 2 and latest.sour[1].key == sour_key,
        "middle removal compacts every effect in the same update without changing surviving animation identity")
    levels[11].ice=50; step()
    check(row("ice") == 3 and row("poison") == 2,"reappearing ice goes to the bottom")
    levels[11].sour=0; step()
    check(row("poison") == 1 and row("ice") == 2,"head removal compacts the remaining column")
    hud.showing=false; step()
    check(#latest.ice == 0 and #latest.poison == 0,"hidden native health hides all effect widgets")
    levels[11].sour=30; hud.showing=true; step()
    check(row("poison") == 1 and row("ice") == 2 and row("sour") == 3,"returning to a hidden target preserves survivor order and appends newcomers")
    hud.actor=b; step()
    check(row("ice") == 1 and #latest.sour == 0,"another creature gets its own activation order")
    hud.actor=a; step()
    check(row("poison") == 1 and row("sour") == 3,"switching back restores this actor's cached order")
    levels[12].sour=40
    local before_scans=scans
    widgets={hud,second}; step({second})
    check(#latest.sour == 2 and row("sour",1) == 3 and row("sour",2) == 2,
        "two visible actors maintain independent sour positions")
    check(scans == before_scans,"new native HUD events work between global discovery scans")
    second.actor=a
    local before_reads=reads.sour; step()
    check(reads.sour-before_reads == 1,"duplicate HUDs for the same actor do not duplicate effect sampling")
    effects[2].config.Enabled=false; step()
    check(#latest.sour == 0 and row("poison") == 1 and row("ice") == 2,"disabling an effect also compacts the column")
    effects[2].config.Enabled=true; step()
    check(row("sour") == 3,"reenabling an effect appends it without disturbing survivors")
    second.showing=false; hud.actor=c; step()
    levels[13].spicy,levels[13].fifth=10,5; step()
    levels[13].ice,levels[13].poison=3,2; step()
    check(row("sour") == 1 and row("spicy") == 2 and row("fifth") == 3 and row("ice") == 4 and row("poison") == 5,
        "all five effects retain activation order, with registration order only for same-sample ties")
    levels[13].spicy=0; step()
    check(row("fifth") == 2 and row("ice") == 3 and row("poison") == 4,"five-effect middle removal leaves no gap")
    fail.sour=true; step()
    check(#latest.sour == 0 and row("fifth") == 1,"one reader failure does not break other effects or leave a phantom slot")
    fail.sour=false; step()
    check(row("sour") == 4,"a recovered effect rejoins at the bottom")
    local old_builds=builds[b.id]
    hud.actor=d; step()
    hud.actor=b; step()
    check(builds[b.id] > old_builds,"bounded per-target history evicts old hidden actors")
    available,controller.Pawn=false,{}
    step()
    check(base_resets == 1 and clears.ice == 1 and clears.sour == 1 and adapter_resets.sour == 1,
        "world/pawn cleanup clears widgets and per-target order for every effect")
    return checks
end
return M
