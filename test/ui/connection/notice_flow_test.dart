import 'dart:async';

import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/domain/models/flight_sim/switch_offer.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_dialog_host.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_messages.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_panel.dart';
import 'package:flightsim_aide/ui/home/cubit/home_cubit.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';

// AC-11: aircraft change notice names the new aircraft
// AC-27: network lost and sim silent (now a dialog, task 0.14)

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
  generation: 1,
);
const _boeing = AircraftIdentity(
  icao: 'B738',
  description: 'Boeing 737',
  aircraftPath: 'b.acf',
  checklistPath: 'clist.txt',
  generation: 2,
);
const _bare = AircraftIdentity(
  icao: 'PA28',
  description: 'Piper Archer',
  aircraftPath: 'c.acf',
  generation: 3,
);

ChecklistDocument _doc(String name) => ChecklistDocument(
  checklists: const [],
  warnings: const [],
  sourceName: name,
);

final _banner = find.text('Aircraft changed');

void main() {
  late FlightSimRepositoryLocal sim;
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late GoRouter router;

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Result<ChecklistDocument>>? results,
  }) async {
    sim = FlightSimRepositoryLocal();
    checklists = FakeChecklistRepository(
      loadResults: results ?? [Ok(_doc('a.txt'))],
    );
    progress = FakeChecklistProgressRepository();
    router = createRouter();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ChecklistRepository>.value(value: checklists),
          RepositoryProvider<ChecklistProgressRepository>.value(
            value: progress,
          ),
          RepositoryProvider<FlightSimRepository>.value(value: sim),
          RepositoryProvider<SettingsRepository>.value(
            value: FakeSettingsRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // The dialog opens in the frame after the first one.
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await checklists.dispose();
    await sim.dispose();
  }

  /// Connects and loads; the app stays on Home (it never opens the list by
  /// itself).
  Future<void> connectAndStay(WidgetTester tester) async {
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await tester.pumpAndSettle();
  }

  /// Connects, loads, and opens the list with the Checklists card.
  Future<void> connectAndLoad(WidgetTester tester) async {
    await connectAndStay(tester);
    await tester.tap(find.byKey(const Key('home-card-checklists')));
    await tester.pumpAndSettle();
  }

  group('shell', () {
    testWidgets(
      'after Continue on an aircraft without checklist, home still offers the old ones',
      (tester) async {
        await pumpApp(tester, results: [Ok(_doc('a.txt'))]);
        await connectAndLoad(tester);
        router.pop();
        await tester.pumpAndSettle();
        sim.setAircraft(_bare);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue with current checklist'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Checklists'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ChecklistListScreen), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets('after a load, the Checklists bar item reopens the list', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Open checklists'), findsNothing);
      await connectAndLoad(tester);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsNothing);
      expect(find.text('Open checklists'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Checklists'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a new connection does not open the list by itself', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndStay(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      // The hourglass of the search never settles, so pump by hand.
      sim.setStatus(const ConnectionSearching());
      await tester.pump(const Duration(milliseconds: 100));
      sim.setStatus(const ConnectionConnected());
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      await finish(tester);
    });

    testWidgets('a new connection does not stack a second list', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      sim.setStatus(const ConnectionSearching());
      await tester.pump(const Duration(milliseconds: 100));
      sim.setStatus(const ConnectionConnected());
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsNothing);
      await finish(tester);
    });

    testWidgets('home shows the connection panel in a dialog and no banner', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(
        find.descendant(
          of: find.byType(ConnectionPanel),
          matching: find.byType(Dialog),
        ),
        findsOneWidget,
      );
      expect(_banner, findsNothing);
      await finish(tester);
    });

    testWidgets('home list and detail share one HomeCubit instance', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      final fromList = tester
          .element(find.byType(ChecklistListScreen))
          .read<HomeCubit>();
      final fromHome = tester
          .element(find.byType(HomeScreen, skipOffstage: false))
          .read<HomeCubit>();
      expect(identical(fromList, fromHome), isTrue);
      unawaited(router.push(Routes.detailPath('x')));
      await tester.pumpAndSettle();
      final fromDetail = tester
          .element(find.byType(ChecklistDetailScreen))
          .read<HomeCubit>();
      expect(identical(fromDetail, fromHome), isTrue);
      await finish(tester);
    });

    testWidgets('cubits survive navigation between screens', (tester) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      final before = tester
          .element(find.byType(ChecklistListScreen))
          .read<ConnectionCubit>();
      unawaited(router.push(Routes.detailPath('x')));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      final after = tester
          .element(find.byType(HomeScreen))
          .read<ConnectionCubit>();
      expect(identical(before, after), isTrue);
      expect(checklists.loadCount, 1);
      await finish(tester);
    });

    testWidgets('back navigation from detail lands on the list, then home', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      unawaited(router.push(Routes.detailPath('x')));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });
  });

  group('home flow', () {
    testWidgets('search, connect, load, then the card opens the list', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Waiting for connection'), findsOneWidget);
      sim.setStatus(const ConnectionConnecting());
      await tester.pump();
      await tester.pump();
      expect(find.text('Waiting for aircraft to load'), findsOneWidget);
      await connectAndStay(tester);
      expect(find.byType(ChecklistListScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(checklists.loadCount, 1);
      await tester.tap(find.byKey(const Key('home-card-checklists')));
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('waiting for the aircraft, then it appears, then load', (
      tester,
    ) async {
      await pumpApp(tester);
      sim.setStatus(const ConnectionConnecting());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Waiting for aircraft to load'), findsOneWidget);
      expect(_banner, findsNothing);
      expect(checklists.loadCount, 0);
      await connectAndLoad(tester);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('manual IP entry from the panel', (tester) async {
      await pumpApp(tester);
      sim.setStatus(const ConnectionSimUnreachable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter IP address'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10.0.0.5');
      await tester.pump();
      await tester.tap(find.text('Try'));
      await tester.pumpAndSettle();
      expect(sim.manualIp, '10.0.0.5');
      await finish(tester);
    });
  });

  group('connection dialog', () {
    final dialog = find.byType(Dialog);

    testWidgets('network lost covers the list with a dialog, no banner', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: dialog, matching: find.text('Network is off')),
        findsOneWidget,
      );
      expect(_banner, findsNothing);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('the dialog opens over the detail page too', (tester) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      unawaited(router.push(Routes.detailPath('x')));
      await tester.pumpAndSettle();
      sim.setStatus(const ConnectionSimUnreachable());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Waiting for connection'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('not responding'),
        ),
        findsOneWidget,
      );
      expect(_banner, findsNothing);
      await finish(tester);
    });

    testWidgets('with no checklist the dialog has no way out', (tester) async {
      await pumpApp(tester);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Waiting for connection'),
        ),
        findsOneWidget,
      );
      expect(find.text('Continue in manual mode'), findsNothing);
      await tester.tapAt(const Offset(2, 2));
      await tester.pump();
      expect(dialog, findsOneWidget);
      await finish(tester);
    });

    testWidgets('the dialog closes by itself when connected', (tester) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      expect(dialog, findsNothing);
      await finish(tester);
    });

    testWidgets('with a checklist, Continue in manual mode asks Yes or No', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue in manual mode'));
      await tester.pumpAndSettle();
      expect(find.text('Network is off'), findsNothing);
      expect(find.text(notifyQuestion), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // Still down: the dialog stays away. It comes back after a recovery.
      sim.setStatus(const ConnectionSimUnreachable());
      await tester.pumpAndSettle();
      expect(find.text('Continue in manual mode'), findsNothing);
      sim.setStatus(const ConnectionConnected());
      await tester.pumpAndSettle();
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpAndSettle();
      expect(find.text('Continue in manual mode'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('answering No stops the dialog from opening again', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue in manual mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      sim.setStatus(const ConnectionConnected());
      await tester.pumpAndSettle();
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpAndSettle();
      expect(find.text('Network is off'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      await finish(tester);
    });

    testWidgets('disarmed, home shows the panel with the notification switch', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue in manual mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Network is off'), findsOneWidget);
      expect(find.text('Continue in manual mode'), findsNothing);
      final switchFinder = find.byKey(const Key('notify-switch'));
      expect(find.text(notifyOutageLabel), findsOneWidget);
      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
      // Turning it on arms the dialog again, at once.
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(find.text('Continue in manual mode'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('recovery does not reload the checklist', (tester) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpAndSettle();
      sim.setStatus(const ConnectionConnected());
      await tester.pumpAndSettle();
      expect(checklists.loadCount, 1);
      expect(dialog, findsNothing);
      await finish(tester);
    });
  });

  group('aircraft change dialog', () {
    Future<void> changeTo(WidgetTester tester, AircraftIdentity a) async {
      sim.setAircraft(a);
      await tester.pumpAndSettle();
    }

    testWidgets('names the new aircraft and no swap happens', (tester) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      await changeTo(tester, _boeing);
      expect(_banner, findsOneWidget);
      expect(find.text('X-Plane Boeing 737'), findsOneWidget);
      expect(
        find.text('Open checklist for "X-Plane Boeing 737"'),
        findsOneWidget,
      );
      expect(find.text('Continue with current checklist'), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      expect(checklists.loadCount, 1);
      await finish(tester);
    });

    testWidgets(
      'after the user chose the computer, its checklist is opened without a '
      'question',
      (tester) async {
        await pumpApp(tester, results: [Ok(_doc('a.txt')), Ok(_doc('b.txt'))]);
        await connectAndLoad(tester);
        final cubit = tester
            .element(find.byType(ChecklistListScreen))
            .read<ConnectionCubit>();
        await cubit.answerSwitch(accept: true);
        await changeTo(tester, _boeing);
        expect(_banner, findsNothing);
        expect(checklists.loadCount, 2);
        // The new checklist waits on Home; the Checklists card opens it.
        expect(find.byType(HomeScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('home-card-checklists')));
        await tester.pumpAndSettle();
        expect(find.byType(ChecklistListScreen), findsOneWidget);
        expect(router.canPop(), isTrue);
        await finish(tester);
      },
    );

    testWidgets(
      'after the user chose the computer, an aircraft without checklist '
      'is not an Aircraft changed',
      (tester) async {
        await pumpApp(tester);
        await connectAndLoad(tester);
        final cubit = tester
            .element(find.byType(ChecklistListScreen))
            .read<ConnectionCubit>();
        await cubit.answerSwitch(accept: true);
        await changeTo(tester, _bare);
        expect(_banner, findsNothing);
        router.go('/');
        await tester.pumpAndSettle();
        expect(_banner, findsNothing);
        expect(find.text(noChecklistHeadline), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets(
      'after the checklist was carried over to an aircraft without one, the '
      'next aircraft with a checklist replaces it without a question',
      (tester) async {
        await pumpApp(tester, results: [Ok(_doc('a.txt')), Ok(_doc('b.txt'))]);
        await connectAndLoad(tester);
        await changeTo(tester, _bare);
        await tester.tap(find.text('Continue with current checklist'));
        await tester.pumpAndSettle();
        expect(checklists.loadCount, 1);
        await changeTo(tester, _boeing);
        expect(_banner, findsNothing);
        expect(checklists.loadCount, 2);
        await finish(tester);
      },
    );

    testWidgets('a restart on an aircraft without checklist has no checklist '
        'to load', (tester) async {
      await pumpApp(tester);
      sim.setAircraft(_bare);
      sim.setStatus(const ConnectionConnected());
      await tester.pumpAndSettle();
      expect(checklists.loadCount, 0);
      expect(checklists.current, isNull);
      expect(find.byType(ChecklistListScreen), findsNothing);
      expect(_banner, findsNothing);
      await finish(tester);
    });

    testWidgets('an aircraft without checklist cannot be opened', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      await changeTo(tester, _bare);
      // A box like the choices, without the circle, that does nothing.
      expect(
        find.text('X-Plane Piper Archer has no checklist'),
        findsOneWidget,
      );
      final box = find.byKey(const Key('aircraft-no-checklist'));
      expect(
        find.descendant(
          of: box,
          matching: find.byIcon(Icons.radio_button_unchecked),
        ),
        findsNothing,
      );
      expect(find.text('Search for checklist'), findsNothing);
      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget, reason: 'tapping it does nothing');
      expect(find.textContaining('Open checklist for'), findsNothing);
      expect(find.text('Continue with current checklist'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('it opens over the detail page, and cannot be dismissed', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      unawaited(router.push(Routes.detailPath('x')));
      await tester.pumpAndSettle();
      await changeTo(tester, _boeing);
      expect(_banner, findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget);
      await finish(tester);
    });

    testWidgets('the sim returning to the loaded aircraft closes it', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      await changeTo(tester, _boeing);
      await changeTo(tester, _cessna);
      expect(_banner, findsNothing);
      await finish(tester);
    });

    testWidgets('a second change replaces the dialog', (tester) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      await changeTo(tester, _boeing);
      await changeTo(tester, _bare);
      expect(find.textContaining('Boeing'), findsNothing);
      expect(find.text('X-Plane Piper Archer'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('Continue keeps the checklist and does not ask again', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      await changeTo(tester, _boeing);
      await tester.tap(find.text('Continue with current checklist'));
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(checklists.loadCount, 1);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      // A different aircraft asks again.
      await changeTo(tester, _bare);
      expect(_banner, findsOneWidget);
      await finish(tester);
    });

    testWidgets('Open returns to home, loads the new checklist and closes', (
      tester,
    ) async {
      await pumpApp(tester, results: [Ok(_doc('a.txt')), Ok(_doc('b.txt'))]);
      await connectAndLoad(tester);
      unawaited(router.push(Routes.detailPath('x')));
      await tester.pumpAndSettle();
      await changeTo(tester, _boeing);
      await tester.tap(find.byKey(const Key('aircraft-open')));
      await tester.pumpAndSettle();
      expect(checklists.loadCount, 2);
      expect(find.byType(ChecklistDetailScreen), findsNothing);
      // Home stays on screen; the Checklists card opens the new list.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      expect(_banner, findsNothing);
      await tester.tap(find.byKey(const Key('home-card-checklists')));
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      expect(find.text('b.txt'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });
  });

  group('reload', () {
    testWidgets('an edited checklist file is reloaded in place', (
      tester,
    ) async {
      await pumpApp(tester, results: [Ok(_doc('a.txt')), Ok(_doc('b.txt'))]);
      await connectAndLoad(tester);
      unawaited(router.push(Routes.detailPath('x')));
      await tester.pumpAndSettle();
      sim.setAircraft(
        const AircraftIdentity(
          icao: 'C172',
          description: 'Cessna 172',
          aircraftPath: 'a.acf',
          checklistPath: 'clist.txt',
          checklistModified: 99,
          checklistSize: 10,
          generation: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(checklists.loadCount, 2);
      expect(find.byType(ChecklistDetailScreen), findsOneWidget);
      expect(_banner, findsNothing);
      await finish(tester);
    });
  });

  group('switch computer dialog (task 0.16)', () {
    const offer = SwitchOffer(
      from: DiscoveredSim(host: '192.168.1.10', name: 'WIN'),
      to: DiscoveredSim(host: '192.168.1.117', name: 'MAC'),
    );

    testWidgets('names both computers and Yes and No answer it', (
      tester,
    ) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      sim.setStatus(const ConnectionSimUnreachable());
      await tester.pump();
      sim.setSwitchOffer(offer);
      await tester.pump();
      await tester.pump();
      expect(find.text('Switch computer?'), findsOneWidget);
      expect(
        find.text(
          'You were connected to X-Plane on WIN (192.168.1.10). '
          'Do you want to switch to X-Plane on MAC (192.168.1.117)?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('switch-no')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(sim.switchAnswers, [false]);
      expect(find.text('Switch computer?'), findsNothing);
      await finish(tester);
    });

    testWidgets('Yes is passed on', (tester) async {
      await pumpApp(tester);
      await connectAndLoad(tester);
      sim.setStatus(const ConnectionSimUnreachable());
      await tester.pump();
      sim.setSwitchOffer(offer);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('switch-yes')));
      await tester.pump();
      expect(sim.switchAnswers, [true]);
      await finish(tester);
    });
  });
}
