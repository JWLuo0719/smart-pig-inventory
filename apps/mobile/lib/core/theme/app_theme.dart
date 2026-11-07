import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color barnBlue = Color(0xFF0F172A);
  static const Color barnBlueLight = Color(0xFF234F6D);
  static const Color herdTeal = Color(0xFF059669);
  static const Color straw = Color(0xFFD99A2B);
  static const Color mist = Color(0xFFF8FAFC);
  static const Color ink = Color(0xFF0F172A);
  static const Color muted = Color(0xFF61727E);
  static const Color line = Color(0xFFE2E8F0);
  static const Color alert = Color(0xFFB42318);
  static const Color review = Color(0xFF6366F1);
}

/// Single spacing scale for every screen. Hand-written one-off gaps made the
/// vertical rhythm inconsistent between tabs; use these steps instead.
abstract final class AppSpacing {
  /// Inside a single text block (label above its own caption).
  static const double xxs = 4;

  /// Between an icon and its adjacent label.
  static const double xs = 8;

  /// Between tightly related rows inside one card.
  static const double sm = 12;

  /// Between sibling cards or list items.
  static const double md = 16;

  /// Between a section title and its content.
  static const double lg = 20;

  /// Between two unrelated sections.
  static const double xl = 28;

  /// Horizontal screen margin.
  static const double screenH = 12;

  /// Space above the first element of a scrollable screen body.
  static const double screenTop = 12;

  /// Trailing space so the last element clears the navigation bar.
  static const double screenBottom = 28;

  /// Standard scrollable page padding.
  static const EdgeInsets page =
      EdgeInsets.fromLTRB(screenH, screenTop, screenH, screenBottom);

  /// Padding inside a card.
  static const EdgeInsets card = EdgeInsets.all(md);
}

abstract final class AppRadius {
  static const double control = 8;
  static const double card = 10;
  static const double feature = 10;
  static const double pill = 999;
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
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            height: 1.2),
        titleLarge: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
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
        labelSmall: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
          side: BorderSide(color: AppColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide:
                const BorderSide(color: AppColors.herdTeal, width: 1.5)),
      ),
      chipTheme: const ChipThemeData(
        side: BorderSide(color: AppColors.line),
        selectedColor: Color(0xFFE6F4F0),
        labelStyle: TextStyle(fontSize: 13, color: AppColors.ink),
        showCheckmark: false,
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      dividerTheme:
          const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.barnBlue,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.herdTeal,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.line,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        toolbarHeight: 52,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.line)),
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        titleTextStyle: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
        subtitleTextStyle:
            TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        tilePadding: EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: AppColors.muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.barnBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: AppColors.barnBlue,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control)),
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
