import 'dart:async';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/connection_status.dart';
import '../../../domain/models/flight_sim/dataref.dart';
import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../../../domain/models/flight_sim/simulator.dart';
import '../../../domain/models/flight_sim/switch_offer.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/clock.dart';
import '../../../utils/ipv4.dart';
import '../../../utils/result.dart';
import '../../services/flight_sim/flight_sim_service.dart';
import '../../services/flight_sim/model/plugin_session.dart';
import '../../services/flight_sim/model/raw_signal_message.dart';
import '../../services/flight_sim/model/signal_spec.dart';
import '../../services/flight_sim/model/sim_endpoint.dart';
import '../../services/flight_sim/network_status_service.dart';
import '../../services/flight_sim/plugin_session_source.dart';
import '../../services/flight_sim/plugin_state.dart';
import '../../services/flight_sim/sim_discovery_service.dart';
import '../settings/settings_repository.dart';
import 'dataref_watch.dart';
import 'dataref_watch_hub.dart';
import 'flight_sim_repository.dart';

/// [FlightSimRepository] over the companion plugin link.
///
/// It reads the connection from [FlightSimService], the aircraft from
/// [PluginSessionSource] (it makes no HTTP request of its own, D-15) and
/// maps both to domain types. Status precedence (D-33): no network first;
/// then searching until a sim is chosen; then connecting, connected, plugin
/// not detected or version mismatch; a sim that answered before and has gone
/// quiet is unreachable.
class FlightSimRepositoryRemote implements FlightSimRepository {
  /// Creates the repository. Call [start] to begin.
  ///
  /// After the first beacon the repository waits [simSettle] for others
  /// before it connects on its own, so two sims on the LAN are offered as a
  /// choice (D-25) instead of the first one winning.
  FlightSimRepositoryRemote({
    required this.flightSim,
    required this.sessions,
    required this.network,
    required this.settings,
    required this.createDiscovery,
    this.clock = const SystemClock(),
    this.simSettle = const Duration(milliseconds: 1500),
  }) {
    _hub = DatarefWatchHub(source: flightSim, settings: settings, clock: clock);
  }

  /// The live link.
  final FlightSimService flightSim;

  /// Where the loaded aircraft comes from.
  final PluginSessionSource sessions;

  /// Whether the device has a network.
  final NetworkStatusService network;

  /// Stored manual IP.
  final SettingsRepository settings;

  /// The time source.
  final Clock clock;

  /// How long to wait for further sims after the first beacon.
  final Duration simSettle;

  /// Creates the discovery: a beacon listener for `null`, or the manual one.
  final SimDiscoveryService Function(String? manualHost) createDiscovery;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _manualWorked = StreamController<String>.broadcast();
  final _aircraftController = StreamController<AircraftIdentity?>.broadcast();
  final _onGroundController = StreamController<bool?>.broadcast();
  final _simsController = StreamController<List<DiscoveredSim>>.broadcast();
  final _offersController = StreamController<SwitchOffer?>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final DatarefWatchHub _hub;

  ConnectionStatus _status = const ConnectionSearching();
  AircraftIdentity? _aircraft;
  bool? _onGround;
  final List<DiscoveredSim> _sims = [];

  /// Every address each sim announced from, best first; keyed by [_key].
  final Map<String, List<String>> _hosts = {};

  /// The OS each sim's plugin reported; keyed by [_key].
  final Map<String, HostOs> _os = {};

  /// The sims whose plugin was already asked for its OS this search.
  final Set<String> _asked = {};

  /// When each sim's beacon was last heard; keyed by [_key].
  final Map<String, DateTime> _heard = {};
  final Set<String> _probing = {};

  /// A sim whose beacon has not been heard for this long leaves the list.
  /// Beacons come once a second, so this tolerates four lost ones.
  static const beaconExpiry = Duration(seconds: 5);

  Timer? _expiryTimer;

  /// Computers the user said No to: no question and no automatic connection,
  /// but they stay on the list and can still be chosen (task 0.16).
  final Set<String> _declined = {};

  /// The computer last connected to in this run, for the switch question.
  SimEndpoint? _previousEndpoint;
  DiscoveredSim? _previous;
  SwitchOffer? _offer;

  SimDiscoveryService? _discovery;
  StreamSubscription<SimEndpoint>? _discoverySubscription;
  Timer? _settleTimer;

