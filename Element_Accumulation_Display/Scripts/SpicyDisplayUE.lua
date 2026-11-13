-- Read only the two float properties validated by the Spicy recording.
local Numeric,M=require("ElementAccumulationCore"),{}
function M.new(base,probe_config)
    base=base or require("ChillDisplayUE")
    probe_config=probe_config or require("ElementAccumulationConfig")
    local ue,schemas,messages=setmetatable({}, {__index=base}),{},{}
    function ue.once(key,message)
        if not messages[key] then messages[key]=true; ue.log(message) end
    end
    function ue.reset() schemas,messages={},{} end
    function ue.reset_layout() end
    function ue.schema(object)
        local result={fields={},references={},getters={}}
        if ue.is_a(object,"/Script/Maine.SurvivalCreature") then
            result.references={"BodyTemperatureComponent"}; return result
        end
        if not ue.is_a(object,"/Script/Maine.BodyTemperatureComponent") then return result end
        local class=object:GetClass()
        local identity=ue.name(class)
        if schemas[identity] then return schemas[identity] end
        local found,types={},{}
        for _=1,probe_config.MaxClassDepth do
            if not ue.valid(class) or found.CurrentBodyTemperature and found.MaxSizzle then break end
            local count=0
            class:ForEachProperty(function(property)
                count=count+1
                if count > probe_config.MaxFieldsPerClass then return true end
                local key=property:GetFName():ToString()
                if (key ~= "CurrentBodyTemperature" and key ~= "MaxSizzle") or found[key] then return end
                found[key]=true
                local kind=property:GetFullName():match("^(%S+)")
                if kind == "FloatProperty" or kind == "DoubleProperty" then types[key]=kind end
            end)
            class=class:GetSuperStruct()
        end
        if types.CurrentBodyTemperature and types.MaxSizzle then
            result.fields={{key="CurrentBodyTemperature",kind=types.CurrentBodyTemperature},{key="MaxSizzle",kind=types.MaxSizzle}}
            ue.once("spicy-schema:" .. identity,"SPICY_DISPLAY_SCHEMA_READY class=" .. identity
                .. " current=CurrentBodyTemperature max=MaxSizzle")
        else
            ue.once("spicy-type:" .. identity,"SPICY_DISPLAY_SCHEMA_UNAVAILABLE class=" .. identity
                .. " current_kind=" .. tostring(types.CurrentBodyTemperature) .. " max_kind=" .. tostring(types.MaxSizzle))
        end
        schemas[identity]=result
        return result
    end
    function ue.values(object,schema)
        local values={}
        for _,field in ipairs(schema.fields) do
            local value=ue.member(object,field.key)
            if Numeric.finite(value) then values[field.key]=value end
        end
        return values
    end
    return ue
end
return M
