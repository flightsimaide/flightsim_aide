import 'dart:async';
import 'dart:io';

import 'package:flightsim_aide/data/services/flight_sim/multicast_lock_controller.dart';
import 'package:flightsim_aide/data/services/flight_sim/xplane_beacon_discovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lock implements MulticastLockController {
  final events = <String>[];

  @override
  Future<void> acquire() async => events.add('acquire');

  @override
  Future<void> release() async => events.add('release');
}

class _Source implements DatagramSource {
  final _controller = StreamController<Datagram>.broadcast();

  @override
  Stream<Datagram> get datagrams => _controller.stream;

  @override
  Future<void> refreshMembership() async {}

  @override
  Future<void> close() => _controller.close();
}

void main() {
  late _Lock lock;

  XPlaneBeaconDiscovery build({
    String? manualHost,
    DatagramSourceOpener? open,
  }) => XPlaneBeaconDiscovery(
    manualHost: manualHost,
    openSource: open ?? () async => _Source(),
    multicastLock: lock,
  );

  setUp(() => lock = _Lock());

  test('lock is acquired when the listener starts', () async {
    final discovery = build();
    await discovery.start();
    expect(lock.events, ['acquire']);
    await discovery.dispose();
  });

  test('released when it stops', () async {
    final discovery = build();
    await discovery.start();
    await discovery.stop();
    expect(lock.events, ['acquire', 'release']);
    await discovery.dispose();
    expect(lock.events, ['acquire', 'release']);
  });

  test('released on pause (the repository stops discovery)', () async {
    final discovery = build();
    await discovery.start();
    await discovery.stop();
    await discovery.start();
    expect(lock.events, ['acquire', 'release', 'acquire']);
    await discovery.dispose();
  });

  test('not acquired in manual ip mode', () async {
    final discovery = build(manualHost: '10.0.0.5');
    await discovery.start();
    await discovery.stop();
    await discovery.dispose();
    expect(lock.events, isEmpty);
  });

  test('released when the socket cannot be opened', () async {
    final discovery = build(open: () async => throw StateError('no socket'));
    await expectLater(discovery.start(), throwsStateError);
    expect(lock.events, ['acquire', 'release']);
    await discovery.dispose();
  });

  test('stopping without starting does not release', () async {
    final discovery = build();
    await discovery.stop();
    expect(lock.events, isEmpty);
    await discovery.dispose();
  });

  test('no-op controller works on desktop', () async {
    const noop = NoopMulticastLockController();
    await noop.acquire();
    await noop.release();
  });

  group('method channel controller', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flightsim_aide/multicast');
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('forwards acquire and release', () async {
      const controller = MethodChannelMulticastLockController();
      await controller.acquire();
      await controller.release();
      expect(calls, ['acquire', 'release']);
    });

    test('a missing platform implementation is tolerated', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException();
          });
      const controller = MethodChannelMulticastLockController();
      await controller.acquire();
      await controller.release();
    });

    test('a platform error is tolerated', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'fail');
          });
      const controller = MethodChannelMulticastLockController();
      await controller.acquire();
    });

    test('the default is a no-op off Android', () {
      expect(
        defaultMulticastLockController(isAndroid: false),
        isA<NoopMulticastLockController>(),
      );
      expect(
        defaultMulticastLockController(isAndroid: true),
        isA<MethodChannelMulticastLockController>(),
      );
    });
  });
}
