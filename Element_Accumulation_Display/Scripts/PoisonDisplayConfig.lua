-- Share column sizing/spacing and animation style with the ice bar.
-- Disabling ice display does not disable this independently enabled poison bar.
return setmetatable({
    Enabled=true,
    FillTweenSeconds=0,
    -- Observed cap on the recorded PotatoBug; not a reflected native maximum.
    ReferenceMaximum=100,
    PoisonColor={R=0.66,G=0.30,B=1.0,A=1},
}, {__index=require("ChillDisplayConfig")})
