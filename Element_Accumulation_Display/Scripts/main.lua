local ok,err = pcall(function()
    local ue = require("ElementAccumulationUE")
    ue.log("SELF_TESTS PASS count=" .. require("ElementAccumulationTests").run())
    local ui_ok,ui_result = pcall(function() return require("ElementAccumulationUIProbeTests").run() end)
    if ui_ok then ue.log("UI_PROBE_SELF_TESTS PASS count=" .. ui_result)
    else ue.log("UI_PROBE_STARTUP_ERROR " .. tostring(ui_result) .. "; effect capture remains available") end
    local effect=require("ElementAccumulationConfig").Effect
    if effect == "Sour" then
        ue.log("SOUR_PROBE_SELF_TESTS PASS count=" .. require("SourProbeTests").run())
        require("SourProbeRuntime").start()
    elseif effect == "Spicy" then
        ue.log("SPICY_PROBE_SELF_TESTS PASS count=" .. require("SpicyProbeTests").run())
        require("SpicyProbeRuntime").start()
    elseif effect == "Poison" then
        ue.log("POISON_PROBE_SELF_TESTS PASS count=" .. require("PoisonProbeTests").run())
        require("PoisonProbeRuntime").start()
    elseif effect == "Woozy" then
        ue.log("WOOZY_PROBE_SELF_TESTS PASS count=" .. require("WoozyProbeTests").run())
        require("WoozyProbeRuntime").start()
    elseif effect == "Chill" then require("ElementAccumulationRuntime").start(ui_ok)
    else error("unsupported diagnostic effect " .. tostring(effect)) end
end)
if not ok then print("[Element_Accumulation_Display] STARTUP_ERROR " .. tostring(err) .. "\n") end

-- Run every fake-UI test before starting the shared real UI loop. Test-only global
-- constructor replacements must never overlap a live overlay's construction.
local displays={
    {tag="CHILL",tests="ChillDisplayTests"},
    {tag="SOUR",tests="SourDisplayTests"},
    {tag="SPICY",tests="SpicyDisplayTests"},
    {tag="POISON",tests="PoisonDisplayTests"},
    {tag="WOOZY",tests="WoozyDisplayTests"},
}
for _,display in ipairs(displays) do
    display.ok,display.result=pcall(function() return require(display.tests).run() end)
    if display.ok then
        require("ElementAccumulationUE").log(display.tag .. "_UI_SELF_TESTS PASS count=" .. display.result)
    else
        print("[Element_Accumulation_Display] " .. display.tag .. "_UI_STARTUP_ERROR " .. tostring(display.result) .. "\n")
    end
end
local order_ok,order_result=pcall(function() return require("ElementDisplayTests").run() end)
if order_ok then
    require("ElementAccumulationUE").log("ELEMENT_UI_SELF_TESTS PASS count=" .. order_result)
    local ready={}
    for _,display in ipairs(displays) do ready[display.tag]=display.ok end
    local started,problem=pcall(function() require("ElementDisplayRuntime").start(ready) end)
    if not started then print("[Element_Accumulation_Display] ELEMENT_UI_STARTUP_ERROR " .. tostring(problem) .. "\n") end
else print("[Element_Accumulation_Display] ELEMENT_UI_STARTUP_ERROR " .. tostring(order_result) .. "\n") end
