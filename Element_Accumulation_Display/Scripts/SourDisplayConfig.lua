-- Share column sizing/spacing and animation style with the ice bar.
-- Disabling ice display does not disable this independently enabled sour bar.
return setmetatable({
    Enabled=true,
    FillTweenSeconds=0,
    -- Observed cap on the recorded PotatoBug; not a reflected native maximum.
    ReferenceMaximum=100,
    SourColor={R=0.35,G=0.82,B=0.13,A=1},
}, {__index=require("ChillDisplayConfig")})
