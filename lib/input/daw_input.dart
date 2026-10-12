/// Input modes shown in the pixel status bar, plus the grid pointer that every
/// input source (keyboard, mouse, touch, MIDI) ultimately drives.
library;

enum InputMode {
  normal,
  insert,
  draw,
  erase,
  visual,
  visualLine,
  command,
  piano,
  replace,
}

extension InputModeLabel on InputMode {
  String get label => switch (this) {
        InputMode.normal => 'NORMAL',
        InputMode.insert => 'INSERT',
        InputMode.draw => 'DRAW',
        InputMode.erase => 'ERASE',
        InputMode.visual => 'VISUAL',
        InputMode.visualLine => 'V-LINE',
        InputMode.command => 'COMMAND',
        InputMode.piano => 'PIANO',
        InputMode.replace => 'REPLACE',
      };
}

enum ViewMode { roll, pattern, arrangement, mixer, sample, automation, help }

extension ViewModeLabel on ViewMode {
  String get label => switch (this) {
        ViewMode.roll => 'ROLL',
        ViewMode.pattern => 'PATTERN',
        ViewMode.arrangement => 'ARRANGE',
        ViewMode.mixer => 'MIXER',
        ViewMode.sample => 'SAMPLE',
        ViewMode.automation => 'AUTO',
        ViewMode.help => 'HELP',
      };
}

/// The single source of truth for "where am I" on the grid.
///
/// `row = pitch`, `column = time` exactly as the spec describes, so moving the
/// pointer, drawing, and live recording all share one address.
class GridPointer {
  /// MIDI pitch under the pointer.
  int pitch;

  /// 16th-note step under the pointer.
  int col;

  InputMode mode;

  /// Digits typed before a motion (vim count), e.g. the `8` in `8l`.
  String count;

  /// Operator awaiting a motion (`d`, `y`, `c`, `g`) or null.
  String? pending;

  GridPointer({this.pitch = 60, this.col = 0, this.mode = InputMode.normal})
      : count = '',
        pending = null;

  bool get hasCount => count.isNotEmpty;
  int get countValue => hasCount ? int.parse(count) : 1;

  void clearCount() => count = '';
  void clearPending() => pending = null;
}
