local function log(message) print("[Player_HP_Display] " .. tostring(message) .. "\n") end
local ok, err = pcall(function()
    log("SELF_TESTS PASS count=" .. require("PlayerHPTests").run())
    require("PlayerHPRuntime").start()
end)
if not ok then log("STARTUP ERROR " .. tostring(err)) end
