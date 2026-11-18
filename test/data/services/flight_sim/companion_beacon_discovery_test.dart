import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flightsim_aide/data/services/flight_sim/companion_beacon_discovery.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/sim_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/xplane_beacon_discovery.dart';
import 'package:flightsim_aide/domain/models/flight_sim/simulator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/services/fake_sim_discovery_service.dart';

class _FakeSource implements DatagramSource {
  final controller = StreamController<Datagram>.broadcast();
  bool closed = false;

  @override
  Stream<Datagram> get datagrams => controller.stream;

  @override
  Future<void> refreshMembership() async {}

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }

  void send(List<int> bytes, String from) => controller.add(
    Datagram(Uint8List.fromList(bytes), InternetAddress(from), 18094),
  );
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final from = InternetAddress('192.168.1.10');

  group('decodeCompanionBeacon', () {
    test('reads the golden file shared with the plugin', () {
      final golden = File(
        'testing/fixtures/protocol/companion_beacon_msfs.json',
      ).readAsBytesSync();
      final beacon = decodeCompanionBeacon(golden, from);
      expect(beacon?.ip, '192.168.1.10');
      expect(beacon?.name, 'FLIGHT-PC');
      expect(beacon?.port, 18086);
      expect(beacon?.simKind, 'msfs');
    });

    test('refuses what is not the beacon', () {
      for (final text in [
        '',
        'not json',
        '[]',
        '{}',
        '{"fsaide":2,"sim":"msfs","name":"A","port":18086}',
        '{"sim":"msfs","name":"A","port":18086}',
        '{"fsaide":1,"name":"A","port":18086}',
        '{"fsaide":1,"sim":"","name":"A","port":18086}',
        '{"fsaide":1,"sim":"msfs","port":18086}',
        '{"fsaide":1,"sim":"msfs","name":"A"}',
        '{"fsaide":1,"sim":"msfs","name":"A","port":"18086"}',
        '{"fsaide":1,"sim":"msfs","name":"A","port":0}',
        '{"fsaide":1,"sim":"msfs","name":"A","port":65536}',
        '{"fsaide":1,"sim":7,"name":"A","port":18086}',
      ]) {
        expect(decodeCompanionBeacon(_bytes(text), from), isNull, reason: text);
      }
    });

    test(
      'refuses a datagram that is too large and bytes that are not UTF-8',
      () {
        expect(
          decodeCompanionBeacon(_bytes('{"a":"${'x' * 600}"}'), from),
          isNull,
        );
        expect(
          decodeCompanionBeacon(Uint8List.fromList([0xff, 0xfe, 0x7b]), from),
          isNull,
        );
      },
    );
  });

  group('CompanionBeaconDiscovery', () {
    late _FakeSource source;
    late CompanionBeaconDiscovery discovery;
    late List<SimEndpoint> found;

    setUp(() {
      source = _FakeSource();
      found = [];
      discovery = CompanionBeaconDiscovery(openSource: () async => source);
      discovery.endpoints.listen(found.add);
    });

    tearDown(() async => discovery.dispose());

    test('a beacon becomes an endpoint that names its simulator', () async {
      await discovery.start();
      source.send(
        utf8.encode(
          '{"fsaide":1,"sim":"msfs","name":"FLIGHT-PC","port":18087}',
        ),
        '192.168.1.20',
      );
      await pumpEventQueue();
      expect(found, [
        const SimEndpoint(
          host: '192.168.1.20',
          name: 'FLIGHT-PC',
          simulator: Simulator.msfs,
        ),
      ]);
    });

    test('a simulator this app does not know is not listed', () async {
      await discovery.start();
      source.send(
        utf8.encode('{"fsaide":1,"sim":"prepar3d","name":"A","port":18086}'),
        '192.168.1.20',
      );
      source.send([1, 2, 3], '192.168.1.20');
      await pumpEventQueue();
      expect(found, isEmpty);
    });

    test('every beacon is passed on, so the list stays fresh', () async {
      await discovery.start();
      for (var i = 0; i < 3; i++) {
        source.send(
          utf8.encode('{"fsaide":1,"sim":"msfs","name":"A","port":18086}'),
          '192.168.1.20',
        );
      }
      await pumpEventQueue();
      expect(found, hasLength(3));
    });

    test(
      'a socket that cannot be opened leaves it deaf, not failing',
      () async {
        final deaf = CompanionBeaconDiscovery(
          openSource: () async => throw const SocketException('in use'),
        );
        await deaf.start();
        await deaf.refresh();
        await deaf.stop();
        await deaf.dispose();
      },
    );

    test('stop closes the socket and start listens again', () async {
      await discovery.start();
      await discovery.stop();
      expect(source.closed, isTrue);
    });
  });

  group('CompositeSimDiscovery', () {
    test(
      'starts, refreshes and stops every part and merges what they find',
      () async {
        final a = FakeSimDiscoveryService();
        final b = FakeSimDiscoveryService();
        final composite = CompositeSimDiscovery([a, b]);
        final found = <SimEndpoint>[];
        composite.endpoints.listen(found.add);

        await composite.start();
        await composite.refresh();
        a.see(const SimEndpoint(host: '10.0.0.1', simulator: Simulator.xplane));
        b.see(const SimEndpoint(host: '10.0.0.2', simulator: Simulator.msfs));
        await pumpEventQueue();
        await composite.stop();

        expect([a.starts, b.starts], [1, 1]);
        expect([a.refreshes, b.refreshes], [1, 1]);
        expect([a.stops, b.stops], [1, 1]);
        expect(found.map((e) => e.host), ['10.0.0.1', '10.0.0.2']);

        await composite.dispose();
        expect([a.disposed, b.disposed], [true, true]);
      },
    );
  });
}
