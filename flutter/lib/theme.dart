import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const themeBg = Color(0xFF050508);
const themeRaised = Color(0xFF121218);
const themePanel = Color(0xFF18181F);
const themeLine = Color(0x22FFFFFF);
const themeText = Color(0xFFF5F5F7);
const themeMuted = Color(0xFF9A9AA3);
const themeFaint = Color(0xFF6B6B74);
const themeAccent = Color(0xFFE50914);
const themeAccentSoft = Color(0xFFFF4D57);
const themeFocus = Color(0xFFFFFFFF);
const themeDanger = Color(0xFFFF453A);

const posterColors = [
  Color(0xFF1A1520),
  Color(0xFF121820),
  Color(0xFF1C1612),
  Color(0xFF141A16),
  Color(0xFF1A1218),
  Color(0xFF16141C),
];

Color posterColor(String seed) {
  var hash = 0;
  for (final code in seed.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return posterColors[hash % posterColors.length];
}

TextStyle brandStyle({double size = 42, FontWeight weight = FontWeight.w700, Color? color}) {
  return GoogleFonts.bebasNeue(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 2.4,
    height: 1,
    color: color ?? themeText,
  );
}

TextStyle displayStyle({double size = 48, FontWeight weight = FontWeight.w700, Color? color}) {
  return GoogleFonts.outfit(
    fontSize: size,
    fontWeight: weight,
    height: 1.05,
    letterSpacing: -0.6,
    color: color ?? themeText,
  );
}

TextStyle bodyStyle({double size = 18, FontWeight weight = FontWeight.w400, Color? color, double height = 1.45}) {
  return GoogleFonts.outfit(
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? themeText,
  );
}

/// Shrink TV UI without Transform.scale (that composites video → stutter).
/// Stronger text clamp + slightly tighter visual density.
Widget densifyUi(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(
      textScaler: TextScaler.linear(mq.textScaler.scale(1).clamp(0.62, 0.72)),
      boldText: false,
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

ThemeData buildNiceTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: themeBg,
    canvasColor: themeBg,
    colorScheme: const ColorScheme.dark(
      surface: themeBg,
      primary: themeAccent,
      onPrimary: Colors.white,
      secondary: themeText,
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.outfitTextTheme(base.textTheme).apply(
      bodyColor: themeText,
      displayColor: themeText,
    ),
    focusColor: themeFocus.withValues(alpha: 0.18),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
