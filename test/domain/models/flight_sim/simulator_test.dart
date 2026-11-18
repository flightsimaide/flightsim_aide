import 'package:flightsim_aide/domain/models/flight_sim/simulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a hello sim kind maps to its simulator', () {
    expect(Simulator.fromWire('xplane'), Simulator.xplane);
    expect(Simulator.fromWire('msfs'), Simulator.msfs);
  });

  test('an absent or unknown sim kind maps to null', () {
    expect(Simulator.fromWire(null), isNull);
    expect(Simulator.fromWire('prepar3d'), isNull);
  });
}
