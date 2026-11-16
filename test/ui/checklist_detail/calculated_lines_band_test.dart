import 'dart:async';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/calculate_line.dart';
import 'package:flightsim_aide/domain/models/checklist/calculated_value.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/calculated_lines_band.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

// AC-57: the calculated lines are shown under their item in a band that is
// not an item (not counted, not tappable); a warning names each input that is
// beyond the table; a line with no value says so.

const _torque = CalculateLine(
  table: 't',
  column: 'torque',
  label: 'Torque',
  unit: 'psi',
  step: 0.1,
);
const _fuel = CalculateLine(
  table: 't',
  column: 'ff',
  label: 'Fuel flow',
  unit: 'lb/h',
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('formatting', () {
    test('formatNumber groups thousands and keeps the decimals asked for', () {
      expect(formatNumber(32000), '32,000');
      expect(formatNumber(34.56, decimals: 1), '34.6');
      expect(formatNumber(1234567.5, decimals: 1), '1,234,567.5');
      expect(formatNumber(-4), '-4');
      expect(formatNumber(-0.04, decimals: 1), '0.0');
      expect(formatNumber(999), '999');
    });

    test('decimalsForStep shows what the step rounds to', () {
      expect(decimalsForStep(0.1), 1);
      expect(decimalsForStep(0.01), 2);
      expect(decimalsForStep(0.25), 2);
      expect(decimalsForStep(1), 0);
      expect(decimalsForStep(10), 0);
    });

    test('calculatedText gives the number and unit, or null', () {
      expect(calculatedText(_torque, const CalculatedValue(34.6)), '34.6 psi');
      expect(calculatedText(_fuel, const CalculatedValue(1475)), '1,475 lb/h');
      expect(
        calculatedText(_torque, const CalculatedValue.unavailable()),
        isNull,
      );
    });

    test('limitMessage names the input, the side and the value used', () {
      expect(
        limitMessage(
          const LimitExceeded(
            name: 'Altitude',
            unit: 'ft',
            actual: 32000,
            limit: 30000,
            above: true,
          ),
        ),
        'Altitude 32,000 ft is above the 30,000 ft limit: using 30,000 ft.',
      );
      expect(
        limitMessage(
          const LimitExceeded(
            name: 'w',
            actual: 2999.5,
            limit: 3175,
            above: false,
          ),
        ),
        'w 2,999.5 is below the 3,175 limit: using 3,175.',
      );
    });
  });

  group('band', () {
    testWidgets('shows the first line large and the others as rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CalculatedLinesBand(
            lines: [_torque, _fuel],
            values: [CalculatedValue(34.6), CalculatedValue(475)],
          ),
        ),
      );
      expect(find.textContaining('34.6'), findsOneWidget);
      expect(find.textContaining('psi'), findsOneWidget);
      expect(find.textContaining('Torque'), findsOneWidget);
      expect(find.text('Fuel flow'), findsOneWidget);
      expect(find.text('475 lb/h'), findsOneWidget);
      expect(find.byType(StatusPill), findsNothing);
    });

    testWidgets('a warning for each input beyond the table comes first', (
      tester,
    ) async {
      const altitude = LimitExceeded(
        name: 'Altitude',
        unit: 'ft',
        actual: 32000,
        limit: 30000,
        above: true,
      );
      const isa = LimitExceeded(
        name: 'ISA deviation',
        unit: 'C',
        actual: 34,
        limit: 30,
        above: true,
      );
      await tester.pumpWidget(
        _host(
          const CalculatedLinesBand(
            lines: [_torque, _fuel],
            // Both lines were beyond the same two limits: each shows once.
            values: [
              CalculatedValue(25.7, limits: [altitude, isa]),
              CalculatedValue(358, limits: [altitude, isa]),
            ],
          ),
        ),
      );
      expect(find.byType(StatusPill), findsNWidgets(2));
      expect(
        find.text(
          'Altitude 32,000 ft is above the 30,000 ft limit: using 30,000 ft.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('ISA deviation 34 C is above the 30 C limit: using 30 C.'),
        findsOneWidget,
      );
      // The first warning is above the big value.
      expect(
        tester.getTopLeft(find.byType(StatusPill).first).dy,
        lessThan(tester.getTopLeft(find.textContaining('25.7')).dy),
      );
    });

    testWidgets('a long warning wraps inside the pill on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const CalculatedLinesBand(
            lines: [_torque],
            values: [
              CalculatedValue(
                25.7,
                limits: [
                  LimitExceeded(
                    name: 'Pressure altitude of the aircraft',
                    unit: 'ft',
                    actual: 32000,
                    limit: 30000,
                    above: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no value says so for every line', (tester) async {
      await tester.pumpWidget(
        _host(
          const CalculatedLinesBand(
            lines: [_torque, _fuel],
            values: [
              CalculatedValue.unavailable(),
              CalculatedValue.unavailable(),
            ],
          ),
        ),
      );
      expect(find.textContaining('Torque · no data'), findsOneWidget);
      expect(find.text('no data'), findsOneWidget);
      expect(find.textContaining('psi'), findsNothing);
    });

    testWidgets('a missing value is shown as no data', (tester) async {
      await tester.pumpWidget(
        _host(const CalculatedLinesBand(lines: [_torque, _fuel], values: [])),
      );
      expect(find.textContaining('no data'), findsNWidgets(2));
    });
  });

  group('on the screen', () {
    const text = '''
sw_checklist:Cruise
sw_item:Power|SET
sw_calculate:t|y|Torque|psi|0.1
sw_calculate:t|y|Torque again|psi|0.1
sw_item:Other|OK
sw_table:t|x=a/x|y
sw_row:0|0
sw_row:10|100
sw_table_end
''';

    late FakeChecklistRepository repository;
    late ChecklistProgressRepositoryImpl progress;
    late GoRouter router;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repository = FakeChecklistRepository(
        current: const AircraftWorkflowParser().parse(text),
      );
      progress = ChecklistProgressRepositoryImpl();
      router = createRouter(initialLocation: Routes.list);
      addTearDown(router.dispose);
      addTearDown(repository.dispose);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ChecklistRepository>.value(value: repository),
            RepositoryProvider<ChecklistProgressRepository>.value(
              value: progress,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      unawaited(router.push(Routes.detailPath('Cruise')));
      await tester.pumpAndSettle();
    }

    testWidgets('the band shows under its item and is not counted', (
      tester,
    ) async {
      await pump(tester);
      // Two check items; the two calculated lines are not items.
      expect(find.text('0/2'), findsOneWidget);
      expect(find.byType(ChecklistItemTile), findsNWidgets(2));
      expect(find.byType(CalculatedLinesBand), findsOneWidget);
      // With no sim the lines have no value.
      expect(find.textContaining('Torque · no data'), findsOneWidget);
      // The band sits between the two items.
      final power = tester.getBottomLeft(find.byType(ChecklistItemTile).first);
      final band = tester.getTopLeft(find.byType(CalculatedLinesBand));
      final other = tester.getTopLeft(find.byType(ChecklistItemTile).last);
      expect(band.dy, greaterThanOrEqualTo(power.dy));
      expect(band.dy, lessThan(other.dy));
    });

    testWidgets('tapping the band does not tick anything', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(CalculatedLinesBand));
      await tester.pumpAndSettle();
      expect(find.text('0/2'), findsOneWidget);
    });
  });
}
