-- Share the left column and static full-value gold frame with ice/sour.
-- Every target supplies its own native MaxSizzle; no configured maximum.
return setmetatable({
    Enabled=true,
    FillTweenSeconds=0,
    SpicyColor={R=1.0,G=0.24,B=0.06,A=1},
}, {__index=require("ChillDisplayConfig")})
