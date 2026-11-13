import 'package:equatable/equatable.dart';

/// Which aircraft the simulator has loaded, and what is known about its
/// checklist file. Built by the repository from the plugin's raw answer.
class AircraftIdentity extends Equatable {
  /// Creates an identity. The checklist fields are null when the aircraft has
  /// no checklist file.
  const AircraftIdentity({
    required this.icao,
    required this.description,
    required this.aircraftPath,
    this.checklistModified,
    this.checklistSize,
    this.checklistPath,
    this.generation,
  });

  /// ICAO type code; may be empty.
  final String icao;

  /// Human-readable aircraft name.
  final String description;

  /// Path of the `.acf` as the simulator reports it. Opaque; it keys caches.
  final String aircraftPath;

  /// Last-write time of the checklist file, epoch milliseconds UTC.
  final int? checklistModified;

  /// Size of the checklist file in bytes.
  final int? checklistSize;

  /// Path of the checklist file the plugin used.
  final String? checklistPath;

  /// Counter that rises on every aircraft load (not on file edits).
  final int? generation;

  @override
  List<Object?> get props => [
    icao,
    description,
    aircraftPath,
    checklistModified,
    checklistSize,
    checklistPath,
    generation,
  ];
}
