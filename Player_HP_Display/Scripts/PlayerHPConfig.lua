return {
    Enabled = true,
    UpdateIntervalMs = 100,
    DiscoveryInterval = 1.0,
    FontSize = 18,
    MinimumFontSize = 10,
    FitFontToBarHeight = true,
    Color = { R = 1, G = 1, B = 1, A = 1 },
    OffsetX = 0,
    OffsetY = 0,
    RequireBottomLeft = true,
    MinimumBarWidth = 30,
    MinimumBarAspectRatio = 1.5,
    -- Runtime-confirmed local-player vitals subtree (not overhead nameplates).
    -- Optional exact, case-insensitive substring from a HEALTH_WIDGET log entry.
    -- Never bypasses ownership, world or visibility checks.
    TargetWidgetPathContains = "WBP_PlayerVitals_Augusta.",
    -- Signed HP changes, anchored just outside the full bar's right edge.
    PopupEnabled = true,
    AnimationIntervalMs = 16,
    PopupFontSize = 20,
    PopupLifetime = 1.1,
    PopupRise = 60,
    PopupGap = 12,
    PopupOffsetY = 0,
    PopupFadeStart = 0.3, -- fraction of lifetime; early linear fade
    MaxPopups = 12,
    HealColor = { R = 0.25, G = 1, B = 0.35, A = 1 },
    DamageColor = { R = 1, G = 0.25, B = 0.2, A = 1 },
}
