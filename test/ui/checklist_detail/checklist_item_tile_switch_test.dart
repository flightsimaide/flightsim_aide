import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/switch_gate.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Switches (D-82): the switch row.

const _switchRow = ChecklistItem(
  ChecklistItemType.option,
  'Use GPU',
  '',
  [],
  [],
  null,
  ChecklistJustify.center,
  null,
  SwitchDef('gpu'),
);

Future<void> _pump(
  WidgetTester tester,
  ChecklistItem item, {
  bool optionOn = false,
  bool autoOn = false,
  bool checked = false,
  VoidCallback? onTap,
  VoidCallback? onSwitch,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ChecklistItemTile(
          item: item,
          checked: checked,
          onTap: onTap ?? () {},
          onSwitch: onSwitch,
          optionOn: optionOn,
          autoOn: autoOn,
        ),
      ),
    ),
  ),
);

void main() {
  group('switch row', () {
    testWidgets('shows the label and a switch that follows optionOn', (
      tester,
    ) async {
      await _pump(tester, _switchRow);
      expect(find.text('Use GPU'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(optionSwitchKey)).value, isFalse);
      await _pump(tester, _switchRow, optionOn: true);
      expect(tester.widget<Switch>(find.byKey(optionSwitchKey)).value, isTrue);
    });

    testWidgets('tapping the row ticks it, tapping the switch flips it', (
      tester,
    ) async {
      var taps = 0;
      var flips = 0;
      await _pump(
        tester,
        _switchRow,
        onTap: () => taps++,
        onSwitch: () => flips++,
      );
      await tester.tap(find.text('Use GPU'));
      expect([taps, flips], [1, 0]);
      await tester.tap(find.byKey(optionSwitchKey));
      expect([taps, flips], [1, 1]);
    });

    testWidgets('has a check circle at the far left that shows the tick', (
      tester,
    ) async {
      await _pump(tester, _switchRow);
      final marker = find.byType(ChecklistMarker);
      expect(marker, findsOneWidget);
      expect(tester.widget<ChecklistMarker>(marker).checked, isFalse);
      expect(
        tester.getTopLeft(marker).dx,
        lessThan(tester.getTopLeft(find.text('Use GPU')).dx),
      );
      await _pump(tester, _switchRow, checked: true, optionOn: false);
      expect(tester.widget<ChecklistMarker>(marker).checked, isTrue);
      expect(
        tester.widget<Switch>(find.byKey(optionSwitchKey)).value,
        isFalse,
        reason: 'the tick does not move the switch',
      );
    });

    testWidgets('is flagged as a manual item while auto is on', (tester) async {
      await _pump(tester, _switchRow, autoOn: true);
      expect(find.text('manual item'), findsOneWidget);
      await _pump(tester, _switchRow);
      expect(find.text('manual item'), findsNothing);
    });

    testWidgets('is as tall as a check row and has a line on top', (
      tester,
    ) async {
      await _pump(tester, _switchRow);
      expect(
        tester.getSize(find.byType(ChecklistItemTile)).height,
        greaterThanOrEqualTo(58),
      );
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('is read as a switch with its position', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _switchRow);
      expect(
        find.bySemanticsLabel(RegExp('Use GPU, unchecked.*switch off')),
        findsOneWidget,
      );
      await _pump(tester, _switchRow, optionOn: true, checked: true);
      expect(
        find.bySemanticsLabel(RegExp('Use GPU, checked.*switch on')),
        findsOneWidget,
      );
      handle.dispose();
    });

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      testWidgets('uses no status colour, ${theme.brightness.name}', (
        tester,
      ) async {
        await _pump(tester, _switchRow, optionOn: true, theme: theme);
        final track = tester.widget<Switch>(find.byKey(optionSwitchKey));
        expect(track.activeThumbColor, isNull);
        expect(track.activeTrackColor, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
