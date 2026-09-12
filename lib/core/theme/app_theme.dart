import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Flowexa palette — deep teal accent over green-biased neutrals, mirroring the web app.
class AppPalette {
  AppPalette._();

  static const accent = Color(0xFF0F766E);
  static const accentDark = Color(0xFF2DD4BF);

  // light
  static const ground = Color(0xFFF4F7F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFEDF2F0);
  static const ink = Color(0xFF131D1A);
  static const muted = Color(0xFF566661);
  static const line = Color(0xFFE0E6E3);

  // dark
  static const groundD = Color(0xFF0E1512);
  static const surfaceD = Color(0xFF151D1A);
  static const surfaceAltD = Color(0xFF1C2622);
  static const inkD = Color(0xFFE7EFEC);
  static const mutedD = Color(0xFF9BAFA9);
  static const lineD = Color(0xFF263029);

  // semantic
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF0369A1);

  // lead priority / score
  static const hot = Color(0xFFDC2626);
  static const warm = Color(0xFFEA580C);
  static const cool = Color(0xFF0284C7);
  static const cold = Color(0xFF64748B);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final dark = b == Brightness.dark;
    final accent = dark ? AppPalette.accentDark : AppPalette.accent;
    final ground = dark ? AppPalette.groundD : AppPalette.ground;
    final surface = dark ? AppPalette.surfaceD : AppPalette.surface;
    final ink = dark ? AppPalette.inkD : AppPalette.ink;
    final muted = dark ? AppPalette.mutedD : AppPalette.muted;
    final line = dark ? AppPalette.lineD : AppPalette.line;

    // Uses the platform font (SF Pro on iOS/macOS, Roboto on Android). Fonts
    // are not bundled, so we never reach out to fonts.gstatic.com at runtime.
    final textTheme = (dark ? ThemeData.dark() : ThemeData.light())
        .textTheme
        .apply(bodyColor: ink, displayColor: ink);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: ground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.accent,
        brightness: b,
        primary: accent,
        surface: surface,
        error: AppPalette.danger,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppPalette.surfaceAltD : AppPalette.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: dark ? AppPalette.groundD : Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? AppPalette.surfaceAltD : AppPalette.surfaceAlt,
        labelStyle: TextStyle(color: muted, fontSize: 12),
        side: BorderSide.none,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: ground),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      extensions: [
        _Flowexa(muted: muted, line: line, surfaceAlt: dark ? AppPalette.surfaceAltD : AppPalette.surfaceAlt),
      ],
    );
  }
}

/// Small theme extension so widgets can read semantic tokens off `Theme.of(context)`.
class _Flowexa extends ThemeExtension<_Flowexa> {
  const _Flowexa(
      {required this.muted, required this.line, required this.surfaceAlt});
  final Color muted;
  final Color line;
  final Color surfaceAlt;

  @override
  _Flowexa copyWith({Color? muted, Color? line, Color? surfaceAlt}) => _Flowexa(
      muted: muted ?? this.muted,
      line: line ?? this.line,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt);

  @override
  _Flowexa lerp(_Flowexa? other, double t) => this;
}

extension FlowexaContext on BuildContext {
  Color get mutedColor =>
      Theme.of(this).extension<_Flowexa>()?.muted ?? AppPalette.muted;
  Color get lineColor =>
      Theme.of(this).extension<_Flowexa>()?.line ?? AppPalette.line;
  Color get altSurface =>
      Theme.of(this).extension<_Flowexa>()?.surfaceAlt ?? AppPalette.surfaceAlt;
  Color get accentColor => Theme.of(this).colorScheme.primary;
}
