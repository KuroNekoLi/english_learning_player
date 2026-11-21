const _coordinatedModes = {'opfsShared', 'opfsLocks', 'sharedIndexedDb'};

/// Whether a Drift storage mode persists data and coordinates browser tabs.
bool webStorageModeAllowsWrites(String mode) =>
    _coordinatedModes.contains(mode);
