local Core,M = require("SourProbeCore"),{}
function M.new(base,config)
    base=base or require("ElementAccumulationUE")
    config=config or require("ElementAccumulationConfig")
    -- Separate schema/messages from cold display. F5 must not reset its caches.
    local ue,schemas,messages=setmetatable({}, {__index=base}),{},{}
    function ue.log(message)
        message=tostring(message)
        base.log(message:match("^SOUR_") and message or "SOUR_" .. message)
    end
    function ue.once(key,message)
        if not messages[key] then messages[key]=true; ue.log(message) end
    end
    function ue.reset() schemas,messages={},{} end
    function ue.schema(object)
        local class=object:GetClass()
        local identity=ue.name(class)
        if schemas[identity] then return schemas[identity] end
        local count=0; for _ in pairs(schemas) do count=count+1 end
        assert(count < config.MaxSchemasPerCapture,"sour schema budget exceeded")
        local focused=ue.is_a(object,"/Script/Maine.CorrosionComponent")
        local result,seen_fields,seen_functions={fields={},references={},getters={}}, {},{}
        if focused then ue.once("corrosion-class:" .. identity,"SOUR_COMPONENT_CLASS " .. identity) end
        for depth=1,config.MaxClassDepth do
            if not ue.valid(class) then break end
            local fields,functions=0,0
            class:ForEachProperty(function(property)
                fields=fields+1
                if fields > config.MaxFieldsPerClass then
                    ue.once("field-limit:" .. identity,"SOUR_SCHEMA_LIMIT fields class=" .. identity); return true
                end
                local key=property:GetFName():ToString()
                if seen_fields[key] then return end
                seen_fields[key]=true
                local description=property:GetFullName()
                local kind=description:match("^(%S+)")
                if focused or Core.related(key) then
                    local allowed=Core.safe_field(key,kind,focused)
                    ue.once("property:" .. description,"SOUR_SCHEMA_PROPERTY " .. description .. " read=" .. tostring(allowed))
                    if allowed then result.fields[#result.fields+1]={key=key,kind=kind} end
                end
                if Core.object_kind(kind) then
                    local lower=key:lower()
                    if lower:find("component",1,true) or Core.related(key) or lower:find("combat",1,true)
                        or lower:find("attribute",1,true) or lower:find("stat",1,true) then
                        result.references[#result.references+1]=key
                    end
                end
            end)
            class:ForEachFunction(function(fn)
                functions=functions+1
                if functions > config.MaxFunctionsPerClass then
                    ue.once("function-limit:" .. identity,"SOUR_SCHEMA_LIMIT functions class=" .. identity); return true
                end
                local key=fn:GetFName():ToString()
                if seen_functions[key] or not (Core.related(key) or focused and depth == 1) then return end
                seen_functions[key]=true
                local ok,args=pcall(ue.parameters,fn)
                local parts={}
                if ok then for _,field in ipairs(args) do parts[#parts+1]=field.kind .. " " .. field.key end end
                local path=Core.function_path(ue.name(fn))
                ue.once("function:" .. path,"SOUR_SCHEMA_FUNCTION " .. path .. " ["
                    .. (ok and table.concat(parts,", ") or "signature_unavailable") .. "] invoke=false")
            end)
            class=class:GetSuperStruct()
        end
        schemas[identity]=result
        return result
    end
    function ue.values(object,schema)
        local values={}
        for _,field in ipairs(schema.fields) do
            local key=ue.name(object) .. ":" .. field.key
            ue.once("read-begin:" .. key,"SOUR_READ_BEGIN field=" .. field.key .. " source=" .. ue.name(object))
            local value=ue.member(object,field.key)
            if Core.accepted(field.kind,value) then values[field.key]=value
            else ue.once("read-rejected:" .. key,"SOUR_VALUE_REJECTED field=" .. field.key
                .. " kind=" .. field.kind .. " type=" .. type(value) .. " source=" .. ue.name(object)) end
            ue.once("read-end:" .. key,"SOUR_READ_END field=" .. field.key .. " value=" .. tostring(values[field.key]))
        end
        return values
    end
    return ue
end
return M
