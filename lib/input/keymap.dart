import 'package:flutter/services.dart';

import 'daw_input.dart';

/// Every intent the input layer can produce. The UI switches on these, so the
/// same action can come from a key, a gesture, or (later) a MIDI learn binding.
enum DawAction {
  moveLeft,
  moveRight,
  moveUp,
  moveDown,
  moveBeatLeft,
  moveBeatRight,
  moveOctaveUp,
  moveOctaveDown,
  nextNote,
  prevNote,
  barStart,
  barEnd,
  lowestPitch,
  highestPitch,
  gotoPrefix,
  gotoLastLine,
  drawToggle,
  eraseToggle,
  replacePitch,
  visualToggle,
  visualLineToggle,
  deleteSelection,
  yankSelection,
  pasteAfter,
  pasteBefore,
  undo,
  redo,
  repeatLast,
  enterCommand,
  chordPrefix,
  lengthUp,
  lengthDown,
  cancel,
  quantize,
  transposeUp,
  transposeDown,
  octaveTransposeUp,
  octaveTransposeDown,
  cyclePalette,
  toggleGhost,
  toggleCrt,
  toggleFollow,
  toggleMetronome,
  toggleHelp,
  playPause,
  stop,
  record,
  viewRoll,
  viewPattern,
  viewArrangement,
  viewMixer,
  viewSample,
  viewAutomation,
  viewHelp,
  focusNext,
  focusPrev,
  focusFirst,
  focusLast,
  moveFocusUp,
  moveFocusDown,
  moveFocusLeft,
  moveFocusRight,
}

/// Resolves raw keyboard events into [DawAction]s using a per-mode binding
/// table. Kept free of UI so it is unit-testable and user-rebindable later
/// (`:map` / `:noremap` in M4).
class Keymap {
  static final Map<InputMode, Map<String, DawAction>> bindings = {
    InputMode.normal: _normal,
    InputMode.draw: _normal,
    InputMode.erase: _normal,
  };

  /// Override a binding at runtime (used by future `:map` support).
  static void bind(InputMode mode, String key, DawAction action) {
    (bindings[mode] ??= {})[key] = action;
  }

  static DawAction? resolve(InputMode mode, KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed;
    final shift = kb.isShiftPressed;
    final key = event.logicalKey;
    final ch = event.character;

    // Global.
    if (key == LogicalKeyboardKey.escape) return DawAction.cancel;
    if (key == LogicalKeyboardKey.f1) return DawAction.toggleHelp;

    if (ctrl) {
      return switch (key) {
        LogicalKeyboardKey.space => DawAction.playPause,
        LogicalKeyboardKey.keyR => DawAction.redo,
        LogicalKeyboardKey.digit1 => DawAction.viewRoll,
        LogicalKeyboardKey.digit2 => DawAction.viewPattern,
        LogicalKeyboardKey.digit3 => DawAction.viewArrangement,
        LogicalKeyboardKey.digit4 => DawAction.viewMixer,
        LogicalKeyboardKey.digit5 => DawAction.viewSample,
        LogicalKeyboardKey.digit6 => DawAction.viewAutomation,
        LogicalKeyboardKey.digit7 => DawAction.viewHelp,
        _ => null,
      };
    }

    // The command line owns printable keys while it is open.
    if (mode == InputMode.command) return null;

    // Global focus navigation (works in all modes except command).
    if (key == LogicalKeyboardKey.tab) {
      return shift ? DawAction.focusPrev : DawAction.focusNext;
    }
    if (key == LogicalKeyboardKey.escape) return DawAction.cancel;

    // Transport.
    if (key == LogicalKeyboardKey.enter) return DawAction.playPause;
    if (key == LogicalKeyboardKey.period) return DawAction.stop;

    // Enter command line via ':'.
    if (ch == ':') return DawAction.enterCommand;

    // Arrow keys for spatial focus navigation (when not moving pointer).
    if (key == LogicalKeyboardKey.arrowUp) return DawAction.moveFocusUp;
    if (key == LogicalKeyboardKey.arrowDown) return DawAction.moveFocusDown;
    if (key == LogicalKeyboardKey.arrowLeft) return DawAction.moveFocusLeft;
    if (key == LogicalKeyboardKey.arrowRight) return DawAction.moveFocusRight;

    // Motions.
    final shifted = shift;
    switch (key) {
      case LogicalKeyboardKey.keyH:
      case LogicalKeyboardKey.arrowLeft:
        return shifted ? DawAction.moveBeatLeft : DawAction.moveLeft;
      case LogicalKeyboardKey.keyL:
      case LogicalKeyboardKey.arrowRight:
        return shifted ? DawAction.moveBeatRight : DawAction.moveRight;
      case LogicalKeyboardKey.keyK:
      case LogicalKeyboardKey.arrowUp:
        return shifted ? DawAction.moveOctaveUp : DawAction.moveUp;
      case LogicalKeyboardKey.keyJ:
      case LogicalKeyboardKey.arrowDown:
        return shifted ? DawAction.moveOctaveDown : DawAction.moveDown;
      case LogicalKeyboardKey.keyW:
        return DawAction.nextNote;
      case LogicalKeyboardKey.keyB:
        return DawAction.prevNote;
      case LogicalKeyboardKey.home:
        return DawAction.barStart;
      case LogicalKeyboardKey.end:
        return DawAction.barEnd;
      case LogicalKeyboardKey.keyG:
        return shifted ? DawAction.gotoLastLine : DawAction.gotoPrefix;
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyI:
        return DawAction.drawToggle;
      case LogicalKeyboardKey.keyX:
        return DawAction.eraseToggle;
      case LogicalKeyboardKey.keyR:
        return DawAction.replacePitch;
      case LogicalKeyboardKey.keyV:
        return shifted ? DawAction.visualLineToggle : DawAction.visualToggle;
      case LogicalKeyboardKey.keyU:
        return DawAction.undo;
      case LogicalKeyboardKey.keyY:
        return DawAction.yankSelection;
      case LogicalKeyboardKey.keyP:
        return shift ? DawAction.pasteBefore : DawAction.pasteAfter;
      case LogicalKeyboardKey.keyD:
        return DawAction.deleteSelection;
      case LogicalKeyboardKey.keyQ:
        return null; // macros arrive in M6
      case LogicalKeyboardKey.equal:
        return shift ? DawAction.transposeUp : DawAction.quantize;
      case LogicalKeyboardKey.minus:
        return DawAction.transposeDown;
      case LogicalKeyboardKey.keyC:
        return DawAction.chordPrefix;
      case LogicalKeyboardKey.bracketRight:
        return DawAction.lengthUp;
      case LogicalKeyboardKey.bracketLeft:
        return DawAction.lengthDown;
      case LogicalKeyboardKey.keyT:
        return DawAction.toggleGhost;
      default:
        return null;
    }
  }

