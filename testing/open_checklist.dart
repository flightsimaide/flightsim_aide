import 'dart:async';

import 'package:flightsim_aide/ui/home/cubit/home_cubit.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Starts a checklist load the way the network flow does: through the
/// [HomeCubit] below the home screen.
Future<void> openChecklist(WidgetTester tester) async {
  final context = tester.element(find.byType(HomeScreen));
  unawaited(context.read<HomeCubit>().load());
  await tester.pump();
}

/// Taps the Checklists card on the home screen (the list no longer opens by
/// itself after a load) and waits for the list to show.
Future<void> tapChecklistsCard(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-card-checklists')));
  await tester.pumpAndSettle();
}
