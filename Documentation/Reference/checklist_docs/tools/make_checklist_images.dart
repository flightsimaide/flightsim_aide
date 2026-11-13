// Renders the app's real checklist screens to PNG files for the docs.
//
// Run from the repository root:
//
//   flutter test Documentation/Reference/checklist_docs/tools/make_checklist_images.dart
//
// It loads the sample checklist below into the real list and detail screens
// (light and dark theme), then writes whole-screen pictures of both and cropped
// pictures of single rows (dark theme) to `Documentation/Reference/checklist_docs/images/`.
//
// Notes:
// - The Material fonts come from the Flutter SDK (`FLUTTER_ROOT`), because a
//   widget test draws blocks otherwise.
// - The app only draws a file's colour when it contrasts enough with the
//   background, so the sample defines colours per theme (see [_themes]).
// - To change a picture, edit the sample or the crop rows in [main] and run
//   it again. It is not part of `flutter test` or `tools/verify.sh`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/repositories/fake_checklist_repository.dart';

const _outDir = 'Documentation/Reference/checklist_docs/images';

/// The sample checklist. `BLUEV` and `REDV` are filled in per theme.
const _sample = r'''
sw_define_colour:blue:BLUEV
sw_define_colour:red:REDV
sw_define_colour:white:0.9,0.9,0.9
sw_checklist:Before Start:Before Start
sw_remark:Complete each checklist from top to bottom.
sw_itemvoid:---------- OVERHEAD PANEL ----------
sw_itemvoid_c:\blue\EXAMPLE TWIN TURBOPROP
sw_item:Parking Brake|SET:sim/flightmodel/controls/parkbrake:1
sw_item:Flight Control Lock|REMOVED
sw_item_c:\blue\Beacon\red\ light|ON:sim/cockpit2/switches/beacon_on:1
sw_item_c:\blue\Gear \red\DOWN\\ check|3 GREEN
sw_iteminfo:Fuel quantity limit|3200 LBS
sw_item:Landing Gear Handle|DOWN:sim/cockpit2/controls/gear_handle_down:1
''';

/// One theme to render: its name, theme data and the two sample colours.
typedef _Theme = ({String name, ThemeData data, String blue, String red});

final List<_Theme> _themes = [
  (
    name: 'light',
    data: AppTheme.light,
    blue: '0.1,0.3,0.8',
    red: '0.75,0.0,0.0',
  ),
  (name: 'dark', data: AppTheme.dark, blue: '0.5,0.7,1.0', red: '1.0,0.5,0.5'),
];

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'E:/FlutterSDK/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String file) async =>
      ByteData.sublistView(await File('$dir/$file').readAsBytes());
  await (FontLoader('Roboto')
        ..addFont(bytes('Roboto-Regular.ttf'))
        ..addFont(bytes('Roboto-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(bytes('MaterialIcons-Regular.otf'))).load();
}

void main() {
  testWidgets('make checklist images', (tester) async {
    await tester.runAsync(_loadFonts);
    Directory(_outDir).createSync(recursive: true);
    // 420 x 750 logical pixels, written at 2x. Row crops use the dark theme.
    tester.view.physicalSize = const Size(840, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();

    Future<void> writePng(ui.Image image, String name) async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    }

    Future<ui.Image> capture(double pixelRatio) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return boundary.toImage(pixelRatio: pixelRatio);
    }

    // Whole screen, written at 1x (420 wide).
    Future<void> shot(String name) => tester.runAsync(() async {
      await writePng(await capture(1), name);
    });

    // A horizontal strip between [top] and [bottom] logical pixels.
    Future<void> crop(String name, double top, double bottom) =>
        tester.runAsync(() async {
          final image = await capture(2);
          final height = (bottom - top) * 2;
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawImageRect(
            image,
            Rect.fromLTWH(0, top * 2, 840, height),
            Rect.fromLTWH(0, 0, 840, height),
            Paint(),
          );
          await writePng(
            await recorder.endRecording().toImage(840, height.round()),
            name,
          );
        });

    for (final theme in _themes) {
      final text = _sample
          .replaceAll('BLUEV', theme.blue)
          .replaceAll('REDV', theme.red);
      final repository = FakeChecklistRepository(
        current: const AircraftWorkflowParser().parse(text),
      );
      final progress = ChecklistProgressRepositoryImpl();
      final router = createRouter(initialLocation: Routes.list);
      addTearDown(router.dispose);
      addTearDown(repository.dispose);
      addTearDown(progress.dispose);
      final dark = theme.name == 'dark';

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<ChecklistRepository>.value(value: repository),
              RepositoryProvider<ChecklistProgressRepository>.value(
                value: progress,
              ),
            ],
            child: MaterialApp.router(
              theme: theme.data,
              debugShowCheckedModeBanner: false,
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot('list_${theme.name}');
      if (dark) await crop('c_checklist', 55, 140);

      unawaited(router.push(Routes.detailPath('Before Start')));
      await tester.pumpAndSettle();
      await shot('detail_${theme.name}');
      if (dark) {
        // Row positions (logical pixels) in the 420 x 750 detail screen.
        await crop('c_remark', 120, 160);
        await crop('c_itemvoid', 170, 210);
        await crop('c_itemvoid_c', 225, 260);
        await crop('c_item', 262, 384);
        await crop('c_item_c', 384, 502);
        await crop('c_iteminfo', 503, 552);
      }

      // Tick the first check item.
      await tester.tap(find.byType(ChecklistMarker).at(0));
      await tester.pumpAndSettle();
      await shot('detail_ticked_${theme.name}');
      if (dark) await crop('c_item_ticked', 262, 384);
    }
  });
}
