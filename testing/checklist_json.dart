import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';

/// [doc] as plain JSON data: palette, checklists with their continue links,
/// and items with their colour runs (warnings are left out).
Map<String, Object?> documentToJson(ChecklistDocument doc) => {
  'colours': {
    for (final c in doc.colours.values) c.name: [c.red, c.green, c.blue],
  },
  'checklists': [
    for (final c in doc.checklists)
      {
        'name': c.name,
        'title': c.title,
        'continues': [for (final l in c.continues) l.target ?? '(next)'],
        'items': [
          for (final i in c.items)
            {
              'type': i.type.name,
              'label': i.label,
              'result': i.result,
              if (i.labelRuns.isNotEmpty) 'labelRuns': _runs(i.labelRuns),
              if (i.resultRuns.isNotEmpty) 'resultRuns': _runs(i.resultRuns),
            },
        ],
      },
  ],
};

List<Map<String, Object?>> _runs(List<ColourRun> runs) => [
  for (final r in runs) {'text': r.text, 'colour': r.colour},
];