  bool _manual = false;

  /// A typed address that has not connected yet, so is not saved.
  String? _temporaryIp;
  bool _networkUp = true;
  bool _paused = false;
  bool _disposed = false;
  SimEndpoint? _target;
  bool _everConnected = false;
  DateTime? _lastSeen;
  AppException? _sessionError;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  ConnectionStatus get current => _status;

  @override
  Stream<AircraftIdentity?> get liveAircraft => _aircraftController.stream;

  @override
  AircraftIdentity? get currentAircraft => _aircraft;

  @override
  Stream<bool?> get onGroundChanges => _onGroundController.stream;

  @override
  bool? get onGround => _onGround;

  @override
  String? get runId => flightSim.runId;

  @override
  Stream<List<DiscoveredSim>> get sims => _simsController.stream;

  @override
  List<DiscoveredSim> get currentSims => List.unmodifiable(_sims);

  @override
  DiscoveredSim? get currentTarget {
    final target = _target;
    if (target == null) return null;
    return DiscoveredSim(
      host: target.host,
      name: target.name,
      simulator: _manual ? null : Simulator.xplane,
      os: _os[target.name ?? target.host],
    );
  }

  @override
  DiscoveredSim? get previousSim => _previous;

  @override
  List<DiscoveredSim> get declinedSims => List.unmodifiable([
    for (final sim in _sims)
      if (_declined.contains(_key(sim))) sim,
  ]);

  @override
  Stream<SwitchOffer?> get switchOffers => _offersController.stream;

  @override
  SwitchOffer? get currentSwitchOffer => _offer;

  @override
  Future<void> start() async {
    if (_subscriptions.isNotEmpty || _disposed) return;
    _subscriptions
      ..add(flightSim.pluginStates.listen((_) => _recompute()))
      ..add(flightSim.streamConnected.listen(_onStreamConnected))
      ..add(flightSim.signals.listen(_onSignal))
      ..add(flightSim.unavailableSignals.listen(_onUnavailable))
      ..add(network.availability.listen(_onNetwork))
      ..add(sessions.changes.listen(_onSession, onError: _onSessionError));
    network.start();
    final session = sessions.current;
    if (session != null) _setAircraft(_identity(session));
    final manual = await settings.manualIp();
    _expiryTimer = clock.periodic(const Duration(seconds: 1), (_) => _expire());
    if (manual != null) {
      await _connectManual(manual);
    }
    // The beacon listener always runs, so the list of computers is current.
    await _startAutomatic();
  }

  // --- user actions -------------------------------------------------------

  @override
  Future<Result<void>> useManualIp(String input) async {
    final ip = input.trim();
    if (!isUsableIpv4(ip)) return Error(InvalidManualIp(input));
    _undeclineHost(ip);
    _temporaryIp = ip;
    await _connectManual(ip);
    return const Ok(null);
  }

  @override
  Stream<String> get manualIpWorked => _manualWorked.stream;

  @override
  Future<void> dropManualIp() async {
    _manual = false;
    _temporaryIp = null;
    await _searchAgain();
  }

  @override
  Future<void> useAutomaticDiscovery() async {
    await settings.clearManualIp();
    await dropManualIp();
  }

  @override
  Future<void> retry() async {
    final target = _target;
    if (_manual && target != null) {
      await _connect(target);
      return;
    }
    await _searchAgain();
  }

  @override
  Future<void> cancelConnecting() async {
    _settleTimer?.cancel();
    await flightSim.disconnect();
    _recompute();
  }

  @override
  Future<void> resumeConnecting() async {
    final target = _target;
    if (target == null) {
      await _searchAgain();
    } else {
      await _connect(target);
    }
  }

  /// Forgets the sim and listens for beacons from scratch.
  Future<void> _searchAgain() async {
    await flightSim.disconnect();
    _paused = false;
    _target = null;
    _everConnected = false;
    _lastSeen = null;
    _sessionError = null;
    _sims.clear();
    _hosts.clear();
    _os.clear();
    _asked.clear();
    _setOffer(null);
    _simsController.add(currentSims);
    _recompute();
    await _stopDiscovery();
    await _startAutomatic();
  }

  @override
  Future<void> selectSim(DiscoveredSim sim) async {
    _settleTimer?.cancel();
    _declined.remove(_key(sim));
    _setOffer(null);
    await _connect(_endpointFor(sim));
  }

