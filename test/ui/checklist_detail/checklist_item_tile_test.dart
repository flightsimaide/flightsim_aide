import 'package:flightsim_aide/domain/models/checklist/checklist_colour.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/run_colours.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/themes/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _condition = CompareCondition(
  DatarefExpr(Dataref('a/b')),
  CompareOp.equal,
  NumberExpr(1),
);
const _check = ChecklistItem(
  ChecklistItemType.check,
  'Parking brake',
  'SET',
  [],
  [],
  _condition,
);
const _manual = ChecklistItem(ChecklistItemType.check, 'Parking brake', 'SET');
const _note = ChecklistItem(ChecklistItemType.note, '----- Prepare -----');

Future<void> _pump(
  WidgetTester tester,
  ChecklistItem item, {
  bool checked = false,
  VoidCallback? onTap,
  Map<String, ChecklistColour> colours = const {},
  double textScale = 1,
  Size? size,
  bool skipped = false,
  bool disagreed = false,
  bool autoOn = false,
}) {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChecklistItemTile(
            item: item,
            checked: checked,
            onTap: onTap ?? () {},
            colours: colours,
            skipped: skipped,
            disagreed: disagreed,
            autoOn: autoOn,
          ),
        ),
      ),
    ),
  );
}

Color? _rowColour(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(
            of: find.byType(ChecklistItemTile),
            matching: find.byType(Material),
          )
          .first,
    )
    .color;

