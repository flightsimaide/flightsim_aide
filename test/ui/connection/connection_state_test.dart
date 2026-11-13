import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
);
const _b = AircraftIdentity(
  icao: 'B738',
  description: 'Boeing',
  aircraftPath: 'b.acf',
);

void main() {
  final all = <ConnectionViewState>[
    const LinkSearching(sims: [DiscoveredSim(host: '1.2.3.4')]),
    const LinkConnecting(),
    const LinkConnected(_a),
    const LinkNoChecklist(_b),
    const LinkAircraftChanged(loaded: _a, live: _b),
    const LinkNoNetwork(),
    LinkSimUnreachable(lastSeen: DateTime.utc(2026)),
    const LinkLocalNetworkDenied(),
    const LinkVersionMismatch(found: 2, required: 1),
  ];

  test('equal values are equal and differing values are not', () {
    expect(const LinkConnected(_a), const LinkConnected(_a));
    expect(const LinkConnected(_a), isNot(const LinkConnected(_b)));
    expect(const LinkConnecting(), isNot(const LinkConnecting(hint: true)));
    expect(
      const LinkVersionMismatch(found: 2, required: 1),
      isNot(const LinkVersionMismatch(found: 3, required: 1)),
    );
    expect(
      const LinkAircraftChanged(loaded: _a, live: _b),
      isNot(const LinkAircraftChanged(loaded: _b, live: _a)),
    );
    expect(
      const LinkSimUnreachable(),
      isNot(LinkSimUnreachable(lastSeen: DateTime.utc(2026))),
    );
  });

  test('switch is exhaustive', () {
    for (final state in all) {
      final name = switch (state) {
        LinkSearching() => 'searching',
        LinkConnecting() => 'connecting',
        LinkConnected() => 'connected',
        LinkNoChecklist() => 'nochecklist',
        LinkAircraftChanged() => 'changed',
        LinkNoNetwork() => 'nonetwork',
        LinkSimUnreachable() => 'unreachable',
        LinkLocalNetworkDenied() => 'denied',
        LinkVersionMismatch() => 'mismatch',
      };
      expect(name, isNotEmpty);
    }
  });

  test('withInputError keeps the state and sets only the error', () {
    for (final state in all) {
      final with_ = state.withInputError('bad');
      expect(with_.runtimeType, state.runtimeType);
      expect(with_.inputError, 'bad');
      expect(with_, isNot(state));
      expect(with_.withInputError(null), state);
    }
  });

  test('aircraft changed knows whether the new aircraft has a checklist', () {
    expect(
      const LinkAircraftChanged(loaded: _a, live: _a).liveHasChecklist,
      isTrue,
    );
    expect(
      const LinkAircraftChanged(loaded: _a, live: _b).liveHasChecklist,
      isFalse,
    );
  });
}
