-- Folder name retained so the existing UE4SS activation entry keeps working.
local function log(message) print("[Grounded2CombatHUD] " .. tostring(message) .. "\n") end
local ok, err = pcall(function()
    local tests = require("Grounded2CombatTests")
    log("SELF_TESTS PASS count=" .. tests.run())
    require("Grounded2CombatRuntime").start()
end)
if not ok then log("STARTUP ERROR " .. tostring(err)) end