  /// Resolve a character delivered by an IME / soft keyboard into an action.
  /// Exact case is tried first so `V` (line select) is not flattened to `v`.
  static DawAction? resolveChar(String ch) =>
      _normal[ch] ?? _normal[ch.toLowerCase()];

  /// Chord-mode quality key → a `namedChordShapes` name. Used both by the
  /// logical-key path (hardware, Ctrl may be held) and the text path.
  static String? chordShapeFor(LogicalKeyboardKey key, bool shift) {
    if (key == LogicalKeyboardKey.keyM) return shift ? 'Major' : 'Minor';
    if (key == LogicalKeyboardKey.keyA) return 'aug';
    if (key == LogicalKeyboardKey.keyD) return 'dim';
    if (key == LogicalKeyboardKey.keyS) return '7';
    if (key == LogicalKeyboardKey.keyT) return 'maj7';
    return null;
  }

  static String? chordShapeForChar(String ch) {
    switch (ch) {
      case 'M':
        return 'Major';
      case 'm':
        return 'Minor';
      case 'a':
      case 'A':
        return 'aug';
      case 'd':
      case 'D':
        return 'dim';
      case 's':
      case 'S':
        return '7';
      case 't':
      case 'T':
        return 'maj7';
    }
    return null;
  }

  /// A count digit (vim `3l`), or null if the key is not a bare digit.
  static int? countDigit(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isAltPressed || kb.isShiftPressed) return null;
    return _digits[event.logicalKey];
  }

  static final Map<LogicalKeyboardKey, int> _digits = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
  };

  static const Map<String, DawAction> _normal = {
    'h': DawAction.moveLeft,
    'l': DawAction.moveRight,
    'k': DawAction.moveUp,
    'j': DawAction.moveDown,
    'w': DawAction.nextNote,
    'b': DawAction.prevNote,
    'G': DawAction.gotoLastLine,
    'gg': DawAction.lowestPitch,
    'i': DawAction.drawToggle,
    'x': DawAction.eraseToggle,
    'v': DawAction.visualToggle,
    'V': DawAction.visualLineToggle,
    'u': DawAction.undo,
    'd': DawAction.deleteSelection,
    'y': DawAction.yankSelection,
    'p': DawAction.pasteAfter,
    'P': DawAction.pasteBefore,
    'c': DawAction.chordPrefix,
    ']': DawAction.lengthUp,
    '[': DawAction.lengthDown,
    // 'g' and 'G' already mapped to gotoPrefix/gotoLastLine in _normal.
    ':': DawAction.enterCommand,
  };
}
