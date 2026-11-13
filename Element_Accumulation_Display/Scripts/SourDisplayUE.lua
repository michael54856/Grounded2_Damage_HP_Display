-- UI helpers are shared; corrosion schemas/messages are isolated from cold.
local Layout,Numeric,M=require("SourDisplayCore"),require("ElementAccumulationCore"),{}
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
            result.references={"CorrosionComponent"}; return result
        end
        if not ue.is_a(object,"/Script/Maine.CorrosionComponent") then return result end
        local class=object:GetClass()
        local identity=ue.name(class)
        if schemas[identity] then return schemas[identity] end
        local config=probe_config
        local found=false
        for _=1,config.MaxClassDepth do
            if not ue.valid(class) or found then break end
            local count=0
            class:ForEachProperty(function(property)
                count=count+1
                if count > config.MaxFieldsPerClass then return true end
                if property:GetFName():ToString() ~= "CurrentCorrosionLevel" then return end
                found=true
                local kind=property:GetFullName():match("^(%S+)")
                if kind == "FloatProperty" or kind == "DoubleProperty" then
                    result.fields={{key="CurrentCorrosionLevel",kind=kind}}
                    ue.once("sour-display-schema:" .. identity,"SOUR_DISPLAY_SCHEMA_READY class=" .. identity .. " kind=" .. kind)
                else ue.once("sour-display-type:" .. identity,"SOUR_DISPLAY_SCHEMA_UNAVAILABLE kind=" .. tostring(kind)) end
                return true
            end)
            class=class:GetSuperStruct()
        end
        schemas[identity]=result
        return result
    end
    function ue.values(object,schema)
        local values={}
        if #schema.fields == 1 then
            local value=ue.member(object,"CurrentCorrosionLevel")
            if Numeric.finite(value) then values.CurrentCorrosionLevel=value end
        end
        return values
    end
    function ue.bar_rect(controller,bar,viewport,config,row)
        if not ue.live(bar) or not ue.is_a(bar,"/Script/UMG.ProgressBar") or not ue.visible(bar) then return nil end
        local health=ue.widget_rect(bar,controller)
        if not health then return nil end
        local rect=Layout.rect(health,viewport,config,row or config.Row or 1)
        if rect then ue.once("sour-column-ready","SOUR_COLUMN_READY row=" .. rect.row .. " reference_max=" .. config.ReferenceMaximum)
        else ue.once("sour-column-space","SOUR_COLUMN_UNAVAILABLE insufficient_left_or_vertical_space_or_invalid_layout") end
        return rect
    end
    return ue
end
return M
