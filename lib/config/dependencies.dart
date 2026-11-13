import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/parsers/aircraft_workflow_parser.dart';
import '../data/repositories/checklist/checklist_progress_repository.dart';
import '../data/repositories/checklist/checklist_progress_repository_impl.dart';
import '../data/repositories/checklist/checklist_repository.dart';
import '../data/repositories/checklist/checklist_repository_impl.dart';
import '../data/services/checklist/checklist_source_service.dart';

/// Repositories shared by every environment, reading from [source].
///
/// [progress] replaces the in-memory progress repository, for the sources that
/// save progress per aircraft.
List<RepositoryProvider<dynamic>> sharedProviders(
  ChecklistSourceService source, {
  ChecklistProgressRepository Function()? progress,
}) => [
  RepositoryProvider<ChecklistRepository>(
    create: (_) => ChecklistRepositoryImpl(
      source: source,
      parser: const AircraftWorkflowParser(),
    ),
  ),
  RepositoryProvider<ChecklistProgressRepository>(
    create: (_) => progress?.call() ?? ChecklistProgressRepositoryImpl(),
  ),
];
