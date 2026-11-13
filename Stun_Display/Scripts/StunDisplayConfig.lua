return {
    Enabled = true,
    -- Image opacity; filled and empty regions never overlap underneath.
    Opacity = 0.75,
    UpdateIntervalMs = 100,
    AnimationIntervalMs = 16,
    FillTweenSeconds = 0.10,
    DiscoveryInterval = 1.0,
    MaxCachedWidgets = 8,
    AppearanceRetryFrames = 3,
    ErrorRetrySeconds = 2.0,
    MaxBars = 2,
    WidthScale = 0.5,
    HeightScale = 0.5,
    GapBelowHealthBar = 0,
    OffsetX = 0,
    OffsetY = 0,
    NormalColor = {R=1,G=1,B=1,A=1},
    -- Optional extra tint. State colors are already baked into exact-alpha PNGs.
    StunnedColor = {R=1,G=1,B=1,A=1},
    CooldownColor = {R=1,G=1,B=1,A=1},
    -- Normally resolved from this mod's Scripts directory, independent of Steam path.
    AssetDirectory = nil,
}
