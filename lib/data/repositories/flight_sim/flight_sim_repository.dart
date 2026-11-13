import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/connection_status.dart';
import '../../../domain/models/flight_sim/dataref.dart';
import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../../../domain/models/flight_sim/switch_offer.dart';
import '../../../utils/result.dart';
import 'dataref_watch.dart';

/// The app's view of the simulator: whether it is reachable, which aircraft
/// it has loaded and whether that aircraft is on the ground. It knows nothing
/// about checklists. Every value is available both as a snapshot and as a
/// stream of changes.
abstract class FlightSimRepository {
  /// Where the connection stands. Emitted on change only.
  Stream<ConnectionStatus> get connectionStatus;

  /// The current connection status.
  ConnectionStatus get current;

  /// The aircraft X-Plane has loaded right now; null when unknown.
  Stream<AircraftIdentity?> get liveAircraft;

  /// The aircraft X-Plane has loaded right now, or null.
  AircraftIdentity? get currentAircraft;

  /// Whether the aircraft is on the ground; null when not known.
  Stream<bool?> get onGroundChanges;

  /// Whether the aircraft is on the ground, or null when not known.
  bool? get onGround;

  /// The plugin's run id (it changes when X-Plane is restarted), or null when
  /// not known.
  String? get runId;

  /// The simulators seen on the network, most recently found last.
  Stream<List<DiscoveredSim>> get sims;

  /// The simulators seen on the network.
  List<DiscoveredSim> get currentSims;

  /// The simulator the app is connecting or connected to, or null while it
  /// is still looking.
  DiscoveredSim? get currentTarget;

  /// The computer the app was last connected to in this run, or null. Forgotten
  /// when the app restarts.
  DiscoveredSim? get previousSim;

  /// Computers the user answered No to: no switch question and no automatic
  /// connection in this run, but they stay on the list. [selectSim] or a typed
  /// address that is theirs forgets the No.
  List<DiscoveredSim> get declinedSims;

  /// The question to switch computers (task 0.16), or null when none is
  /// open. Emitted when it opens and again with null when it closes.
  Stream<SwitchOffer?> get switchOffers;

  /// The open switch question, or null.
  SwitchOffer? get currentSwitchOffer;

  /// Answers the open switch question. Yes connects to the offered computer;
  /// No declines it for this run and keeps waiting for the previous one.
  Future<void> answerSwitch({required bool accept});

  /// Watches [datarefs] live: values arrive in batches at the stream rate
  /// option, each name is subscribed once however many watches ask, and every
  /// value is unknown while the link is down. Call [DatarefWatch.release] when
  /// done.
  DatarefWatch watch(Iterable<Dataref> datarefs);

  /// Starts looking for the simulator (or connects to the stored manual IP).
  Future<void> start();

  /// Tries the sim at [input] (the temporary address) instead of discovering
  /// one, without saving it. A bad address is an `InvalidManualIp` and the
  /// existing connection stays.
  Future<Result<void>> useManualIp(String input);

  /// Emits a typed address, once, when it has connected and is not the saved
  /// address: the moment to ask whether to keep it.
  Stream<String> get manualIpWorked;

  /// Forgets the typed or saved address for this run and finds the sim by its
  /// beacon. The saved address stays saved.
  Future<void> dropManualIp();

  /// Erases the saved address and finds the sim by its beacon.
  Future<void> useAutomaticDiscovery();

  /// Connects to [sim] and remembers the choice.
  Future<void> selectSim(DiscoveredSim sim);

  /// Fetches the aircraft again (the plugin does not announce file edits).
  Future<Result<AircraftIdentity>> reload();

  /// Stops trying to connect. The sim stays the target (for display) and
  /// nothing reconnects until [retry], [selectSim] or a manual address.
  Future<void> cancelConnecting();

  /// Connects again to the sim that [cancelConnecting] stopped.
  Future<void> resumeConnecting();

  /// Starts over: finds the sim again by its beacon, or reconnects to the
  /// stored manual address.
  Future<void> retry();

  /// Closes the connection (the app went to the background).
  Future<void> pause();

  /// Reconnects after [pause].
  Future<void> resume();

  /// Releases everything.
  Future<void> dispose();
}
