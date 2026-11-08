import 'package:flutter/material.dart';

class NetGetStatusColors extends ThemeExtension<NetGetStatusColors> {
  final Color downloading;
  final Color paused;
  final Color queued;
  final Color completed;
  final Color failed;
  final Color warning;

  const NetGetStatusColors({
    required this.downloading,
    required this.paused,
    required this.queued,
    required this.completed,
    required this.failed,
    required this.warning,
  });

  static const light = NetGetStatusColors(
    downloading: Color(0xFF1D5CC9),
    paused: Color(0xFFD97706),
    queued: Color(0xFF64748B),
    completed: Color(0xFF15803D),
    failed: Color(0xFFDC2626),
    warning: Color(0xFFD97706),
  );

  static const dark = NetGetStatusColors(
    downloading: Color(0xFF60A5FA),
    paused: Color(0xFFFBBF24),
    queued: Color(0xFF94A3B8),
    completed: Color(0xFF4ADE80),
    failed: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
  );

  @override
  NetGetStatusColors copyWith({
    Color? downloading,
    Color? paused,
    Color? queued,
    Color? completed,
    Color? failed,
    Color? warning,
  }) {
    return NetGetStatusColors(
      downloading: downloading ?? this.downloading,
      paused: paused ?? this.paused,
      queued: queued ?? this.queued,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      warning: warning ?? this.warning,
    );
  }

  @override
  NetGetStatusColors lerp(ThemeExtension<NetGetStatusColors>? other, double t) {
    if (other is! NetGetStatusColors) return this;
    return NetGetStatusColors(
      downloading: Color.lerp(downloading, other.downloading, t) ?? downloading,
      paused: Color.lerp(paused, other.paused, t) ?? paused,
      queued: Color.lerp(queued, other.queued, t) ?? queued,
      completed: Color.lerp(completed, other.completed, t) ?? completed,
      failed: Color.lerp(failed, other.failed, t) ?? failed,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
    );
  }
}

extension NetGetThemeDataX on ThemeData {
  NetGetStatusColors get statusColors =>
      extension<NetGetStatusColors>() ??
      (brightness == Brightness.dark
          ? NetGetStatusColors.dark
          : NetGetStatusColors.light);
}

class NetGetTheme {
  static const Color brandNavy = Color(0xFF0F172A);
  static const Color brandDeepNavy = Color(0xFF090D16);
  static const Color brandCyan = Color(0xFF38BDF8);
  static const Color brandBlue = Color(0xFF1D5CC9);
  static const Color brandGreen = Color(0xFF15803D);
  static const Color brandWhite = Color(0xFFFFFFFF);

  static const Color primaryBlue = brandBlue;
  static const Color accentCyan = brandCyan;
  static const Color successGreen = brandGreen;
  static const Color warningAmber = Color(0xFFD97706);
  static const Color errorRed = Color(0xFFDC2626);

  static ThemeData lightTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1D5CC9),
      onPrimary: Colors.white,
      secondary: Color(0xFF475569),
      onSecondary: Colors.white,
      tertiary: Color(0xFF15803D),
      onTertiary: Colors.white,
      error: Color(0xFFDC2626),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF0F172A),
      surfaceContainerHighest: Color(0xFFF1F5F9),
      outline: Color(0xFFCBD5E1),
      outlineVariant: Color(0xFFE2E8F0),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      extensions: const [NetGetStatusColors.light],
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF1D5CC9),
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF1D5CC9),
        linearTrackColor: Color(0xFFE2E8F0),
        linearMinHeight: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: Color(0xFF1D5CC9), width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData darkTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF60A5FA),
      onPrimary: Color(0xFF0F172A),
      secondary: Color(0xFF94A3B8),
      onSecondary: Color(0xFF0F172A),
      tertiary: Color(0xFF4ADE80),
      onTertiary: Color(0xFF0F172A),
      error: Color(0xFFF87171),
      onError: Color(0xFF0F172A),
      surface: Color(0xFF131B2E),
      onSurface: Color(0xFFF1F5F9),
      surfaceContainerHighest: Color(0xFF1E293B),
      outline: Color(0xFF334155),
      outlineVariant: Color(0xFF1E293B),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0B1120),
      extensions: const [NetGetStatusColors.dark],
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Color(0xFF131B2E),
        foregroundColor: Color(0xFFF1F5F9),
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF60A5FA),
        foregroundColor: Color(0xFF0F172A),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF60A5FA),
        linearTrackColor: Color(0xFF1E293B),
        linearMinHeight: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF131B2E),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: Color(0xFF60A5FA), width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1E293B),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
