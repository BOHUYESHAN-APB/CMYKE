import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';

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

  static CmykeChrome light({
    UiPalette palette = UiPalette.jade,
    UiGlass glass = UiGlass.standard,
  }) {
    final tokens = _paletteTokens[palette] ?? _paletteTokens[UiPalette.jade]!;
    final accent = tokens.accentLight;

    const baseBackground0 = Color(0xFFF7F6F3);
    const baseBackground1 = Color(0xFFF1F4F7);
    const baseSurface = Color(0xFFFDFCF9);
    const baseSurfaceElevated = Color(0xFFFFFFFF);

    final background0 = _tint(baseBackground0, tokens.tintLight, 0.18);
    final background1 = _tint(baseBackground1, tokens.tintLight, 0.34);
    final surface = _tint(baseSurface, tokens.tintLight, 0.12);
    final surfaceElevated = _tint(baseSurfaceElevated, tokens.tintLight, 0.08);

    final blurSigma = 18 * _glassBlur(glass);
    final frostedTint = _withOpacity(
      _tint(const Color(0xFFFFFFFF), tokens.tintLight, 0.18),
      _glassAlpha(glass, base: 0.78),
    );
    final frostedBorder = _withOpacity(
      _tint(const Color(0xFFFFFFFF), tokens.tintLight, 0.12),
      _glassBorderAlpha(glass, base: 0.2),
    );
    final frostedHighlight = _withOpacity(
      _tint(const Color(0xFFFFFFFF), tokens.tintLight, 0.22),
      _glassHighlightAlpha(glass, base: 0.25),
    );

    return CmykeChrome(
      accent: accent,
      textPrimary: const Color(0xFF14171D),
      textSecondary: const Color(0xFF5C6372),
      separator: const Color(0x1A1B2A3A),
      separatorStrong: const Color(0x331B2A3A),
      background0: background0,
      background1: background1,
      surface: surface,
      surfaceElevated: surfaceElevated,
      frostedTint: frostedTint,
      frostedBorder: frostedBorder,
      frostedHighlight: frostedHighlight,
      radiusM: 14,
      radiusL: 18,
      radiusXL: 26,
      blurSigma: blurSigma,
      elevationShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  static CmykeChrome dark({
    UiPalette palette = UiPalette.jade,
    UiGlass glass = UiGlass.standard,
  }) {
    final tokens = _paletteTokens[palette] ?? _paletteTokens[UiPalette.jade]!;
    final accent = tokens.accentDark;

    const baseBackground0 = Color(0xFF0B0D10);
    const baseBackground1 = Color(0xFF121722);
    const baseSurface = Color(0xFF12161C);
    const baseSurfaceElevated = Color(0xFF171D26);

    final background0 = _tint(baseBackground0, tokens.tintDark, 0.16);
    final background1 = _tint(baseBackground1, tokens.tintDark, 0.24);
    final surface = _tint(baseSurface, tokens.tintDark, 0.14);
    final surfaceElevated = _tint(baseSurfaceElevated, tokens.tintDark, 0.12);

    final blurSigma = 22 * _glassBlur(glass);
    final frostedTint = _withOpacity(
      _tint(const Color(0xFF161C26), tokens.tintDark, 0.28),
      _glassAlpha(glass, base: 0.4),
    );
    final frostedBorder = _withOpacity(
      _tint(const Color(0xFFFFFFFF), tokens.tintDark, 0.08),
      _glassBorderAlpha(glass, base: 0.2),
    );
    final frostedHighlight = _withOpacity(
      _tint(const Color(0xFFFFFFFF), tokens.tintDark, 0.1),
      _glassHighlightAlpha(glass, base: 0.08),
    );

    return CmykeChrome(
      accent: accent,
      textPrimary: const Color(0xFFEAF0F7),
      textSecondary: const Color(0xFFB2BDCC),
      separator: const Color(0x1AFFFFFF),
      separatorStrong: const Color(0x33FFFFFF),
      background0: background0,
      background1: background1,
      surface: surface,
      surfaceElevated: surfaceElevated,
      frostedTint: frostedTint,
      frostedBorder: frostedBorder,
      frostedHighlight: frostedHighlight,
      radiusM: 14,
      radiusL: 18,
      radiusXL: 26,
      blurSigma: blurSigma,
      elevationShadow: const [
        BoxShadow(
          color: Color(0x80000000),
          blurRadius: 28,
          offset: Offset(0, 14),
        ),
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    );
  }

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

class _PaletteTokens {
  const _PaletteTokens({
    required this.accentLight,
    required this.accentDark,
    required this.tintLight,
    required this.tintDark,
  });

  final Color accentLight;
  final Color accentDark;
  final Color tintLight;
  final Color tintDark;
}

const Map<UiPalette, _PaletteTokens> _paletteTokens = {
  UiPalette.jade: _PaletteTokens(
    accentLight: Color(0xFF20B58F),
    accentDark: Color(0xFF32D2A5),
    tintLight: Color(0xFFDAF4EC),
    tintDark: Color(0xFF0F2A25),
  ),
  UiPalette.ocean: _PaletteTokens(
    accentLight: Color(0xFF3AA0FF),
    accentDark: Color(0xFF5BB6FF),
    tintLight: Color(0xFFDCEBFF),
    tintDark: Color(0xFF132238),
  ),
  UiPalette.ember: _PaletteTokens(
    accentLight: Color(0xFFFF8A3D),
    accentDark: Color(0xFFFFA05C),
    tintLight: Color(0xFFFFE8D7),
    tintDark: Color(0xFF2B1A12),
  ),
  UiPalette.rose: _PaletteTokens(
    accentLight: Color(0xFFFF5C8A),
    accentDark: Color(0xFFFF78A5),
    tintLight: Color(0xFFFFDCE6),
    tintDark: Color(0xFF2E1621),
  ),
  UiPalette.slate: _PaletteTokens(
    accentLight: Color(0xFF5C748A),
    accentDark: Color(0xFF8DA2B5),
    tintLight: Color(0xFFE6ECEF),
    tintDark: Color(0xFF141C24),
  ),
};

Color _tint(Color base, Color tint, double amount) {
  return Color.lerp(base, tint, amount) ?? base;
}

Color _withOpacity(Color color, double opacity) {
  final value = opacity.clamp(0.0, 1.0);
  return color.withValues(alpha: value);
}

double _glassBlur(UiGlass glass) {
  switch (glass) {
    case UiGlass.soft:
      return 0.82;
    case UiGlass.standard:
      return 1.0;
    case UiGlass.strong:
      return 1.22;
  }
}

double _glassAlpha(UiGlass glass, {required double base}) {
  switch (glass) {
    case UiGlass.soft:
      return (base * 0.85).clamp(0.0, 1.0);
    case UiGlass.standard:
      return base;
    case UiGlass.strong:
      return (base * 1.1).clamp(0.0, 1.0);
  }
}

double _glassBorderAlpha(UiGlass glass, {required double base}) {
  switch (glass) {
    case UiGlass.soft:
      return (base * 0.7).clamp(0.0, 1.0);
    case UiGlass.standard:
      return base;
    case UiGlass.strong:
      return (base * 1.05).clamp(0.0, 1.0);
  }
}

double _glassHighlightAlpha(UiGlass glass, {required double base}) {
  switch (glass) {
    case UiGlass.soft:
      return (base * 0.7).clamp(0.0, 1.0);
    case UiGlass.standard:
      return base;
    case UiGlass.strong:
      return (base * 1.15).clamp(0.0, 1.0);
  }
}

extension CmykeChromeContext on BuildContext {
  CmykeChrome get chrome {
    final ext = Theme.of(this).extension<CmykeChrome>();
    assert(ext != null, 'CmykeChrome ThemeExtension is missing.');
    return ext!;
  }
}
