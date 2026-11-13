import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/switch_offer.dart';
import 'connection_cubit.dart';
import 'connection_state.dart';

/// Which dialog the connection flow wants on screen (task 0.14).
enum ConnectionDialogKind {
  /// None.
  none,

  /// The connection panel as a dialog.
  connection,

  /// "Do you want to continue to be notified of lost connections?"
  askNotify,

  /// X-Plane loaded a different aircraft than the checklist on screen.
  aircraftChanged,

  /// The connection to one computer is lost and another one answered: switch?
  switchComputer,
}

/// What [ConnectionDialogCubit] decided.
class ConnectionDialogState extends Equatable {
  /// Creates the state.
  const ConnectionDialogState(
    this.kind, {
    this.canContinue = false,
    this.live,
    this.offer,
    this.autoOpen = false,
  });

  /// The dialog to show.
  final ConnectionDialogKind kind;

  /// Whether the connection dialog offers "Continue in manual mode" (a
  /// checklist is loaded). Without it the dialog cannot be left.
  final bool canContinue;

  /// For [ConnectionDialogKind.aircraftChanged]: the aircraft X-Plane has now.
  final AircraftIdentity? live;

  /// For [ConnectionDialogKind.switchComputer]: the question.
  final SwitchOffer? offer;

  /// For [ConnectionDialogKind.aircraftChanged]: the user chose this computer,
  /// so its checklist is opened without a question.
  final bool autoOpen;

  @override
  List<Object?> get props => [kind, canContinue, live, offer, autoOpen];
}

/// Decides when the connection dialog opens, and runs the Continue in manual
/// mode / notification flow (task 0.14):
///
/// * not connected and no checklist loaded: the dialog, with no way out;
/// * not connected with a checklist: the dialog with Continue in manual mode,
///   as long as the user wants to be notified of lost connections;
/// * Continue removes the dialog until the connection has come back, and asks
///   whether to keep being notified (Yes / No);
/// * a new run of X-Plane (a different run id) asks that question again when
///   the answer was No;
/// * connected, but X-Plane has a different aircraft than the checklist on
///   screen: a dialog on any page to open its checklist or to continue with
///   the current one. Continue is remembered for that aircraft; another
///   aircraft, or a return to the loaded one, asks again.
class ConnectionDialogCubit extends Cubit<ConnectionDialogState> {
  /// Creates the cubit over [connection]; [runId] gives the run id of the
  /// plugin now connected.
  ConnectionDialogCubit({
    required this._connection,
    required this._runId,
    this._notify = true,
  }) : super(const ConnectionDialogState(ConnectionDialogKind.none)) {
    _connected = _isConnected(_connection.state);
    _trackAircraft(_connection.state);
    if (_connected) _lastRunId = _runId();
    _offer = _connection.currentSwitchOffer;
    _subscription = _connection.stream.listen(_onConnection);
    _offerSubscription = _connection.switchOffers.listen((offer) {
      _offer = offer;
      _recompute();
    });
    _recompute();
  }

  final ConnectionCubit _connection;
  final String? Function() _runId;
  late final StreamSubscription<ConnectionViewState> _subscription;
  late final StreamSubscription<SwitchOffer?> _offerSubscription;
  SwitchOffer? _offer;

  bool _connected = false;
  bool _hasChecklist = false;
  bool _prompting = false;
  bool _notify;
  bool _manual = false;
  bool _askPending = false;
  String? _lastRunId;
  AircraftIdentity? _changedTo;
  String? _continuedWith;

  /// Whether the user wants the dialog to open on every lost connection.
  bool get notify => _notify;

  /// Whether a lost connection opens the dialog right now: false after
  /// Continue in manual mode, until the connection comes back or the user
  /// turns the notification on.
  bool get armed => _notify && !_manual;

  /// The user turned the notification of lost connections on: the dialog
  /// opens at once if the connection is down.
  void enableNotification() {
    _notify = true;
    _manual = false;
    _askPending = false;
    _recompute();
  }

  /// Tells the cubit whether a checklist is loaded ([hasChecklist]) and
  /// whether the restore question is on screen ([prompting]); the notification
  /// question waits for the restore question.
  void setChecklist({required bool hasChecklist, required bool prompting}) {
    if (hasChecklist == _hasChecklist && prompting == _prompting) return;
    _hasChecklist = hasChecklist;
    _prompting = prompting;
    _recompute();
  }

  /// The user chose Continue in manual mode.
  void continueManually() {
    if (!_hasChecklist) return;
    _manual = true;
    _askPending = true;
    _recompute();
  }

  /// The answer to the notification question.
  void answerNotify({required bool notify}) {
    _notify = notify;
    _askPending = false;
    _recompute();
  }

  /// The user keeps the checklist on screen although X-Plane has [_changedTo].
  void continueWithCurrentChecklist() {
    _continuedWith = _changedTo?.aircraftPath;
    _recompute();
  }

  static bool _isConnected(ConnectionViewState s) =>
      s is LinkConnected || s is LinkNoChecklist || s is LinkAircraftChanged;

  void _trackAircraft(ConnectionViewState state) {
    if (state is LinkAircraftChanged) {
      _changedTo = state.live;
    } else {
      _changedTo = null;
      _continuedWith = null;
    }
  }

  void _onConnection(ConnectionViewState state) {
    _connected = _isConnected(state);
    _trackAircraft(state);
    if (_connected) {
      _manual = false;
      final runId = _runId();
      if (runId != null) {
        if (_lastRunId != null && runId != _lastRunId && !_notify) {
          _askPending = true;
        }
        _lastRunId = runId;
      }
    }
    _recompute();
  }

  void _recompute() {
    if (isClosed) return;
    final ConnectionDialogState next;
    if (_askPending && !_prompting) {
      next = const ConnectionDialogState(ConnectionDialogKind.askNotify);
    } else if (_changedTo != null &&
        _changedTo!.aircraftPath != _continuedWith) {
      next = ConnectionDialogState(
        ConnectionDialogKind.aircraftChanged,
        live: _changedTo,
        autoOpen:
            _connection.takeOverNewChecklist &&
            _changedTo!.checklistPath != null,
      );
    } else if (!_connected &&
        _offer != null &&
        (!_hasChecklist || (_notify && !_manual))) {
      // Another computer answered while this one is lost: ask before moving.
      next = ConnectionDialogState(
        ConnectionDialogKind.switchComputer,
        offer: _offer,
      );
    } else if (!_connected && (!_hasChecklist || (_notify && !_manual))) {
      next = ConnectionDialogState(
        ConnectionDialogKind.connection,
        canContinue: _hasChecklist,
      );
    } else {
      next = const ConnectionDialogState(ConnectionDialogKind.none);
    }
    emit(next);
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _offerSubscription.cancel();
    return super.close();
  }
}
