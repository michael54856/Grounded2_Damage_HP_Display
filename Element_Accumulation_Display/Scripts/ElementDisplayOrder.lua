-- Per-target activation order. Retain active survivors, then append newcomers.
local M={}
function M.update(previous,active,limit)
    local available,seen,result={},{},{}
    for _,id in ipairs(active) do available[id]=true end
    local function add(id)
        if available[id] and not seen[id] and #result < limit then
            seen[id]=true; result[#result+1]=id
        end
    end
    for _,id in ipairs(previous or {}) do add(id) end
    for _,id in ipairs(active) do add(id) end
    return result
end
return M
