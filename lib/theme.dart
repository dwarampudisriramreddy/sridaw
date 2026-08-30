import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bgDeep = Color(0xFF14120F);
  static const panel = Color(0xFF1E1B17);
  static const panelRaised = Color(0xFF262219);
  static const line = Color(0xFF3A342A);
  static const lineSoft = Color(0xFF2A251E);
  static const text = Color(0xFFEDE6D6);
  static const textDim = Color(0xFF8C8371);
  static const textFaint = Color(0xFF5A5448);
  static const amber = Color(0xFFE8A33D);
  static const amberDim = Color(0xFF5C4726);
  static const teal = Color(0xFF4FBDBA);
  static const tealDim = Color(0xFF1E3E3D);
  static const red = Color(0xFFD65C4F);
  static const purple = Color(0xFFC77DD4);
}

/// Convenience text widgets. `Space Grotesk` for UI, `JetBrains Mono` for numerics.
class AppText {
  static Text ui(String text,
      {double size = 14,
      FontWeight weight = FontWeight.w400,
      Color color = AppColors.text,
      double? letterSpacing,
      int? maxLines}) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
      style: GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      ),
    );
  }

  static Text mono(String text,
      {double size = 14,
      FontWeight weight = FontWeight.w400,
      Color color = AppColors.text,
      double? letterSpacing}) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      ),
    );
  }

  static TextStyle uiStyle(double size,
      {FontWeight weight = FontWeight.w400,
      Color color = AppColors.text,
      double? letterSpacing}) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle monoStyle(double size,
      {FontWeight weight = FontWeight.w400,
      Color color = AppColors.text,
      double? letterSpacing}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
}

ThemeData buildAppTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: AppColors.bgDeep,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.teal,
      surface: AppColors.panel,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgDeep,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.lineSoft),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: AppColors.teal,
      inactiveTrackColor: AppColors.line,
      thumbColor: AppColors.text,
    ),
  );
}
