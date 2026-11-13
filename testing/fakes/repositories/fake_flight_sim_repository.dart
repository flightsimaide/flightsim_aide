import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/data/services/flight_sim/simulated_signal_source.dart';
import 'package:flightsim_aide/utils/clock.dart';

import 'fake_settings_repository.dart';

/// A scriptable [FlightSimRepositoryLocal] for UI and cubit tests.
class FakeFlightSimRepository extends FlightSimRepositoryLocal {
  /// Creates the fake with its own settings and, optionally, a clock.
  FakeFlightSimRepository({Clock? clock, SettingsRepository? settings})
    : super(
        settings: settings ?? FakeSettingsRepository(),
        signals: SimulatedSignalSource(clock: clock ?? const SystemClock()),
      );
}
