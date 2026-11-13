return {
    Enabled = true,
    UpdateIntervalMs = 16,
    AnimationIntervalMs = 16,
    -- Show each freshly read value immediately, without added tween delay.
    FillTweenSeconds = 0,
    DiscoveryInterval = 1.0,
    ErrorRetrySeconds = 2.0,
    MaxBars = 2,
    MaxCachedWidgets = 8,
    MaxCachedTargets = 8,
    AppearanceRetryFrames = 3,
    -- Fixed width in DPI-scaled UMG units, independent of monster health width.
    BarWidth = 120,
    -- Only the height follows the native monster health bar.
    HeightScale = 1.0,
    IconHeightScale = 2.0,
    IconAspectRatio = 1.0,
    -- Overlap the transparent image margins slightly to bring the bar closer.
    IconGap = -4,
    -- The supplied PNGs already share matching transparent frame margins.
    FillInsetHeightScale = 0,
    -- Dedicated column to the left of native health; activation order is dynamic.
    ColumnGap = 12,
    ColumnRowGap = 4,
    MaxEffectRows = 5,
    OffsetX = 0,
    OffsetY = 0,
    HideWhenInactive = true,
    FullEffectEnabled = true,
    -- Animate only inside_bar; icon and gold outline remain steady.
    FullPulseEnabled = true,
    FullFlashSeconds = 0.18,
    FullPulseSeconds = 1.0,
    FullFrameEffectEnabled = true,
    -- Static gold inside_bar silhouette behind the background/fill.
    FullFrameThickness = 4,
    FullFrameColor = {R=1.0,G=0.72,B=0.12,A=1},
    ChillingColor = {R=0.40,G=0.78,B=1.0,A=1},
    FrozenColor = {R=0.40,G=0.78,B=1.0,A=1},
    AssetDirectory = nil,
}