  @override
  Future<void> answerSwitch({required bool accept}) async {
    final offer = _offer;
    if (offer == null) return;
    _setOffer(null);
    if (accept) {
      _declined.remove(_key(offer.to));
      _settleTimer?.cancel();
      await _connect(_endpointFor(offer.to));
    } else {
      _declined.add(_key(offer.to));
    }
  }

  void _undeclineHost(String host) {
    for (final sim in List.of(_sims)) {
      if ((_hosts[_key(sim)] ?? [sim.host]).contains(host)) {
        _declined.remove(_key(sim));
      }
    }
  }

  void _setOffer(SwitchOffer? offer) {
    if (offer == _offer) return;
    _offer = offer;
    if (!_disposed) _offersController.add(offer);
  }

  bool _isSame(DiscoveredSim sim, SimEndpoint? e) {
    if (e == null) return false;
    if (_key(sim) == (e.name ?? e.host)) return true;
    final hosts = _hosts[_key(sim)] ?? [sim.host];
    return hosts.contains(e.host) || e.alternateHosts.any(hosts.contains);
  }

  /// A computer whose beacon has not been heard for [beaconExpiry] is asked
  /// for its hello: X-Plane stops beaconing while it loads an aircraft but its
  /// plugin still answers, so an answer keeps the computer listed. No answer
  /// (X-Plane was closed, or the network is gone) drops it.
  void _expire() {
    if (_disposed || _paused) return;
    final now = clock.now();
    for (final sim in List.of(_sims)) {
      final key = _key(sim);
      if (now.difference(_heard[key] ?? now) < beaconExpiry) continue;
      if (!_probing.add(key)) continue;
      unawaited(
        flightSim.peekHello(_endpointFor(sim)).then((hello) {
          _probing.remove(key);
          if (_disposed || _paused) return;
          if (hello != null) {
            if (_heard.containsKey(key)) _heard[key] = clock.now();
            return;
          }
          // Beacons may have come back while the probe was running.
          final last = _heard[key];
          if (last != null && clock.now().difference(last) < beaconExpiry) {
            return;
          }
          _drop(key);
        }),
      );
    }
  }

  void _drop(String key) {
    _heard.remove(key);
    _hosts.remove(key);
    _asked.remove(key);
    final before = _sims.length;
    final gone = _sims.where((s) => _key(s) == key).toList();
    _sims.removeWhere((s) => _key(s) == key);
    if (_sims.length == before) return;
    final offer = _offer;
    if (offer != null && _key(offer.to) == key) _setOffer(null);
    if (gone.isNotEmpty) _simsController.add(currentSims);
  }

  /// The computer being waited for is back on another address (same name,
  /// new beacon address): retry there instead of at the old one.
  void _followAddressChange(DiscoveredSim sim) {
    final target = _target;
    if (target == null || _manual || target.name == null) return;
    if (target.name != sim.name || !_isSame(sim, target)) return;
    if (_status is! ConnectionSimUnreachable) return;
    final next = _endpointFor(sim);
    if (next.host == target.host &&
        next.alternateHosts.length == target.alternateHosts.length) {
      return;
    }
    _target = next;
    unawaited(flightSim.connect(next));
  }

  /// The connected computer is gone and a beacon from another one,
  /// not blocked, is known: ask before moving (task 0.16).
  void _checkLostOffer() {
    if (_offer != null || _disposed || _target == null) return;
    if (_status is! ConnectionSimUnreachable) return;
    for (final sim in _sims) {
      if (_isSame(sim, _target) || _declined.contains(_key(sim))) continue;
      _setOffer(SwitchOffer(from: _previous ?? currentTarget, to: sim));
      return;
    }
  }

  @override
  Future<Result<AircraftIdentity>> reload() async {
    final result = await sessions.reload();
    switch (result) {
      case Error(:final error):
        if (error is PluginVersionMismatch) {
          _sessionError = error;
          _recompute();
        }
        return Error(error);
      case Ok(:final value):
        _sessionError = null;
        final identity = _identity(value);
        _setAircraft(identity);
        _recompute();
        return Ok(identity);
    }
  }

  @override
  DatarefWatch watch(Iterable<Dataref> datarefs) => _hub.watch(datarefs);

