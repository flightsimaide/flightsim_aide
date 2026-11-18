import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../domain/models/flight_sim/simulator.dart';
import 'model/raw_companion_beacon.dart';
import 'model/sim_endpoint.dart';
import 'multicast_lock_controller.dart';
import 'sim_discovery_service.dart';
import 'xplane_beacon_discovery.dart';

/// The companion beacon's group and UDP port (`plugin/PROTOCOL.md` section 11).
const companionBeaconGroup = '239.255.18.86';
const companionBeaconPort = 18094;

const _maxBeaconBytes = 512;

/// Decodes a companion beacon received from [source]. Returns null for text
/// that is not the beacon (not JSON, no `"fsaide":1`, a missing or mistyped
/// field, a port outside 1 to 65535). Never throws.
RawCompanionBeacon? decodeCompanionBeacon(
  Uint8List bytes,
  InternetAddress source,
) {
  if (bytes.isEmpty || bytes.length > _maxBeaconBytes) return null;
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?> || json['fsaide'] != 1) return null;
  final sim = json['sim'];
  final name = json['name'];
  final port = json['port'];
  if (sim is! String || sim.isEmpty) return null;
  if (name is! String) return null;
  if (port is! int || port < 1 || port > 65535) return null;
  return RawCompanionBeacon(
    ip: source.address,
    name: name,
    port: port,
    simKind: sim,
  );
}

/// [SimDiscoveryService] for a simulator that has no beacon of its own and whose
/// companion sends one (Microsoft Flight Simulator): listens on the companion
/// beacon's multicast group and reports each computer it hears.
class CompanionBeaconDiscovery implements SimDiscoveryService {
  /// Creates the discovery.
  ///
  /// While the listener runs, [multicastLock] holds the Wi-Fi multicast lock (a
  /// no-op except on Android).
  CompanionBeaconDiscovery({
    this.openSource = _openSocket,
    this.multicastLock = const NoopMulticastLockController(),
  });

  /// Holds the multicast lock while listening.
  final MulticastLockController multicastLock;

  /// Opens the datagram source.
  final DatagramSourceOpener openSource;

  static Future<DatagramSource> _openSocket() =>
      openBeaconSocket(group: companionBeaconGroup, port: companionBeaconPort);

  final _controller = StreamController<SimEndpoint>.broadcast();
  DatagramSource? _source;
  StreamSubscription<Datagram>? _subscription;
  bool _starting = false;
  bool _disposed = false;

  @override
  Stream<SimEndpoint> get endpoints => _controller.stream;

  @override
  Future<void> start() async {
    if (_disposed || _source != null || _starting) return;
    _starting = true;
    var opened = false;
    try {
      await multicastLock.acquire();
      final source = await openSource();
      if (_disposed) {
        await source.close();
        return;
      }
      _source = source;
      _subscription = source.datagrams.listen(_onDatagram);
      opened = true;
    } on Object {
      // The group or port is taken or the network is off: X-Plane's beacon and
      // the manual address still work, so this discovery just stays deaf.
    } finally {
      _starting = false;
      if (!opened) await multicastLock.release();
    }
  }

  void _onDatagram(Datagram datagram) {
    final beacon = decodeCompanionBeacon(datagram.data, datagram.address);
    if (beacon == null) return;
    final simulator = Simulator.fromWire(beacon.simKind);
    // A simulator this app does not know is not listed.
    if (simulator == null) return;
    // Every beacon is passed on: the repository keeps its list fresh from them.
    _controller.add(
      SimEndpoint(host: beacon.ip, name: beacon.name, simulator: simulator),
    );
  }

  @override
  Future<void> refresh() async => _source?.refreshMembership();

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final source = _source;
    _source = null;
    await source?.close();
    if (source != null) await multicastLock.release();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _controller.close();
  }
}

/// Runs several discoveries as one: starts and stops them together and passes
/// on everything any of them finds.
class CompositeSimDiscovery implements SimDiscoveryService {
  /// Creates the discovery from [parts].
  CompositeSimDiscovery(this.parts) {
    for (final part in parts) {
      _subscriptions.add(part.endpoints.listen(_controller.add));
    }
  }

  /// The discoveries this one is made of.
  final List<SimDiscoveryService> parts;

  final _controller = StreamController<SimEndpoint>.broadcast();
  final _subscriptions = <StreamSubscription<SimEndpoint>>[];
  bool _disposed = false;

  @override
  Stream<SimEndpoint> get endpoints => _controller.stream;

  @override
  Future<void> start() async {
    if (_disposed) return;
    for (final part in parts) {
      await part.start();
    }
  }

  @override
  Future<void> refresh() async {
    for (final part in parts) {
      await part.refresh();
    }
  }

  @override
  Future<void> stop() async {
    for (final part in parts) {
      await part.stop();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final part in parts) {
      await part.dispose();
    }
    await _controller.close();
  }
}
