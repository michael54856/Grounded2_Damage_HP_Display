-- Read-only native status-row inspection. No widgets/effects are created or
-- modified; only two typed UMG child getters may execute here.
local Core,M = require("ElementAccumulationCore"),{}
local COUNT,CHILD = "/Script/UMG.PanelWidget:GetChildrenCount","/Script/UMG.PanelWidget:GetChildAt"
local function related(key)
    local lower = key:lower()
    for _,word in ipairs({"status","effect","buff","debuff","timer","duration","remaining","percent","progress","item","entry",
        "child","refresh","update","setcharacter","settarget","construct","icon","panel","row","list","root","box","brush","background"}) do
        if lower:find(word,1,true) then return true end
    end
    return false
end
function M.new(ue,config)
    local probe,schemas,reports,panel_api = {},{},{},nil
    function probe.reset() schemas,reports,panel_api = {},{},nil end
    local function schema(object)
        local class = object:GetClass()
        local identity = ue.name(class)
        if schemas[identity] then return schemas[identity] end
        local count = 0
        for _ in pairs(schemas) do count=count+1 end
        assert(count < config.MaxUIClasses,"UI class budget exceeded")
        ue.log("UI_SCHEMA " .. identity)
        local result,fields,functions = {refs={},scalars={},handles={},brushes={}}, {},{}
        for _=1,config.MaxUIClassDepth do
            if not ue.valid(class) then break end
            local field_count,function_count = 0,0
            class:ForEachProperty(function(property)
                field_count=field_count+1
                if field_count > config.MaxUIFields then
                    ue.once("ui-field-limit:" .. identity,"UI_SCHEMA_LIMIT fields " .. identity); return true
                end
                local key,description = property:GetFName():ToString(),property:GetFullName()
                if fields[key] then return end
                fields[key] = true
                local kind = description:match("^(%S+)")
                if not related(key) then return end
                ue.once("ui-property:" .. description,"UI_PROPERTY " .. description)
                if Core.object_kind(kind) then result.refs[#result.refs+1] = key
                elseif kind == "FloatProperty" or kind == "DoubleProperty" or kind == "IntProperty" or kind == "BoolProperty" then
                    result.scalars[#result.scalars+1] = key
                elseif kind == "StructProperty" and (key:lower():find("rowhandle",1,true) or key == "Brush" or key == "Background") then
                    local ok,struct = pcall(function() return property:GetStruct():GetFullName() end)
                    ue.log("UI_STRUCT field=" .. key .. " type=" .. (ok and struct or "unavailable"))
                    if ok and struct == "ScriptStruct /Script/Engine.DataTableRowHandle" then result.handles[#result.handles+1] = key end
                    if ok and struct == "ScriptStruct /Script/SlateCore.SlateBrush" then result.brushes[#result.brushes+1] = key end
                end
            end)
            class:ForEachFunction(function(fn)
                function_count=function_count+1
                if function_count > config.MaxUIFunctions then
                    ue.once("ui-function-limit:" .. identity,"UI_SCHEMA_LIMIT functions " .. identity); return true
                end
                local key = fn:GetFName():ToString()
                if functions[key] or not related(key) or key:find("ExecuteUbergraph",1,true) then return end
                functions[key] = true
                local parts = {}
                local ok,args = pcall(ue.parameters,fn)
                if ok then for _,field in ipairs(args) do parts[#parts+1] = field.kind .. " " .. field.key end end
                local path = Core.function_path(ue.name(fn))
                ue.once("ui-function:" .. path,"UI_FUNCTION " .. path .. " ["
                    .. (ok and table.concat(parts,", ") or "signature_unavailable") .. "] invoke=false")
            end)
            class = class:GetSuperStruct()
        end
        schemas[identity] = result
        return result
    end
    local function panel_ready()
        if panel_api ~= nil then return panel_api end
        local ok,err = pcall(function()
            local count = ue.parameters(assert(ue.find(COUNT),"GetChildrenCount missing"))
            local child = ue.parameters(assert(ue.find(CHILD),"GetChildAt missing"))
            assert(#count == 1 and count[1].key == "ReturnValue" and count[1].kind == "IntProperty","unexpected count signature")
            assert(#child == 2 and child[1].key == "Index" and child[1].kind == "IntProperty"
                and child[2].key == "ReturnValue" and Core.object_kind(child[2].kind),"unexpected child signature")
        end)
        panel_api = ok
        if not ok then ue.log("UI_API_UNAVAILABLE " .. tostring(err) .. "; reflected widget references remain available") end
        return panel_api
    end
    local function snapshot(hud,world)
        local queue,seen,lines,limited = {},{},{},false
        local function add(object,parent,via,depth,native_child)
            object = ue.unwrap(object)
            if not ue.live(object) or not ue.is_a(object,"/Script/UMG.Widget") or ue.world(object) ~= world then return end
            -- Native children may have their PlayerController as outer; a direct
            -- reflected reference must remain inside this HUD's outer chain.
            if not native_child and not ue.same(object,hud) and not ue.belongs(object,hud) then return end
            local id = ue.address(object)
            if not id or seen[id] then return end
            if #queue >= config.MaxUINodes then limited=true; return end
            seen[id] = true
            queue[#queue+1] = {object=object,id=id,parent=parent,via=via,depth=depth}
        end
        add(hud,0,"enemy_hud",0,false)
        local focus = ue.member(hud,"UI_StatusEffectTimerRow")
        add(focus,ue.address(hud),"UI_StatusEffectTimerRow",1,false)
        local focused = ue.address(focus) and not ue.same(focus,hud) and seen[ue.address(focus)] or false
        lines[#lines+1] = "UI_FOCUS native_status_row=" .. tostring(focused)
        local index = 1
        while index <= #queue do
            local node = queue[index]
            index=index+1
            local object = node.object
            lines[#lines+1] = "UI_NODE id=" .. node.id .. " parent=" .. node.parent .. " via=" .. node.via
                .. " depth=" .. node.depth .. " object=" .. ue.name(object)
            local shape = schema(object)
            for _,key in ipairs(shape.scalars) do
                local value = ue.member(object,key)
                if Core.finite(value) or type(value) == "boolean" then
                    lines[#lines+1] = "UI_VALUE node=" .. node.id .. " field=" .. key .. " value=" .. tostring(value)
                end
            end
            for _,key in ipairs(shape.handles) do
                local ok,row,table_name = pcall(function()
                    local handle = assert(ue.member(object,key),"row handle unavailable")
                    return handle.RowName:ToString(),ue.name(handle.DataTable)
                end)
                if ok then lines[#lines+1] = "UI_ROW_HANDLE node=" .. node.id .. " field=" .. key
                    .. " row=" .. row .. " table=" .. table_name end
            end
            for _,key in ipairs(shape.brushes) do
                local ok,resource = pcall(function() return ue.name(ue.member(object,key).ResourceObject) end)
                if ok then lines[#lines+1] = "UI_BRUSH node=" .. node.id .. " field=" .. key .. " resource=" .. resource end
            end
            for _,key in ipairs(shape.refs) do
                local value = ue.member(object,key)
                lines[#lines+1] = "UI_REF node=" .. node.id .. " field=" .. key .. " value=" .. ue.name(value)
                if node.depth < config.MaxUIDepth and (not focused or not ue.same(object,hud) or key == "UI_StatusEffectTimerRow") then
                    add(value,node.id,key,node.depth+1,false)
                end
            end
            if node.depth < config.MaxUIDepth then
                if ue.is_a(object,"/Script/UMG.UserWidget") and (not focused or not ue.same(object,hud)) then
                    local tree = ue.member(object,"WidgetTree")
                    add(ue.member(tree,"RootWidget"),node.id,"WidgetTree.RootWidget",node.depth+1,false)
                end
                if ue.is_a(object,"/Script/UMG.PanelWidget") and panel_ready() then
                    -- Unbound native UFunctions with explicit live panel context.
                    local count = ue.call(object,COUNT)
                    assert(Core.integer(count) and count >= 0,"invalid native child count")
                    local read = math.min(count,config.MaxUIChildren)
                    if read < count then limited=true end
                    lines[#lines+1] = "UI_CHILDREN node=" .. node.id .. " count=" .. count .. " examined=" .. read
                    for child_index=0,read-1 do
                        add(ue.call(object,CHILD,child_index),node.id,"child[" .. child_index .. "]",node.depth+1,true)
                    end
                end
            else limited=true end
        end
        return lines,#queue,limited
    end
    function probe.scan(controller,world,targets,elapsed)
        local visible,count = {},0
        for _,hud in ipairs(ue.all("EnemyHealthWidget")) do
            if count >= config.MaxUIWidgets then break end
            -- Reuse the validated local HUD / target ownership gate.
            local actor = ue.target_from_widget(hud,controller,world)
            local actor_id = actor and ue.address(actor)
            if actor_id and targets[actor_id] and ue.same(targets[actor_id].actor,actor) then
                local hud_id = ue.address(hud)
                if hud_id then
                    count=count+1
                    local key = actor_id .. ":" .. hud_id
                    visible[key] = true
                    local ok,lines,nodes,limited = pcall(snapshot,hud,world)
                    if ok then
                        local fingerprint = table.concat(lines,"\n") .. " limited=" .. tostring(limited)
                        if Core.should_report(reports[key],fingerprint,elapsed,config.UIHeartbeatSeconds) then
                            ue.log("UI_SNAPSHOT target_id=" .. actor_id .. " hud_id=" .. hud_id .. " elapsed=" .. Core.number(elapsed)
                                .. " nodes=" .. nodes .. " limited=" .. tostring(limited))
                            for _,line in ipairs(lines) do ue.log(line .. " target_id=" .. actor_id .. " hud_id=" .. hud_id) end
                            reports[key] = {fingerprint=fingerprint,time=elapsed}
                        end
                    else ue.once("ui-probe:" .. tostring(lines),"UI_PROBE_ERROR " .. tostring(lines)) end
                end
            end
        end
        for key in pairs(reports) do
            if not visible[key] then ue.log("UI_TARGET_NOT_VISIBLE key=" .. key .. " elapsed=" .. Core.number(elapsed)); reports[key]=nil end
        end
    end
    return probe
end
return M
