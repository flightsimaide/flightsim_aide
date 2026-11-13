import 'package:equatable/equatable.dart';

/// The reserved signal that follows the aircraft generation.
const aircraftGenerationSignal = 'flightsim_aide/aircraft_generation';

/// X-Plane's stock "any wheel on the ground" dataref (1 parked, 0 airborne).
const onGroundSignal = 'sim/flightmodel/failures/onground_any';

/// A signal to subscribe to and how often.
class SignalSpec extends Equatable {
  /// Creates a spec.
  const SignalSpec(this.name, this.hz);

  /// The signal's name.
  final String name;

  /// Requested rate, 1 to 60.
  final int hz;

  @override
  List<Object?> get props => [name, hz];
}

/// What the app subscribes to: the aircraft generation and the on-ground flag.
const defaultSignals = [
  SignalSpec(aircraftGenerationSignal, 1),
  SignalSpec(onGroundSignal, 2),
];
