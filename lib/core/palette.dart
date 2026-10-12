import 'dart:ui' show Color;

/// A 16-colour indexed palette. Index 0 is always the background, index 15 the
/// brightest foreground, matching the chunky 8-bit look the spec asks for.
///
/// Notes use indices semantically: [bg] [faint] [dim] [text] [accent] etc. so a
/// hot-swap with `:pal` works without touching drawing code.
class PixelPalette {
  final String name;
  final List<Color> colors;

  const PixelPalette(this.name, this.colors);

  /// Background of the whole canvas.
  Color get bg => colors[0];

  /// Faintest lines (rows outside scale, bar guides).
  Color get faint => colors[1];

  /// Dim UI text / secondary lines.
  Color get dim => colors[2];

  /// Bright line / selected notes.
  Color get line => colors[3];

  /// Primary text / notes.
  Color get text => colors[4];

  /// Accent 1 (cursor, mode chip).
  Color get accent => colors[5];

  /// Accent 2 (visual selection).
  Color get accent2 => colors[6];

  /// Playhead / record.
  Color get playhead => colors[7];

  /// Warning / error in the status line.
  Color get error => colors[8];

  Color operator [](int index) => colors[index & 15];

  /// Build a note colour for [velocity] 0..127 using a dithered brightness
  /// ramps through the note band (indices 9..15).
  int velocityShade(int velocity) {
    final v = velocity.clamp(0, 127);
    return 9 + ((v * 6) ~/ 127);
  }

  static const PixelPalette vimdaw = PixelPalette('vimdaw', [
    Color(0xFF0B0F14),
    Color(0xFF16202B),
    Color(0xFF2C3E50),
    Color(0xFF4E6E81),
    Color(0xFF9FB3C8),
    Color(0xFF2EC4B6),
    Color(0xFFE7C24C),
    Color(0xFFFF5C5C),
    Color(0xFFFF3860),
    Color(0xFF2E7D6B),
    Color(0xFF3AA98F),
    Color(0xFF57C99E),
    Color(0xFF8EE0B6),
    Color(0xFFC4F0D8),
    Color(0xFFEBFBF2),
    Color(0xFFFFFFFF),
  ]);

  static const PixelPalette gameboy = PixelPalette('gameboy', [
    Color(0xFF0F380F),
    Color(0xFF306230),
    Color(0xFF4E7A32),
    Color(0xFF6B8E23),
    Color(0xFF8BAC0F),
    Color(0xFF9BBC0F),
    Color(0xFFA5C21F),
    Color(0xFFB0CC33),
    Color(0xFFBBD747),
    Color(0xFFC6E25B),
    Color(0xFFD1ED6F),
    Color(0xFFDCF883),
    Color(0xFFE7FF97),
    Color(0xFFEFFFAD),
    Color(0xFFF6FFC8),
    Color(0xFFFCFFE6),
  ]);

  static const PixelPalette nes = PixelPalette('nes', [
    Color(0xFF000000),
    Color(0xFF1A1A2E),
    Color(0xFF3B3B6D),
    Color(0xFF5C5C8A),
    Color(0xFF1E3A8A),
    Color(0xFF2563EB),
    Color(0xFF60A5FA),
    Color(0xFFBFDBFE),
    Color(0xFF7F1D1D),
    Color(0xFFDC2626),
    Color(0xFFF87171),
    Color(0xFFFECACA),
    Color(0xFF166534),
    Color(0xFF22C55E),
    Color(0xFF86EFAC),
    Color(0xFFFDE68A),
  ]);

  static const PixelPalette c64 = PixelPalette('c64', [
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFF880000),
    Color(0xFFAAFFEE),
    Color(0xFFCC44CC),
    Color(0xFF00CC55),
    Color(0xFF0000AA),
    Color(0xFFEEEE77),
    Color(0xFFDD8855),
    Color(0xFF664400),
    Color(0xFFFF7777),
    Color(0xFF333333),
    Color(0xFF777777),
    Color(0xFFAAFF66),
    Color(0xFF0088FF),
    Color(0xFFBBBBBB),
  ]);

  static const PixelPalette pico8 = PixelPalette('pico8', [
    Color(0xFF000000),
    Color(0xFF1D2B53),
    Color(0xFF7E2553),
    Color(0xFF008751),
    Color(0xFFAB5236),
    Color(0xFF5F574F),
    Color(0xFFC2C3C7),
    Color(0xFFFFF1E8),
    Color(0xFFFF004D),
    Color(0xFFFFA300),
    Color(0xFFFFEC27),
    Color(0xFF00E436),
    Color(0xFF29ADFF),
    Color(0xFF83769C),
    Color(0xFFFF77A8),
    Color(0xFFFFCCAA),
  ]);

  static const PixelPalette mono = PixelPalette('mono', [
    Color(0xFF000000),
    Color(0xFF111111),
    Color(0xFF222222),
    Color(0xFF333333),
    Color(0xFF444444),
    Color(0xFF555555),
    Color(0xFF666666),
    Color(0xFF777777),
    Color(0xFF888888),
    Color(0xFF999999),
    Color(0xFFAAAAAA),
    Color(0xFFBBBBBB),
    Color(0xFFCCCCCC),
    Color(0xFFDDDDDD),
    Color(0xFFEEEEEE),
    Color(0xFFFFFFFF),
  ]);

  static const Map<String, PixelPalette> registry = {
    'vimdaw': vimdaw,
    'gameboy': gameboy,
    'nes': nes,
    'c64': c64,
    'pico8': pico8,
    'mono': mono,
  };

  static List<String> get names => registry.keys.toList();

  static PixelPalette byName(String name) => registry[name] ?? vimdaw;
}
