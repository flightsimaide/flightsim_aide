import 'package:http/http.dart' as http;

import '../data/repositories/flight_sim/flight_sim_repository_remote.dart';
import '../data/repositories/settings/settings_repository.dart';
import '../data/repositories/settings/settings_repository_impl.dart';
import '../data/services/checklist/network_checklist_source_service.dart';
import '../data/services/flight_sim/companion_beacon_discovery.dart';
import '../data/services/flight_sim/companion_plugin_service.dart';
import '../data/services/flight_sim/flight_sim_connection_service.dart';
import '../data/services/flight_sim/model/sim_endpoint.dart';
import '../data/services/flight_sim/multicast_lock_controller.dart';
import '../data/services/flight_sim/network_status_service.dart';
import '../data/services/flight_sim/plugin_session_service.dart';
import '../data/services/flight_sim/xplane_beacon_discovery.dart';
import '../data/services/local/checklist_cache_service.dart';
import '../data/services/local/preferences_service.dart';
import '../domain/models/settings/user_options.dart';

/// Wires the network services behind the checklist source and the flight-sim
/// repository: the companion plugin, beacon discovery, sessions, settings and
/// the local cache.
///
/// With [discover] false the sim address comes straight from
/// `--dart-define=SIM_IP=...`; with it true the repository finds the sim from
/// its beacon (or a stored manual IP). Starting and stopping is explicit so
/// tests can build the link without opening a socket.
class NetworkLink {
  /// Builds the services for the sim at [simIp].
  NetworkLink({
    required this.simIp,
    this.discover = false,
    this.streamRateHz = const int.fromEnvironment('STREAM_RATE_HZ'),
  }) {
    _http = HttpCompanionPluginService(client: http.Client());
    flightSim = FlightSimConnectionService(companion: _http);
    sessions = PluginSessionService(flightSim: flightSim, companion: _http);
    network = PollingNetworkStatusService();
    settings = SettingsRepositoryImpl(preferences: SharedPreferencesService());
    flightSimRepository = FlightSimRepositoryRemote(
      flightSim: flightSim,
      sessions: sessions,
      network: network,
      settings: settings,
      createDiscovery: (host) => host != null
          ? XPlaneBeaconDiscovery(manualHost: host)
          : CompositeSimDiscovery([
              XPlaneBeaconDiscovery(
                multicastLock: defaultMulticastLockController(),
              ),
              CompanionBeaconDiscovery(
                multicastLock: defaultMulticastLockController(),
              ),
            ]),
    );
    source = NetworkChecklistSourceService(
      sessions: sessions,
      companion: _http,
      cache: FileChecklistCacheService.inApplicationSupport(),
    );
  }

  /// The sim machine's address.
  final String simIp;

  /// True to find the sim by beacon instead of connecting to [simIp].
  final bool discover;

  /// `--dart-define=STREAM_RATE_HZ=n`: sets the stream rate option at start
  /// (0, the default, leaves the stored value alone).
  final int streamRateHz;

  late final HttpCompanionPluginService _http;

  /// The live link.
  late final FlightSimConnectionService flightSim;

  /// The aircraft source.
  late final PluginSessionService sessions;

  /// Whether the device has a network.
  late final PollingNetworkStatusService network;

  /// Stored manual IP.
  late final SettingsRepository settings;

  /// What the UI reads the connection from.
  late final FlightSimRepositoryRemote flightSimRepository;

  /// The checklist source the repository reads from.
  late final NetworkChecklistSourceService source;

  /// Starts listening and connects to the sim (does not wait for the plugin).
  void start() {
    _loadOptions();
    sessions.start();
    if (discover) {
      flightSimRepository.start();
    } else {
      flightSim.connect(SimEndpoint(host: simIp));
    }
  }

  /// Reads the stored options, then applies the dart-defines over them.
  Future<void> _loadOptions() async {
    await settings.loadOptions();
    final next = optionsWithOverrides(
      settings.options,
      streamRateHz: streamRateHz,
    );
    if (next != settings.options) await settings.update((_) => next);
  }

  /// Stops everything.
  Future<void> dispose() async {
    await flightSimRepository.dispose();
    network.dispose();
    await sessions.dispose();
    await flightSim.dispose();
    _http.dispose();
  }
}

/// [options] with the dart-define overrides applied: a [streamRateHz] above 0
/// replaces the stored value.
UserOptions optionsWithOverrides(UserOptions options, {int streamRateHz = 0}) {
  var next = options;
  if (streamRateHz > 0) {
    next = next.set(UserOptions.streamRateHzOption, streamRateHz);
  }
  return next;
}
