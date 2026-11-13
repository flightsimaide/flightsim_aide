import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/flight_sim/flight_sim_repository.dart';
import '../../../data/repositories/settings/settings_repository.dart';
import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/connection_status.dart';
import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../../../domain/models/flight_sim/switch_offer.dart';
import '../../../utils/clock.dart';
import '../../../utils/result.dart';
import 'connection_state.dart';
import 'known_address.dart';

/// Turns the flight-sim repository's streams into the one state the
/// connection UI shows, and carries the user's connection actions.
///
/// The cubit does not know which checklist is on screen; the home flow tells
/// it through [setLoadedAircraft] so it can notice that the simulator moved
/// on to a different aircraft (D-32).
class ConnectionCubit extends Cubit<ConnectionViewState> {
  /// Creates the cubit and starts following [flightSim].
  ConnectionCubit({
    required this._flightSim,
    required this._settings,
    this._clock = const SystemClock(),
  }) : super(const LinkSearching()) {
    _subscriptions
      ..add(_flightSim.connectionStatus.listen((_) => _onRepository(true)))
      ..add(_flightSim.liveAircraft.listen((_) => _onRepository(false)))
      ..add(_flightSim.sims.listen((_) => _onRepository(false)));
    _recompute();
  }

  final FlightSimRepository _flightSim;
  final SettingsRepository _settings;
  final Clock _clock;
  final _subscriptions = <StreamSubscription<Object?>>[];

  AircraftIdentity? _loaded;
  String? _inputError;
  Timer? _hintTimer;
  bool _hint = false;
  DateTime? _chosenAt;
  String? _livePath;
  bool _liveHadChecklist = true;
  bool _cameFromNoChecklist = false;
  String? _acceptedPath;

  /// Tells the cubit which aircraft's checklist is on screen (null for none).
  void setLoadedAircraft(AircraftIdentity? aircraft) {
    _loaded = aircraft;
    _recompute();
  }

  /// The question to switch to another computer, or null (task 0.16).
  SwitchOffer? get currentSwitchOffer => _flightSim.currentSwitchOffer;

  /// Changes of [currentSwitchOffer].
  Stream<SwitchOffer?> get switchOffers => _flightSim.switchOffers;

  /// Answers the switch question: Yes connects to the other computer, No
  /// keeps waiting for the previous one and stops asking about this one.
  Future<void> answerSwitch({required bool accept}) {
    if (accept) _chosenAt = _clock.now();
    return _flightSim.answerSwitch(accept: accept);
  }

  /// Whether the user chose the computer now connected (or being connected
  /// to): its aircraft's checklist then replaces the one on screen without
  /// asking again.
  ///
  /// The choice counts for [chosenWindow]: the new computer may take a while
  /// to report its aircraft, and the old computer's aircraft can show up
  /// first.
  bool get switchedByUser {
    final at = _chosenAt;
    return at != null && _clock.now().difference(at) < chosenWindow;
  }

  /// How long after the user's choice a different aircraft is taken over
  /// without a question.
  static const chosenWindow = Duration(seconds: 60);

  /// Whether the checklist of the aircraft X-Plane has now replaces the one on
  /// screen without a question: the user chose its computer, or the aircraft
  /// before it had no checklist of its own.
  bool get takeOverNewChecklist => switchedByUser || _cameFromNoChecklist;

  /// The checklist of the chosen computer has been taken over.
  void clearSwitchedByUser() => _chosenAt = null;

  /// The stored manual address, for the dialog to pre-fill.
  Future<String?> savedManualIp() => _settings.manualIp();

  /// The addresses the IP dialog lists: the saved one, the one in use, and
  /// every computer whose X-Plane has been seen, each with what is known about
  /// it. With none of these, the example address.
  Future<List<KnownAddress>> knownAddresses() async {
    final saved = await _settings.manualIp();
    final target = _flightSim.currentTarget;
    final connected = _flightSim.current is ConnectionConnected
        ? target?.host
        : null;
    final sims = <DiscoveredSim>[?target, ..._flightSim.currentSims];
    final hosts = <String>{?saved, ?connected, for (final s in sims) s.host};
    if (hosts.isEmpty) {
      return const [
        KnownAddress(address: exampleAddress, description: 'example'),
      ];
    }
    final declined = {for (final s in _flightSim.declinedSims) s.host};
    String describe(String host) {
      final parts = <String>{
        [
          if (host == saved) 'saved',
          if (host == connected) 'connected',
        ].join(' and '),
        for (final s in sims)
          if (s.host == host) ..._facts(s),
        if (declined.contains(host)) 'declined this session',
      }..remove('');
      return parts.isEmpty ? 'unknown' : parts.join(', ');
    }

    return [
      for (final host in hosts)
        KnownAddress(address: host, description: describe(host)),
    ];
  }

  static List<String> _facts(DiscoveredSim sim) => [
    ?sim.name,
    ?sim.os?.displayName,
    ?sim.simulator?.displayName,
  ];

  /// Connects to the sim at [input]. A bad address is shown in the state and
  /// the current connection stays.
  Future<void> setManualIp(String input) async {
    final result = await _flightSim.useManualIp(input);
    if (isClosed) return;
    switch (result) {
      case Error(:final error):
        _inputError = error.message;
      case Ok():
        _inputError = null;
    }
    _recompute();
  }

