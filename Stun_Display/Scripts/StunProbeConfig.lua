return {
    SampleIntervalMs = 100,
    DiscoveryInterval = 1.0,
    CaptureSeconds = 600,
    HeartbeatSeconds = 2.0,
    MaxTargets = 2,
    MaxComponentsToInspect = 64,
    MaxProvidersPerTarget = 12,
    MaxClassDepth = 8,
    MaxFieldsPerClass = 256,
    MaxFunctionsPerClass = 256,
    MaxSchemasPerCapture = 64,
    MaxEnumEntries = 32,
    -- Optional exact, case-insensitive source path substring from PROVIDER logs.
    PreferredProviderPathContains = nil,
}
