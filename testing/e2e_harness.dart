import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flightsim_aide/app.dart';
import 'package:flightsim_aide/config/dependencies.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/services/checklist/model/raw_checklist_document.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flightsim_aide/utils/text_decoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/services/fake_checklist_source_service.dart';

/// Fixture text, decoded the way the real file source decodes it.
String fixtureText(String fixture) => decodeChecklistText(
  File('testing/fixtures/$fixture.txt').readAsBytesSync(),
);

/// A source that returns the named fixture.
FakeChecklistSourceService fixtureSource(String fixture) =>
    FakeChecklistSourceService(
      Ok(
        RawChecklistDocument(name: '$fixture.txt', text: fixtureText(fixture)),
      ),
    );

/// A source that returns [text] as a file called [name].
FakeChecklistSourceService textSource(String name, String text) =>
    FakeChecklistSourceService(
      Ok(RawChecklistDocument(name: name, text: text)),
    );

/// Deterministic random bytes, decoded as the real file source would.
String randomBytesText({int length = 2048, int seed = 7}) {
  final random = Random(seed);
  final bytes = [for (var i = 0; i < length; i++) random.nextInt(256)];
  return decodeChecklistText(Uint8List.fromList(bytes));
}

/// Pumps the real [App] (real repositories) reading from [source], on a view
/// tall enough that every list row is built.
Future<void> pumpApp(WidgetTester tester, FakeChecklistSourceService source) {
  tester.view.physicalSize = const Size(800, 20000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(App(providers: sharedProviders(source)));
}

/// The app's [ChecklistRepository], read from the widget tree.
ChecklistRepository repositoryOf(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first).read<ChecklistRepository>();
