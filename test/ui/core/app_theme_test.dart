import 'dart:math';

import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/themes/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  test('dark theme has Brightness.dark', () {
    expect(AppTheme.dark.brightness, Brightness.dark);
  });

  test('light theme has Brightness.light', () {
    expect(AppTheme.light.brightness, Brightness.light);
  });

  test('both themes are Material 3 with padded tap targets', () {
    for (final t in [AppTheme.light, AppTheme.dark]) {
      expect(t.useMaterial3, isTrue);
      expect(t.materialTapTargetSize, MaterialTapTargetSize.padded);
    }
  });

  test('row text is at least 18 in both themes', () {
    for (final t in [AppTheme.light, AppTheme.dark]) {
      expect(t.textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(18));
      expect(t.textTheme.titleMedium!.fontSize, greaterThanOrEqualTo(18));
    }
  });

  test(
    'onSurface vs surface contrast ratio is at least 4.5 in both themes',
    () {
      for (final t in [AppTheme.light, AppTheme.dark]) {
        final ratio = contrast(t.colorScheme.onSurface, t.colorScheme.surface);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    },
  );

  test('text (4.5:1) and status icons (3:1) are readable on both grounds', () {
    for (final t in [AppTheme.light, AppTheme.dark]) {
      final scheme = t.colorScheme;
      final status = t.extension<StatusColors>()!;
      for (final ground in [scheme.surface, scheme.surfaceContainerHigh]) {
        for (final c in [scheme.onSurface, scheme.onSurfaceVariant]) {
          expect(
            contrast(c, ground),
            greaterThanOrEqualTo(4.5),
            reason: '${t.brightness} text $c on $ground',
          );
        }
        for (final c in [
          status.success,
          status.caution,
          status.error,
          status.info,
        ]) {
          expect(
            contrast(c, ground),
            greaterThanOrEqualTo(3),
            reason: '${t.brightness} status $c on $ground',
          );
        }
      }
    }
  });

  test(
    'checked-row tint is distinct from the surface and keeps text readable',
    () {
      for (final t in [AppTheme.light, AppTheme.dark]) {
        final scheme = t.colorScheme;
        expect(scheme.primaryContainer, isNot(scheme.surface));
        expect(
          contrast(scheme.onSurface, scheme.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.onSurfaceVariant, scheme.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );
}
