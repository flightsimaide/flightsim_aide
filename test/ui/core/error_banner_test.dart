import 'package:flightsim_aide/ui/core/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ErrorBanner', () {
    testWidgets('shows the message', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorBanner(message: 'Boom')));
      expect(find.text('Boom'), findsOneWidget);
    });

    testWidgets('shows an error icon (not color alone)', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorBanner(message: 'Boom')));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('dismiss button calls the callback', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _wrap(ErrorBanner(message: 'Boom', onDismiss: () => calls++)),
      );
      await tester.tap(find.byType(IconButton));
      expect(calls, 1);
    });

    testWidgets('no dismiss button when callback is null', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorBanner(message: 'Boom')));
      expect(find.byType(IconButton), findsNothing);
    });
  });
}
