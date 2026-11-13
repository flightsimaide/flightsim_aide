import 'package:flutter/material.dart';

/// Black or white, whichever has the higher contrast against [fill]: the colour
/// for text and icons on a status colour.
Color readableOn(Color fill) {
  final l = fill.computeLuminance();
  return (l + 0.05) / 0.05 >= 1.05 / (l + 0.05) ? Colors.black : Colors.white;
}

/// The four status colours, each with its icon (never colour alone).
///
/// Red means warning or critical, amber a caution, green good, cyan
/// information. `error` is also
/// the `ColorScheme.error` colour.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  /// Creates the status colours.
  const StatusColors({
    required this.success,
    required this.caution,
    required this.error,
    required this.info,
    this.cautionFill,
  });

  /// Defaults that read well on a dark surface.
  static const StatusColors dark = StatusColors(
    success: Color(0xFF4CAF50),
    caution: Color(0xFFFFC107),
    error: Color(0xFFFF5252),
    info: Color(0xFF00BCD4),
  );

  /// Defaults that read well on a light surface.
  static const StatusColors light = StatusColors(
    success: Color(0xFF2E7D32),
    caution: Color(0xFF9E5A00),
    error: Color(0xFFC62828),
    info: Color(0xFF00838F),
    cautionFill: Color(0xFFFFC107),
  );

  /// Good: a tick where the aircraft data agrees.
  final Color success;

  /// Caution: can continue, degraded (a skipped item).
  final Color caution;

  /// Warning: critical, cannot continue (an error, or a tick the data
  /// disagrees with).
  final Color error;

  /// Information: a message or state that does not affect the operation of the
  /// aircraft (the Auto/Manual button).
  final Color info;

  /// Caution as a background (a skipped row): a true yellow. The light
  /// [caution] is a dark amber, which reads brown or red as a large fill. Null
  /// means [caution] is used.
  final Color? cautionFill;

  /// The colour for a caution background.
  Color get cautionBackground => cautionFill ?? caution;

  /// Filled check mark in [success].
  Icon get successIcon => Icon(Icons.check_circle, color: success);

  /// Filled warning triangle in [caution].
  Icon get cautionIcon => Icon(Icons.warning, color: caution);

  /// Filled error icon in [error].
  Icon get errorIcon => Icon(Icons.error, color: error);

  /// Filled info icon in [info].
  Icon get infoIcon => Icon(Icons.info, color: info);

  @override
  StatusColors copyWith({
    Color? success,
    Color? caution,
    Color? error,
    Color? info,
    Color? cautionFill,
  }) => StatusColors(
    success: success ?? this.success,
    caution: caution ?? this.caution,
    error: error ?? this.error,
    info: info ?? this.info,
    cautionFill: cautionFill ?? this.cautionFill,
  );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      cautionFill: Color.lerp(cautionFill, other.cautionFill, t),
    );
  }
}
