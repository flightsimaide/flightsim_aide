/// Typed failure carried by `Error` results; repositories never throw to the UI.
sealed class AppException implements Exception {
  /// Human-readable description of the failure.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The checklist text could not be parsed.
class ParseFailure extends AppException {
  /// Creates a parse failure described by [message].
  ParseFailure(this.message);

  @override
  final String message;
}

/// The user dismissed the source picker without choosing anything.
class SourceCancelled extends AppException {
  /// Creates a cancellation failure.
  SourceCancelled();

  @override
  String get message => 'Source selection was cancelled';
}

/// The checklist source could not be read.
class SourceReadFailure extends AppException {
  /// Creates a read failure described by [message].
  SourceReadFailure(this.message);

  @override
  final String message;
}

/// No companion plugin answered the handshake.
class PluginNotDetected extends AppException {
  /// Creates the failure.
  PluginNotDetected();

  @override
  String get message => 'The FlightSim Aide plugin was not detected';
}

/// The plugin speaks a protocol version this app does not.
class PluginVersionMismatch extends AppException {
  /// Creates the failure for a plugin reporting [found] where [required] is
  /// needed.
  PluginVersionMismatch({required this.found, required this.required});

  /// The protocol version the plugin reported.
  final int found;

  /// The protocol version this app requires.
  final int required;

  @override
  String get message =>
      'The plugin speaks protocol $found but this app needs $required';
}

/// The plugin could not be reached (refused, timed out or dropped).
class PluginUnreachable extends AppException {
  /// Creates the failure. [noRouteToHost] is set when the OS refused the
  /// connection with errno 65, which iOS reports while Local Network access
  /// is denied.
  PluginUnreachable({this.noRouteToHost = false});

  /// Whether the connection failed with errno 65 (`No route to host`).
  final bool noRouteToHost;

  @override
  String get message => 'The FlightSim Aide plugin could not be reached';
}

/// The loaded aircraft has no checklist file.
class NoChecklistForAircraft extends AppException {
  /// Creates the failure.
  NoChecklistForAircraft();

  @override
  String get message => 'The loaded aircraft has no checklist';
}

/// The plugin answered something the protocol does not allow.
class ProtocolError extends AppException {
  /// Creates a protocol failure described by [detail].
  ProtocolError(this.detail);

  /// What was wrong with the answer.
  final String detail;

  @override
  String get message => 'Unexpected answer from the plugin: $detail';
}

/// The manually entered simulator address is not usable.
class InvalidManualIp extends AppException {
  /// Creates the failure for the entered [input].
  InvalidManualIp(this.input);

  /// What the user typed.
  final String input;

  @override
  String get message => '"$input" is not a valid IP address';
}
