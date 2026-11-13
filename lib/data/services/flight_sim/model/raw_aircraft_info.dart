import 'package:equatable/equatable.dart';

/// The `GET /v1/aircraft` answer, as sent. Nothing is computed here.
class RawAircraftInfo extends Equatable {
  /// Creates an aircraft answer.
  const RawAircraftInfo({
    required this.protocolVersion,
    required this.generation,
    required this.icao,
    required this.description,
    required this.aircraftPath,
    this.checklistPath,
    this.checklistModified,
    this.checklistSize,
  });

  /// The protocol version the plugin speaks.
  final int protocolVersion;

  /// Counter that rises on every aircraft load.
  final int generation;

  /// ICAO code; may be empty.
  final String icao;

  /// Human-readable aircraft name.
  final String description;

  /// Path of the `.acf`.
  final String aircraftPath;

  /// Path of the checklist file, when one exists.
  final String? checklistPath;

  /// Last-write time of the checklist file in epoch milliseconds.
  final int? checklistModified;

  /// Size of the checklist file in bytes.
  final int? checklistSize;

  @override
  List<Object?> get props => [
    protocolVersion,
    generation,
    icao,
    description,
    aircraftPath,
    checklistPath,
    checklistModified,
    checklistSize,
  ];
}
