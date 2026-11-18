import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../../../domain/models/flight_sim/simulator.dart';
import '../cubit/connection_state.dart';

/// The simulator of [computer]; X-Plane when it is not known (the first
/// simulator, and the one an address typed by hand has been assumed to be).
Simulator _simulatorOf(DiscoveredSim? computer) =>
    computer?.simulator ?? Simulator.xplane;

/// "X-Plane on Windows-PC (192.168.1.10)": which simulator, on which
/// computer, at which address.
String computerLabel(DiscoveredSim sim) {
  final simulator = _simulatorOf(sim).displayName;
  final name = sim.name;
  return name == null
      ? '$simulator at ${sim.host}'
      : '$simulator on $name (${sim.host})';
}

/// "Connected to X-Plane on Windows-PC"; without a known computer, just
/// "Connected to X-Plane".
String connectedHeadline(DiscoveredSim? computer) {
  final simulator = _simulatorOf(computer).displayName;
  if (computer == null) return 'Connected to $simulator';
  return 'Connected to $simulator on ${computer.name ?? computer.host}';
}

/// How a message is coloured: the status colours mean good, caution (can
/// continue, degraded), warning (cannot continue) and nothing else.
enum MessageTone {
  /// The theme's own colours.
  neutral,

  /// Green, with the filled check mark.
  good,

  /// Yellow, with the filled warning icon; the headline is yellow too.
  caution,

  /// Red, with the filled error icon; the headline is red too.
  warning,
}

/// The text for a connection state and the actions that make sense with it.
class ConnectionMessage {
  /// Creates a message.
  const ConnectionMessage({
    required this.headline,
    this.detail = '',
    this.offersRetry = false,
    this.offersManualIp = false,
    this.offersDetails = false,
    this.offersCancel = false,
    this.cancelLabel = 'Cancel',
    this.offersReload = false,
    this.spinning = false,
    this.showIcon = true,
    this.tone = MessageTone.neutral,
    this.warning,
    this.note,
    this.detailGap = 32,
  });

  /// The one-line statement of what is going on.
  final String headline;

  /// What it means for the checklist and what to do; may be empty.
  final String detail;

  /// Whether a Retry action fits.
  final bool offersRetry;

  /// Whether entering an IP address fits.
  final bool offersManualIp;

  /// Whether Cancel (stop connecting) fits.
  final bool offersCancel;

  /// The text of the Cancel button.
  final String cancelLabel;

  /// Whether the Details page fits.
  final bool offersDetails;

  /// Whether Reload fits.
  final bool offersReload;

  /// Whether the turning hourglass replaces the state's icon.
  final bool spinning;

  /// Whether the headline has an icon at all.
  final bool showIcon;

  /// The status colour of the icon (and of the headline for caution and
  /// warning).
  final MessageTone tone;

  /// Text shown in a red box below the headline, or null.
  final String? warning;

  /// Text shown in a red outlined box with red letters, or null.
  final String? note;

  /// Space between the headline and the detail line.
  final double detailGap;
}

String get _simulatorNames =>
    supportedSimulators.map((s) => s.displayName).join(' or ');

/// What the panel says when nothing has been heard from a simulator: the
/// first sentence and a pointer to the Details button. It names the supported
/// simulators only, so it grows with [supportedSimulators].
String get noActivityText =>
    'FlightSim Aide requires a network connection to $_simulatorNames flight '
    'simulator. Press Details for more information.';

/// The rest of the no-activity text, shown in the panel's Details section.
String get noActivityDetails =>
    'To connect, install the FlightSim Aide plugin for $_simulatorNames, then '
    'run $_simulatorNames. FlightSim Aide will automatically connect to '
    '$_simulatorNames.\n\n'
    'If it keeps waiting, $_simulatorNames may not be announcing itself on '
    'the network. This happens on a PC where Windows has reserved the UDP '
    'port that $_simulatorNames uses for its announcement (49707), for '
    'example with Hyper-V or WSL installed. Open the simulator\'s Log.txt and '
    'look for "Failed to init multicast *BEACON* socket". Use Enter IP '
    'address and type the PC\'s address to connect without the announcement.';

/// Shown after a long wait for the aircraft. It makes no claim about the
/// plugin: a long wait looks the same whether the aircraft is still loading
/// or something else is wrong.
const waitingHint =
    'If the aircraft has loaded and FlightSim Aide is still waiting, open the '
    'X-Plane Plugins menu, choose Show Plugin Admin and check that FlightSim Aide '
    'is listed and enabled.';

