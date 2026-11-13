import 'dart:async';

/// Time and timers behind one seam, so code with deadlines (stale detection,
/// back-off, polling) can be tested without sleeping.
abstract interface class Clock {
  /// The current time.
  DateTime now();

  /// Runs [callback] once after [delay].
  Timer timer(Duration delay, void Function() callback);

  /// Runs [callback] every [period] until cancelled.
  Timer periodic(Duration period, void Function(Timer timer) callback);
}

/// The real clock.
class SystemClock implements Clock {
  /// Creates the clock.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Timer timer(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  @override
  Timer periodic(Duration period, void Function(Timer timer) callback) =>
      Timer.periodic(period, callback);
}
