import 'dart:async';

import 'package:flightsim_aide/utils/clock.dart';

/// A clock that only moves when a test calls [advance]. Timers fire in due
/// order during an advance, including timers set by other timers' callbacks.
class ManualClock implements Clock {
  /// Creates the clock at [start] (default: a fixed instant).
  ManualClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 10, 25, 12);

  DateTime _now;
  final List<_ManualTimer> _timers = [];

  @override
  DateTime now() => _now;

  /// How many timers are waiting to fire.
  int get pendingTimers => _timers.where((t) => t.isActive).length;

  @override
  Timer timer(Duration delay, void Function() callback) =>
      _add(delay, null, (_) => callback());

  @override
  Timer periodic(Duration period, void Function(Timer timer) callback) =>
      _add(period, period, callback);

  _ManualTimer _add(
    Duration delay,
    Duration? period,
    void Function(Timer) callback,
  ) {
    final timer = _ManualTimer(_now.add(delay), period, callback);
    _timers.add(timer);
    return timer;
  }

  /// Moves time forward by [by], firing every timer that falls due.
  void advance(Duration by) {
    final target = _now.add(by);
    while (true) {
      _timers.removeWhere((t) => !t.isActive);
      _ManualTimer? next;
      for (final t in _timers) {
        if (!t.due.isAfter(target) &&
            (next == null || t.due.isBefore(next.due))) {
          next = t;
        }
      }
      if (next == null) break;
      _now = next.due;
      next.fire();
    }
    _now = target;
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.due, this._period, this._callback);

  DateTime due;
  final Duration? _period;
  final void Function(Timer) _callback;
  bool _active = true;
  int _ticks = 0;

  void fire() {
    _ticks++;
    final period = _period;
    if (period == null) {
      _active = false;
    } else {
      due = due.add(period);
    }
    _callback(this);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;
}