/// The wait hint for the simulator of [computer].
String waitingHintFor(DiscoveredSim? computer) =>
    _simulatorOf(computer) == Simulator.msfs ? _waitingHintMsfs : waitingHint;

const _waitingHintMsfs =
    'If the aircraft has loaded and FlightSim Aide is still waiting, check '
    'that it was installed for Microsoft Flight Simulator (run '
    'FlightSimAide-MSFS-Setup.exe) and that flightsim_aide_msfs.exe is '
    'running in Task Manager. The simulator starts it about 90 seconds after '
    'it opens.';

/// The title the searching panels share.
const waitingHeadline = 'Waiting for connection';

/// The title when X-Plane loads a different aircraft than the checklist on
/// screen.
const aircraftChangedHeadline = 'Aircraft changed';

/// The line naming the simulator's aircraft.
String aircraftLine(AircraftIdentity aircraft, [DiscoveredSim? computer]) =>
    '${_simulatorOf(computer).displayName} ${aircraft.description}';

/// The title when the loaded aircraft has no checklist file.
const noChecklistHeadline = 'Aircraft has no Checklist';

/// The title while more than one computer answered and the user picks one.
const selectConnectionHeadline = 'Select Connection';

const _progressKept = 'Your progress is kept.';

String _clockTime(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// The message for [state].
ConnectionMessage messageFor(ConnectionViewState state) => switch (state) {
  LinkSearching(:final sims) when sims.length > 1 => ConnectionMessage(
    headline: selectConnectionHeadline,
    detail: noActivityText,
    showIcon: false,
    offersManualIp: true,
    offersDetails: true,
  ),
  LinkSearching() => ConnectionMessage(
    headline: waitingHeadline,
    detail: noActivityText,
    spinning: true,
    offersManualIp: true,
    offersDetails: true,
  ),
  LinkConnecting(:final hint) => ConnectionMessage(
    headline: 'Waiting for aircraft to load',
    spinning: true,
    offersCancel: true,
    note: hint ? waitingHintFor(state.computer) : null,
  ),
  LinkConnected(:final aircraft, :final computer) => ConnectionMessage(
    headline: connectedHeadline(computer),
    tone: MessageTone.good,
    detail: aircraft.icao.isEmpty
        ? aircraft.description
        : '${aircraft.description} (${aircraft.icao})',
    detailGap: 8,
    offersReload: true,
    offersManualIp: true,
  ),
  LinkNoChecklist(:final aircraft) => ConnectionMessage(
    headline: noChecklistHeadline,
    tone: MessageTone.caution,
    detail: aircraftLine(aircraft, state.computer),
    offersReload: true,
    offersManualIp: true,
  ),
  LinkAircraftChanged(:final live) => ConnectionMessage(
    headline: aircraftChangedHeadline,
    tone: MessageTone.caution,
    detail: aircraftLine(live, state.computer),
    // After Continue with current checklist the dialog is gone; the card must
    // still lead somewhere (found on the tablet, task 0.16).
    offersReload: true,
    offersManualIp: true,
  ),
  LinkNoNetwork() => const ConnectionMessage(
    headline: 'Network is off',
    tone: MessageTone.warning,
    detail:
        'FlightSim Aide requires an ethernet or wifi connection to operate. '
        'Please turn on your device network.',
  ),
  LinkLocalNetworkDenied() => const ConnectionMessage(
    headline: 'Local Network access may be off.',
    detail:
        'Turn on Local Network for this app in Settings, then retry. '
        'Your progress is kept.',
    offersRetry: true,
    offersManualIp: true,
    offersDetails: true,
  ),
  LinkSimUnreachable(:final manualAddress?) => ConnectionMessage(
    headline: waitingHeadline,
    warning: 'Using Manual IP address $manualAddress',
    spinning: true,
    offersManualIp: true,
    offersCancel: true,
    cancelLabel: 'Rediscover IP address',
  ),
  LinkSimUnreachable(:final lastSeen) => ConnectionMessage(
    headline: lastSeen == null
        ? '${_simulatorOf(state.computer).displayName} is not responding. Retrying...'
        : '${_simulatorOf(state.computer).displayName} is not responding. Last seen ${_clockTime(lastSeen)}. '
              'Retrying...',
    detail: _progressKept,
    offersRetry: true,
    offersManualIp: true,
  ),
  LinkVersionMismatch(:final found, :final required) => ConnectionMessage(
    headline: 'Update the plugin to continue.',
    detail:
        'The plugin speaks version $found; this app needs version $required. '
        'Your progress is kept.',
    offersRetry: true,
    offersManualIp: true,
    offersDetails: true,
  ),
};
