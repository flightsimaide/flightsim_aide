import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flightsim_aide/data/services/flight_sim/beacon_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/plugin/fake_beacon_sender.dart';

void main() {
  final source = InternetAddress('192.168.1.10');

  test('real xp12 beacon fixture decodes', () {
    final bytes = File('testing/fixtures/protocol/becn_xp12.bin')
        .readAsBytesSync();
    final beacon = decodeBeacon(bytes, source);
    expect(beacon, isNotNull);
    expect(beacon!.ip, '192.168.1.10');
    expect(beacon.port, 49000);
    expect(beacon.name, 'SIMPC');
    expect(beacon.version, 124417);
  });

  test('built packet round-trips its fields', () {
    final packet = FakeBeaconSender.build(
      name: 'Cockpit PC',
      port: 49001,
      version: 120000,
    );
    final beacon = decodeBeacon(packet, source)!;
    expect(beacon.name, 'Cockpit PC');
    expect(beacon.port, 49001);
    expect(beacon.version, 120000);
  });

  test('truncated packet gives null', () {
    final packet = FakeBeaconSender.build();
    for (var length = 0; length < 22; length++) {
      expect(
        decodeBeacon(FakeBeaconSender.truncated(packet, length), source),
        isNull,
        reason: 'length $length',
      );
    }
  });

  test('wrong header gives null', () {
    final packet = FakeBeaconSender.build();
    packet[0] = 0x58;
    expect(decodeBeacon(packet, source), isNull);
  });

  test('non-master role gives null', () {
    expect(decodeBeacon(FakeBeaconSender.build(role: 2), source), isNull);
    expect(decodeBeacon(FakeBeaconSender.build(role: 3), source), isNull);
  });

  test('a name without a terminator still gives null', () {
    final packet = FakeBeaconSender.build();
    final cut = Uint8List.sublistView(packet, 0, packet.length - 3);
    expect(decodeBeacon(cut, source), isNull);
  });

  test('500 random buffers never throw', () {
    final random = Random(42);
    for (var i = 0; i < 500; i++) {
      final bytes = Uint8List.fromList(
        List.generate(random.nextInt(80), (_) => random.nextInt(256)),
      );
      if (i.isEven && bytes.length > 5) {
        bytes.setRange(0, 5, const [0x42, 0x45, 0x43, 0x4e, 0x00]);
      }
      expect(() => decodeBeacon(bytes, source), returnsNormally);
    }
  });
}
