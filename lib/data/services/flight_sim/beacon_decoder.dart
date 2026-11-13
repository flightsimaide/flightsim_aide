import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'model/raw_beacon.dart';

const _header = [0x42, 0x45, 0x43, 0x4e, 0x00]; // "BECN" and a NUL
const _nameOffset = 21;
const _masterRole = 1;

/// Decodes an X-Plane `BECN` multicast datagram received from [source].
///
/// Layout (little endian): header, major u8, minor u8, host id i32, version
/// i32, role u32, port u16, a NUL-terminated name. Returns null for a short
/// packet, a wrong header, a role other than master or an unterminated name.
/// Never throws.
RawBeacon? decodeBeacon(Uint8List bytes, InternetAddress source) {
  if (bytes.length <= _nameOffset) return null;
  for (var i = 0; i < _header.length; i++) {
    if (bytes[i] != _header[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(15, Endian.little) != _masterRole) return null;
  final end = bytes.indexOf(0, _nameOffset);
  if (end < 0) return null;
  return RawBeacon(
    ip: source.address,
    port: data.getUint16(19, Endian.little),
    name: utf8.decode(bytes.sublist(_nameOffset, end), allowMalformed: true),
    version: data.getInt32(11, Endian.little),
  );
}
