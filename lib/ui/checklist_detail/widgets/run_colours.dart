import 'package:flutter/painting.dart';

import '../../../domain/models/checklist/checklist_colour.dart';
import '../../../domain/models/checklist/colour_run.dart';

/// Smallest contrast ratio a file's colour needs against the background.
///
/// Below this the run falls back to the default text colour, so a colour
/// written for a dark cockpit panel (white, pale grey) is still readable in
/// the light theme and the other way round.
const double minRunContrast = 4.5;

/// The colour for a run called [name], or null to use the default colour.
///
/// Null when [name] is null, is not in [palette], or would be hard to read
/// against [background].
Color? readableRunColour({
  required String? name,
  required Map<String, ChecklistColour> palette,
  required Color background,
}) {
  final defined = name == null ? null : palette[name];
  if (defined == null) return null;
  final colour = Color.from(
    alpha: 1,
    red: defined.red,
    green: defined.green,
    blue: defined.blue,
  );
  return contrastRatio(colour, background) >= minRunContrast ? colour : null;
}

/// WCAG contrast ratio between [a] and [b], from 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Text spans for [runs], coloured through [palette] where readable.
List<TextSpan> runSpans(
  List<ColourRun> runs,
  Map<String, ChecklistColour> palette,
  Color background,
) => [
  for (final run in runs)
    TextSpan(
      text: run.text,
      style: switch (readableRunColour(
        name: run.colour,
        palette: palette,
        background: background,
      )) {
        final colour? => TextStyle(color: colour),
        null => null,
      },
    ),
];
