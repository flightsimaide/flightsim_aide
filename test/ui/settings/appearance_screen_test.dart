import 'package:flightsim_aide/app.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/settings/widgets/appearance_screen.dart';
import 'package:flightsim_aide/ui/settings/widgets/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';

void main() {
  late FakeSettingsRepository settings;

  setUp(() => settings = FakeSettingsRepository());

  Future<void> pumpApp(WidgetTester tester, {String at = Routes.home}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = createRouter(initialLocation: at);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      App(
        router: router,
        providers: [
          RepositoryProvider<ChecklistRepository>.value(
            value: FakeChecklistRepository(),
          ),
          RepositoryProvider<ChecklistProgressRepository>.value(
            value: FakeChecklistProgressRepository(),
          ),
          RepositoryProvider<SettingsRepository>.value(value: settings),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  Color primary(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(AppearanceScreen)))
          .colorScheme
          .primary;

  testWidgets('Settings in the bar opens Settings, then Appearance', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      tester
          .widgetList<NavigationBar>(find.byType(NavigationBar))
          .last
          .selectedIndex,
      3,
    );

    await tester.tap(find.byKey(const Key('settings-appearance')));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceScreen), findsOneWidget);
    expect(
      tester
          .widgetList<NavigationBar>(find.byType(NavigationBar))
          .last
          .selectedIndex,
      3,
    );

    // Settings in the bar goes back to the Settings list.
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(AppearanceScreen), findsNothing);
  });

  testWidgets('choosing Dark changes the app theme mode and is kept', (
    tester,
  ) async {
    await pumpApp(tester, at: Routes.appearance);
    expect(app(tester).themeMode, ThemeMode.system);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mode-buttons')),
        matching: find.text('Dark'),
      ),
    );
    await tester.pumpAndSettle();
    expect(app(tester).themeMode, ThemeMode.dark);

    // A new start reads it back.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, at: Routes.appearance);
    expect(app(tester).themeMode, ThemeMode.dark);
  });

  testWidgets('a typed colour changes ColorScheme.primary and is kept', (
    tester,
  ) async {
    await pumpApp(tester, at: Routes.appearance);
    // The accent field is the fifth hex field.
    await tester.enterText(find.byType(TextField).at(4), '00FF00');
    await tester.pumpAndSettle();
    expect(primary(tester), const Color(0xFF00FF00));

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, at: Routes.appearance);
    expect(primary(tester), const Color(0xFF00FF00));
  });

  testWidgets('the picker applies a colour; Cancel puts the old one back', (
    tester,
  ) async {
    await pumpApp(tester, at: Routes.appearance);
    final before = primary(tester);

    await tester.tap(find.byKey(const Key('swatch-accent')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), '00FF00');
    await tester.pumpAndSettle();
    expect(primary(tester), const Color(0xFF00FF00));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(primary(tester), before);
    expect((await settings.appearance()).valueOrNull!.colors, isEmpty);

    await tester.tap(find.byKey(const Key('swatch-accent')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), '00FF00');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(primary(tester), const Color(0xFF00FF00));
    expect((await settings.appearance()).valueOrNull!.colors.values, [
      0xFF00FF00,
    ]);
  });

  testWidgets('Restore defaults brings back the chosen colours', (
    tester,
  ) async {
    await pumpApp(tester, at: Routes.appearance);
    final before = primary(tester);
    await tester.enterText(find.byType(TextField).at(4), '00FF00');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-defaults')));
    await tester.pumpAndSettle();
    expect(primary(tester), before);
    expect(
      before,
      anyOf(AppTheme.darkPalette.accent, AppTheme.lightPalette.accent),
    );
    expect(app(tester).themeMode, ThemeMode.system);
    expect((await settings.appearance()).valueOrNull!.colors, isEmpty);
  });
}
