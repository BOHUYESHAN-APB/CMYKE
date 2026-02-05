import 'package:flutter/material.dart';

@immutable
class CmykeChrome extends ThemeExtension<CmykeChrome> {
  const CmykeChrome({
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.separator,
    required this.separatorStrong,
    required this.background0,
    required this.background1,
    required this.surface,
    required this.surfaceElevated,
    required this.frostedTint,
    required this.frostedBorder,
    required this.frostedHighlight,
    required this.radiusM,
    required this.radiusL,
    required this.radiusXL,
    required this.blurSigma,
    required this.elevationShadow,
  });

  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color separator;
  final Color separatorStrong;

  final Color background0;
  final Color background1;

  final Color surface;
  final Color surfaceElevated;

  /// The color used for glass/blur overlays (should be translucent).
  final Color frostedTint;
  final Color frostedBorder;
  final Color frostedHighlight;

  final double radiusM;
  final double radiusL;
  final double radiusXL;

  final double blurSigma;

  final List<BoxShadow> elevationShadow;

  static CmykeChrome light() => const CmykeChrome(
    accent: Color(0xFF20B58F),
    textPrimary: Color(0xFF14171D),
    textSecondary: Color(0xFF5C6372),
    separator: Color(0x1A1B2A3A),
    separatorStrong: Color(0x331B2A3A),
    background0: Color(0xFFF7F6F3),
    background1: Color(0xFFF1F4F7),
    surface: Color(0xFFFDFCF9),
    surfaceElevated: Color(0xFFFFFFFF),
    frostedTint: Color(0xC8FFFFFF),
    frostedBorder: Color(0x33FFFFFF),
    frostedHighlight: Color(0x40FFFFFF),
    radiusM: 14,
    radiusL: 18,
    radiusXL: 26,
    blurSigma: 18,
    elevationShadow: [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
      BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
    ],
  );

  static CmykeChrome dark() => const CmykeChrome(
    accent: Color(0xFF32D2A5),
    textPrimary: Color(0xFFEAF0F7),
    textSecondary: Color(0xFFB2BDCC),
    separator: Color(0x1AFFFFFF),
    separatorStrong: Color(0x33FFFFFF),
    background0: Color(0xFF0B0D10),
    background1: Color(0xFF121722),
    surface: Color(0xFF12161C),
    surfaceElevated: Color(0xFF171D26),
    frostedTint: Color(0x66161C26),
    frostedBorder: Color(0x33FFFFFF),
    frostedHighlight: Color(0x14FFFFFF),
    radiusM: 14,
    radiusL: 18,
    radiusXL: 26,
    blurSigma: 22,
    elevationShadow: [
      BoxShadow(
        color: Color(0x80000000),
        blurRadius: 28,
        offset: Offset(0, 14),
      ),
      BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
    ],
  );

  @override
  CmykeChrome copyWith({
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? separator,
    Color? separatorStrong,
    Color? background0,
    Color? background1,
    Color? surface,
    Color? surfaceElevated,
    Color? frostedTint,
    Color? frostedBorder,
    Color? frostedHighlight,
    double? radiusM,
    double? radiusL,
    double? radiusXL,
    double? blurSigma,
    List<BoxShadow>? elevationShadow,
  }) {
    return CmykeChrome(
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      separator: separator ?? this.separator,
      separatorStrong: separatorStrong ?? this.separatorStrong,
      background0: background0 ?? this.background0,
      background1: background1 ?? this.background1,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      frostedTint: frostedTint ?? this.frostedTint,
      frostedBorder: frostedBorder ?? this.frostedBorder,
      frostedHighlight: frostedHighlight ?? this.frostedHighlight,
      radiusM: radiusM ?? this.radiusM,
      radiusL: radiusL ?? this.radiusL,
      radiusXL: radiusXL ?? this.radiusXL,
      blurSigma: blurSigma ?? this.blurSigma,
      elevationShadow: elevationShadow ?? this.elevationShadow,
    );
  }

  @override
  CmykeChrome lerp(ThemeExtension<CmykeChrome>? other, double t) {
    if (other is! CmykeChrome) {
      return this;
    }
    return CmykeChrome(
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      separatorStrong: Color.lerp(separatorStrong, other.separatorStrong, t)!,
      background0: Color.lerp(background0, other.background0, t)!,
      background1: Color.lerp(background1, other.background1, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      frostedTint: Color.lerp(frostedTint, other.frostedTint, t)!,
      frostedBorder: Color.lerp(frostedBorder, other.frostedBorder, t)!,
      frostedHighlight: Color.lerp(
        frostedHighlight,
        other.frostedHighlight,
        t,
      )!,
      radiusM: lerpDouble(radiusM, other.radiusM, t),
      radiusL: lerpDouble(radiusL, other.radiusL, t),
      radiusXL: lerpDouble(radiusXL, other.radiusXL, t),
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t),
      elevationShadow: t < 0.5 ? elevationShadow : other.elevationShadow,
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

extension CmykeChromeContext on BuildContext {
  CmykeChrome get chrome {
    final ext = Theme.of(this).extension<CmykeChrome>();
    assert(ext != null, 'CmykeChrome ThemeExtension is missing.');
    return ext!;
  }
}
