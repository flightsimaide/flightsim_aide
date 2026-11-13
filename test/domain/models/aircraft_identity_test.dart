import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AircraftIdentity make({String path = 'Aircraft/A/a.acf'}) => AircraftIdentity(
    icao: 'C172',
    description: 'Cessna Skyhawk 172SP',
    aircraftPath: path,
    checklistModified: 1761206400123,
    checklistSize: 267,
    checklistPath: 'Aircraft/A/clist.txt',
    generation: 12,
  );

  test('equal identities are ==', () {
    expect(make(), make());
  });

  test('different path is !=', () {
    expect(make(), isNot(make(path: 'Aircraft/B/b.acf')));
  });

  test('hashCode matches', () {
    expect(make().hashCode, make().hashCode);
  });

  test('no-checklist identity has null fields', () {
    const identity = AircraftIdentity(
      icao: 'C172',
      description: 'Cessna',
      aircraftPath: 'Aircraft/A/a.acf',
    );
    expect(identity.checklistModified, isNull);
    expect(identity.checklistSize, isNull);
    expect(identity.checklistPath, isNull);
    expect(identity.generation, isNull);
  });
}
