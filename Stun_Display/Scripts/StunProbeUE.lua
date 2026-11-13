local Core, Config = require("StunProbeCore"), require("StunProbeConfig")
local State = require("StunProbeState")
local M, objects, schemas, messages, enum_schemas = {}, {}, {}, {}, {}
function M.log(message) print("[Stun_Display] " .. tostring(message) .. "\n") end
function M.once(key, message)
    if not messages[key] then messages[key] = true; M.log(message) end
end
function M.reset()
    objects, schemas, messages, enum_schemas = {}, {}, {}, {}
end
function M.valid(object)
    if object == nil then return false end
    local ok, value = pcall(function() return object:IsValid() end)
    return ok and value == true
end
function M.live(object)
    if not M.valid(object) then return false end
    local ok, bad = pcall(function() return object:HasAnyFlags(0x18030) end)
    return ok and not bad
end
function M.address(object)
    if not M.valid(object) then return nil end
    local ok, id = pcall(function() return object:GetAddress() end)
    if ok and Core.finite(id) and id ~= 0 then return id end
end
function M.same(a,b)
    local first, second = M.address(a), M.address(b)
    return first ~= nil and first == second
end
function M.name(object)
    if not M.valid(object) then return "INVALID" end
    local ok, value = pcall(function() return object:GetFullName() end)
    return ok and value or "NAME_UNAVAILABLE"
end
function M.find(path)
    if M.valid(objects[path]) then return objects[path] end
    local ok, value = pcall(StaticFindObject, path)
    if ok and M.valid(value) then objects[path] = value; return value end
end
function M.is_a(object,path)
    local class = M.find(path)
    if not M.live(object) or not M.valid(class) then return false end
    local ok, value = pcall(function() return object:IsA(class) end)
    return ok and value == true
end
function M.member(object,key)
    if not M.live(object) then return nil end
    local ok, value = pcall(function() return object:GetPropertyValue(key) end)
    if ok then return value end
end
function M.call(object,path,...)
    -- Static engine getters deliberately use their class default object.
    assert(M.valid(object), "invalid getter context: " .. path)
    return assert(M.find(path), "missing getter: " .. path)(object,...)
end
function M.unwrap(value)
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end
function M.world(object)
    if not M.live(object) then return nil end
    local ok, value = pcall(function() return object:GetWorld() end)
    return ok and M.address(value) or nil
end
function M.all(class)
    local ok, value = pcall(FindAllOf, class)
    return ok and value or {}
end
function M.local_player()
    for _, controller in ipairs(M.all("PlayerController")) do
        if M.live(controller) and M.is_a(M.member(controller,"Player"),"/Script/Engine.LocalPlayer") then
            local pawn, world = M.member(controller,"Pawn"), M.world(controller)
            if M.live(pawn) and world then return controller,pawn,world end
        end
    end
end
function M.time(controller)
    local class = assert(M.find("/Script/Engine.GameplayStatics"), "GameplayStatics unavailable")
    local now = M.call(class:GetCDO(),"/Script/Engine.GameplayStatics:GetRealTimeSeconds",controller)
    assert(Core.finite(now), "real-time clock unavailable")
    return now
