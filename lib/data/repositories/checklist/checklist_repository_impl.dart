import 'dart:async';

import '../../../domain/models/checklist/checklist_document.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import '../../parsers/aircraft_workflow_parser.dart';
import '../../services/checklist/checklist_source_service.dart';
import 'checklist_repository.dart';

/// [ChecklistRepository] that reads from a [ChecklistSourceService] and parses.
class ChecklistRepositoryImpl implements ChecklistRepository {
  /// Creates a repository reading from [source] and parsing with [parser].
  ChecklistRepositoryImpl({
    required this._source,
    this._parser = const AircraftWorkflowParser(),
  });

  final ChecklistSourceService _source;
  final AircraftWorkflowParser _parser;
  final _changes = StreamController<ChecklistDocument?>.broadcast();
  ChecklistDocument? _current;

  @override
  ChecklistDocument? get current => _current;

  @override
  Stream<ChecklistDocument?> get changes => _changes.stream;

  @override
  Future<Result<ChecklistDocument>> load() async {
    try {
      final raw = await _source.load();
      switch (raw) {
        case Error(:final error):
          return Error(error);
        case Ok(:final value):
          final doc = _parser
              .parse(value.text)
              .copyWith(sourceName: value.name);
          if (doc.checklists.isEmpty) {
            return Error(ParseFailure(_emptyMessage(doc)));
          }
          _current = doc;
          _changes.add(doc);
          return Ok(doc);
      }
    } catch (e) {
      return Error(ParseFailure('Could not read checklist: $e'));
    }
  }

  String _emptyMessage(ChecklistDocument doc) {
    final shown = doc.warnings.take(3).join('; ');
    return shown.isEmpty ? 'No checklists found' : shown;
  }
}
