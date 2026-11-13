-- Inspect the visible native status row only; never insert/modify buff entries.
local M = {}
local function entry_class(name)
    name = name:lower()
    local status = name:find("statuseffect",1,true) or name:find("buff",1,true) or name:find("debuff",1,true)
    return status and not (name:find("row",1,true) or name:find("list",1,true)
        or name:find("panel",1,true) or name:find("container",1,true) or name:find("tooltip",1,true))
end
function M.new(ue,config)
    local layout = {}
    local function walk(root,world,consume)
        local queue,seen,limited = {{object=root,depth=0}}, {},false
        local index = 1
        while index <= #queue do
            local node=queue[index]; index=index+1
            local object,id=node.object,ue.address(node.object)
            if id and not seen[id] and ue.live(object) and ue.world(object) == world then
                seen[id]=true
                local descend=consume(object,node.depth)
                if descend ~= false then
                    if node.depth >= config.MaxBuffDepth then limited=true
                    else
                        local children,truncated=ue.widget_children(object,config.MaxBuffChildren)
                        limited=limited or truncated
                        for _,child in ipairs(children) do
                            if #queue >= config.MaxBuffNodes then limited=true; break end
                            queue[#queue+1]={object=child,depth=node.depth+1}
                        end
                    end
                end
            end
        end
        return limited
    end
    function layout.read(hud,controller,health)
        local world=ue.world(hud)
        local row=ue.member(hud,"UI_StatusEffectTimerRow")
        if not ue.live(row) or not ue.is_a(row,"/Script/UMG.Widget") or not ue.belongs(row,hud) then
            row=nil
            walk(hud,world,function(object)
                local name=ue.class_key(object):lower()
                if not ue.same(object,hud) and (name:find("statuseffect",1,true) or name:find("buff",1,true))
                    and (name:find("row",1,true) or name:find("list",1,true)) then row=object; return false end
                return row == nil
            end)
        end
        if not row then return {mode="unknown",reason="status_row_unavailable"} end
        if not ue.visible(row) then return {mode="empty",reason="status_row_hidden",count=0} end
        local row_rect=ue.widget_rect(row,controller)
        local entries,icons,bottom,pending,unknown = 0,0,nil,false,false
        local limited=walk(row,world,function(object)
            if not ue.visible(object) then return false end
            if not ue.same(object,row) and ue.is_a(object,"/Script/UMG.UserWidget") then
                if entry_class(ue.class_key(object)) then
                    local rect=ue.widget_rect(object,controller)
                    if rect then entries=entries+1; bottom=math.max(bottom or 0,rect.Y+rect.height)
                    else pending=true end
                    return false -- entry geometry includes its labels / timers
                else unknown=true end
            end
            if ue.is_a(object,"/Script/UMG.Image") and ue.image_resource(object) then
                local rect=ue.widget_rect(object,controller)
                if rect and rect.height > 0 and rect.width/rect.height >= 0.5 and rect.width/rect.height <= 2.0
                    and rect.width < health.width*0.5 then
                    icons=icons+1; bottom=math.max(bottom or 0,rect.Y+rect.height)
                end
            end
        end)
        if bottom then
            if row_rect then bottom=math.max(bottom,row_rect.Y+row_rect.height) end
            return {mode="present",bottom=bottom,count=entries > 0 and entries or icons,
                reason=entries > 0 and "visible_status_entries" or "visible_status_icons"}
        end
        if limited or pending or unknown then return {mode="unknown",reason="incomplete_status_layout",
            bottom=row_rect and row_rect.Y+row_rect.height} end
        return {mode="empty",count=0,reason="no_visible_status_entries"}
    end
    return layout
end
return M
