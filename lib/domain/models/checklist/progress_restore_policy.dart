/// What to do with progress saved for an aircraft when it is attached.
enum RestoreAction {
  /// Nothing was saved; start clean.
  nothing,

  /// Load the saved marks silently.
  restore,

  /// Ask the user.
  prompt,
}

/// What to do when the connection comes back with the same aircraft.
enum ReconnectAction {
  /// Leave everything as it is.
  keep,

  /// Ask the user.
  prompt,
}

/// The restore rule (D-35, reworked by task 0.15): pure, no I/O. A run id
/// from the plugin tells an X-Plane restart (a different id) from a dropped
/// link (the same id).
abstract final class ProgressRestorePolicy {
  /// Decides for a cold start or a switch to another aircraft. [savedRunId] is
  /// the run id stored with the marks, [runId] the one X-Plane reports now;
  /// either may be null when unknown, which asks the user.
  static RestoreAction decide({
    required bool hasSaved,
    required String? savedRunId,
    required String? runId,
  }) {
    if (!hasSaved) return RestoreAction.nothing;
    if (runId != null && runId == savedRunId) return RestoreAction.restore;
    return RestoreAction.prompt;
  }

  /// Decides when the connection returns with the same aircraft while the app
  /// kept running and holds marks.
  static ReconnectAction decideReconnect({
    required String? lastRunId,
    required String? runId,
  }) {
    if (runId != null && runId == lastRunId) return ReconnectAction.keep;
    return ReconnectAction.prompt;
  }
}
