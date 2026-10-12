import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern dark palette for the app chrome. The piano roll keeps its own
/// hand-drawn look but pulls its accent colours from here so the whole app
/// stays coherent when the user cycles themes.
abstract final class DawColors {
  static const Color bg = Color(0xFF0E0E10);
  static const Color bgTop = Color(0xFF0E0E10);
  static const Color surface = Color(0xFF141416);
  static const Color surfaceAlt = Color(0xFF19191C);
  static const Color surfaceHi = Color(0xFF212125);
  static const Color border = Color(0xFF2A2A2E);
  static const Color borderSoft = Color(0xFF1F1F22);

  static const Color text = Color(0xFFEDEDED);
  static const Color textDim = Color(0xFF9A9AA0);
  static const Color textFaint = Color(0xFF5C5C63);

  static const Color playhead = Color(0xFFEDEDED);
  static const Color record = Color(0xFFCF6679);
  static const Color ok = Color(0xFF8FBF9F);
  static const Color warn = Color(0xFFC9B074);
  static const Color error = Color(0xFFCF6679);

  // Piano roll surface.
  static const Color rollBg = Color(0xFF0E0E10);
  static const Color rollBgTop = Color(0xFF0E0E10);
  static const Color rowWhite = Color(0xFF141417);
  static const Color rowBlack = Color(0xFF101013);
  static const Color rowScale = Color(0xFF1A1A1E);
  static const Color barLine = Color(0xFF4A4A52);
  static const Color beatLine = Color(0xFF303036);
  static const Color stepLine = Color(0xFF202024);
  static const Color rowLine = Color(0xFF202024);
  static const Color octaveLine = Color(0xFF3A3A42);
  static const Color keyShadow = Color(0x33000000);

  // Piano keys.
  static const Color keyWhite = Color(0xFFD6D6DA);
  static const Color keyBlack = Color(0xFF1A1A1D);
  static const Color keyWhiteEdge = Color(0xFF7A7A80);
  static const Color keyLabel = Color(0xFF55555B);

  // Notes.
  static const Color noteBody = Color(0xFF6E6E78);
  static const Color noteEdge = Color(0xFF45454C);

  // Mixer / chrome
  static const Color panelBg = Color(0xFF141416);
  static const Color textMuted = Color(0xFF6C6C73);
}

/// Gradients used across the chrome.
abstract final class DawGradients {
  static const LinearGradient appBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [DawColors.bgTop, DawColors.bg],
  );

  static LinearGradient accent(Color a, [Color? b]) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, b ?? a],
      );

  static LinearGradient glass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      DawColors.surface.withValues(alpha: 0.85),
      DawColors.surfaceAlt.withValues(alpha: 0.72),
    ],
  );
}

/// Typography. Space Grotesk for display, Inter for UI, JetBrains Mono for
/// values (numbers, commands, positions).
abstract final class DawFonts {
  static TextStyle display({
    double size = 15,
    FontWeight weight = FontWeight.w700,
    Color color = DawColors.text,
    double spacing = 0.2,
    double height = 1.1,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: height,
      );

  static TextStyle body({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color color = DawColors.textDim,
    double spacing = 0.1,
    double height = 1.2,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: height,
      );

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w600,
    Color color = DawColors.textDim,
    double spacing = 0,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
      );

  // Mixer / UI specific
  static TextStyle get ui => body(size: 13, weight: FontWeight.w500);
  static TextStyle get uiSmall => body(size: 10, weight: FontWeight.w400);
  static TextStyle get uiBold => body(size: 11, weight: FontWeight.w700);
  static TextStyle get mono10 => mono(size: 10, weight: FontWeight.w500);
  static TextStyle get mono9 => mono(size: 9, weight: FontWeight.w500);
  static TextStyle get mono12 => mono(size: 12, weight: FontWeight.w600);
}

/// A selectable accent pair (primary + secondary). `:pal <name>` and the
/// palette button cycle through these.
class DawAccent {
  final String name;
  final Color accent;
  final Color accent2;

  const DawAccent(this.name, this.accent, this.accent2);
}

/// Fixed layout metrics for the chrome. Kept in one place so the roll can be
/// sized to exactly the remaining space.
abstract final class DawLayout {
  static const double toolbarH = 60;
  static const double tabsH = 46;
  static const double statusH = 28;
  static const double accessoryH = 54;
  static const double chromeH = toolbarH + tabsH + statusH + accessoryH;

  static const double pad = 12;
  static const double radius = 12;
}

abstract final class DawTheme {
  static const List<DawAccent> accents = [
    DawAccent('mono', Color(0xFFE8E8EC), Color(0xFFB0B0B6)),
    DawAccent('slate', Color(0xFFA9B4C0), Color(0xFF8A97A6)),
    DawAccent('sand', Color(0xFFC9BFA8), Color(0xFFA89C86)),
    DawAccent('moss', Color(0xFFAFC0A9), Color(0xFF8FA089)),
    DawAccent('rose', Color(0xFFC9A8AE), Color(0xFFA8868C)),
  ];

  static DawAccent byName(String name) =>
      accents.firstWhere((a) => a.name == name, orElse: () => accents.first);
}
