-- Share column sizing/spacing and animation style with the ice bar.
-- Disabling ice display does not disable this independently enabled woozy bar.
return setmetatable({
    Enabled=true,
    FillTweenSeconds=0,
    -- Observed cap on the recorded PotatoBug; not a reflected native maximum.
    ReferenceMaximum=100,
    WoozyColor={R=1.0,G=0.84,B=0.10,A=1},
}, {__index=require("ChillDisplayConfig")})