TextDecoration? _decoration(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.decoration;

void main() {
  group('check row', () {
    testWidgets('shows label and result', (tester) async {
      await _pump(tester, _check);
      expect(find.text('Parking brake'), findsOneWidget);
      expect(find.text('SET'), findsOneWidget);
    });

    testWidgets('unchecked has no line-through', (tester) async {
      await _pump(tester, _check);
      expect(
        _decoration(tester, 'Parking brake'),
        isNot(TextDecoration.lineThrough),
      );
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    BoxDecoration marker(WidgetTester tester) =>
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(ChecklistMarker),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;

    Color? textColour(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style?.color;

    testWidgets('open: a grey ring and the normal text colour', (tester) async {
      await _pump(tester, _check);
      final ring = marker(tester);
      expect(ring.shape, BoxShape.circle);
      expect(ring.color, isNull);
      expect(ring.border?.top.color, AppTheme.light.colorScheme.outline);
      expect(tester.getSize(find.byType(ChecklistMarker)), const Size(22, 22));
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('checked: only the circle is green, text stays normal', (
      tester,
    ) async {
      await _pump(tester, _check, checked: true);
      expect(marker(tester).color, StatusColors.light.success);
      expect(
        find.descendant(
          of: find.byType(ChecklistMarker),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      for (final text in ['Parking brake', 'SET']) {
        expect(_decoration(tester, text), isNot(TextDecoration.lineThrough));
        expect(textColour(tester, text), isNot(StatusColors.light.success));
      }
      expect(
        textColour(tester, 'Parking brake'),
        AppTheme.light.colorScheme.onSurface,
      );
    });

    testWidgets(
      'an open row is a shade lighter than the page, a checked row is tinted',
      (tester) async {
        Color? background() => tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(ChecklistItemTile),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;
        await _pump(tester, _check);
        final page = AppTheme.light.colorScheme.surface;
        expect(
          background(),
          ChecklistItemTile.rowColour(AppTheme.light.colorScheme),
        );
        expect(
          background()!.computeLuminance(),
          greaterThan(page.computeLuminance()),
        );
        await _pump(tester, _check, checked: true);
        expect(background(), AppTheme.light.colorScheme.primaryContainer);
      },
    );

    testWidgets('skipped: amber row, normal text and a solid disc', (
      tester,
    ) async {
      await _pump(tester, _check, skipped: true);
      expect(_rowColour(tester), StatusColors.light.cautionBackground);
      expect(marker(tester).color, textColour(tester, 'Parking brake'));
      expect(
        textColour(tester, 'Parking brake'),
        isNot(StatusColors.light.caution),
      );
    });

    testWidgets('overridden: red row, normal text and the error icon', (
      tester,
    ) async {
      await _pump(tester, _check, checked: true, disagreed: true);
      expect(_rowColour(tester), StatusColors.light.error);
      expect(
        textColour(tester, 'Parking brake'),
        isNot(StatusColors.light.error),
      );
      expect(find.byKey(disagreedMarkerKey), findsOneWidget);
    });

    testWidgets('the result is in capitals and muted; the label keeps case', (
      tester,
    ) async {
      await _pump(
        tester,
        const ChecklistItem(
          ChecklistItemType.check,
          'Fuel Pump',
          'check off',
          [],
          [],
          _condition,
        ),
      );
      expect(find.text('CHECK OFF'), findsOneWidget);
      expect(find.text('Fuel Pump'), findsOneWidget);
      expect(
        textColour(tester, 'CHECK OFF'),
        AppTheme.light.colorScheme.onSurfaceVariant,
      );
    });

    testWidgets('the spoken label keeps the result as written', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const ChecklistItem(
          ChecklistItemType.check,
          'Fuel Pump',
          'check off',
          [],
          [],
          _condition,
        ),
      );
      expect(
        find.bySemanticsLabel('Fuel Pump, check off, unchecked'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the result is right-justified and stays put when checked', (
      tester,
    ) async {
      await _pump(tester, _check, size: const Size(600, 400));
      final tile = tester.getRect(find.byType(ChecklistItemTile));
      final unchecked = tester.getRect(find.text('SET'));
      // Flush against the right end of its column.
      expect(tile.right - unchecked.right, closeTo(16, 1));
      await _pump(tester, _check, checked: true, size: const Size(600, 400));
      expect(tester.getRect(find.text('SET')).right, unchecked.right);
    });

    testWidgets('every check row has one line, on its top edge, inset 16', (
      tester,
    ) async {
      Finder lines() => find.descendant(
        of: find.byType(ChecklistItemTile),
        matching: find.byType(Divider),
      );
      await _pump(tester, _check, size: const Size(600, 400));
      expect(lines(), findsOneWidget);
      final tile = tester.getRect(find.byType(ChecklistItemTile));
      final line = tester.getRect(lines());
      expect(line.left - tile.left, 16);
      expect(tile.right - line.right, 16);
      expect(line.top, closeTo(tile.top, 1), reason: 'above the row');
    });

    testWidgets('the marker is 18 from the left and the label starts at 50', (
      tester,
    ) async {
      await _pump(tester, _check, size: const Size(600, 400));
      final tile = tester.getRect(find.byType(ChecklistItemTile));
      expect(tester.getRect(find.byType(ChecklistMarker)).left - tile.left, 18);
      expect(tester.getRect(find.text('Parking brake')).left - tile.left, 50);
    });

    testWidgets('a wrapped label keeps the result vertically centred', (
      tester,
    ) async {
      final item = ChecklistItem(
        ChecklistItemType.check,
        'L ' * 60,
        'SET',
        [],
        [],
        _condition,
      );
      await _pump(tester, item, size: const Size(320, 640));
      final tile = tester.getRect(find.byType(ChecklistItemTile));
      expect(tile.height, greaterThan(73));
      expect(
        tester.getRect(find.text('SET')).center.dy,
        closeTo(tile.center.dy, 2),
      );
    });

    testWidgets('tapping the label toggles', (tester) async {
      var taps = 0;
      await _pump(tester, _check, onTap: () => taps++);
      await tester.tap(find.text('Parking brake'));
      expect(taps, 1);
    });

    testWidgets('tapping the result text toggles', (tester) async {
      var taps = 0;
      await _pump(tester, _check, onTap: () => taps++);
      await tester.tap(find.text('SET'));
      expect(taps, 1);
    });

    testWidgets('tapping the marker toggles once (not twice)', (tester) async {
      var taps = 0;
      await _pump(tester, _check, onTap: () => taps++);
      await tester.tap(find.byType(ChecklistMarker));
      expect(taps, 1);
    });

    testWidgets('height at least 58', (tester) async {
      await _pump(
        tester,
        const ChecklistItem(
          ChecklistItemType.check,
          'A',
          '',
          [],
          [],
          _condition,
        ),
      );
      expect(
        tester.getSize(find.byType(ChecklistItemTile)).height,
        greaterThanOrEqualTo(58),
      );
    });

    testWidgets('semantics includes checked state', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _check, checked: true);
      expect(
        find.bySemanticsLabel('Parking brake, SET, checked'),
        findsOneWidget,
      );
      await _pump(tester, _check);
      expect(
        find.bySemanticsLabel('Parking brake, SET, unchecked'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('empty result shows nothing on the right', (tester) async {
      await _pump(
        tester,
        const ChecklistItem(
          ChecklistItemType.check,
          'Only a label',
          '',
          [],
          [],
          _condition,
        ),
      );
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('a readable colour run is drawn in its colour', (tester) async {
      await _pump(
        tester,
        const ChecklistItem(
          ChecklistItemType.check,
          'Red plain',
          '',
          [ColourRun('Red', 'red'), ColourRun(' plain')],
          [],
          _condition,
        ),
        colours: const {'red': ChecklistColour('red', 0.6, 0, 0)},
      );
      final text = tester.widget<Text>(find.byType(Text));
      final spans = text.textSpan! as TextSpan;
      final children = spans.children!.cast<TextSpan>();
      expect(children.first.style?.color, const Color.fromARGB(255, 153, 0, 0));
      expect(children.last.style, isNull);
    });

    testWidgets('an unreadable colour falls back to the default', (
      tester,
    ) async {
      await _pump(
        tester,
        const ChecklistItem(
          ChecklistItemType.check,
          'Pale',
          '',
          [ColourRun('Pale', 'white')],
          [],
          _condition,
        ),
        colours: const {'white': ChecklistColour('white', 1, 1, 1)},
      );
      final text = tester.widget<Text>(find.byType(Text));
      final children = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(children.single.style, isNull);
    });
  });

  group('note row', () {
    testWidgets('note shows text', (tester) async {
      await _pump(tester, _note);
      expect(find.text('----- Prepare -----'), findsOneWidget);
    });

    testWidgets('a note has no marker', (tester) async {
      await _pump(tester, _note);
      expect(find.byType(ChecklistMarker), findsNothing);
    });

    testWidgets('tapping a note calls nothing', (tester) async {
      var taps = 0;
      await _pump(tester, _note, onTap: () => taps++);
      await tester.tap(find.text('----- Prepare -----'));
      expect(taps, 0);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('note text is styled as a header', (tester) async {
      await _pump(tester, _note);
      final style = tester.widget<Text>(find.text('----- Prepare -----')).style;
      expect(style?.fontWeight, FontWeight.bold);
    });
  });

  group('long text safety', () {
    final label = 'L' * 500;
    final result = 'R' * 100;
    final long = ChecklistItem(
      ChecklistItemType.check,
      label,
      result,
      [],
      [],
      _condition,
    );

    testWidgets('no overflow at 320 px and text scale 2.0', (tester) async {
      await _pump(tester, long, textScale: 2, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets('label wraps to multiple lines', (tester) async {
      await _pump(tester, long, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      final height = tester.getSize(find.text(label)).height;
      expect(height, greaterThan(100));
    });

    testWidgets('a long note does not overflow either', (tester) async {
      await _pump(
        tester,
        ChecklistItem(ChecklistItemType.note, label, result),
        textScale: 2,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('manual item (no condition)', () {
    const withCondition = ChecklistItem(
      ChecklistItemType.check,
      'Fuel pumps',
      'ON',
      [],
      [],
      CompareCondition(
        DatarefExpr(Dataref('a/b')),
        CompareOp.equal,
        NumberExpr(1),
      ),
    );

    testWidgets('open item without a condition says manual item with auto on', (
      tester,
    ) async {
      await _pump(tester, _manual, autoOn: true);
      expect(find.text('manual item'), findsOneWidget);
    });

    testWidgets('with auto off nothing is flagged', (tester) async {
      await _pump(tester, _manual);
      expect(find.text('manual item'), findsNothing);
    });

    testWidgets('item with a condition has no label', (tester) async {
      await _pump(tester, withCondition, autoOn: true);
      expect(find.text('manual item'), findsNothing);
    });

    testWidgets('a flagged row keeps the normal tint (it joins its details)', (
      tester,
    ) async {
      await _pump(tester, withCondition, autoOn: true);
      final plain = _rowColour(tester);
      await _pump(tester, _manual, autoOn: true);
      expect(_rowColour(tester), plain);
    });

    testWidgets('checked and skipped rows do not show it', (tester) async {
      await _pump(tester, _manual, checked: true, autoOn: true);
      expect(find.text('manual item'), findsNothing);
      await _pump(tester, _manual, skipped: true, autoOn: true);
      expect(find.text('manual item'), findsNothing);
    });

    testWidgets('notes do not show it', (tester) async {
      await _pump(tester, _note, autoOn: true);
      expect(find.text('manual item'), findsNothing);
    });

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      testWidgets('label reads on the tint in ${theme.brightness.name}', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ChecklistItemTile(
                item: _manual,
                checked: false,
                autoOn: true,
                onTap: () {},
              ),
            ),
          ),
        );
        final label = tester.widget<Text>(find.text('manual item'));
        final fill =
            (tester
                        .widget<DecoratedBox>(
                          find
                              .ancestor(
                                of: find.text('manual item'),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .color!;
        expect(
          contrastRatio(label.style!.color!, fill),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}
