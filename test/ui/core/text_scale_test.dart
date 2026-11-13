import 'package:flightsim_aide/ui/core/widgets/error_banner.dart';
import 'package:flightsim_aide/ui/core/widgets/loading_indicator.dart';
import 'package:flightsim_aide/ui/core/widgets/warnings_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpScaled(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: c!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('text scale 2.0 at 320 px wide', () {
    testWidgets('ErrorBanner: no overflow exception', (tester) async {
      await _pumpScaled(
        tester,
        ErrorBanner(
          message: 'Could not load the checklist file. Please try again.',
          onDismiss: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingIndicator: no overflow exception', (tester) async {
      await _pumpScaled(tester, const LoadingIndicator());
      expect(tester.takeException(), isNull);
    });

    testWidgets('WarningsBanner: no overflow exception', (tester) async {
      await _pumpScaled(
        tester,
        WarningsBanner(
          warnings: List<String>.generate(
            12,
            (i) => 'Line ${i + 1}: unrecognised directive',
          ),
          onDismiss: () {},
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
