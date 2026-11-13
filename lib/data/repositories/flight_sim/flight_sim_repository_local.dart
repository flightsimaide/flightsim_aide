import 'dart:async';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/connection_status.dart';
import '../../../domain/models/flight_sim/dataref.dart';
import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../../../domain/models/flight_sim/switch_offer.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/ipv4.dart';
import '../../../utils/result.dart';
import '../../services/flight_sim/simulated_signal_source.dart';
import '../settings/settings_repository.dart';
import 'dataref_watch.dart';
import 'dataref_watch_hub.dart';
import 'flight_sim_repository.dart';

/// A [FlightSimRepository] with no sockets: state is set from code (or a dev
/// control) and every call is recorded. It backs the UI tests.
class FlightSimRepositoryLocal implements FlightSimRepository {
  /// Creates the repository in the "searching" state.
  ///
  /// [settings] gives the stream rate to [watch]; without it [watch] cannot be
  /// used. [signals] is the simulated sim a test or dev control scripts.
  FlightSimRepositoryLocal({this.settings, SimulatedSignalSource? signals})
    : signals = signals ?? SimulatedSignalSource();

  /// Where the stream rate option lives, or null.
  final SettingsRepository? settings;

  /// The simulated values behind [watch].
  final SimulatedSignalSource signals;

  DatarefWatchHub? _hub;

  @override
  DatarefWatch watch(Iterable<Dataref> datarefs) {
    final s = settings;
    if (s == null) {
      throw StateError('FlightSimRepositoryLocal needs settings to watch');
    }
    return (_hub ??= DatarefWatchHub(
      source: signals,
      settings: s,
      clock: signals.clock,
    )).watch(datarefs);
  }

  final _status = StreamController<ConnectionStatus>.broadcast();
  final _aircraft = StreamController<AircraftIdentity?>.broadcast();
  final _onGround = StreamController<bool?>.broadcast();
  final _sims = StreamController<List<DiscoveredSim>>.broadcast();
  final _manualWorked = StreamController<String>.broadcast();

  ConnectionStatus _currentStatus = const ConnectionSearching();
  AircraftIdentity? _currentAircraft;
  bool? _currentOnGround;
  List<DiscoveredSim> _currentSims = const [];

  /// What [currentTarget] answers.
  @override
  DiscoveredSim? currentTarget;

  /// The address last accepted by [useManualIp], or null.
  String? manualIp;

  /// The sim last passed to [selectSim].
  DiscoveredSim? selectedSim;

  /// How often each call happened.
  int starts = 0;
  int reloads = 0;
  int pauses = 0;
  int retries = 0;
  int cancels = 0;
  int drops = 0;
  int resumes = 0;
  int resumeCalls = 0;

  @override
  Stream<ConnectionStatus> get connectionStatus => _status.stream;

  @override
  ConnectionStatus get current => _currentStatus;

  @override
  Stream<AircraftIdentity?> get liveAircraft => _aircraft.stream;

  @override
  AircraftIdentity? get currentAircraft => _currentAircraft;

  @override
  Stream<bool?> get onGroundChanges => _onGround.stream;

  @override
  bool? get onGround => _currentOnGround;

  /// The run id reported to callers; tests change it to act out a restart.
  @override
  String? runId;

  @override
  Stream<List<DiscoveredSim>> get sims => _sims.stream;

  @override
  List<DiscoveredSim> get currentSims => _currentSims;

  /// Sets the connection status and announces a change.
  void setStatus(ConnectionStatus status) {
    if (status == _currentStatus) return;
    _currentStatus = status;
    _status.add(status);
  }

  /// Sets the loaded aircraft and announces a change.
  void setAircraft(AircraftIdentity? aircraft) {
    if (aircraft == _currentAircraft) return;
    _currentAircraft = aircraft;
    _aircraft.add(aircraft);
  }

  /// Sets the on-ground value and announces a change.
  void setOnGround(bool? value) {
    if (value == _currentOnGround) return;
    _currentOnGround = value;
    _onGround.add(value);
  }

  /// Sets the discovered sims and announces them.
  void setSims(List<DiscoveredSim> sims) {
    _currentSims = List.unmodifiable(sims);
    _sims.add(_currentSims);
  }

  @override
  DiscoveredSim? previousSim;

  @override
  List<DiscoveredSim> declinedSims = const [];

  final _offers = StreamController<SwitchOffer?>.broadcast();
  SwitchOffer? _offer;

  /// The answers given to [answerSwitch], in order.
  final List<bool> switchAnswers = [];

  @override
  Stream<SwitchOffer?> get switchOffers => _offers.stream;

  @override
  SwitchOffer? get currentSwitchOffer => _offer;

  /// Opens (or, with null, closes) the switch question and announces it.
  void setSwitchOffer(SwitchOffer? offer) {
    if (offer == _offer) return;
    _offer = offer;
    _offers.add(offer);
  }

  @override
  Future<void> answerSwitch({required bool accept}) async {
    switchAnswers.add(accept);
    setSwitchOffer(null);
  }

  @override
  Future<void> start() async => starts++;

  @override
  Future<Result<void>> useManualIp(String input) async {
    final ip = input.trim();
    if (!isUsableIpv4(ip)) return Error(InvalidManualIp(input));
    manualIp = ip;
    return const Ok(null);
  }

  @override
  Stream<String> get manualIpWorked => _manualWorked.stream;

  /// Announces that the typed [address] connected.
  void setManualIpWorked(String address) => _manualWorked.add(address);

  @override
  Future<void> dropManualIp() async {
    drops++;
    manualIp = null;
  }

  @override
  Future<void> useAutomaticDiscovery() async => manualIp = null;

  @override
  Future<void> selectSim(DiscoveredSim sim) async => selectedSim = sim;

  @override
  Future<Result<AircraftIdentity>> reload() async {
    reloads++;
    final aircraft = _currentAircraft;
    return aircraft == null ? Error(PluginNotDetected()) : Ok(aircraft);
  }

  @override
  Future<void> retry() async => retries++;

  @override
  Future<void> cancelConnecting() async => cancels++;

  @override
  Future<void> resumeConnecting() async => resumeCalls++;

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> dispose() async {
    await _hub?.dispose();
    await signals.dispose();
    await _manualWorked.close();
    await _offers.close();
    await _status.close();
    await _aircraft.close();
    await _onGround.close();
    await _sims.close();
  }
}
