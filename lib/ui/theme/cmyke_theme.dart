import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import 'cmyke_chrome.dart';

class CmykeTheme {
  const CmykeTheme._();

  static const List<String> _fontFallback = [
    // These are "best effort" cross-platform. If the font is not installed
    // (or not bundled as an app asset), Flutter falls back to the platform
    // default font.
    'MiSans',
    'HarmonyOSSansSC',
    'Noto Sans SC',
    'Noto Sans CJK SC',
    'Roboto',
    'Arial',
  ];

  static ThemeData light({
    UiPalette palette = UiPalette.jade,
    UiGlass glass = UiGlass.standard,
  }) => _build(Brightness.light, palette, glass);
  static ThemeData dark({
    UiPalette palette = UiPalette.jade,
    UiGlass glass = UiGlass.standard,
  }) => _build(Brightness.dark, palette, glass);

  static ThemeData _build(
    Brightness brightness,
    UiPalette palette,
    UiGlass glass,
  ) {
    final chrome = brightness == Brightness.dark
        ? CmykeChrome.dark(palette: palette, glass: glass)
        : CmykeChrome.light(palette: palette, glass: glass);

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: chrome.accent,
          brightness: brightness,
          surface: chrome.surface,
        ).copyWith(
          primary: chrome.accent,
          onPrimary: brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          surface: chrome.surface,
          onSurface: chrome.textPrimary,
          outline: chrome.separatorStrong,
          outlineVariant: chrome.separator,
        );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(chrome.radiusL),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: chrome.background0,
      dividerColor: chrome.separator,
      fontFamily: _fontFallback.first,
      fontFamilyFallback: _fontFallback,
      extensions: [chrome],
      textTheme: baseTextTheme.apply(
        bodyColor: chrome.textPrimary,
        displayColor: chrome.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: chrome.textPrimary,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: chrome.textPrimary,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: chrome.textPrimary,
        unselectedLabelColor: chrome.textSecondary,
        indicatorColor: chrome.accent,
        labelStyle: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: chrome.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.radiusXL),
          side: BorderSide(color: chrome.separator),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.radiusM),
        ),
        iconColor: chrome.textSecondary,
        textColor: chrome.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? chrome.surfaceElevated
            : const Color(0xFFF2EEE6),
        hintStyle: TextStyle(color: chrome.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(chrome.radiusL),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF1B2330)
            : const Color(0xFF1F2228),
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.radiusL),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          side: BorderSide(color: chrome.separatorStrong),
          foregroundColor: chrome.textPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          foregroundColor: chrome.textPrimary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: chrome.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.radiusL),
          side: BorderSide(color: chrome.separator),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: chrome.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.radiusXL),
          side: BorderSide(color: chrome.separator),
        ),
      ),
    );
  }
}
