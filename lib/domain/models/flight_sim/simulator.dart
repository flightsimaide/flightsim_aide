/// A flight simulator FlightSim Aide can connect to.
enum Simulator {
  /// Laminar Research X-Plane.
  xplane('X-Plane', 'xplane'),

  /// Microsoft Flight Simulator (2020 and 2024).
  msfs('Microsoft Flight Simulator', 'msfs');

  const Simulator(this.displayName, this.wireKind);

  /// The name shown to the user.
  final String displayName;

  /// The `sim.kind` the simulator's companion reports in its hello.
  final String wireKind;

  /// The simulator for a hello's `sim.kind`, or null when absent or unknown.
  static Simulator? fromWire(String? kind) {
    for (final simulator in values) {
      if (simulator.wireKind == kind) return simulator;
    }
    return null;
  }
}

/// The simulators that have a companion plugin today. Only supported
/// simulators belong here; the no-activity text is built from it.
const supportedSimulators = [Simulator.xplane, Simulator.msfs];

/// The operating system of the computer a simulator runs on.
enum HostOs {
  /// Microsoft Windows.
  windows('Windows'),

  /// Apple macOS.
  macos('macOS'),

  /// Linux.
  linux('Linux');

  const HostOs(this.displayName);

  /// The name shown to the user.
  final String displayName;

  /// The OS for the plugin's `os` value, or null when absent or unknown.
  static HostOs? fromWire(String? value) {
    for (final os in values) {
      if (os.name == value) return os;
    }
    return null;
  }
}
