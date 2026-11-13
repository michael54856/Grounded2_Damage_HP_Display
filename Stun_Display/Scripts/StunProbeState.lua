-- State decoding uses reflected enum names, never assumed numeric ordinals.
local Core, M = require("StunProbeCore"),{}
M.enum_getter_path = "/Script/Maine.ReactionComponent:GetStunState"
M.bool_getter_path = "/Script/Maine.ReactionComponent:IsStunned"
function M.integer(value)
    return Core.finite(value) and value == math.floor(value)
end
function M.enum_info(path,rows,limit)
    if type(path) ~= "string" or path == "" or type(rows) ~= "table" or not M.integer(limit)
        or limit <= 0 or #rows == 0 or #rows > limit then return nil,"invalid_enum_metadata" end
    local result,by_name = {path=path,names={},rows={}},{}
    for _, row in ipairs(rows) do
        if type(row) ~= "table" or type(row.name) ~= "string" or row.name == "" or not M.integer(row.value) then return nil,"invalid_enum_entry" end
        if result.names[row.value] and result.names[row.value] ~= row.name then return nil,"ambiguous_enum_value" end
        if by_name[row.name] ~= nil and by_name[row.name] ~= row.value then return nil,"ambiguous_enum_name" end
        if not result.names[row.value] then result.rows[#result.rows+1] = {name=row.name,value=row.value} end
        result.names[row.value],by_name[row.name] = row.name,row.value
    end
    table.sort(result.rows,function(a,b) return a.value < b.value end)
    return result
end
function M.enum_text(info)
    local parts = {}
    for _, row in ipairs(info.rows) do parts[#parts+1] = row.name .. "=" .. tostring(row.value) end
    return table.concat(parts," ")
end
function M.safe_getter(path,fields)
    if type(fields) ~= "table" or #fields ~= 1 or type(fields[1]) ~= "table"
        or fields[1].key ~= "ReturnValue" then return false end
    if path == M.bool_getter_path then return fields[1].kind == "BoolProperty" end
    if path == M.enum_getter_path then
        local info = fields[1].enum_info
        return fields[1].kind == "EnumProperty" and type(info) == "table"
            and type(info.names) == "table" and next(info.names) ~= nil and type(info.path) == "string"
    end
    return false
end
local function named_phase(name)
    local leaf = name:match("([^:]+)$")
    return ({None="normal",Stunned="stunned",StunCooldown="cooldown"})[leaf] or "unknown"
end
function M.observe(values,info)
    local raw,stunned = values["GetStunState()"],values["IsStunned()"]
    local observation = {raw=M.integer(raw) and raw or nil,phase="unknown",mapped_phase="unknown",
        enum_path=info and info.path or "unavailable",name="unavailable",check="enum_unavailable"}
    if type(stunned) == "boolean" then observation.is_stunned = stunned end
    if info then
        if observation.raw == nil then observation.check = "value_unavailable"
        elseif not info.names[observation.raw] then observation.name,observation.check = "unknown_value","unknown_value"
        else
            observation.name = info.names[observation.raw]
            observation.mapped_phase = named_phase(observation.name)
            observation.phase = observation.mapped_phase
            if observation.phase == "unknown" then observation.check = "unknown_enum_name"
            elseif observation.is_stunned == nil then observation.check = "enum_only"
            elseif (observation.phase == "stunned") ~= observation.is_stunned then
                observation.phase,observation.check = "unknown","conflict"
            else observation.check = "agree" end
        end
    end
    return observation
end
function M.describe(observation)
    local raw = observation.raw ~= nil and tostring(observation.raw) or "unavailable"
    local stunned = observation.is_stunned == nil and "unavailable" or tostring(observation.is_stunned)
    return "state_raw=" .. raw .. " state_name=" .. observation.name .. " phase=" .. observation.phase
        .. " mapped_phase=" .. observation.mapped_phase .. " is_stunned=" .. stunned
        .. " state_check=" .. observation.check .. " state_enum=" .. observation.enum_path
end
function M.event(previous,current,now)
    local fingerprint = M.describe(current)
    local record = {observation=current,fingerprint=fingerprint,time=now}
    if not previous then return "STUN_STATE_INITIAL " .. fingerprint,record end
    if previous.fingerprint ~= fingerprint then
        return "STUN_STATE_TRANSITION from_raw=" .. tostring(previous.observation.raw)
            .. " from_name=" .. previous.observation.name .. " from_phase=" .. previous.observation.phase
            .. " previous_state_seconds=" .. Core.number(now - previous.time) .. " " .. fingerprint,record
    end
    return nil,previous -- retain state-entry time, not the latest sample time
end
return M