  @override
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    _settleTimer?.cancel();
    _asked.clear();
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _discovery?.stop();
    await flightSim.pause();
  }

  @override
  Future<void> resume() async {
    if (!_paused || _disposed) return;
    _paused = false;
    // Beacons were not listened to while paused: give every entry a new start.
    final now = clock.now();
    _heard.updateAll((_, _) => now);
    _expiryTimer ??= clock.periodic(
      const Duration(seconds: 1),
      (_) => _expire(),
    );
    await _discovery?.start();
    await flightSim.resume();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
    _expiryTimer?.cancel();
    await _hub.dispose();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _stopDiscovery();
    await _statusController.close();
    await _manualWorked.close();
    await _aircraftController.close();
    await _onGroundController.close();
    await _simsController.close();
    await _offersController.close();
  }

  // --- discovery ----------------------------------------------------------

  Future<void> _startAutomatic() async {
    final discovery = createDiscovery(null);
    _discovery = discovery;
    _discoverySubscription = discovery.endpoints.listen(_onSimSeen);
    await discovery.start();
  }

  Future<void> _stopDiscovery() async {
    _settleTimer?.cancel();
    _settleTimer = null;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    final discovery = _discovery;
    _discovery = null;
    await discovery?.dispose();
  }

  void _onSimSeen(SimEndpoint endpoint) {
    if (_disposed) return;
    // One X-Plane announces itself once per network adapter, from a different
    // address each time; the computer name makes them one sim.
    final key = endpoint.name ?? endpoint.host;
    _heard[key] = clock.now();
    final hosts = _hosts.putIfAbsent(key, () => []);
    if (!hosts.contains(endpoint.host)) {
      hosts
        ..add(endpoint.host)
        ..sort((a, b) => _hostRank(a).compareTo(_hostRank(b)));
    }
    final sim = DiscoveredSim(
      host: hosts.first,
      name: endpoint.name,
      // A beacon on X-Plane's multicast group comes from X-Plane.
      simulator: Simulator.xplane,
      os: _os[key],
    );
    final index = _sims.indexWhere((s) => _key(s) == key);
    if (index >= 0) {
      if (_sims[index] == sim) {
        _followAddressChange(sim);
        _checkLostOffer();
        return;
      }
      _sims[index] = sim;
    } else {
      _sims.add(sim);
    }
    _simsController.add(currentSims);
    if (_target != null) {
      _followAddressChange(sim);
      _checkLostOffer();
      return;
    }
    _askAboutFacts();
    _settleTimer ??= clock.timer(simSettle, _decide);
  }

  /// With a choice to make, asks each computer's plugin which OS it runs on
  /// (once per search). A plugin that does not answer, or does not say, leaves
  /// the OS unknown.
  void _askAboutFacts() {
    if (_sims.length < 2) return;
    for (final sim in List.of(_sims)) {
      final key = _key(sim);
      if (!_asked.add(key)) continue;
      unawaited(
        flightSim.peekHello(_endpointFor(sim)).then((hello) {
          final os = HostOs.fromWire(hello?.os);
          if (os == null || _disposed) return;
          _os[key] = os;
          final index = _sims.indexWhere((s) => _key(s) == key);
          if (index < 0) return;
          _sims[index] = _sims[index].withOs(os);
          _simsController.add(currentSims);
        }),
      );
    }
  }

  void _decide() {
    _settleTimer = null;
    if (_target != null || _manual || _offer != null) return;
    final open = [
      for (final sim in _sims)
        if (!_declined.contains(_key(sim))) sim,
    ];
    if (open.length != 1) return;
    final sim = open.single;
    final before = _previousEndpoint;
    if (before != null && !_isSame(sim, before)) {
      // Never move to another computer without asking (task 0.16).
      _setOffer(SwitchOffer(from: _previous, to: sim));
      return;
    }
    unawaited(_connect(_endpointFor(sim)));
  }

  static String _key(DiscoveredSim sim) => sim.name ?? sim.host;

  SimEndpoint _endpointFor(DiscoveredSim sim) {
    final hosts = _hosts[_key(sim)] ?? [sim.host];
    return SimEndpoint(
      host: hosts.first,
      name: sim.name,
      alternateHosts: hosts.skip(1).toList(),
    );
  }

  /// Lower is tried first: home and office networks (192.168, 10) before the
  /// virtual adapters of containers and WSL (172.16 to 172.31).
  static int _hostRank(String host) {
    if (host.startsWith('192.168.')) return 0;
    if (host.startsWith('10.')) return 1;
    final second = int.tryParse(host.split('.').elementAtOrNull(1) ?? '');
    if (host.startsWith('172.') &&
        second != null &&
        second >= 16 &&
        second <= 31) {
      return 3;
    }
    return 2;
  }

  Future<void> _connectManual(String host) async {
    _manual = true;
    await _connect(SimEndpoint(host: host));
  }

  Future<void> _connect(SimEndpoint sim) async {
    _target = sim;
    _everConnected = false;
    _lastSeen = null;
    _sessionError = null;
    _recompute();
    await flightSim.connect(sim);
    _recompute();
  }

  // --- inputs -------------------------------------------------------------

  void _onStreamConnected(bool up) {
    if (up) {
      _everConnected = true;
      _lastSeen = clock.now();
      _previousEndpoint = _target;
      _previous = currentTarget;
      _offerToSave();
    } else {
      _setOnGround(null);
    }
    _recompute();
  }

  /// A typed address answered: let the user decide whether to keep it.
  void _offerToSave() {
    final ip = _temporaryIp;
    if (ip == null || !_manual || _target?.host != ip) return;
    _temporaryIp = null;
    unawaited(_announceIfNew(ip));
  }

  Future<void> _announceIfNew(String ip) async {
    if (await settings.manualIp() == ip || _disposed) return;
    _manualWorked.add(ip);
  }

  void _onSignal(RawSignalMessage signal) {
    _lastSeen = clock.now();
    if (signal.name != onGroundSignal) return;
    final value = signal.value;
    _setOnGround(value == null ? null : value != 0);
  }

  void _onUnavailable(String name) {
    if (name == onGroundSignal) _setOnGround(null);
  }

  void _onNetwork(bool up) {
    _networkUp = up;
    _recompute();
  }

  void _onSession(PluginSession? session) {
    _sessionError = null;
    _setAircraft(session == null ? null : _identity(session));
    _recompute();
  }

  void _onSessionError(Object error) {
    if (error is PluginVersionMismatch) {
      _sessionError = error;
      _recompute();
    }
  }

  // --- derived values -----------------------------------------------------

  AircraftIdentity _identity(PluginSession session) {
    final a = session.aircraft;
    return AircraftIdentity(
      icao: a.icao,
      description: a.description,
      aircraftPath: a.aircraftPath,
      checklistModified: a.checklistModified,
      checklistSize: a.checklistSize,
      checklistPath: a.checklistPath,
      generation: a.generation,
    );
  }

  void _setAircraft(AircraftIdentity? aircraft) {
    if (aircraft == _aircraft) return;
    _aircraft = aircraft;
    _aircraftController.add(aircraft);
  }

  void _setOnGround(bool? value) {
    if (value == _onGround) return;
    _onGround = value;
    _onGroundController.add(value);
  }

  void _recompute() {
    if (_disposed) return;
    final next = _derive();
    if (next == _status) return;
    _status = next;
    _statusController.add(next);
    if (next is ConnectionConnected) _setOffer(null);
    _checkLostOffer();
  }

  ConnectionStatus _derive() {
    if (!_networkUp) return const ConnectionNoNetwork();
    if (_target == null) return const ConnectionSearching();
    final state = flightSim.pluginState;
    final mismatch = _sessionError;
    if (state is PluginStateVersionMismatch) {
      return ConnectionPluginVersionMismatch(
        found: state.found,
        required: state.required,
      );
    }
    if (mismatch is PluginVersionMismatch) {
      return ConnectionPluginVersionMismatch(
        found: mismatch.found,
        required: mismatch.required,
      );
    }
    if (flightSim.isStreamConnected && state is PluginStateReady) {
      return const ConnectionConnected();
    }
    if (state is PluginStateNotDetected && state.noRoute) {
      return const ConnectionLocalNetworkDenied();
    }
    final manualAddress = _manual ? _target?.host : null;
    if (_everConnected) {
      return ConnectionSimUnreachable(
        lastSeen: _lastSeen,
        manualAddress: manualAddress,
      );
    }
    if (state is PluginStateNotDetected && _manual) {
      return ConnectionSimUnreachable(manualAddress: manualAddress);
    }
    // No answer yet proves nothing: the aircraft may still be loading,
    // however long that takes.
    return const ConnectionConnecting();
  }
}