end
function M.enum_info(property)
    local ok,info = pcall(function()
        local enum = property:GetEnum()
        assert(M.valid(enum), "enum metadata unavailable")
        local path = assert(M.name(enum):match("^Enum%s+(.+)$"),"enum identity unavailable")
        if enum_schemas[path] then return enum_schemas[path] end
        local rows,limited = {},false
        enum:ForEachName(function(name,value)
            if #rows >= Config.MaxEnumEntries then limited = true; return true end
            rows[#rows+1] = {name=name:ToString(),value=value}
        end)
        assert(not limited, "enum entry budget exceeded")
        local compiled,reason = State.enum_info(path,rows,Config.MaxEnumEntries)
        assert(compiled,reason)
        enum_schemas[path] = compiled
        M.once("enum:" .. path,"STUN_ENUM path=" .. path .. " " .. State.enum_text(compiled))
        return compiled
    end)
    if ok then return info end
    M.once("enum-error:" .. tostring(info),"STATE_ENUM_ERROR " .. tostring(info)
        .. "; GetStunState will not be invoked without verified enum metadata")
end
function M.parameters(fn)
    local fields = {}
    local read_state_enum = Core.function_path(M.name(fn)) == State.enum_getter_path
    fn:ForEachProperty(function(property)
        assert(#fields < 32, "function parameter budget exceeded")
        local field = {key=property:GetFName():ToString(), kind=property:GetFullName():match("^(%S+)")}
        if read_state_enum and field.key == "ReturnValue" and field.kind == "EnumProperty" then
            field.enum_info = M.enum_info(property)
        end
        fields[#fields+1] = field
    end)
    return fields
end
local function signature(fields)
    local parts = {}
    for _, field in ipairs(fields) do parts[#parts+1] = field.kind .. " " .. field.key end
    return table.concat(parts,", ")
end
function M.schema(object)
    local class = object:GetClass()
    local cache_key = M.name(class)
    if schemas[cache_key] then return schemas[cache_key] end
    local count = 0
    for _ in pairs(schemas) do count = count + 1 end
    assert(count < Config.MaxSchemasPerCapture, "schema budget exceeded; stop and start a fresh capture")
    local result = {fields={},references={},getters={}}
    local visited_fields, visited_functions = {}, {}
    for _ = 1,Config.MaxClassDepth do
        if not M.valid(class) then break end
        local field_count, function_count = 0,0
        class:ForEachProperty(function(property)
            field_count = field_count + 1
            if field_count > Config.MaxFieldsPerClass then
                M.once("field-limit:" .. cache_key,"SCHEMA_LIMIT fields class=" .. cache_key); return true
            end
            local key, description = property:GetFName():ToString(),property:GetFullName()
            if visited_fields[key] then return end
            visited_fields[key] = true
            local kind = description:match("^(%S+)")
            if Core.related(key) then
                M.once("field:" .. description,"SCHEMA_PROPERTY " .. description)
                if Core.safe_field(key,kind) then result.fields[#result.fields+1] = {key=key,kind=kind} end
            end
            if Core.object_kind(kind) then
                local lower = key:lower()
                if lower:find("component",1,true) or Core.related(key) or lower:find("combat",1,true)
                    or lower:find("attribute",1,true) or lower:find("stat",1,true) then
                    result.references[#result.references+1] = key
                end
            end
        end)
        class:ForEachFunction(function(fn)
            function_count = function_count + 1
            if function_count > Config.MaxFunctionsPerClass then
                M.once("function-limit:" .. cache_key,"SCHEMA_LIMIT functions class=" .. cache_key); return true
            end
            local key = fn:GetFName():ToString()
            if visited_functions[key] or not Core.related(key) then return end
            visited_functions[key] = true
            local ok, fields = pcall(M.parameters,fn)
            local path = Core.function_path(M.name(fn))
            local state_getter = ok and State.safe_getter(path,fields)
            local allowed = ok and (Core.safe_getter(key,fields) or state_getter)
            M.once("function:" .. path,"SCHEMA_FUNCTION " .. path .. " ["
                .. (ok and signature(fields) or tostring(fields)) .. "] read=" .. tostring(allowed))
            -- ForEachFunction binds this wrapper to the class, NOT the instance.
            -- Keep only its path and signature; never retain/invoke that wrapper.
            if allowed then
                result.getters[#result.getters+1] = {key=key,path=path,kind=fields[1].kind}
                if state_getter then
                    result.state_enabled = true
                    if fields[1].enum_info then result.state_enum = fields[1].enum_info end
                end
            end
        end)
        class = class:GetSuperStruct()
    end
    schemas[cache_key] = result
    return result
end
function M.values(object,schema)
    local values = {}
    for _, field in ipairs(schema.fields) do
        M.once("read-field-begin:" .. M.name(object) .. ":" .. field.key,
            "READ_BEGIN field=" .. field.key .. " source=" .. M.name(object))
        local value = M.member(object,field.key)
        if Core.finite(value) or type(value) == "boolean" then values[field.key] = value end
        M.once("read-field-end:" .. M.name(object) .. ":" .. field.key,
            "READ_END field=" .. field.key .. " value=" .. tostring(value))
    end
    for _, getter in ipairs(schema.getters) do
        -- StaticFindObject returns an unbound callable. Pass the live component
        -- explicitly, matching the working health getter implementation.
        M.once("read-getter-begin:" .. M.name(object) .. ":" .. getter.path,
            "READ_BEGIN getter=" .. getter.path .. " source=" .. M.name(object))
        local ok, value = pcall(M.call,object,getter.path)
        local accepted = ok and ((getter.kind == "BoolProperty" and type(value) == "boolean")
            or (getter.kind == "EnumProperty" and State.integer(value))
            or ((getter.kind == nil or getter.kind == "FloatProperty" or getter.kind == "DoubleProperty") and Core.finite(value)))
        if accepted then values[getter.key .. "()"] = value
        elseif not ok then M.once("getter:" .. getter.path,"GETTER_ERROR " .. getter.path .. " " .. tostring(value))
        else M.once("getter-type:" .. getter.path,"GETTER_VALUE_REJECTED " .. getter.path .. " expected="
            .. tostring(getter.kind) .. " value=" .. tostring(value)) end
        M.once("read-getter-end:" .. M.name(object) .. ":" .. getter.path,
            "READ_END getter=" .. getter.path .. " ok=" .. tostring(ok) .. " value=" .. tostring(value))
    end
    return values
end
function M.component_owned(component,actor)
    if not M.is_a(component,"/Script/Engine.ActorComponent") or M.world(component) ~= M.world(actor) then return false end
    local ok, owner = pcall(M.call,component,"/Script/Engine.ActorComponent:GetOwner")
    return ok and M.same(owner,actor)
end
function M.component_list(container,limit)
    assert(Core.finite(limit) and limit > 0 and limit == math.floor(limit), "invalid component enumeration limit")
    local results, examined, limited = {},0,false
    local function add(element)
        if examined >= limit then limited = true; return true end
        examined = examined + 1
        local object = M.unwrap(element)
        if M.valid(object) and M.address(object) then results[#results+1] = object end
    end
    local kind, for_each = type(container),nil
    if kind == "table" then
        for_each = rawget(container,"ForEach")
    elseif kind == "userdata" then
        local ok, method = pcall(function() return container.ForEach end)
        if ok then for_each = method end
    end
    local representation
    if type(for_each) == "function" then
        representation = "tarray"
        for_each(container,function(_,element) return add(element) end)
    elseif kind == "table" and for_each == nil then
        -- UE4SS 1176's GetNonTrivialLocal array return uses 1-based Lua keys.
        -- Its elements may still be RemoteUnrealParam wrappers: unwrap now.
        representation = "lua_table"
        assert(rawget(container,0) == nil, "unexpected zero-based component return table")
        local count = #container
        assert(count > 0 or next(container) == nil, "unexpected non-array component return table")
        for index = 1,math.min(count,limit) do add(container[index]) end
        limited = count > limit
    else
        error("unsupported component array return: " .. kind)
    end
    return results,representation,limited,examined
end
function M.components(actor)
    local fn
    for _, path in ipairs({"/Script/Engine.Actor:K2_GetComponentsByClass","/Script/Engine.Actor:GetComponentsByClass"}) do
        fn = M.find(path)
        if fn then break end
    end
    if not fn then M.once("components-missing","COMPONENT_ENUM_UNAVAILABLE; using reflected actor references"); return {} end
    local fields = M.parameters(fn)
    assert(#fields == 2 and fields[1].key == "ComponentClass" and fields[1].kind == "ClassProperty"
        and fields[2].key == "ReturnValue" and fields[2].kind == "ArrayProperty", "unexpected component-list getter signature")
    -- assert returns ALL arguments; in the final argument position it used to
    -- pass the error string as an extra native parameter. Assignment keeps one.
    local component_class = assert(M.find("/Script/Engine.ActorComponent"),"ActorComponent class missing")
    local components = fn(actor,component_class)
    local results,representation,limited,examined = M.component_list(components,Config.MaxComponentsToInspect)
    local id = tostring(M.address(actor))
    M.once("component-enum:" .. id,"COMPONENT_ENUM_READY format=" .. representation .. " count=" .. #results
        .. " examined=" .. examined .. " actor=" .. M.name(actor))
    if limited then M.once("component-limit:" .. id,"COMPONENT_ENUM_LIMIT actor=" .. M.name(actor)) end
    return results
end
function M.belongs(object,actor)
    if not M.live(object) then return false end
    if M.same(object,actor) then return true end
    if M.is_a(object,"/Script/Engine.ActorComponent") then return M.component_owned(object,actor) end
    local outer, visited = object,{}
    for _ = 1,12 do
        if not M.live(outer) then return false end
        local id = M.address(outer)
        if not id or visited[id] then return false end
        visited[id] = true
        if M.same(outer,actor) then return true end
        outer = outer:GetOuter()
    end
    return false
end
function M.target_from_widget(widget,controller,world)
    if not M.live(widget) or M.world(widget) ~= world or M.member(widget,"bShowing") ~= true then return nil end
    local ok, owner = pcall(M.call,widget,"/Script/Maine.GameUserWidget:GetOwningSurvivalPlayerController")
    if not ok or not M.same(owner,controller) then return nil end
    local actor = M.member(widget,"TargetActor")
    if M.is_a(actor,"/Script/Maine.SurvivalCreature") and M.world(actor) == world then return actor end
end
return M
