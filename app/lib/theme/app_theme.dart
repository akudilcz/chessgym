import 'package:flutter/material.dart';

/// War-room palette: pitch canvas, neon cyan + amber + magenta, monospaced
/// numerics. Shared across every screen.
class WR {
  static const canvas = Color(0xFF0A0E14);       // near-black background
  static const panel = Color(0xFF111821);        // card surface
  static const panelElev = Color(0xFF17202C);    // elevated card surface
  static const divider = Color(0xFF1F2A38);
  static const text = Color(0xFFDDE4EE);
  static const muted = Color(0xFF7A8597);

  // Neons.
  static const cyan = Color(0xFF00E5FF);
  static const green = Color(0xFF39FF8C);
  static const amber = Color(0xFFFFC400);
  static const magenta = Color(0xFFFF3C8B);
  static const red = Color(0xFFFF5252);
  static const violet = Color(0xFFB388FF);

  // Semantic.
  static const positive = green;
  static const negative = red;
  static const warning = amber;

  static const mono = TextStyle(fontFamily: 'monospace');
}

ThemeData buildLightTheme() => _buildWarRoomTheme();
ThemeData buildDarkTheme() => _buildWarRoomTheme();

ThemeData _buildWarRoomTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'monospace',
    scaffoldBackgroundColor: WR.canvas,
    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: WR.cyan,
      onPrimary: WR.canvas,
      secondary: WR.amber,
      onSecondary: WR.canvas,
      tertiary: WR.magenta,
      onTertiary: WR.canvas,
      surface: WR.canvas,
      onSurface: WR.text,
      surfaceContainerLowest: WR.panel,
      surfaceContainerLow: WR.panel,
      surfaceContainer: WR.panelElev,
      surfaceContainerHigh: WR.panelElev,
      surfaceContainerHighest: WR.panelElev,
      outline: WR.divider,
      outlineVariant: WR.divider,
      error: WR.red,
    ),
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: WR.canvas,
      surfaceTintColor: WR.canvas,
      foregroundColor: WR.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'monospace',
        color: WR.text,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(color: WR.panel),
    dividerColor: WR.divider,
    textTheme: base.textTheme.apply(
      fontFamily: 'monospace',
      bodyColor: WR.text,
      displayColor: WR.text,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WR.cyan,
        foregroundColor: WR.canvas,
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WR.cyan,
        side: const BorderSide(color: WR.cyan),
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: WR.cyan,
      linearTrackColor: WR.divider,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: WR.panelElev,
      labelStyle: TextStyle(color: WR.text, fontFamily: 'monospace'),
    ),
  );
}
