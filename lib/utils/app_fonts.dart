import 'package:flutter/material.dart';

/// Local-first font helper.
/// 
/// Returns a TextStyle that uses the locally bundled Cairo font.
/// This is critical: it prevents the app from hanging on first launch
/// trying to download the font from the internet (the original cause
/// of the splash-screen freeze).
class AppFonts {
  AppFonts._();

  static const String cairo = 'Cairo';

  /// Drop-in replacement for `GoogleFonts.cairo(...)` that uses the
  /// bundled font, no network required.
  static TextStyle cairoStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
    TextDecoration? decoration,
    FontStyle? fontStyle,
    Color? backgroundColor,
  }) {
    return TextStyle(
      fontFamily: cairo,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      shadows: shadows,
      decoration: decoration,
      fontStyle: fontStyle,
      backgroundColor: backgroundColor,
    );
  }
}
