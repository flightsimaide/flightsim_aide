import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    for (final status in PillStatus.values) {
      testWidgets('$name $status: text and icon are readable on the fill', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            // No style given, as in the checklist list.
            home: Scaffold(
              body: StatusPill(status: status, text: 'Pill'),
            ),
          ),
        );
        final fill =
            (tester
                        .widget<DecoratedBox>(find.byType(DecoratedBox).first)
                        .decoration
                    as BoxDecoration)
                .color!;
        final text = tester.widget<Text>(find.text('Pill')).style!.color!;
        expect(_contrast(text, fill), greaterThanOrEqualTo(4.5));
        final icon = tester.widget<Icon>(find.byType(Icon)).color!;
        expect(_contrast(icon, fill), greaterThanOrEqualTo(4.5));
      });
    }
  }
}
