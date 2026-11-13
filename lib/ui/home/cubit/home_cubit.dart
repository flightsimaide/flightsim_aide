import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/checklist/checklist_progress_repository.dart';
import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../data/repositories/flight_sim/flight_sim_repository.dart';
import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/checklist/attach_outcome.dart';
import '../../../domain/models/checklist/checklist_document.dart';
import '../../../domain/models/flight_sim/connection_status.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import 'home_state.dart';

/// Opens a checklist file and clears progress for the new document.
class HomeCubit extends Cubit<HomeState> {
  /// Creates the cubit over the given repositories.
  HomeCubit({
    required this._checklistRepository,
    required this._progressRepository,
    FlightSimRepository? flightSim,
  }) : _flightSim = flightSim,
       super(const HomeInitial()) {
    final sim = flightSim;
    if (sim == null) return;
    _subscriptions
      ..add(sim.connectionStatus.listen(_onStatus))
      ..add(sim.liveAircraft.listen(_onAircraft));
    _maybeAutoLoad();
  }

  final ChecklistRepository _checklistRepository;
  final ChecklistProgressRepository _progressRepository;
  final FlightSimRepository? _flightSim;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _autoLoaded = false;
  bool _lost = false;
  bool _paused = false;
  HomeState? _deferred;

  void _onStatus(ConnectionStatus status) {
    switch (status) {
      case ConnectionNoNetwork() || ConnectionSimUnreachable():
        _lost = true;
      case ConnectionConnected():
        if (_lost) {
          _lost = false;
          unawaited(_reconnect());
        }
      default:
        break;
    }
    _maybeAutoLoad();
  }

  void _onAircraft(AircraftIdentity? live) {
    _maybeAutoLoad();
    unawaited(_maybeRefresh(live));
  }

  /// The same aircraft's checklist file changed on disk (seen after Reload):
  /// load it again in place. The marks stay (same aircraft, so attach is a
  /// no-op) and, with no loading state in between, the list is not reopened.
  Future<void> _maybeRefresh(AircraftIdentity? live) async {
    final current = state;
    final loaded = current is HomeLoaded ? current.aircraft : null;
    if (current is! HomeLoaded || loaded == null || live == null) return;
    if (live.aircraftPath != loaded.aircraftPath) return;
    if (live.checklistModified == loaded.checklistModified &&
        live.checklistSize == loaded.checklistSize) {
      return;
    }
    final result = await _checklistRepository.load();
    if (isClosed || result is! Ok<ChecklistDocument>) return;
    if (state != current) return;
    await _progressRepository.attach(result.value, aircraft: live);
    if (isClosed) return;
    emit(HomeLoaded(result.value, aircraft: live));
  }

  /// The connection is back: with the same aircraft the reconnect rule decides
  /// whether to keep the marks (D-35); another aircraft is left to the
  /// notice and Switch (D-32).
  Future<void> _reconnect() async {
    final sim = _flightSim;
    final current = state;
    if (sim == null || current is! HomeLoaded) return;
    final live = sim.currentAircraft;
    final loaded = current.aircraft;
    if (live == null || loaded == null) return;
    if (live.aircraftPath != loaded.aircraftPath) return;
    final outcome = await _progressRepository.reconnected(runId: sim.runId);
    if (isClosed) return;
    if (outcome is! AttachNeedsPrompt) return;
    _emitOrDefer(HomeReconnectPrompt(current.document, aircraft: loaded));
  }

  /// The app went to the background.
  void appPaused() {
    _paused = true;
  }

  /// The app is back; a prompt that came up meanwhile is shown now.
  void appResumed() {
    _paused = false;
    final deferred = _deferred;
    _deferred = null;
    if (deferred != null && !isClosed) emit(deferred);
  }

  void _emitOrDefer(HomeState next) {
    if (_paused) {
      _deferred = next;
    } else {
      emit(next);
    }
  }

  /// Loads the first aircraft's checklist once, when the simulator is
  /// connected and has an aircraft with a checklist. Later aircraft changes
  /// go through the notice and Switch (D-32).
  void _maybeAutoLoad() {
    final sim = _flightSim;
    if (sim == null || _autoLoaded || isClosed) return;
    if (sim.current is! ConnectionConnected) return;
    if (sim.currentAircraft?.checklistPath == null) return;
    _autoLoaded = true;
    unawaited(load());
  }

  /// Asks the repository for a document; ignored while already loading.
  ///
  /// With a simulator, the aircraft and run id are read before the
  /// load. If the simulator has another aircraft when the load ends, the
  /// result is discarded and nothing is attached (D-32).
  Future<void> load() async {
    if (state is HomeLoading) return;
    final sim = _flightSim;
    final aircraft = sim?.currentAircraft;
    final runId = sim?.runId;
    emit(const HomeLoading());
    final result = await _checklistRepository.load();
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        if (sim != null && !_sameAircraft(sim.currentAircraft, aircraft)) {
          emit(const HomeAircraftChanged());
          _autoLoaded = false;
          _maybeAutoLoad();
          return;
        }
        final outcome = await _progressRepository.attach(
          value,
          aircraft: aircraft,
          runId: runId,
        );
        if (isClosed) return;
        final next = switch (outcome) {
          AttachNeedsPrompt() => HomePromptRestore(value, aircraft: aircraft),
          _ => HomeLoaded(value, aircraft: aircraft),
        };
        if (next is HomePromptRestore) {
          _emitOrDefer(next);
        } else {
          emit(next);
        }
      case Error(error: SourceCancelled()):
        emit(const HomeInitial());
      case Error(:final error):
        emit(HomeFailure(error.message));
    }
  }

  /// Answers the restore prompt: use the saved marks or start clean.
  Future<void> answerPrompt({required bool useSaved}) async {
    final current = state;
    if (current is HomeReconnectPrompt) {
      await _progressRepository.resolvePrompt(useSaved: useSaved);
      if (isClosed) return;
      emit(HomeLoaded(current.document, aircraft: current.aircraft));
      return;
    }
    if (current is! HomePromptRestore) return;
    await _progressRepository.resolvePrompt(useSaved: useSaved);
    if (isClosed) return;
    emit(
      HomeLoaded(
        current.document,
        aircraft: current.aircraft,
        openLast: useSaved ? _progressRepository.lastViewed : null,
        openList: useSaved,
      ),
    );
  }

  static bool _sameAircraft(AircraftIdentity? a, AircraftIdentity? b) =>
      a?.aircraftPath == b?.aircraftPath && a?.generation == b?.generation;

  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    return super.close();
  }

  /// Clears a failure so the banner goes away; no effect in other states.
  void dismissError() {
    if (state is HomeFailure) emit(const HomeInitial());
  }
}
