import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../../testing/fakes/services/manual_clock.dart';

// AC-41: both repositories offer watch(); the local one runs on scripted values

void main() {
  const rpm = Dataref('a/rpm');

  test('the local repository watches scripted values', () async {
    final clock = ManualClock();
    final repo = FakeFlightSimRepository(clock: clock);
    final w = repo.watch([rpm]);
    final batches = <double?>[];
    w.batches.listen((b) => batches.add(b[rpm]!.number));
    repo.signals.setValue('a/rpm', 900);
    clock.advance(const Duration(seconds: 1));
    repo.signals.setValue('a/rpm', 1200);
    clock.advance(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(batches, [900, 1200]);
    w.release();
    await repo.dispose();
  });

  test('without settings the local repository cannot watch', () {
    expect(() => FlightSimRepositoryLocal().watch([rpm]), throwsStateError);
  });
}
