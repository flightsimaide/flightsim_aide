import 'dart:async';
import 'dart:io';

import 'package:flightsim_aide/data/services/flight_sim/network_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/services/manual_clock.dart';

void main() {
  late ManualClock clock;
  late List<InternetAddress> addresses;
  Object? failure;
  late PollingNetworkStatusService service;
  late List<bool> events;
  late StreamSubscription<bool> subscription;

  final lan = InternetAddress('192.168.1.10');
  final loopback = InternetAddress.loopbackIPv4;
  final linkLocal = InternetAddress('169.254.10.20');

  Future<void> settle() => pumpEventQueue();

  Future<void> start() async {
    service = PollingNetworkStatusService(
      listAddresses: () async {
        if (failure != null) throw failure!;
        return addresses;
      },
      clock: clock,
    );
    events = [];
    subscription = service.availability.listen(events.add);
    service.start();
    await settle();
  }

  setUp(() {
    clock = ManualClock();
    addresses = [];
    failure = null;
  });

  tearDown(() async {
    await subscription.cancel();
    service.dispose();
  });

  Future<void> tick() async {
    clock.advance(const Duration(seconds: 2));
    await settle();
  }

  test('address present gives available', () async {
    addresses = [loopback, lan];
    await start();
    expect(service.isAvailable, isTrue);
    expect(events, [true]);
  });

  test('only loopback gives unavailable', () async {
    addresses = [loopback];
    await start();
    expect(service.isAvailable, isFalse);
    expect(events, [false]);
  });

  test('only link-local gives unavailable', () async {
    addresses = [linkLocal];
    await start();
    expect(events, [false]);
  });

  test(
    'interface list throwing gives unavailable and does not crash',
    () async {
      failure = const SocketException('no interfaces');
      await start();
      expect(events, [false]);
      await tick();
      expect(service.isAvailable, isFalse);
    },
  );

  test('emits only on change', () async {
    addresses = [lan];
    await start();
    await tick();
    await tick();
    expect(events, [true]);
    addresses = [];
    await tick();
    addresses = [];
    await tick();
    addresses = [lan];
    await tick();
    expect(events, [true, false, true]);
  });

  test(
    'send failure flips to unavailable until the next successful poll',
    () async {
      addresses = [lan];
      await start();
      service.reportSendFailure();
      await settle();
      expect(service.isAvailable, isFalse);
      expect(events, [true, false]);
      service.reportSendFailure();
      await settle();
      expect(events, [true, false]);
      await tick();
      expect(service.isAvailable, isTrue);
      expect(events, [true, false, true]);
    },
  );

  test('no timers remain after dispose', () async {
    addresses = [lan];
    await start();
    expect(clock.pendingTimers, 1);
    service.dispose();
    expect(clock.pendingTimers, 0);
  });
}
