import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/domain/models/flight_sim/simulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('X-Plane and Microsoft Flight Simulator are supported', () {
    expect(supportedSimulators, [Simulator.xplane, Simulator.msfs]);
    expect(Simulator.xplane.displayName, 'X-Plane');
    expect(Simulator.msfs.displayName, 'Microsoft Flight Simulator');
  });

  test('HostOs reads the plugin value and shows its name', () {
    expect(HostOs.fromWire('windows'), HostOs.windows);
    expect(HostOs.fromWire('macos'), HostOs.macos);
    expect(HostOs.fromWire('linux'), HostOs.linux);
    expect(HostOs.macos.displayName, 'macOS');
  });

  test('HostOs.fromWire gives null for absent or unknown values', () {
    expect(HostOs.fromWire(null), isNull);
    expect(HostOs.fromWire('beos'), isNull);
  });

  test('DiscoveredSim.withOs keeps the other fields', () {
    const sim = DiscoveredSim(
      host: '10.0.0.5',
      name: 'A',
      simulator: Simulator.xplane,
    );
    final withOs = sim.withOs(HostOs.linux);
    expect(withOs.os, HostOs.linux);
    expect(withOs.host, '10.0.0.5');
    expect(withOs.name, 'A');
    expect(withOs.simulator, Simulator.xplane);
    expect(withOs, isNot(sim));
  });
}
