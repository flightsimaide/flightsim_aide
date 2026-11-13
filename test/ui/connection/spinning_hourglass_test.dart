import 'package:flightsim_aide/ui/connection/widgets/spinning_hourglass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HourglassPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(SpinningHourglass),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as HourglassPainter;

double _progress(WidgetTester tester) => _painter(tester).progress;

Widget _app({bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: const Center(
      child: SpinningHourglass(size: 64, period: Duration(seconds: 4)),
    ),
  ),
);

void main() {
  testWidgets('has the given size', (tester) async {
    await tester.pumpWidget(_app());
    expect(tester.getSize(find.byType(SpinningHourglass)), const Size(64, 64));
  });

  testWidgets('the sand runs, then the glass turns, and it loops', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    expect(_progress(tester), 0);
    expect(_painter(tester).sandRun, 0);
    expect(_painter(tester).angle, 0);

    await tester.pump(const Duration(seconds: 2)); // half a cycle
    expect(_progress(tester), closeTo(0.5, 0.01));
    expect(_painter(tester).sandRun, closeTo(0.625, 0.02));
    expect(_painter(tester).angle, 0);

    await tester.pump(const Duration(milliseconds: 1200)); // 3.2 s: all run
    expect(_painter(tester).sandRun, 1);
    expect(_painter(tester).angle, 0);

    await tester.pump(const Duration(milliseconds: 400)); // 3.6 s: mid flip
    expect(_painter(tester).angle, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 600)); // 4.2 s: wrapped
    expect(_progress(tester), closeTo(0.05, 0.01));
    expect(_painter(tester).sandRun, closeTo(0.06, 0.02));
  });

  testWidgets('is the same picture at the end of the flip and at the start', (
    tester,
  ) async {
    const end = HourglassPainter(progress: 1, color: Colors.black);
    const start = HourglassPainter(progress: 0, color: Colors.black);
    expect(end.angle, closeTo(3.14159, 0.001)); // half a turn, symmetric glass
    expect(end.sandRun, 1);
    expect(start.sandRun, 0);
  });

  testWidgets('stands still when animations are disabled', (tester) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    await tester.pump(const Duration(seconds: 3));
    expect(_progress(tester), HourglassPainter.stillProgress);
  });

  testWidgets('draws without error at several points of the cycle', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('stops when removed', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
