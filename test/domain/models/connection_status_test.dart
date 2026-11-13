import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('simple states are equal to themselves', () {
    expect(const ConnectionSearching(), const ConnectionSearching());
    expect(const ConnectionConnected(), const ConnectionConnected());
    expect(const ConnectionSearching(), isNot(const ConnectionConnecting()));
  });

  test('lastSeen takes part in equality', () {
    final t = DateTime.utc(2026, 10, 25, 12);
    expect(
      ConnectionSimUnreachable(lastSeen: t),
      ConnectionSimUnreachable(lastSeen: t),
    );
    expect(
      ConnectionSimUnreachable(lastSeen: t),
      isNot(
        ConnectionSimUnreachable(lastSeen: t.add(const Duration(seconds: 1))),
      ),
    );
    expect(
      const ConnectionSimUnreachable(),
      isNot(ConnectionSimUnreachable(lastSeen: t)),
    );
    expect(
      ConnectionSimUnreachable(lastSeen: t).hashCode,
      ConnectionSimUnreachable(lastSeen: t).hashCode,
    );
  });

  test('version mismatch compares found and required', () {
    expect(
      const ConnectionPluginVersionMismatch(found: 2, required: 1),
      const ConnectionPluginVersionMismatch(found: 2, required: 1),
    );
    expect(
      const ConnectionPluginVersionMismatch(found: 2, required: 1),
      isNot(const ConnectionPluginVersionMismatch(found: 3, required: 1)),
    );
  });

  test('switch is exhaustive without default', () {
    String describe(ConnectionStatus s) => switch (s) {
      ConnectionSearching() => 'searching',
      ConnectionConnecting() => 'connecting',
      ConnectionConnected() => 'connected',
      ConnectionNoNetwork() => 'noNetwork',
      ConnectionSimUnreachable() => 'simUnreachable',
      ConnectionLocalNetworkDenied() => 'localNetworkDenied',
      ConnectionPluginVersionMismatch() => 'pluginVersionMismatch',
    };
    expect(describe(const ConnectionNoNetwork()), 'noNetwork');
  });
}
