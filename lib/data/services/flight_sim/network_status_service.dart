import 'dart:async';
import 'dart:io';

import '../../../utils/clock.dart';

/// Reports whether the device has a usable local network.
abstract class NetworkStatusService {
  /// The latest known availability (false until the first poll).
  bool get isAvailable;

  /// Availability, emitted only when it changes.
  Stream<bool> get availability;

  /// Marks the network down at once, after a send failure such as "network
  /// unreachable". The next poll that finds an address brings it back.
  void reportSendFailure();

  /// Starts polling.
  void start();

  /// Stops polling and closes the stream.
  void dispose();
}

/// Lists the device's local addresses.
typedef LocalAddressLister = Future<List<InternetAddress>> Function();

/// Every IPv4 address of every network interface.
Future<List<InternetAddress>> listLocalIPv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  return [for (final i in interfaces) ...i.addresses];
}

/// [NetworkStatusService] that polls the interface list every [interval].
class PollingNetworkStatusService implements NetworkStatusService {
  /// Creates the service. [listAddresses] defaults to the real interfaces.
  PollingNetworkStatusService({
    LocalAddressLister listAddresses = listLocalIPv4Addresses,
    this.clock = const SystemClock(),
    this.interval = const Duration(seconds: 2),
  }) : _list = listAddresses;

  final LocalAddressLister _list;

  /// The time source.
  final Clock clock;

  /// How often the interfaces are checked.
  final Duration interval;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  Timer? _timer;
  bool? _last;
  bool _disposed = false;

  @override
  bool get isAvailable => _last ?? false;

  @override
  Stream<bool> get availability => _controller.stream;

  @override
  void start() {
    if (_timer != null || _disposed) return;
    _timer = clock.periodic(interval, (_) => _poll());
    _poll();
  }

  @override
  void reportSendFailure() => _publish(false);

  Future<void> _poll() async {
    bool usable;
    try {
      final addresses = await _list();
      usable = addresses.any((a) => !a.isLoopback && !a.isLinkLocal);
    } on Object {
      usable = false;
    }
    _publish(usable);
  }

  void _publish(bool value) {
    if (_disposed || _last == value) return;
    _last = value;
    _controller.add(value);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_controller.close());
  }
}