  /// Typed addresses that connected and are not saved yet.
  Stream<String> get saveOffers => _flightSim.manualIpWorked;

  /// Keeps [address] for the next start.
  Future<void> saveManualIp(String address) async {
    await _settings.saveManualIp(address);
  }

  /// Drops the typed or saved address for this run and searches by beacon; the
  /// saved address stays saved.
  Future<void> dropManualIp() => _flightSim.dropManualIp();

  /// Erases the saved address and goes back to finding the sim by its beacon.
  Future<void> clearManualIp() async {
    await _flightSim.useAutomaticDiscovery();
    if (isClosed) return;
    _inputError = null;
    _recompute();
  }

  /// The computer being connected to, or null while still searching.
  DiscoveredSim? get target => _flightSim.currentTarget;

  /// Stops trying to connect to [target].
  Future<void> cancelConnecting() => _flightSim.cancelConnecting();

  /// Connects again to the sim that [cancelConnecting] stopped.
  Future<void> resumeConnecting() => _flightSim.resumeConnecting();

  /// Starts the search and connection over.
  Future<void> retry() => _flightSim.retry();

  /// Closes the connection while the app is in the background.
  Future<void> pauseLink() => _flightSim.pause();

  /// Reconnects after [pauseLink].
  Future<void> resumeLink() => _flightSim.resume();

  /// Fetches the aircraft and its checklist details again. True when the
  /// sim answered.
  Future<bool> reload() async => await _flightSim.reload() is Ok;

  /// Connects to the chosen [sim].
  Future<void> selectSim(DiscoveredSim sim) {
    _chosenAt = _clock.now();
    return _flightSim.selectSim(sim);
  }

  void _onRepository(bool statusChanged) {
    if (statusChanged) _inputError = null;
    _recompute();
  }

  void _recompute() {
    if (isClosed) return;
    final next = _derive();
    if (next is LinkConnecting) {
      _hintTimer ??= _clock.timer(waitingHintDelay, _onHintDelay);
    } else {
      _hintTimer?.cancel();
      _hintTimer = null;
      _hint = false;
    }
    emit(next.withInputError(_inputError));
  }

  void _onHintDelay() {
    _hintTimer = null;
    _hint = true;
    _recompute();
  }

  ConnectionViewState _derive() {
    final status = _flightSim.current;
    switch (status) {
      case ConnectionSearching():
        return LinkSearching(sims: _flightSim.currentSims);
      case ConnectionConnecting():
        return LinkConnecting(hint: _hint);
      case ConnectionNoNetwork():
        return const LinkNoNetwork();
      case ConnectionLocalNetworkDenied():
        return const LinkLocalNetworkDenied();
      case ConnectionSimUnreachable(:final lastSeen, :final manualAddress):
        final lost = _flightSim.currentTarget;
        return LinkSimUnreachable(
          lastSeen: lastSeen,
          manualAddress: manualAddress,
          computer: lost,
          others: _otherComputers(lost),
        );
      case ConnectionPluginVersionMismatch(:final found, :final required):
        return LinkVersionMismatch(found: found, required: required);
      case ConnectionConnected():
        final live = _flightSim.currentAircraft;
        if (live == null) return LinkConnecting(hint: _hint);
        final loaded = _loaded;
        final computer = _flightSim.currentTarget;
        final others = _otherComputers(computer);
        if (live.aircraftPath != _livePath) {
          // The checklist carried over to an aircraft without one is only a
          // stopgap: the next aircraft's own checklist replaces it.
          _cameFromNoChecklist = _livePath != null && !_liveHadChecklist;
          _livePath = live.aircraftPath;
        }
        _liveHadChecklist = live.checklistPath != null;
        if (_acceptedPath != live.aircraftPath) _acceptedPath = null;
        if (loaded != null && loaded.aircraftPath != live.aircraftPath) {
          // The user chose this computer: its aircraft is not a change. One
          // without a checklist is just that (no checklist); one with a
          // checklist is opened by the dialog host.
          if (switchedByUser) _acceptedPath = live.aircraftPath;
          if (_acceptedPath == live.aircraftPath &&
              live.checklistPath == null) {
            _chosenAt = null; // nothing to open: the choice is used up
          }
          if (_acceptedPath == live.aircraftPath &&
              live.checklistPath == null) {
            return LinkNoChecklist(live, computer: computer, others: others);
          }
          return LinkAircraftChanged(
            loaded: loaded,
            live: live,
            computer: computer,
            others: others,
          );
        }
        if (live.checklistPath == null) {
          return LinkNoChecklist(live, computer: computer, others: others);
        }
        return LinkConnected(live, computer: computer, others: others);
    }
  }

  /// The computers on the list other than [computer].
  List<DiscoveredSim> _otherComputers(DiscoveredSim? computer) => [
    for (final sim in _flightSim.currentSims)
      if (computer == null ||
          !(sim.host == computer.host ||
              (sim.name != null && sim.name == computer.name)))
        sim,
  ];

  @override
  Future<void> close() async {
    _hintTimer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    return super.close();
  }
}
