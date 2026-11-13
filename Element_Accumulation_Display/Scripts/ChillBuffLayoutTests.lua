local M={}
function M.run(check,config)
    local serial=0
    local function node(class,children,rect,hidden)
        serial=serial+1
        return {id=serial,class=class,children=children or {},rect=rect,hidden=hidden}
    end
    local row=node("UI_StatusEffectTimerRow_C",{}, {X=100,Y=45,width=400,height=35})
    local hud=node("UI_EnemyHealth_C",{row}); hud.UI_StatusEffectTimerRow=row
    local function is_a(object,path)
        local class=path:match("([^%.]+)$")
        if class == "Widget" then return true end
        if class == "UserWidget" then return object.class:find("UI_",1,true) == 1 end
        return object.class == class
    end
    local ue={live=function(value) return type(value) == "table" end,
        address=function(value) return value.id end,world=function() return 1 end,
        member=function(object,key) return object[key] end,
        same=function(a,b) return a.id == b.id end,belongs=function() return true end,is_a=is_a,
        class_key=function(object) return object.class end,visible=function(object) return not object.hidden end,
        widget_rect=function(object) return object.rect end,
        widget_children=function(object,limit)
            local results={}
            for i=1,math.min(#object.children,limit) do results[i]=object.children[i] end
            return results,#object.children > limit
        end,
        image_resource=function(object) return object.resource end}
    local layout=require("ChillBuffLayout").new(ue,config)
    local health={X=100,Y=20,width=400,height=20}
    local function read() return layout.read(hud,{},health) end
    check(read().mode == "empty","visible row with no entries is empty, regardless of reserved row size")
    row.hidden=true
    check(read().mode == "empty","hidden row moves accumulation up")
    row.hidden=false
    local buff=node("UI_StatusEffectTimer_C",{}, {X=100,Y=45,width=28,height=28})
    row.children={buff}
    check(read().mode == "present" and read().bottom == 80,"visible native buff reserves the entire row geometry")
    buff.hidden=true
    check(read().mode == "empty","hidden entry and its descendants do not count as buffs")
    buff.hidden=false
    local second=node("UI_StatusEffectTimer_C",{}, {X=100,Y=85,width=28,height=28})
    row.children={buff,second}
    check(read().bottom == 113 and read().count == 2,"wrapped entries reserve the lowest visible row")
    local icon=node("Image",{}, {X=100,Y=45,width=28,height=28}); icon.resource={}
    row.children={node("HorizontalBox",{icon})}
    check(read().mode == "present" and read().count == 1,"native icon image can identify a visible buff without assuming a blueprint class")
    icon.hidden=true
    check(read().mode == "empty","hidden native icon is ignored")
    row.children={node("UI_UnrecognizedEntry_C",{})}
    check(read().mode == "unknown","unrecognized user widgets are not silently treated as empty")
    row.children={node("UI_StatusEffectTimer_C",{})}
    check(read().mode == "unknown","visible entry awaiting layout reserves space")
    row.children={buff}; hud.UI_StatusEffectTimerRow=nil
    check(read().mode == "present","bounded HUD traversal can locate an unnamed row reference")
    hud.children={}
    check(read().mode == "unknown","missing row never means no buffs")
    hud.UI_StatusEffectTimerRow=row
    local nested=node("HorizontalBox",{})
    local cursor=nested
    for _=1,config.MaxBuffDepth+2 do
        local child=node("HorizontalBox",{}); cursor.children={child}; cursor=child
    end
    row.children={nested}
    check(read().mode == "unknown","traversal budget cannot turn an incomplete inspection into an empty row")
end
return M
