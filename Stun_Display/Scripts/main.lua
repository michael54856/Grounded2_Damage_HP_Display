local function log(message) print("[Stun_Display] " .. tostring(message) .. "\n") end
local ok, err = pcall(function()
    log("SELF_TESTS PASS count=" .. require("StunProbeTests").run())
    require("StunProbeRuntime").start()
end)
if not ok then log("STARTUP ERROR " .. tostring(err)) end
local ui_ok,ui_error = pcall(function()
    log("UI_SELF_TESTS PASS count=" .. require("StunDisplayTests").run())
    require("StunDisplayRuntime").start()
end)
if not ui_ok then log("UI_STARTUP_ERROR " .. tostring(ui_error)) end
