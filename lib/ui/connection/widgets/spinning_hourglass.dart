import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An hourglass for a wait: sand runs from the top bulb to the bottom one,
/// then the glass turns over and it starts again. Stands still, half run,
/// when the system asks for reduced motion.
class SpinningHourglass extends StatefulWidget {
  /// Creates the hourglass.
  const SpinningHourglass({
    required this.size,
    this.color,
    this.period = const Duration(seconds: 4),
    super.key,
  });

  /// Width and height of the icon.
  final double size;

  /// The glass and sand colour; the icon theme's when null.
  final Color? color;

  /// Time for one cycle: the sand running, then the flip.
  final Duration period;

  @override
  State<SpinningHourglass> createState() => _SpinningHourglassState();
}

class _SpinningHourglassState extends State<SpinningHourglass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: HourglassPainter(
            progress: still
                ? HourglassPainter.stillProgress
                : _controller.value,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Draws an hourglass at [progress] (0 to 1) of one cycle.
///
/// From 0 to [runShare] the sand runs; from there to 1 the glass turns over
/// by half a turn. At 1 the picture equals the one at 0, so the cycle loops
/// without a jump.
class HourglassPainter extends CustomPainter {
  /// Creates the painter.
  const HourglassPainter({required this.progress, required this.color});

  /// The share of the cycle in which the sand runs; the rest is the flip.
  static const double runShare = 0.8;

  /// The picture shown when motion is off: sand in both bulbs.
  static const double stillProgress = 0.4;

  /// Position in the cycle, 0 to 1.
  final double progress;

  /// Colour of the glass and the sand.
  final Color color;

  /// How much of the sand has run (0 to 1) at [progress].
  double get sandRun => (progress / runShare).clamp(0.0, 1.0);

  /// The turn of the glass in radians at [progress] (0 to pi).
  double get angle {
    if (progress <= runShare) return 0;
    final t = (progress - runShare) / (1 - runShare);
    return math.pi * Curves.easeInOut.transform(t.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = math.max(1.5, s * 0.07);
    final centre = Offset(size.width / 2, size.height / 2);
    final halfW = s * 0.27; // half the glass width
    final bulb = s * 0.37; // height of one bulb
    final top = centre.dy - bulb;
    final bottom = centre.dy + bulb;
    final neck = s * 0.035; // half the neck width

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(angle);
    canvas.translate(-centre.dx, -centre.dy);

    // Half width of a bulb at distance d from the middle: it opens quickly
    // above the neck and rounds off to upright sides at the cap.
    double half(double d) =>
        neck +
        (halfW - neck) * math.pow(math.sin(d / bulb * math.pi / 2), 0.55);

    // The band of a bulb between distances d0 and d1 from the middle, inset
    // by half a stroke; dir is -1 for the top bulb and 1 for the bottom one.
    Path band(double dir, double d0, double d1) {
      const n = 14;
      final inset = stroke / 2;
      final path = Path();
      for (var i = 0; i <= n; i++) {
        final d = d0 + (d1 - d0) * i / n;
        final x = centre.dx - math.max(0.0, half(d) - inset);
        final y = centre.dy + dir * d;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      for (var i = n; i >= 0; i--) {
        final d = d0 + (d1 - d0) * i / n;
        path.lineTo(
          centre.dx + math.max(0.0, half(d) - inset),
          centre.dy + dir * d,
        );
      }
      return path..close();
    }

    final sand = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final f = sandRun;

    // Sand left in the top bulb, from the neck up to its level.
    if (f < 1) {
      canvas.drawPath(band(-1, 0, bulb * (1 - f) * 0.85), sand);
    }

    // Sand in the bottom bulb, from the floor up to its level.
    final bottomD = bulb - bulb * f * 0.75;
    if (f > 0) {
      canvas.drawPath(band(1, bottomD, bulb - stroke / 2), sand);
    }

    // The falling stream, while sand is still running.
    if (f > 0 && f < 0.97) {
      canvas.drawLine(
        centre,
        Offset(centre.dx, centre.dy + bottomD),
        Paint()
          ..color = sand.color
          ..strokeWidth = math.max(1, s * 0.03)
          ..strokeCap = StrokeCap.round,
      );
    }

    // The glass: two curved bulbs meeting at the neck, with a cap at each end.
    final glass = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final outline = Path();
    for (final side in [-1.0, 1.0]) {
      const n = 24;
      for (var i = 0; i <= 2 * n; i++) {
        final y = top + (bottom - top) * i / (2 * n);
        final x = centre.dx + side * half((y - centre.dy).abs());
        i == 0 ? outline.moveTo(x, y) : outline.lineTo(x, y);
      }
    }
    outline
      ..moveTo(centre.dx - halfW, top)
      ..lineTo(centre.dx + halfW, top)
      ..moveTo(centre.dx - halfW, bottom)
      ..lineTo(centre.dx + halfW, bottom);
    canvas.drawPath(outline, glass);

    canvas.restore();
  }

  @override
  bool shouldRepaint(HourglassPainter old) =>
      old.progress != progress || old.color != color;
}
