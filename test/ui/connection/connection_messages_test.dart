import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/domain/models/flight_sim/simulator.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_state.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_messages.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-9: plugin not detected text
// AC-14: no checklist for this aircraft text
// AC-27: no network and not responding texts

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
);
const _bare = AircraftIdentity(
  icao: 'PA28',
  description: 'Piper Archer',
  aircraftPath: 'b.acf',
);

void main() {
  test('the aircraft line names the simulator of the computer', () {
    const msfs = DiscoveredSim(
      host: '10.0.0.5',
      name: 'PC',
      simulator: Simulator.msfs,
    );
    expect(aircraftLine(_cessna), 'X-Plane Cessna 172');
    expect(
      aircraftLine(_cessna, msfs),
      'Microsoft Flight Simulator Cessna 172',
    );
  });

  test('no network text is shown for LinkNoNetwork', () {
    final m = messageFor(const LinkNoNetwork());
    expect(m.headline, 'Network is off');
  });

  test('sim not responding shows the last seen time', () {
    final m = messageFor(
      LinkSimUnreachable(lastSeen: DateTime(2026, 10, 25, 14, 32)),
    );
    expect(
      m.headline,
      'X-Plane is not responding. Last seen 14:32. Retrying...',
    );
  });

  test('the messages name the simulator of the computer', () {
    const msfs = DiscoveredSim(
      host: '10.0.0.7',
      name: 'FLIGHT-PC',
      simulator: Simulator.msfs,
    );
    expect(
      messageFor(const LinkSimUnreachable(computer: msfs)).headline,
      'Microsoft Flight Simulator is not responding. Retrying...',
    );
    expect(
      messageFor(const LinkNoChecklist(_cessna, computer: msfs)).detail,
      'Microsoft Flight Simulator Cessna 172',
    );
    expect(
      messageFor(const LinkConnecting(hint: true, computer: msfs)).note,
      contains('flightsim_aide_msfs.exe'),
    );
    expect(
      messageFor(const LinkConnecting(hint: true)).note,
      contains('Plugin Admin'),
    );
  });

  test('sim not responding without a last seen time has no time', () {
    expect(
      messageFor(const LinkSimUnreachable()).headline,
      'X-Plane is not responding. Retrying...',
    );
  });

  test('an unanswered typed address is the waiting panel with a red box', () {
    final m = messageFor(const LinkSimUnreachable(manualAddress: '10.0.0.7'));
    expect(m.headline, waitingHeadline);
    expect(m.spinning, isTrue);
    expect(m.warning, 'Using Manual IP address 10.0.0.7');
    expect(m.detail, isEmpty);
    expect(m.offersManualIp, isTrue);
    expect(m.offersCancel, isTrue);
    expect(m.cancelLabel, 'Rediscover IP address');
    expect([m.offersRetry, m.offersDetails], everyElement(isFalse));
  });

  test('last seen time is zero padded', () {
    final m = messageFor(
      LinkSimUnreachable(lastSeen: DateTime(2026, 1, 1, 7, 5)),
    );
    expect(m.headline, contains('07:05'));
  });

  test('searching says waiting, with the no-activity text, at any time', () {
    for (final state in [const LinkSearching()]) {
      final m = messageFor(state);
      expect(m.headline, 'Waiting for connection');
      expect(
        m.detail,
        'FlightSim Aide requires a network connection to X-Plane or Microsoft '
        'Flight Simulator. '
        'Press Details for more information.',
      );
    }
  });

  test('the rest of the no-activity text is for the Details page', () {
    expect(
      noActivityDetails,
      'To connect, install the FlightSim Aide plugin for X-Plane or the '
      'FlightSim Aide companion for Microsoft Flight Simulator (run '
      'FlightSimAide-MSFS-Setup.exe), then run the simulator. FlightSim Aide '
      'will automatically connect to it.\n\n'
      'If it keeps waiting with X-Plane, X-Plane may not be announcing itself '
      'on the network. This happens on a PC where Windows has reserved the UDP '
      'port that X-Plane uses for its announcement (49707), for example with '
      'Hyper-V or WSL installed. Open the simulator\'s Log.txt and look for '
      '"Failed to init multicast *BEACON* socket".\n\n'
      'With Microsoft Flight Simulator the companion starts about 90 seconds '
      'after the simulator opens and announces itself on UDP port 18094. Check '
      'that flightsim_aide_msfs.exe is running in Task Manager and that '
      'Windows Firewall allows it on private networks.\n\n'
      'Use Enter IP address and type the PC\'s address to connect without the '
      'announcement.',
    );
  });

  test('searching offers Enter IP address and Details, not Retry', () {
    for (final state in [const LinkSearching()]) {
      final m = messageFor(state);
      expect(m.offersRetry, isFalse, reason: '$state');
      expect(m.offersManualIp, isTrue, reason: '$state');
      expect(m.offersDetails, isTrue, reason: '$state');
      expect(m.headline, waitingHeadline);
      expect(m.spinning, isTrue);
    }
  });

  test(
    'no network has no buttons: it clears itself when the network returns',
    () {
      final m = messageFor(const LinkNoNetwork());
      expect([
        m.offersRetry,
        m.offersManualIp,
        m.offersDetails,
        m.offersCancel,
        m.offersReload,
      ], everyElement(isFalse));
      expect(
        m.detail,
        'FlightSim Aide requires an ethernet or wifi connection to operate. '
        'Please turn on your device network.',
      );
    },
  );

  test('every other state that is not connected offers all three buttons', () {
    for (final state in [
      const LinkLocalNetworkDenied(),
      const LinkVersionMismatch(found: 2, required: 1),
    ]) {
      final m = messageFor(state);
      expect(
        [m.offersRetry, m.offersManualIp, m.offersDetails],
        everyElement(isTrue),
        reason: '$state',
      );
    }
  });

  test('X-Plane is not responding offers Retry and Enter IP, no Details', () {
    final m = messageFor(const LinkSimUnreachable());
    expect(m.offersRetry, isTrue);
    expect(m.offersManualIp, isTrue);
    expect(m.offersDetails, isFalse);
  });

  test('connecting offers only Cancel', () {
    final m = messageFor(const LinkConnecting());
    expect(m.offersCancel, isTrue);
    expect([
      m.offersRetry,
      m.offersManualIp,
      m.offersDetails,
      m.offersReload,
    ], everyElement(isFalse));
  });

  test('connected states do not offer Details', () {
    expect(messageFor(const LinkConnected(_cessna)).offersDetails, isFalse);
    expect(messageFor(const LinkNoChecklist(_bare)).offersDetails, isFalse);
  });

  test('waiting for the aircraft: title, no message, Cancel only', () {
    final m = messageFor(const LinkConnecting());
    expect(m.headline, 'Waiting for aircraft to load');
    expect(m.detail, isEmpty);
    expect(m.spinning, isTrue);
    expect(m.note, isNull);
    expect(m.offersCancel, isTrue);
  });

  test('a long wait adds the red note about the Plugin Admin', () {
    final m = messageFor(const LinkConnecting(hint: true));
    expect(m.headline, 'Waiting for aircraft to load');
    expect(m.note, waitingHint);
    expect(waitingHint, contains('Show Plugin Admin'));
    expect(waitingHint, contains('FlightSim Aide'));
    expect(
      waitingHint.toLowerCase(),
      isNot(anyOf(contains('not installed'), contains('missing'))),
    );
  });

  test('local network denied says Local Network access may be off', () {
    final m = messageFor(const LinkLocalNetworkDenied());
    expect(m.headline, 'Local Network access may be off.');
    expect(m.detail, allOf(contains('Settings'), contains('progress is kept')));
    expect(m.offersRetry, isTrue);
    expect(m.offersManualIp, isTrue);
  });

  test('version message shows found and required', () {
    final m = messageFor(const LinkVersionMismatch(found: 2, required: 1));
    expect(m.headline, contains('Update the plugin'));
    expect(m.detail, allOf(contains('version 2'), contains('version 1')));
  });

  test('no checklist message names the aircraft', () {
    final m = messageFor(const LinkNoChecklist(_bare));
    expect(m.headline, 'Aircraft has no Checklist');
    expect(m.detail, 'X-Plane Piper Archer');
    expect(m.tone, MessageTone.caution);
  });

  test('aircraft changed names the new aircraft, as a caution', () {
    for (final live in [_bare, _cessna]) {
      final m = messageFor(LinkAircraftChanged(loaded: _cessna, live: live));
      expect(m.headline, 'Aircraft changed');
      expect(m.detail, 'X-Plane ${live.description}');
      expect(m.tone, MessageTone.caution);
      expect(m.offersManualIp, isTrue, reason: 'never a card with no button');
      expect(m.offersReload, isTrue);
    }
  });

  test('connected names the aircraft and offers reload', () {
    final m = messageFor(const LinkConnected(_cessna));
    expect(m.headline, 'Connected to X-Plane');
    expect(m.detail, contains('Cessna 172'));
    expect(m.offersReload, isTrue);
  });

  test('connected names the computer', () {
    final m = messageFor(
      const LinkConnected(
        _cessna,
        computer: DiscoveredSim(host: '192.168.1.10', name: 'WIN'),
      ),
    );
    expect(m.headline, 'Connected to X-Plane on WIN');
    expect(m.detail, 'Cessna 172 (C172)');
    expect(m.detailGap, lessThan(32));
  });

  test('connected to a typed address names the address', () {
    final m = messageFor(
      const LinkConnected(_cessna, computer: DiscoveredSim(host: '10.0.0.7')),
    );
    expect(m.headline, 'Connected to X-Plane on 10.0.0.7');
  });

  test('connected and no-checklist offer the IP address so it can be changed or cleared', () {
    expect(messageFor(const LinkConnected(_cessna)).offersManualIp, isTrue);
    expect(messageFor(const LinkNoChecklist(_cessna)).offersManualIp, isTrue);
  });

  test('lost-connection messages say progress is kept', () {
    expect(
      messageFor(const LinkSimUnreachable()).detail,
      contains('Your progress is kept'),
    );
  });

  test('connecting has a plain message and no reload or switch', () {
    final m = messageFor(const LinkConnecting());
    expect(m.headline, 'Waiting for aircraft to load');
    expect([m.offersReload], everyElement(isFalse));
  });

  test('failures offer retry', () {
    for (final state in [
      const LinkSimUnreachable(),
      const LinkLocalNetworkDenied(),
      const LinkVersionMismatch(found: 2, required: 1),
    ]) {
      expect(messageFor(state).offersRetry, isTrue, reason: '$state');
    }
  });
}
