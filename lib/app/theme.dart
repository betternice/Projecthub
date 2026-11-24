import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const bg = Color(0xFF000000);
  static const raised = Color(0xFF1C1C1E);
  static const sheet = Color(0xFF141416);
  static const line = Color(0x24FFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFFA1A1A6);
  static const faint = Color(0xFF6E6E73);
  static const overview = Color(0xFFD1D1D6);
  static const accent = Color(0xFFFFFFFF);
  static const accentInk = Color(0xFF000000);
  static const danger = Color(0xFFFF453A);

  static const _posterColors = [
    Color(0xFF1C1C1E),
    Color(0xFF2C2C2E),
    Color(0xFF1A2330),
    Color(0xFF242426),
    Color(0xFF1E2422),
    Color(0xFF2A2430),
  ];

  /// สีพื้นปกสำรองที่คงที่ต่อไฟล์ เพื่อให้ปกเดิมไม่เปลี่ยนสีทุกครั้งที่ rebuild
  static Color poster(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0xFFFFFFFF;
    }
    return _posterColors[hash % _posterColors.length];
  }
}

abstract final class AppText {
  static TextStyle body({double size = 15, Color color = AppColors.text, double? height}) =>
      GoogleFonts.outfit(fontSize: size, color: color, height: height, fontWeight: FontWeight.w400);

  static TextStyle medium({double size = 15, Color color = AppColors.text, double? height}) =>
      GoogleFonts.outfit(fontSize: size, color: color, height: height, fontWeight: FontWeight.w500);

  static TextStyle semibold({double size = 15, Color color = AppColors.text, double? height}) =>
      GoogleFonts.outfit(fontSize: size, color: color, height: height, fontWeight: FontWeight.w600);

  static TextStyle display({double size = 28, Color color = AppColors.text}) =>
      GoogleFonts.fraunces(fontSize: size, color: color, fontWeight: FontWeight.w600);
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.bg,
      primary: AppColors.accent,
      onPrimary: AppColors.accentInk,
      error: AppColors.danger,
    ),
    textTheme: GoogleFonts.outfitTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.raised,
      hintStyle: AppText.body(color: AppColors.faint),
      contentPadding: const EdgeInsets.all(14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.muted),
      ),
    ),
  );
}
