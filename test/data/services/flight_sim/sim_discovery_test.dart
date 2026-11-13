import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flightsim_aide/data/services/flight_sim/model/sim_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/xplane_beacon_discovery.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/plugin/fake_beacon_sender.dart';

class _FakeSource implements DatagramSource {
  final controller = StreamController<Datagram>.broadcast();
  bool closed = false;
  int refreshes = 0;

  @override
  Stream<Datagram> get datagrams => controller.stream;

  @override
  Future<void> refreshMembership() async => refreshes++;

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }

  void send(List<int> bytes, String from) => controller.add(
    Datagram(Uint8List.fromList(bytes), InternetAddress(from), 49707),
  );
}

void main() {
  late _FakeSource source;
  late int opened;
  late XPlaneBeaconDiscovery discovery;
  late List<SimEndpoint> found;

  setUp(() {
    source = _FakeSource();
    opened = 0;
    found = [];
    discovery = XPlaneBeaconDiscovery(
      openSource: () async {
        opened++;
        return source;
      },
    );
    discovery.endpoints.listen(found.add);
  });

  tearDown(() async => discovery.dispose());

  test('decoded beacons are emitted', () async {
    await discovery.start();
    source.send(FakeBeaconSender.build(name: 'SIMPC'), '192.168.1.10');
    await pumpEventQueue();
    expect(found, [const SimEndpoint(host: '192.168.1.10', name: 'SIMPC')]);
  });

  test('undecodable datagrams are ignored', () async {
    await discovery.start();
    source.send([1, 2, 3], '192.168.1.10');
    source.send(FakeBeaconSender.build(role: 2), '192.168.1.10');
    await pumpEventQueue();
    expect(found, isEmpty);
  });

  test('every beacon of one sim is reported (the repository keeps its list fresh from them)', () async {
    await discovery.start();
    for (var i = 0; i < 5; i++) {
      source.send(FakeBeaconSender.build(), '192.168.1.10');
    }
    await pumpEventQueue();
    expect(found.length, 5);
  });

  test('two sims are both reported', () async {
    await discovery.start();
    source.send(FakeBeaconSender.build(name: 'A'), '192.168.1.10');
    source.send(FakeBeaconSender.build(name: 'B'), '192.168.1.117');
    await pumpEventQueue();
    expect([for (final e in found) e.host], ['192.168.1.10', '192.168.1.117']);
  });

  test('a sim that changes name is reported again', () async {
    await discovery.start();
    source.send(FakeBeaconSender.build(name: 'A'), '192.168.1.10');
    source.send(FakeBeaconSender.build(name: 'B'), '192.168.1.10');
    await pumpEventQueue();
    expect(found.length, 2);
  });

  test('manual ip mode never opens the group listener', () async {
    await discovery.dispose();
    discovery = XPlaneBeaconDiscovery(
      manualHost: '192.168.1.10',
      openSource: () async {
        opened++;
        return source;
      },
    );
    final manual = <SimEndpoint>[];
    discovery.endpoints.listen(manual.add);
    await discovery.start();
    await pumpEventQueue();
    expect(opened, 0);
    expect(manual, [const SimEndpoint(host: '192.168.1.10')]);
  });

  test('listener closes on dispose', () async {
    await discovery.start();
    expect(opened, 1);
    await discovery.dispose();
    expect(source.closed, isTrue);
  });

  test('start twice opens one listener and stop closes it', () async {
    await discovery.start();
    await discovery.start();
    expect(opened, 1);
    await discovery.stop();
    expect(source.closed, isTrue);
  });

  test('refresh re-joins the group', () async {
    await discovery.start();
    await discovery.refresh();
    expect(source.refreshes, 1);
  });

  group('parseManualIp', () {
    test('accepts an IPv4 address', () {
      expect(
        parseManualIp(' 192.168.1.10 ').valueOrNull,
        const SimEndpoint(host: '192.168.1.10'),
      );
    });

    test('rejects text, empty and out-of-range input', () {
      for (final bad in ['', 'abc', '192.168.50', '300.1.1.1', '1.2.3.4.5']) {
        expect(
          parseManualIp(bad).errorOrNull,
          isA<InvalidManualIp>(),
          reason: bad,
        );
      }
    });
  });
}
