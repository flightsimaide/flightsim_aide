import 'dart:async';
import 'dart:io';

import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import 'beacon_decoder.dart';
import 'model/raw_beacon.dart';
import 'model/sim_endpoint.dart';
import 'multicast_lock_controller.dart';
import 'sim_discovery_service.dart';

/// X-Plane's beacon group and port.
const beaconGroup = '239.255.1.1';
const beaconPort = 49707;

/// A stream of datagrams, so the real socket can be replaced in tests.
abstract class DatagramSource {
  /// Everything received.
  Stream<Datagram> get datagrams;

  /// Joins the beacon group on every current non-loopback IPv4 interface.
  Future<void> refreshMembership();

  /// Closes the socket.
  Future<void> close();
}

/// Opens a [DatagramSource].
typedef DatagramSourceOpener = Future<DatagramSource> Function();

/// The real socket: UDP 49707 with address reuse, joined to the group on each
/// non-loopback IPv4 interface.
Future<DatagramSource> openBeaconSocket() async {
  final socket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    beaconPort,
    reuseAddress: true,
  );
  final source = _SocketSource(socket);
  await source.refreshMembership();
  return source;
}

class _SocketSource implements DatagramSource {
  _SocketSource(this._socket) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram != null) _controller.add(datagram);
    }, onDone: _controller.close);
  }

  final RawDatagramSocket _socket;
  final _controller = StreamController<Datagram>.broadcast();
  final _joined = <String>{};

  @override
  Stream<Datagram> get datagrams => _controller.stream;

  @override
  Future<void> refreshMembership() async {
    final group = InternetAddress(beaconGroup);
    final List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    } on SocketException {
      return;
    }
    for (final interface in interfaces) {
      final usable = interface.addresses.any(
        (a) => !a.isLoopback && !a.isLinkLocal,
      );
      final key =
          '${interface.index}:${interface.addresses.map((a) => a.address).join(',')}';
      if (!usable || !_joined.add(key)) continue;
      try {
        _socket.joinMulticast(group, interface);
      } on Object {
        _joined.remove(key);
      }
    }
  }

  @override
  Future<void> close() async {
    _socket.close();
    await _controller.close();
  }
}

/// Parses text typed by the user into an endpoint. Only dotted IPv4 addresses
/// are accepted.
Result<SimEndpoint> parseManualIp(String input) {
  final text = input.trim();
  final address = InternetAddress.tryParse(text);
  if (address == null ||
      address.type != InternetAddressType.IPv4 ||
      text.split('.').length != 4) {
    return Error(InvalidManualIp(input));
  }
  return Ok(SimEndpoint(host: address.address));
}

/// [SimDiscoveryService] for X-Plane: listens for its multicast beacon, or,
/// in manual mode, reports the one address it was given and opens no socket.
class XPlaneBeaconDiscovery implements SimDiscoveryService {
  /// Creates the discovery. A non-null [manualHost] switches to manual mode.
  ///
  /// While the beacon listener runs, [multicastLock] holds the Wi-Fi multicast
  /// lock (a no-op except on Android).
  XPlaneBeaconDiscovery({
    this.manualHost,
    this.openSource = openBeaconSocket,
    this.multicastLock = const NoopMulticastLockController(),
  });

  /// Holds the multicast lock while listening.
  final MulticastLockController multicastLock;

  /// The address typed by the user, or null to listen for beacons.
  final String? manualHost;

  /// Opens the datagram source.
  final DatagramSourceOpener openSource;

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
    final manual = manualHost;
    if (manual != null) {
      _controller.add(SimEndpoint(host: manual));
      return;
    }
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
    } finally {
      _starting = false;
      if (!opened) await multicastLock.release();
    }
  }

  void _onDatagram(Datagram datagram) {
    final RawBeacon? beacon = decodeBeacon(datagram.data, datagram.address);
    if (beacon == null) return;
    // Every beacon is passed on: the repository uses them to keep its list of
    // computers fresh (a computer leaves the list when they stop).
    _controller.add(SimEndpoint(host: beacon.ip, name: beacon.name));
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
