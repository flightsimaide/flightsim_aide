import 'package:bloc_test/bloc_test.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_app_bar_title.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_state.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockConnection extends MockCubit<ConnectionViewState>
    implements ConnectionCubit {}

const _pc12 = AircraftIdentity(
  icao: 'PC12',
  description: 'Pilatus PC-12/47',
  aircraftPath: 'pc12.acf',
);
const _noIcao = AircraftIdentity(
  icao: '',
  description: 'Homebuilt',
  aircraftPath: 'h.acf',
);

Future<void> _pump(
  WidgetTester tester, {
  ConnectionViewState? state,
  String title = 'Before takeoff',
  Size size = const Size(800, 600),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bar = Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: ChecklistAppBarTitle(title: title),
    ),
  );
  Widget home = bar;
  if (state != null) {
    final cubit = _MockConnection();
    when(() => cubit.state).thenReturn(state);
    home = BlocProvider<ConnectionCubit>.value(value: cubit, child: bar);
  }
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.light, home: home),
  );
}

void main() {
  testWidgets('shows the name and the aircraft as the home page does', (
    tester,
  ) async {
    await _pump(tester, state: const LinkConnected(_pc12));
    expect(find.text('Before takeoff'), findsOneWidget);
    expect(find.text('Pilatus PC-12/47 (PC12)'), findsOneWidget);
  });

  testWidgets('the aircraft is below the name, smaller and fainter', (
    tester,
  ) async {
    await _pump(tester, state: const LinkConnected(_pc12));
    final name = find.text('Before takeoff');
    final line = find.byKey(aircraftLineKey);
    expect(
      tester.getTopLeft(line).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(name).dy),
    );
    final nameStyle = DefaultTextStyle.of(tester.element(name)).style;
    final lineStyle = tester.widget<Text>(line).style!;
    expect(lineStyle.fontSize!, lessThan(nameStyle.fontSize!));
    expect(lineStyle.color, AppTheme.light.colorScheme.onSurfaceVariant);
  });

  testWidgets('both lines are centred on the bar', (tester) async {
    await _pump(tester, state: const LinkConnected(_pc12));
    expect(tester.getCenter(find.text('Before takeoff')).dx, closeTo(400, 1));
    expect(tester.getCenter(find.byKey(aircraftLineKey)).dx, closeTo(400, 1));
  });

  testWidgets('an empty ICAO leaves the description alone', (tester) async {
    await _pump(tester, state: const LinkConnected(_noIcao));
    expect(find.text('Homebuilt'), findsOneWidget);
  });

  testWidgets('the checklist on screen keeps its aircraft after a change', (
    tester,
  ) async {
    await _pump(
      tester,
      state: const LinkAircraftChanged(loaded: _pc12, live: _noIcao),
    );
    expect(find.text('Pilatus PC-12/47 (PC12)'), findsOneWidget);
  });

  testWidgets('without a connection or an aircraft only the name shows', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Before takeoff'), findsOneWidget);
    expect(find.byKey(aircraftLineKey), findsNothing);
    await _pump(tester, state: const LinkSearching());
    expect(find.byKey(aircraftLineKey), findsNothing);
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'long text stays on one line, no overflow, ${theme.brightness.name}',
      (tester) async {
        await _pump(
          tester,
          state: const LinkConnected(_pc12),
          title: 'A very long checklist name that cannot possibly fit the bar',
          size: const Size(300, 600),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(aircraftLineKey)).height,
          lessThan(20),
          reason: 'one line',
        );
      },
    );
  }
}
