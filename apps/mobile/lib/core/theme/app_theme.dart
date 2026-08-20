import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color barnBlue = Color(0xFF173B57);
  static const Color barnBlueLight = Color(0xFF234F6D);
  static const Color herdTeal = Color(0xFF0B7A75);
  static const Color straw = Color(0xFFD99A2B);
  static const Color mist = Color(0xFFF3F7F8);
  static const Color ink = Color(0xFF14242F);
  static const Color muted = Color(0xFF61727E);
  static const Color line = Color(0xFFD7E1E5);
  static const Color alert = Color(0xFFB42318);
  static const Color review = Color(0xFF7556A4);
}

abstract final class AppTheme {
  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.barnBlue,
      brightness: Brightness.light,
      primary: AppColors.barnBlue,
      secondary: AppColors.herdTeal,
      surface: Colors.white,
      error: AppColors.alert,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.mist,
      fontFamilyFallback: const <String>[
        'Noto Sans SC',
        'Source Han Sans SC',
        'PingFang SC',
        'Microsoft YaHei',
      ],
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            height: 1.2),
        titleLarge: TextStyle(
            fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.ink),
        titleMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.ink,
            height: 1.5),
        bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.muted,
            height: 1.45),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: AppColors.line),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.mist,
        foregroundColor: AppColors.ink,
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.barnBlue,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.barnBlue,
          side: const BorderSide(color: AppColors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: Color(0x1F0B7A75),
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
