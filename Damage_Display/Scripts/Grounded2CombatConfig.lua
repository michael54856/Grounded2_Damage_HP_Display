return {
    HealthEnabled = true,
    DamageEnabled = true,
    HealthDecimals = 0,
    DamageDecimals = 0,
    MinimumDamage = 1,
    -- health_bar: snapshot the full bar's right edge; world: legacy hit position.
    DamageAnchor = "health_bar",
    -- Offset below the bar's top-right corner; zero starts exactly at the corner.
    DamageBarOffsetY = 0,
    -- Initial angle below rightward horizontal; always launch to the right.
    DamageAngleMin = 15,
    DamageAngleMax = 80,
    DamageFallDistance = 100,
    DamageFontSize = 30,
    DamageLifetime = 1.1,
    DamageFadeStart = 0.55,
    DamageFadePower = 1,
    DamageArcHeight = 70,
    DamageTravelMin = 55,
    DamageTravelMax = 110,
    MaxPopups = 36,
    MaxQueuedEvents = 128,
    -- Prefer one update per engine frame; timer is only a compatibility fallback.
    PreferFrameUpdates = true,
    FrameIntervalMs = 8,
    MaintenanceIntervalMs = 100,
    HealthInterval = 0.10,
    DiscoveryInterval = 1.0,
    DamageColor = { R = 1.0, G = 0.9, B = 0.45, A = 1.0 },
}
