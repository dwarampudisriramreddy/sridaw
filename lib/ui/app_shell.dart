import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'icons.dart';

import '../core/audio_engine.dart';
import '../input/daw_input.dart';
import '../input/keymap.dart';
import '../input/keyboard_controller.dart';
import '../model/gm_instruments.dart';
import '../model/project.dart';
import '../music_theory.dart' as theory;
import '../render/arrangement_view.dart';
import '../render/automation_view.dart';
import '../render/browser_view.dart';
import '../render/mixer_view.dart';
import '../render/pattern_view.dart';
import '../render/piano_roll_view.dart';
import '../render/roll_layout.dart';
import 'daw_theme.dart';
import 'focus_manager.dart' as focus_mgr;

/// The whole application surface. Owns the project, the grid pointer, the
/// render scene, playback state and the audio engine handle, then routes every
/// input source into [_handleAction].
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final Project _project = Project.demo();
  final GridPointer _pointer = GridPointer(pitch: 60, col: 0);
  final DawAudioEngine _audio = DawAudioEngine();

  ViewMode _view = ViewMode.roll;
  DawAccent _accent = DawTheme.accents.first;

  // Pattern data for Pattern view
  late final List<Pattern> _patterns = [
    Pattern(name: 'Drums 1', color: const Color(0xFF4A90D9), steps: 16, pitchRange: 16),
    Pattern(name: 'Bass', color: const Color(0xFFE67E22), steps: 32, pitchRange: 16),
    Pattern(name: 'Lead', color: const Color(0xFF27AE60), steps: 16, pitchRange: 16),
    Pattern(name: 'Pad', color: const Color(0xFFE74C3C), steps: 64, pitchRange: 16),
  ];
  int _selectedPatternIndex = 0;

  // Arrangement (timeline) state. Lives here so the central key handler can
  // edit clips the same way it edits notes in the piano roll.
  late final List<ArrangementTrack> _arrangeTracks = _buildArrangement();
  int _arrangeCursorTrack = 0;
  int _arrangeCursorStep = 0;
  bool _arrangeSelecting = false;
  int? _arrangeAnchorTrack;
  int? _arrangeAnchorStep;

  // Clip currently being edited in the piano roll (set by `p` in the
  // arrangement; cleared by `p` back in the roll).
  int _clipOpenTrack = -1;

  // Instrument browser state (ViewMode.sample).
  final List<String> _browserCategories = gmFamiliesShort;
  int _browserCategory = 0;
  int _browserIndex = 0;

  List<GmInstrument> get _browserEntries => gmInstruments
      .where((e) => e.family == _browserCategories[_browserCategory])
      .toList();

  // Automation state (ViewMode.automation).
  final List<AutomationLane> _autoLanes = [
    AutomationLane(name: 'Volume', color: const Color(0xFF8FB0C0)),
    AutomationLane(name: 'Pan', color: const Color(0xFFC0A98F)),
    AutomationLane(name: 'Cutoff', color: const Color(0xFFAFC0A9)),
    AutomationLane(name: 'Reverb', color: const Color(0xFFC9A8AE)),
  ];
  int _autoLaneIndex = 0;
  int _autoStep = 0;
  int _autoValue = 100;

  List<ArrangementTrack> _buildArrangement() {
    final tracks = [
      ArrangementTrack(name: 'Track 1', color: const Color(0xFF4A90D9)),
      ArrangementTrack(name: 'Track 2', color: const Color(0xFFE67E22)),
      ArrangementTrack(name: 'Track 3', color: const Color(0xFF27AE60)),
      ArrangementTrack(name: 'Track 4', color: const Color(0xFFE74C3C)),
      ArrangementTrack(name: 'Track 5', color: const Color(0xFF8E44AD)),
      ArrangementTrack(name: 'Track 6', color: const Color(0xFF16A085)),
      ArrangementTrack(name: 'Track 7', color: const Color(0xFFD35400)),
      ArrangementTrack(name: 'Track 8', color: const Color(0xFF2C3E50)),
    ];
    tracks[0].clips.addAll([
      ArrangementClip(name: 'Drums A', trackIndex: 0, start: 0, length: 16, color: const Color(0xFF4A90D9)),
      ArrangementClip(name: 'Drums B', trackIndex: 0, start: 32, length: 16, color: const Color(0xFF4A90D9).withValues(alpha: 0.7)),
      ArrangementClip(name: 'Drums A', trackIndex: 0, start: 64, length: 16, color: const Color(0xFF4A90D9)),
    ]);
    tracks[1].clips.add(
      ArrangementClip(name: 'Bass', trackIndex: 1, start: 0, length: 64, color: const Color(0xFFE67E22)),
    );
    tracks[2].clips.add(
      ArrangementClip(name: 'Lead', trackIndex: 2, start: 32, length: 32, color: const Color(0xFF27AE60)),
    );
    return tracks;
  }

  int _viewLowPitch = 48;
  int _viewCol = 0;

  // Size of the piano-roll surface, recomputed from the window and keyboard
  // insets so the roll exactly fills the space between the chrome bars.
  int _canvasW = 320;
  int _canvasH = 200;

  int _revision = 0;
  bool _blinkOn = true;
  bool _ghostOn = true;
  bool _crtOn = false;

  // Sticky modifiers for the on-screen extra-keys row (Termux style).
  bool _stickyShift = false;
  bool _stickyCtrl = false;
  bool _stickyAlt = false;

  // Keyboard focus manager for vim-like navigation across all views.
  final focus_mgr.FocusManager _focusManager = focus_mgr.FocusManager();

  // CTRL note-grab: tap Ctrl to grab the note under the cursor, move it with
  // h/j/k/l, tap CTRL again to release.
  final List<Note> _grabNotes = [];
  bool _ctrlDown = false;
  bool _ctrlUsed = false;
  bool _grabUndoPushed = false;

  bool get _grabActive => _grabNotes.isNotEmpty;

  bool _showScale = true;
  bool _playing = false;
  int _playCol = 0;
  Timer? _playTimer;

  String _status = '';
  bool _statusError = false;
  String _commandBuffer = '';
  String _showCmd = '';
  Timer? _showCmdTimer;

  final List<List<Note>> _undo = [];
  final List<List<Note>> _redo = [];
  List<Note> _yank = [];
  int _noteLen = 2;

  ({int pitch, int col})? _visualAnchor;
  bool _boxSelecting = false;
  bool _chordPending = false;
  VoidCallback? _lastAction;

  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() {
        _blinkOn = !_blinkOn;
        _revision++;
      });
    });
    _initAudio();
  }

  Future<void> _initAudio() async {
    final ok = await _audio.init();
    if (!mounted) return;
    setState(() {
      _status = ok
          ? 'audio engine ready'
          : 'audio engine unavailable (build cpp/ to enable sound)';
      _statusError = !ok;
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _playTimer?.cancel();
    _showCmdTimer?.cancel();
    _audio.shutdown();
    super.dispose();
  }

  RollLayout get _layout => RollLayout(
        viewLowPitch: _viewLowPitch,
        viewCol: _viewCol,
        width: _canvasW,
        height: _canvasH,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final safe = MediaQuery.paddingOf(context);
    final availW = math.max(1.0, size.width - safe.left - safe.right);
    final availH = math.max(1.0, size.height - safe.top - insets.bottom);
    _canvasW = availW.floor();
    _canvasH = math.max(
      RollLayout.rulerH + RollLayout.cellH * 4,
      (availH - DawLayout.chromeH).floor(),
    );
  }

  // --------------------------------------------------------------- input
  static bool _isModifierKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.capsLock;

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    final isCtrl = key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight;

    if (isCtrl && _pointer.mode != InputMode.command) {
      // Treat CTRL as a tap (grab/release) unless it is used as a modifier.
      if (event is KeyDownEvent) {
        _ctrlDown = true;
        _ctrlUsed = false;
      } else if (event is KeyUpEvent) {
        if (_ctrlDown && !_ctrlUsed) {
          if (_view == ViewMode.arrangement) {
            _arrangeToggleSelect();
          } else {
            _toggleGrab();
          }
        }
        _ctrlDown = false;
      }
      return true;
    }
    if (_ctrlDown) _ctrlUsed = true;

    if (event is KeyUpEvent) return true;
    if (event is! KeyDownEvent) return true;

    if (_chordPending) {
      if (key == LogicalKeyboardKey.escape) {
        setState(() {
          _chordPending = false;
          _status = '';
          _revision++;
        });
        return true;
      }
      if (_isModifierKey(key)) return true;
      final shape = Keymap.chordShapeFor(
            key,
            HardwareKeyboard.instance.isShiftPressed,
          ) ??
          Keymap.chordShapeForChar(event.character ?? '');
      if (shape == null) {
        // Unknown key: stay armed so the next tap can still pick a quality.
        setState(() {
          _status = 'chord: M maj · m min · a aug · d dim · s 7 · t maj7';
          _revision++;
        });
        return true;
      }
      _chordPending = false;
      _applyChordKey(shape);
      return true;
    }

    if (_pointer.mode == InputMode.command) {
      if (key == LogicalKeyboardKey.escape) {
        _setMode(InputMode.normal, message: '');
      } else if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _runCommand(_commandBuffer);
      } else if (key == LogicalKeyboardKey.backspace) {
        setState(() {
          if (_commandBuffer.isNotEmpty) {
            _commandBuffer =
                _commandBuffer.substring(0, _commandBuffer.length - 1);
          }
        });
      } else {
        final ch = event.character;
        if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) {
          setState(() => _commandBuffer += ch);
        }
      }
      return true;
    }

    // Let OS shortcuts (alt+f4, ...) through.
    if (HardwareKeyboard.instance.isAltPressed) return false;

    final digit = Keymap.countDigit(event);
    if (digit != null) {
      _typeDigit(digit);
      return true;
    }

    final action = Keymap.resolve(_pointer.mode, event);
    final disp = _displayFor(action, _keyLabel(event));
    if (action != null) {
      _setShowCmd(disp);
      _handleAction(action);
    } else {
      _setShowCmd(disp);
    }
    return true;
  }

  /// Characters from the soft keyboard / IME. Routed through the *same*
  /// single-character keymap the hardware path uses, so `h j k l`, `w b`,
  /// counts, etc. work identically on touch devices.
  void _onText(String text) {
    if (_pointer.mode == InputMode.command) {
      setState(() => _commandBuffer += text);
      return;
    }
    if (_chordPending) {
      final shape = Keymap.chordShapeForChar(text);
      if (shape == null) return; // ignore stray text; stay in chord mode
      _chordPending = false;
      _applyChordKey(shape);
      return;
    }
    for (final ch in text.split('')) {
      final digit = int.tryParse(ch);
      if (digit != null) {
        _typeDigit(digit);
        continue;
      }
      final action = Keymap.resolveChar(ch);
      _setShowCmd(_displayFor(action, ch));
      if (action != null) _handleAction(action);
    }
  }

  void _typeDigit(int digit) {
    setState(() {
      if (digit == 0 && _pointer.count.isEmpty) {
        _pointer.col =
            (_pointer.col ~/ _project.stepsPerBar) * _project.stepsPerBar;
      } else if (_pointer.count.length < 4) {
        _pointer.count += '$digit';
      }
      _revision++;
    });
    _setShowCmd(_pointer.count);
  }

  /// Vim-style showcmd: the partial command as it is being typed.
  String _displayFor(DawAction? action, String label) {
    final prefix = _pointer.count;
    if (_pointer.pending == 'g' && action == DawAction.gotoPrefix) {
      return 'gg';
    }
    return '$prefix$label';
  }

  void _setShowCmd(String value) {
    _showCmdTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showCmd = value;
      _revision++;
    });
    _showCmdTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _showCmd = '';
        _revision++;
      });
    });
  }

  String _keyLabel(KeyEvent event) {
    final ch = event.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) return ch;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) return 'ESC';
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return 'CR';
    }
    if (key == LogicalKeyboardKey.space) return 'SPC';
    if (key == LogicalKeyboardKey.backspace) return 'BS';
    if (key == LogicalKeyboardKey.tab) return 'TAB';
    if (key == LogicalKeyboardKey.arrowLeft) return '\u2190';
    if (key == LogicalKeyboardKey.arrowRight) return '\u2192';
    if (key == LogicalKeyboardKey.arrowUp) return '\u2191';
    if (key == LogicalKeyboardKey.arrowDown) return '\u2193';
    final label = key.keyLabel;
    return label.isEmpty ? (key.debugName ?? '?') : label;
  }

  void _handleAction(DawAction action) {
    if (_view == ViewMode.arrangement && _handleArrangementAction(action)) {
      return;
    }
    if (_view == ViewMode.sample && _handleBrowserAction(action)) {
      return;
    }
    if (_view == ViewMode.automation && _handleAutomationAction(action)) {
      return;
    }
    switch (action) {
      case DawAction.moveLeft:
        _move(0, -1);
      case DawAction.moveRight:
        _move(0, 1);
      case DawAction.moveUp:
        _move(1, 0);
      case DawAction.moveDown:
        _move(-1, 0);
      case DawAction.moveBeatLeft:
        _move(0, -_project.stepsPerBeat);
      case DawAction.moveBeatRight:
        _move(0, _project.stepsPerBeat);
      case DawAction.moveOctaveUp:
        _move(12, 0);
      case DawAction.moveOctaveDown:
        _move(-12, 0);
      case DawAction.nextNote:
        _jumpNote(1);
      case DawAction.prevNote:
        _jumpNote(-1);
      case DawAction.barStart:
        _teleport(_pointer.pitch, (_pointer.col ~/ _project.stepsPerBar) * _project.stepsPerBar);
      case DawAction.barEnd:
        _teleport(
          _pointer.pitch,
          (_pointer.col ~/ _project.stepsPerBar) * _project.stepsPerBar +
              _project.stepsPerBar -
              1,
        );
      case DawAction.lowestPitch:
      case DawAction.gotoPrefix:
        if (_pointer.pending == 'g') {
          _pointer.clearPending();
          _gotoExtreme(false);
        } else {
          setState(() {
            _pointer.pending = 'g';
            _status = 'g';
            _statusError = false;
          });
        }
      case DawAction.gotoLastLine:
      case DawAction.highestPitch:
        _gotoExtreme(true);
      case DawAction.drawToggle:
        if (_grabNotes.isNotEmpty || _project.selection.isNotEmpty) {
          // On a selection `i` cycles the note length through the note values.
          _cycleLength();
        } else if (_pointer.mode == InputMode.draw) {
          _setMode(InputMode.normal, message: '');
        } else {
          // Seed a one-step note so the first h/j/k/l extends it from here.
          _pushUndo();
          _setMode(InputMode.draw, message: 'DRAW');
          setState(() {
            _addNote(_pointer.pitch, _pointer.col, len: 1);
            _revision++;
          });
        }
      case DawAction.eraseToggle:
        _setMode(_pointer.mode == InputMode.erase ? InputMode.normal : InputMode.erase,
            message: _pointer.mode == InputMode.erase ? '' : 'ERASE');
      case DawAction.replacePitch:
        _replaceUnderCursor();
      case DawAction.visualToggle:
        _enterVisual(line: false);
      case DawAction.visualLineToggle:
        _enterVisual(line: true);
      case DawAction.deleteSelection:
        _deleteSelection();
      case DawAction.yankSelection:
        _yankSelection();
      case DawAction.pasteAfter:
        if (_clipOpenTrack >= 0) {
          // We opened this roll from a clip — `p` goes back to arrange.
          setState(() {
            _clipOpenTrack = -1;
            _view = ViewMode.arrangement;
            _focusManager.setActiveView(ViewMode.arrangement);
            _status = 'back to arrange';
            _statusError = false;
            _revision++;
          });
        } else {
          _paste(before: false);
        }
      case DawAction.pasteBefore:
        _paste(before: true);
      case DawAction.undo:
        _undoAction();
      case DawAction.redo:
        _redoAction();
      case DawAction.repeatLast:
        _lastAction?.call();
      case DawAction.enterCommand:
        _setMode(InputMode.command, message: '');
        _commandBuffer = '';
      case DawAction.chordPrefix:
        setState(() {
          _chordPending = true;
          _status =
              'chord: M maj · m min · a aug · d dim · s 7 · t maj7';
          _statusError = false;
          _revision++;
        });
      case DawAction.focusNext:
        _focusManager.focusNext();
      case DawAction.focusPrev:
        _focusManager.focusPrevious();
      case DawAction.focusFirst:
        _focusManager.focusFirst();
      case DawAction.focusLast:
        _focusManager.focusLast();
      case DawAction.moveFocusUp:
        _focusManager.moveFocusUp();
      case DawAction.moveFocusDown:
        _focusManager.moveFocusDown();
      case DawAction.moveFocusLeft:
        _focusManager.moveFocusLeft();
      case DawAction.moveFocusRight:
        _focusManager.moveFocusRight();
      case DawAction.lengthUp:
        _changeLength(1);
      case DawAction.lengthDown:
        _changeLength(-1);
      case DawAction.cancel:
        _cancel();
      case DawAction.quantize:
        _quantize();
      case DawAction.transposeUp:
        _transpose(1);
      case DawAction.transposeDown:
        _transpose(-1);
      case DawAction.octaveTransposeUp:
        _transpose(12);
      case DawAction.octaveTransposeDown:
        _transpose(-12);
      case DawAction.cyclePalette:
        _cyclePalette();
      case DawAction.toggleGhost:
        setState(() {
          _ghostOn = !_ghostOn;
          _status = 'ghost notes ${_ghostOn ? 'on' : 'off'}';
          _statusError = false;
          _revision++;
        });
      case DawAction.toggleCrt:
        setState(() {
          _crtOn = !_crtOn;
          _revision++;
        });
      case DawAction.toggleFollow:
        _status = 'follow toggled';
        _touch();
      case DawAction.toggleMetronome:
        _status = 'metronome toggled';
        _touch();
      case DawAction.toggleHelp:
        _setView(_view == ViewMode.help ? ViewMode.roll : ViewMode.help);
      case DawAction.playPause:
        _togglePlay();
      case DawAction.stop:
        _stop();
      case DawAction.record:
        _status = 'recording (M3)';
        _touch();
      case DawAction.viewRoll:
        _setView(ViewMode.roll);
      case DawAction.viewPattern:
        _setView(ViewMode.pattern);
      case DawAction.viewArrangement:
        _setView(ViewMode.arrangement);
      case DawAction.viewMixer:
        _setView(ViewMode.mixer);
      case DawAction.viewSample:
        _setView(ViewMode.sample);
      case DawAction.viewAutomation:
        _setView(ViewMode.automation);
      case DawAction.viewHelp:
        _setView(ViewMode.help);
    }
  }

  // -------------------------------------------------------------- pointer
  void _touch() {
    setState(() {
      _statusError = false;
      _revision++;
    });
  }

  void _setMode(InputMode mode, {String? message}) {
    setState(() {
      _grabNotes.clear();
      _boxSelecting = false;
      _grabUndoPushed = false;
      _pointer.mode = mode;
      _pointer.clearCount();
      _pointer.clearPending();
      _chordPending = false;
      if (message != null) {
        _status = message;
        _statusError = false;
      }
      _revision++;
    });
  }

  void _setView(ViewMode view) {
    setState(() {
      _view = view;
      _focusManager.setActiveView(view);
      _status = 'view: ${view.label}';
      _statusError = false;
      _revision++;
    });
  }

  // ------------------------------------------------------------ arrangement
  /// Arrangement-view equivalents of the piano-roll editing verbs, routed from
  /// the one central key handler. Returns true when the action was consumed.
  bool _handleArrangementAction(DawAction action) {
    switch (action) {
      case DawAction.moveLeft:
        _arrangeMove(0, -1);
        return true;
      case DawAction.moveRight:
        _arrangeMove(0, 1);
        return true;
      case DawAction.moveUp:
        _arrangeMove(-1, 0);
        return true;
      case DawAction.moveDown:
        _arrangeMove(1, 0);
        return true;
      case DawAction.moveBeatLeft:
        _arrangeMove(0, -_project.beatsPerBar);
        return true;
      case DawAction.moveBeatRight:
        _arrangeMove(0, _project.beatsPerBar);
        return true;
      case DawAction.barStart:
        _arrangeMove(0, -(_arrangeCursorStep % _project.stepsPerBar));
        return true;
      case DawAction.barEnd:
        _arrangeMove(
          0,
          _project.stepsPerBar - 1 - (_arrangeCursorStep % _project.stepsPerBar),
        );
        return true;
      case DawAction.highestPitch:
        _arrangeMove(-_arrangeCursorTrack, 0);
        return true;
      case DawAction.lowestPitch:
        _arrangeMove(_arrangeTracks.length - 1 - _arrangeCursorTrack, 0);
        return true;
      case DawAction.drawToggle:
        _arrangeInsert();
        return true;
      case DawAction.pasteAfter:
        _arrangeOpenClip();
        return true;
      case DawAction.visualToggle:
      case DawAction.visualLineToggle:
        _arrangeToggleSelect();
        return true;
      case DawAction.deleteSelection:
        _arrangeDelete();
        return true;
      case DawAction.cancel:
        _arrangeCancel();
        return true;
      default:
        return false;
    }
  }

  void _arrangeMove(int dTrack, int dStep) {
    final count = _pointer.countValue;
    _pointer.clearCount();
    setState(() {
      _arrangeCursorTrack = (_arrangeCursorTrack + dTrack * count)
          .clamp(0, _arrangeTracks.length - 1);
      _arrangeCursorStep = (_arrangeCursorStep + dStep * count)
          .clamp(0, _project.totalSteps - 1);
      if (_arrangeSelecting) _arrangeUpdateSelection();
      _status = 'arrange · track ${_arrangeCursorTrack + 1} · '
          'bar ${_arrangeCursorStep ~/ _project.stepsPerBar + 1}';
      _statusError = false;
      _revision++;
    });
  }

  /// `i` — insert a clip at the cursor. One step long, like seeding a note in
  /// the piano roll; a count (`4i`) or the `]`/`[` resize keys set the length.
  void _arrangeInsert() {
    setState(() {
      final count = _pointer.countValue;
      _pointer.clearCount();
      final track = _arrangeTracks[_arrangeCursorTrack];
      final exists = track.clips.any(
        (c) => _arrangeCursorStep >= c.start &&
            _arrangeCursorStep < c.start + c.length,
      );
      if (exists) {
        _status = 'clip already here';
        _statusError = true;
      } else {
        final clip = ArrangementClip(
          name: 'Clip ${track.clips.length + 1}',
          trackIndex: _arrangeCursorTrack,
          start: _arrangeCursorStep,
          length: count,
          color: track.color,
        );
        clip.selected = true;
        track.clips.add(clip);
        _status = 'inserted ${count}-step clip · bar '
            '${_arrangeCursorStep ~/ _project.stepsPerBar + 1} · p edit';
        _statusError = false;
      }
      _revision++;
    });
  }

  /// `p` — open the clip under the cursor in the piano roll. Editing switches
  /// to that track's notes on the existing roll; `p` there returns here.
  void _arrangeOpenClip() {
    final track = _arrangeTracks[_arrangeCursorTrack];
    final clip = track.clips.where(
      (c) =>
          _arrangeCursorStep >= c.start &&
          _arrangeCursorStep < c.start + c.length,
    );
    if (clip.isEmpty) {
      setState(() {
        _status = 'no clip here · i to insert';
        _statusError = true;
        _revision++;
      });
      return;
    }
    final target = clip.first;
    setState(() {
      _clipOpenTrack = target.trackIndex;
      _project.activeTrack =
          target.trackIndex.clamp(0, _project.tracks.length - 1);
      _pointer.col = target.start;
      _pointer.pitch = 60;
      _pointer.mode = InputMode.normal;
      _grabNotes.clear();
      _status = 'editing ${target.name} · p to return to arrange';
      _statusError = false;
      _view = ViewMode.roll;
      _focusManager.setActiveView(ViewMode.roll);
      _revision++;
    });
  }

  /// CTRL tap — start / finish a rectangle clip selection (like the roll box).
  void _arrangeToggleSelect() {
    setState(() {
      if (_arrangeSelecting) {
        _arrangeSelecting = false;
        _arrangeAnchorTrack = null;
        _arrangeAnchorStep = null;
        final n = _arrangeTracks
            .expand((t) => t.clips.where((c) => c.selected))
            .length;
        _status = n == 0
            ? 'box selected nothing'
            : 'selected $n clip(s) · d delete';
        _statusError = n == 0;
      } else {
        _arrangeSelecting = true;
        _arrangeAnchorTrack = _arrangeCursorTrack;
        _arrangeAnchorStep = _arrangeCursorStep;
        _arrangeUpdateSelection();
        _status = 'box select · h/j/k/l · CTRL end';
        _statusError = false;
      }
      _revision++;
    });
  }

  void _arrangeUpdateSelection() {
    final aT = _arrangeAnchorTrack ?? _arrangeCursorTrack;
    final aS = _arrangeAnchorStep ?? _arrangeCursorStep;
    final loT = math.min(aT, _arrangeCursorTrack);
    final hiT = math.max(aT, _arrangeCursorTrack);
    final loS = math.min(aS, _arrangeCursorStep);
    final hiS = math.max(aS, _arrangeCursorStep);
    for (var ti = 0; ti < _arrangeTracks.length; ti++) {
      for (final clip in _arrangeTracks[ti].clips) {
        final clipEnd = clip.start + clip.length - 1;
        clip.selected =
            ti >= loT && ti <= hiT && clip.start <= hiS && clipEnd >= loS;
      }
    }
  }

  /// `d` — delete the selected clips, or the clip under the cursor.
  void _arrangeDelete() {
    setState(() {
      var removed = 0;
      for (final track in _arrangeTracks) {
        final before = track.clips.length;
        track.clips.removeWhere((c) => c.selected);
        removed += before - track.clips.length;
      }
      if (removed == 0) {
        final track = _arrangeTracks[_arrangeCursorTrack];
        final under = track.clips.where(
          (c) =>
              _arrangeCursorStep >= c.start &&
              _arrangeCursorStep < c.start + c.length,
        );
        if (under.isNotEmpty) {
          track.clips.remove(under.first);
          removed = 1;
        }
      }
      _arrangeSelecting = false;
      _arrangeAnchorTrack = null;
      _arrangeAnchorStep = null;
      _status = removed == 0 ? 'nothing to delete' : 'deleted $removed clip(s)';
      _statusError = removed == 0;
      _revision++;
    });
  }

  void _arrangeCancel() {
    setState(() {
      for (final track in _arrangeTracks) {
        for (final clip in track.clips) {
          clip.selected = false;
        }
      }
      _arrangeSelecting = false;
      _arrangeAnchorTrack = null;
      _arrangeAnchorStep = null;
      _status = '';
      _statusError = false;
      _revision++;
    });
  }

  // ------------------------------------------------------- instrument browser
  bool _handleBrowserAction(DawAction action) {
    switch (action) {
      case DawAction.moveDown:
        _browserMoveEntry(1);
        return true;
      case DawAction.moveUp:
        _browserMoveEntry(-1);
        return true;
      case DawAction.moveRight:
      case DawAction.moveBeatRight:
        _browserMoveCategory(1);
        return true;
      case DawAction.moveLeft:
      case DawAction.moveBeatLeft:
        _browserMoveCategory(-1);
        return true;
      case DawAction.drawToggle:
        _browserLoad();
        return true;
      default:
        return false;
    }
  }

  void _browserMoveEntry(int delta) {
    final count = _pointer.countValue;
    _pointer.clearCount();
    setState(() {
      final entries = _browserEntries;
      if (entries.isEmpty) return;
      _browserIndex =
          (_browserIndex + delta * count).clamp(0, entries.length - 1);
      _revision++;
    });
  }

  void _browserMoveCategory(int delta) {
    _pointer.clearCount();
    setState(() {
      _browserCategory =
          (_browserCategory + delta).clamp(0, _browserCategories.length - 1);
      _browserIndex = 0;
      _revision++;
    });
  }

  void _browserLoad() {
    setState(() {
      final entries = _browserEntries;
      if (entries.isEmpty) return;
      final program = entries[_browserIndex].program;
      _project.track.instrument = program;
      _audio.setTrackInstrument(_project.activeTrack, program);
      _status = 'loaded ${gmProgramName(program)} → ${_project.track.name}';
      _statusError = false;
      _revision++;
    });
  }

  bool _handleAutomationAction(DawAction action) {
    switch (action) {
      case DawAction.moveLeft:
        _autoMoveStep(-1);
        return true;
      case DawAction.moveRight:
        _autoMoveStep(1);
        return true;
      case DawAction.moveBeatLeft:
        _autoMoveStep(-(_project.stepsPerBar ~/ _project.beatsPerBar));
        return true;
      case DawAction.moveBeatRight:
        _autoMoveStep(_project.stepsPerBar ~/ _project.beatsPerBar);
        return true;
      case DawAction.moveUp:
        _autoMoveValue(1);
        return true;
      case DawAction.moveDown:
        _autoMoveValue(-1);
        return true;
      case DawAction.lengthUp:
        _autoSelectLane(1);
        return true;
      case DawAction.lengthDown:
        _autoSelectLane(-1);
        return true;
      case DawAction.drawToggle:
        _autoPut();
        return true;
      case DawAction.deleteSelection:
        _autoRemove();
        return true;
      default:
        return false;
    }
  }

  void _autoMoveStep(int delta) {
    final count = _pointer.countValue;
    _pointer.clearCount();
    setState(() {
      _autoStep =
          (_autoStep + delta * count).clamp(0, _project.totalSteps - 1);
      _revision++;
    });
  }

  void _autoMoveValue(int delta) {
    final count = _pointer.countValue;
    _pointer.clearCount();
    setState(() {
      _autoValue = (_autoValue + delta * count).clamp(0, 127);
      _revision++;
    });
  }

  void _autoSelectLane(int delta) {
    _pointer.clearCount();
    setState(() {
      _autoLaneIndex =
          (_autoLaneIndex + delta).clamp(0, _autoLanes.length - 1);
      _revision++;
    });
  }

  void _autoPut() {
    setState(() {
      _autoLanes[_autoLaneIndex].put(_autoStep, _autoValue);
      _status =
          '${_autoLanes[_autoLaneIndex].name} = $_autoValue @ step $_autoStep';
      _statusError = false;
      _revision++;
    });
  }

  void _autoRemove() {
    setState(() {
      _autoLanes[_autoLaneIndex].removeNear(_autoStep);
      _status = 'removed point near step $_autoStep';
      _statusError = false;
      _revision++;
    });
  }

  void _move(int dPitch, int dCol) {
    final count = _pointer.countValue;
    _pointer.clearCount();
    if (_grabActive) {
      _moveGrab(dPitch, dCol, count);
      return;
    }
    final nPitch = (_pointer.pitch + dPitch * count).clamp(0, 127);
    final nCol =
        (_pointer.col + dCol * count).clamp(0, _project.totalSteps - 1);
    if (_pointer.mode == InputMode.draw) {
      _pushUndo();
      _paintLine(_pointer.pitch, _pointer.col, nPitch, nCol);
    } else if (_pointer.mode == InputMode.erase) {
      _pushUndo();
      _eraseLine(_pointer.pitch, _pointer.col, nPitch, nCol);
    } else if (_pointer.mode == InputMode.replace && dPitch != 0) {
      _dragPitch(dPitch * count);
    }
    setState(() {
      _pointer.pitch = nPitch;
      _pointer.col = nCol;
      if (_pointer.mode == InputMode.visual ||
          _pointer.mode == InputMode.visualLine) {
        _updateSelection();
      }
      _revision++;
    });
    _audio.previewNote(nPitch, velocity: 90);
    _ensureVisible();
  }

  /// Move every CTRL-grabbed note; the pointer rides along so the grab sticks.
  void _moveGrab(int dPitch, int dCol, int count) {
    final dp = dPitch * count;
    final dc = dCol * count;
    if (!_grabUndoPushed) {
      _pushUndo();
      _grabUndoPushed = true;
    }
    setState(() {
      for (final n in _grabNotes) {
        n.pitch = (n.pitch + dp).clamp(0, 127);
        n.start = (n.start + dc).clamp(0, _project.totalSteps - n.len);
      }
      _pointer.pitch = (_pointer.pitch + dp).clamp(0, 127);
      _pointer.col =
          (_pointer.col + dc).clamp(0, _project.totalSteps - 1);
      _status = 'move ${_grabNotes.length} note(s) · CTRL to release';
      _statusError = false;
      _revision++;
    });
    _ensureVisible();
  }

  /// CTRL cycle: empty space starts a rectangle box, a second tap grabs the
  /// boxed notes so h/j/k/l move them, a third tap releases.
  void _toggleGrab() {
    if (_pointer.mode == InputMode.command) return;
    if (_grabActive || _boxSelecting) {
      setState(() {
        if (_boxSelecting) {
          // Box drawn — grab the boxed notes and switch to moving.
          _boxSelecting = false;
          _grabNotes
            ..clear()
            ..addAll(_project.selection);
          _grabUndoPushed = false;
          _status = _grabNotes.isEmpty
              ? 'box selected nothing'
              : 'grabbed ${_grabNotes.length} note(s) · h/j/k/l move · CTRL release';
          _statusError = _grabNotes.isEmpty;
} else {
          // Moving — release grab but KEEP selection for further edits (chord, delete, etc.)
          _grabNotes.clear();
          _grabUndoPushed = false;
          // _project.selection.clear();  // keep selection
          _pointer.mode = InputMode.normal;
          _visualAnchor = null;
          _status = 'released · selection kept';
          _statusError = false;
          _revision++;
        }
        _revision++;
      });
      return;
    }
    final under = _project.noteAt(_pointer.pitch, _pointer.col);
    if (_project.selection.isNotEmpty || under != null) {
      final picked = _project.selection.isNotEmpty
          ? _project.selection.toList()
          : [under!];
      setState(() {
        _grabNotes
          ..clear()
          ..addAll(picked);
        _grabUndoPushed = false;
        _project.selection
          ..clear()
          ..addAll(picked);
        _status =
            'grabbed ${picked.length} note(s) · h/j/k/l move · CTRL release';
        _statusError = false;
        _revision++;
      });
      return;
    }
    // Empty cell with nothing selected: start drawing a rectangle box.
    setState(() {
      _pointer.mode = InputMode.visual;
      _visualAnchor = (pitch: _pointer.pitch, col: _pointer.col);
      _boxSelecting = true;
      _updateSelection();
      _status = 'box select · h/j/k/l · CTRL grab';
      _statusError = false;
      _revision++;
    });
  }

  void _teleport(int pitch, int col) {
    setState(() {
      _pointer.pitch = pitch.clamp(0, 127);
      _pointer.col = col.clamp(0, _project.totalSteps - 1);
      if (_pointer.mode == InputMode.draw) {
        _pushUndo();
        _addNote(_pointer.pitch, _pointer.col);
      } else if (_pointer.mode == InputMode.erase) {
        _pushUndo();
        _eraseAt(_pointer.pitch, _pointer.col);
      }
      _revision++;
    });
    _audio.previewNote(_pointer.pitch, velocity: 90);
    _ensureVisible();
  }

  void _ensureVisible() {
    final l = _layout;
    var low = _viewLowPitch;
    if (_pointer.pitch > l.topPitch) low += _pointer.pitch - l.topPitch;
    if (_pointer.pitch < _viewLowPitch) low = _pointer.pitch;
    if (_pointer.col > _viewCol + l.cols - 1) {
      _viewCol = _pointer.col - l.cols + 1;
    }
    if (_pointer.col < _viewCol) _viewCol = _pointer.col;
    if (low != _viewLowPitch) {
      setState(() => _viewLowPitch = math.max(0, low));
    }
  }

  void _jumpNote(int dir) {
    final notes = _project.track.notes.toList()
      ..sort((a, b) => a.start == b.start
          ? a.pitch.compareTo(b.pitch)
          : a.start.compareTo(b.start));
    if (notes.isEmpty) return;
    ({int pitch, int start})? target;
    if (dir > 0) {
      for (final n in notes) {
        if (n.start > _pointer.col ||
            (n.start == _pointer.col && n.pitch > _pointer.pitch)) {
          target = (pitch: n.pitch, start: n.start);
          break;
        }
      }
      target ??= (pitch: notes.first.pitch, start: notes.first.start);
    } else {
      for (final n in notes.reversed) {
        if (n.start < _pointer.col ||
            (n.start == _pointer.col && n.pitch < _pointer.pitch)) {
          target = (pitch: n.pitch, start: n.start);
          break;
        }
      }
      target ??= (pitch: notes.last.pitch, start: notes.last.start);
    }
    _teleport(target.pitch, target.start);
  }

  void _gotoExtreme(bool highest) {
    final notes = _project.track.notes;
    if (notes.isEmpty) return;
    var p = notes.first.pitch;
    for (final n in notes) {
      p = highest ? math.max(p, n.pitch) : math.min(p, n.pitch);
    }
    _teleport(p, _pointer.col);
  }

  // -------------------------------------------------------------- editing
  List<Note> _snapshot() => _project.track.notes.map((n) => n.copy()).toList();

  void _pushUndo() {
    _undo.add(_snapshot());
    _redo.clear();
    if (_undo.length > 100) _undo.removeAt(0);
  }

  void _paintLine(int p0, int c0, int p1, int c1) {
    final steps = math.max((p1 - p0).abs(), (c1 - c0).abs());
    if (steps == 0) {
      _addNote(p1, c1);
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final p = (p0 + ((p1 - p0) * i / steps).round());
      final c = (c0 + ((c1 - c0) * i / steps).round());
      _addNote(p, c, len: 1);
    }
  }

  void _eraseLine(int p0, int c0, int p1, int c1) {
    final steps = math.max((p1 - p0).abs(), (c1 - c0).abs());
    if (steps == 0) {
      _eraseAt(p1, c1);
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final p = (p0 + ((p1 - p0) * i / steps).round());
      final c = (c0 + ((c1 - c0) * i / steps).round());
      _eraseAt(p, c);
    }
  }

  void _addNote(int pitch, int col, {int? len}) {
    if (col < 0 || col >= _project.totalSteps) return;
    // Already covered by a note: nothing to do.
    if (_project.noteAt(pitch, col) != null) return;
    // Continue an adjacent note on the same pitch instead of splitting it.
    final left = _project.noteAt(pitch, col - 1);
    if (left != null && left.start + left.len == col) {
      left.len += 1;
      return;
    }
    final right = _project.noteAt(pitch, col + 1);
    if (right != null && right.start == col + 1) {
      right.start = col;
      right.len += 1;
      return;
    }
    _project.track.notes.add(
      Note(pitch: pitch, start: col, len: len ?? _noteLen, vel: 100),
    );
  }

  void _eraseAt(int pitch, int col) {
    _project.track.notes.removeWhere((n) => n.pitch == pitch && n.contains(col));
    _project.selection.removeWhere((n) => n.pitch == pitch && n.contains(col));
  }

  void _dragPitch(int delta) {
    final n = _project.noteAt(_pointer.pitch, _pointer.col);
    if (n == null) return;
    _pushUndo();
    n.pitch = (n.pitch + delta).clamp(0, 127);
  }

  void _replaceUnderCursor() {
    _setMode(InputMode.replace,
        message: 'REPLACE: move up/down to drag pitch');
  }

  void _enterVisual({required bool line}) {
    _pushUndo();
    setState(() {
      _grabNotes.clear();
      _boxSelecting = false;
      _grabUndoPushed = false;
      _pointer.mode = line ? InputMode.visualLine : InputMode.visual;
      _visualAnchor = (pitch: _pointer.pitch, col: _pointer.col);
      _updateSelection();
      _status = line ? '-- VISUAL LINE --' : '-- VISUAL --';
      _statusError = false;
      _revision++;
    });
  }

  void _updateSelection() {
    _project.selection.clear();
    final anchor = _visualAnchor;
    if (anchor == null) return;
    final p0 = math.min(anchor.pitch, _pointer.pitch);
    final p1 = math.max(anchor.pitch, _pointer.pitch);
    final c0 = math.min(anchor.col, _pointer.col);
    final c1 = math.max(anchor.col, _pointer.col);
    for (final n in _project.track.notes) {
      final inPitch = n.pitch >= p0 && n.pitch <= p1;
      final inTime = n.end > c0 && n.start <= c1;
      final sameLine = n.pitch == _pointer.pitch || n.pitch == anchor.pitch;
      if (inPitch && inTime &&
          (_pointer.mode != InputMode.visualLine || sameLine)) {
        _project.selection.add(n);
      }
    }
  }

  void _deleteSelection() {
    _pushUndo();
    setState(() {
      if (_project.selection.isNotEmpty) {
        _project.track.notes.removeWhere(_project.selection.contains);
        _status = 'deleted ${_project.selection.length} note(s)';
        _project.selection.clear();
      } else {
        _eraseAt(_pointer.pitch, _pointer.col);
        _status = 'deleted note';
      }
      _statusError = false;
      _revision++;
    });
  }

  void _yankSelection() {
    final src = _project.selection.isNotEmpty
        ? _project.selection.toList()
        : (_project.noteAt(_pointer.pitch, _pointer.col) is Note
            ? [_project.noteAt(_pointer.pitch, _pointer.col)!]
            : <Note>[]);
    setState(() {
      _yank = src.map((n) => n.copy()).toList();
      _status = 'yanked ${_yank.length} note(s)';
      _statusError = false;
      _revision++;
    });
  }

  void _paste({required bool before}) {
    if (_yank.isEmpty) return;
    _pushUndo();
    setState(() {
      final baseCol = _yank.map((n) => n.start).reduce(math.min);
      final basePitch = _yank.map((n) => n.pitch).reduce(math.min);
      final deltaCol = _pointer.col - baseCol + (before ? -1 : 0);
      final deltaPitch = _pointer.pitch - basePitch;
      for (final n in _yank) {
        final copy = n.copy()
          ..start = (n.start + deltaCol).clamp(0, _project.totalSteps - 1)
          ..pitch = (n.pitch + deltaPitch).clamp(0, 127);
        _project.track.notes.add(copy);
      }
      _status = 'pasted ${_yank.length} note(s)';
      _statusError = false;
      _revision++;
    });
  }

  void _transpose(int delta) {
    _pushUndo();
    setState(() {
      final targets = _project.selection.isNotEmpty
          ? _project.selection.toList()
          : _project.track.notes.toList();
      for (final n in targets) {
        n.pitch = (n.pitch + delta).clamp(0, 127);
      }
      _status = 'transpose ${delta > 0 ? '+' : ''}$delta';
      _statusError = false;
      _revision++;
    });
  }

  void _quantize() {
    _pushUndo();
    setState(() {
      final div = _project.stepsPerBeat;
      for (final n in _project.track.notes) {
        n.start = (n.start / div).round() * div;
      }
      _status = 'quantized to 1/4 beat';
      _statusError = false;
      _revision++;
    });
  }

  void _undoAction() {
    if (_undo.isEmpty) {
      _status = 'already at oldest change';
      _statusError = true;
      _touch();
      return;
    }
    _redo.add(_snapshot());
    final prev = _undo.removeLast();
    setState(() {
      _grabNotes.clear();
      _boxSelecting = false;
      _grabUndoPushed = false;
      _project.track.notes
        ..clear()
        ..addAll(prev.map((n) => n.copy()));
      _project.selection.clear();
      _status = 'undo';
      _statusError = false;
      _revision++;
    });
  }

  void _redoAction() {
    if (_redo.isEmpty) {
      _status = 'already at newest change';
      _statusError = true;
      _touch();
      return;
    }
    _undo.add(_snapshot());
    final next = _redo.removeLast();
    setState(() {
      _grabNotes.clear();
      _boxSelecting = false;
      _grabUndoPushed = false;
      _project.track.notes
        ..clear()
        ..addAll(next.map((n) => n.copy()));
      _project.selection.clear();
      _status = 'redo';
      _statusError = false;
      _revision++;
    });
  }

  // ------------------------------------------------------------ transport
  void _togglePlay() {
    if (_playing) {
      _pause();
    } else {
      _play();
    }
  }

  void _play() {
    _playTimer?.cancel();
    final stepMs = (60000 / _project.bpm / _project.stepsPerBeat).round();
    _playTimer = Timer.periodic(Duration(milliseconds: math.max(10, stepMs)), (_) {
      if (!mounted) return;
      setState(() {
        _playCol = (_playCol + 1) % _project.totalSteps;
        _revision++;
      });
    });
    if (_audio.available) {
      _audio.playDemo(true);
      _audio.setLoopDuration(_project.totalSteps /
          (_project.bpm / 60.0 * _project.stepsPerBeat / 16.0));
    }
    setState(() {
      _playing = true;
      _status = 'PLAYING';
      _statusError = false;
      _revision++;
    });
  }

  void _pause() {
    _playTimer?.cancel();
    if (_audio.available) {
      _audio.playDemo(false);
    }
    setState(() {
      _playing = false;
      _status = 'PAUSED';
      _statusError = false;
      _revision++;
    });
  }

  void _stop() {
    _playTimer?.cancel();
    if (_audio.available) {
      _audio.playDemo(false);
    }
    setState(() {
      _playing = false;
      _playCol = 0;
      _status = 'STOPPED';
      _statusError = false;
      _revision++;
    });
  }

  // ------------------------------------------------------------- commands
  void _runCommand(String raw) {
    final input = raw.trim();
    setState(() {
      _commandBuffer = '';
      _pointer.mode = InputMode.normal;
    });
    if (input.isEmpty) {
      _touch();
      return;
    }
    final parts = input.split(RegExp(r'\s+'));
    final cmd = parts.first;
    final args = parts.skip(1).toList();
    // Rectangle select: `:ctrl+1.1-E4,1.2-C4` (bar.beat-note pairs).
    if (cmd.startsWith('ctrl+')) {
      _selectBox(cmd.substring(5));
      setState(() => _revision++);
      return;
    }
    switch (cmd) {
      case 'q':
      case 'q!':
        _status = "can't quit Flutter app; close the window";
      case 'w':
        _status = 'save not implemented until M5';
      case 'pal':
      case 'theme':
        final name = args.isEmpty ? '' : args.first;
        _accent = DawTheme.byName(name);
        _status = 'theme: ${_accent.name}';
        _statusError = false;
      case 'crt':
        _crtOn = args.isNotEmpty && args.first == 'on';
        _status = 'crt ${_crtOn ? 'on' : 'off'}';
        _statusError = false;
      case 'ghost':
        _ghostOn = args.isEmpty || args.first != 'off';
        _status = 'ghost ${_ghostOn ? 'on' : 'off'}';
        _statusError = false;
      case 'scale':
        _setScale(args);
      case 'chord':
        _makeChord(args);
      case 'bpm':
        final v = int.tryParse(args.isEmpty ? '' : args.first);
        if (v != null) {
          _project.bpm = v.clamp(20, 300);
          _status = 'bpm ${_project.bpm}';
          _statusError = false;
        } else {
          _status = 'E: bpm expects a number';
          _statusError = true;
        }
      case 'len':
        final v = int.tryParse(args.isEmpty ? '' : args.first);
        if (v != null) {
          _noteLen = v.clamp(1, 64);
          _status = 'len $_noteLen';
          _statusError = false;
        } else {
          _status = 'E: len expects a number';
          _statusError = true;
        }
      case 'view':
        final name = args.isEmpty ? '' : args.first;
        final match = ViewMode.values.where((v) => v.name == name).toList();
        if (match.isEmpty) {
          _status = 'E: unknown view: $name';
          _statusError = true;
        } else {
          _view = match.first;
          _status = 'view: ${_view.label}';
          _statusError = false;
        }
      case 'help':
        _view = ViewMode.help;
        _status = 'help';
        _statusError = false;
      case 'play':
        _play();
      case 'stop':
        _stop();
      case 'pause':
        _pause();
      case 'version':
        _status = 'vimdaw 0.0.1 (M1/M2)';
        _statusError = false;
      default:
        _status = "E: unknown command: '$cmd'";
        _statusError = true;
    }
    setState(() => _revision++);
  }

  /// `:ctrl+1.1-E4,1.2-C4` — select every note whose start lies inside the
  /// rectangle between two `barnumber.beat-note` corners, then grab the
  /// selection so it can be nudged with h/j/k/l until CTRL is pressed again.
  void _selectBox(String payload) {
    final corners = payload.split(',');
    final a = corners.isNotEmpty ? _parseCorner(corners[0]) : null;
    final b = corners.length > 1 ? _parseCorner(corners[1]) : null;
    if (corners.length != 2 || a == null || b == null) {
      _status = 'E: usage :ctrl+1.1-E4,1.2-C4';
      _statusError = true;
      return;
    }
    final loCol = math.min(a.col, b.col);
    final hiCol = math.max(a.col, b.col);
    final loP = math.min(a.pitch, b.pitch);
    final hiP = math.max(a.pitch, b.pitch);
    setState(() {
      _project.selection
        ..clear()
        ..addAll(_project.track.notes.where((n) =>
            n.start >= loCol &&
            n.start <= hiCol &&
            n.pitch >= loP &&
            n.pitch <= hiP));
      _grabNotes
        ..clear()
        ..addAll(_project.selection);
      _grabUndoPushed = false;
      _pointer.pitch = loP.clamp(0, 127);
      _pointer.col = loCol.clamp(0, _project.totalSteps - 1);
      _status = _grabNotes.isEmpty
          ? 'box selected nothing'
          : 'box: grabbed ${_grabNotes.length} note(s) · CTRL release';
      _statusError = _grabNotes.isEmpty;
      _revision++;
    });
    if (_grabNotes.isNotEmpty) _ensureVisible();
  }

  /// Parse a `1.1-E4` corner (bar.beat + note name) into a `(col, pitch)`.
  ({int col, int pitch})? _parseCorner(String raw) {
    final m = RegExp(r'^\s*(\d+)\.(\d+)-([A-Ga-g])(#|b)?(-?\d+)\s*$')
        .firstMatch(raw);
    if (m == null) return null;
    final bar = int.parse(m.group(1)!);
    final beat = int.parse(m.group(2)!);
    const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    var p = base[m.group(3)!.toUpperCase()]!;
    if (m.group(4) == '#') p += 1;
    if (m.group(4) == 'b') p -= 1;
    final pitch = (int.parse(m.group(5)!) + 1) * 12 + p;
    final col =
        (bar - 1) * _project.stepsPerBar + (beat - 1) * _project.stepsPerBeat;
    return (col: col, pitch: pitch);
  }

  /// `:scale` with no args reports the key; `:scale on|off` toggles the row
  /// highlight; `:scale <root> [name]` sets the project key signature.
  void _setScale(List<String> args) {
    if (args.isEmpty) {
      _status =
          'scale: ${theory.noteNames[_project.scaleRoot]} ${_project.scaleName}';
      _statusError = false;
      return;
    }
    if (args.first == 'on' || args.first == 'off') {
      final on = args.first == 'on';
      setState(() {
        _showScale = on;
        _status = 'scale overlay ${on ? 'on' : 'off'}';
        _statusError = false;
        _revision++;
      });
      return;
    }
    final root = _rootPc(args.first);
    if (root == null) {
      _status = 'E: unknown root "${args.first}" (try :scale D Minor)';
      _statusError = true;
      return;
    }
    final wanted = args.skip(1).join(' ');
    String name = _project.scaleName;
    if (wanted.isNotEmpty) {
      final match = _scaleByName(wanted);
      if (match.isEmpty) {
        _status = 'E: unknown scale "$wanted"';
        _statusError = true;
        return;
      }
      name = match;
    }
    setState(() {
      _project.scaleRoot = root;
      _project.scaleName = name;
      _status = 'scale: ${theory.noteNames[root]} $name';
      _statusError = false;
      _revision++;
    });
  }

  /// `:chord [type]` harmonises the selection (or the note under the cursor)
  /// into a chord — `Major` by default — and selects the added tones.
  void _makeChord(List<String> args) {
    final wanted = args.isEmpty ? 'Major' : args.join(' ');
    final shape = theory.namedChordShapes.keys.firstWhere(
      (k) => k.toLowerCase() == wanted.toLowerCase(),
      orElse: () => '',
    );
    if (shape.isEmpty) {
      _status = 'E: chord "<${theory.namedChordShapes.keys.join('|')}>"';
      _statusError = true;
      return;
    }
    _chordFor(shape);
  }

  void _applyChordKey(String? shape) {
    if (shape == null) {
      setState(() {
        _status = 'E: chord key? M m a d s t';
        _statusError = true;
        _revision++;
      });
      return;
    }
    _chordFor(shape);
  }

  /// Build [shape] on every selected note (or the note under the cursor,
  /// or a new root at the cursor) and select the tones that were added.
  void _chordFor(String shape) {
    final under = _project.noteAt(_pointer.pitch, _pointer.col);
    final roots = _project.selection.isNotEmpty
        ? _project.selection.toList()
        : (under != null ? [under] : <Note>[]);
    if (roots.isEmpty) {
      // Create a root note at the cursor so chord can be built on empty cells.
      _pushUndo();
      final root = Note(pitch: _pointer.pitch, start: _pointer.col, len: _noteLen, vel: 100);
      _project.track.notes.add(root);
      roots.add(root);
    }
    final offsets = theory.namedChordShapes[shape]!;
    _pushUndo();
    final created = <Note>[];
    for (final n in roots) {
      for (final off in offsets.skip(1)) {
        final p = n.pitch + off;
        if (p < 0 || p > 127) continue;
        if (_project.noteAt(p, n.start) != null) continue;
        final note = Note(pitch: p, start: n.start, len: n.len, vel: n.vel);
        _project.track.notes.add(note);
        created.add(note);
      }
    }
    setState(() {
      _project.selection.addAll(created);
      _status = 'chord $shape · +${created.length} note(s)';
      _statusError = created.isEmpty;
      _revision++;
    });
    _audio.previewNote(roots.first.pitch, velocity: 100);
  }

  /// Notes a resize acts on: the grab, else the selection, else the note under
  /// the cursor.
  List<Note> _resizeTargets() => _grabNotes.isNotEmpty
      ? _grabNotes
      : _project.selection.isNotEmpty
          ? _project.selection.toList()
          : [
              if (_project.noteAt(_pointer.pitch, _pointer.col) != null)
                _project.noteAt(_pointer.pitch, _pointer.col)!
            ];

  /// Grow/shrink the grabbed set, the selection, or the note under the cursor.
  void _changeLength(int delta) {
    final targets = _resizeTargets();
    if (targets.isEmpty) {
      setState(() {
        _status = 'E: no note to resize';
        _statusError = true;
        _revision++;
      });
      return;
    }
    _pushUndo();
    setState(() {
      for (final n in targets) {
        n.len = (n.len + delta).clamp(1, _project.totalSteps - n.start);
      }
      _status =
          '${delta > 0 ? 'longer' : 'shorter'} · ${targets.length} note(s)';
      _statusError = false;
      _revision++;
    });
    _ensureVisible();
  }

  /// Standard note values (`1/32`…`1`) as lengths in steps for the current
  /// grid. Finer values than the grid can represent collapse to one step and
  /// are de-duplicated.
  List<int> _lengthCycle() {
    final whole = _project.stepsPerBar;
    final out = <int>[];
    for (final denom in const [32, 16, 8, 4, 2, 1]) {
      final v = math.max(1, (whole / denom).round());
      if (!out.contains(v)) out.add(v);
    }
    return out;
  }

  String _lengthLabel(int len) {
    final whole = _project.stepsPerBar;
    if (len >= whole) return '1';
    final denom = (whole / len).round();
    return '1/$denom';
  }

  /// `i` on a selection: advance every note to the next standard note value.
  void _cycleLength() {
    final targets = _resizeTargets();
    if (targets.isEmpty) {
      setState(() {
        _status = 'E: no note to resize';
        _statusError = true;
        _revision++;
      });
      return;
    }
    final cycle = _lengthCycle();
    final current = targets.first.len;
    final next = cycle.firstWhere((v) => v > current, orElse: () => cycle.first);
    _pushUndo();
    setState(() {
      for (final n in targets) {
        n.len = next.clamp(1, _project.totalSteps - n.start);
      }
      _status = 'len ${_lengthLabel(next)} · ${targets.length} note(s)';
      _statusError = false;
      _revision++;
    });
    _ensureVisible();
  }

  /// Fuzzy scale lookup: exact name first, then substring (`Minor` -> Natural
  /// Minor, `Pentatonic` -> Major Pentatonic).
  String _scaleByName(String wanted) {
    final w = wanted.toLowerCase();
    for (final k in theory.scales.keys) {
      if (k.toLowerCase() == w) return k;
    }
    for (final k in theory.scales.keys) {
      if (k.toLowerCase().contains(w)) return k;
    }
    return '';
  }

  /// Parse a note name (`C`, `C#`, `Db`, `A`) to a pitch-class 0..11.
  int? _rootPc(String s) {
    final m = RegExp(r'^([A-Ga-g])(#|b)?$').firstMatch(s.trim());
    if (m == null) return null;
    const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    var p = base[m.group(1)!.toUpperCase()]!;
    if (m.group(2) == '#') p += 1;
    if (m.group(2) == 'b') p -= 1;
    return (p % 12 + 12) % 12;
  }

  void _cyclePalette() {
    final list = DawTheme.accents;
    final i = list.indexWhere((a) => a.name == _accent.name);
    _accent = list[(i + 1) % list.length];
    setState(() {
      _status = 'theme: ${_accent.name}';
      _statusError = false;
      _revision++;
    });
  }

  void _cancel() {
    setState(() {
      _pointer.mode = InputMode.normal;
      _pointer.clearCount();
      _pointer.clearPending();
      _grabNotes.clear();
      _boxSelecting = false;
      _grabUndoPushed = false;
      _project.selection.clear();
      _visualAnchor = null;
      _chordPending = false;
      _commandBuffer = '';
      _status = '';
      _statusError = false;
      _revision++;
    });
  }

  // -------------------------------------------------------------- gestures
  void _onTapAt(Offset local) {
    final l = _layout;
    final x = local.dx.floor();
    final y = local.dy.floor();
    if (l.inGrid(x, y)) {
      final pitch = l.pitchForY(y).clamp(0, 127);
      final col = l.colForX(x).clamp(0, _project.totalSteps - 1);
      _teleport(pitch, col);
    }
  }

  void _handleAccessory(String action) {
    switch (action) {
      case 'shift':
        _toggleSticky(shift: true);
      case 'ctrl':
        _toggleGrab();
      case 'alt':
        _toggleSticky(alt: true);
      case 'esc':
        _clearSticky();
        _cancel();
      case 'tab':
        _clearSticky();
        _setView(ViewMode.values[(_view.index + 1) % ViewMode.values.length]);
      case 'home':
        _clearSticky();
        _handleAction(DawAction.barStart);
      case 'end':
        _clearSticky();
        _handleAction(DawAction.barEnd);
      case 'left':
        _virtualMove(dx: -1);
      case 'right':
        _virtualMove(dx: 1);
      case 'up':
        _virtualMove(dy: 1);
      case 'down':
        _virtualMove(dy: -1);
      case 'command':
        _clearSticky();
        _handleAction(DawAction.enterCommand);
      case 'palette':
        _clearSticky();
        _cyclePalette();
    }
  }

  void _toggleSticky({bool shift = false, bool ctrl = false, bool alt = false}) {
    setState(() {
      if (shift) _stickyShift = !_stickyShift;
      if (ctrl) _stickyCtrl = !_stickyCtrl;
      if (alt) _stickyAlt = !_stickyAlt;
      _showCmd = shift
          ? (_stickyShift ? 'SHIFT' : '')
          : ctrl
              ? (_stickyCtrl ? 'CTRL' : '')
              : (_stickyAlt ? 'ALT' : '');
      _revision++;
    });
    _showCmdTimer?.cancel();
    _showCmdTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _showCmd = '';
        _revision++;
      });
    });
  }

  void _clearSticky() {
    if (!_stickyShift && !_stickyCtrl && !_stickyAlt) return;
    setState(() {
      _stickyShift = false;
      _stickyCtrl = false;
      _stickyAlt = false;
      _revision++;
    });
  }

  /// Arrow buttons honour the sticky modifiers:
  ///   shift + horizontal -> beat,  ctrl + horizontal -> bar
  ///   shift + vertical   -> octave pointer, ctrl + vertical -> octave transpose
  void _virtualMove({int dx = 0, int dy = 0}) {
    final shift = _stickyShift;
    _clearSticky();
    if (dy != 0) {
      _move(shift ? (dy > 0 ? 12 : -12) : dy, 0);
    } else {
      _move(0, shift ? dx * _project.stepsPerBeat : dx);
    }
  }

  void _onPanAt(Offset local) {
    final l = _layout;
    final x = local.dx.floor();
    final y = local.dy.floor();
    if (!l.inGrid(x, y)) return;
    final pitch = l.pitchForY(y).clamp(0, 127);
    final col = l.colForX(x).clamp(0, _project.totalSteps - 1);
    if (_pointer.mode == InputMode.draw) {
      _paintLine(_pointer.pitch, _pointer.col, pitch, col);
      setState(() {
        _pointer.pitch = pitch;
        _pointer.col = col;
        _revision++;
      });
    } else {
      _teleport(pitch, col);
    }
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final safe = MediaQuery.paddingOf(context);
    return focus_mgr.FocusManagerScope(
      manager: _focusManager,
      child: AlwaysOnKeyboard(
        onKey: _onKey,
        onText: _onText,
        child: Material(
          type: MaterialType.transparency,
          child: ColoredBox(
            color: DawColors.bg,
            child: Padding(
              // Keep the whole UI inside the safe area and lift it above the soft
              // keyboard, so the extra-keys row sits on the keyboard's top edge.
              padding: EdgeInsets.only(
                top: safe.top,
                bottom: insets.bottom,
                left: safe.left,
                right: safe.right,
              ),
              child: Column(
                children: [
                  _buildToolbar(),
                  _buildTabs(),
                  Expanded(child: _buildRoll()),
                  _buildStatusBar(),
                  _buildAccessory(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoll() {
    switch (_view) {
      case ViewMode.roll:
        return LayoutBuilder(
          builder: (context, constraints) {
            _canvasW = constraints.maxWidth.floor();
            _canvasH = constraints.maxHeight.floor();
            final scene = RollScene(
              project: _project,
              pointer: _pointer,
              layout: _layout,
              view: _view,
              mode: _pointer.mode,
              blinkOn: _blinkOn,
              playCol: _playCol,
              isPlaying: _playing,
              ghostOn: _ghostOn,
              showScale: _showScale,
              scaleName: _project.scaleName,
              scaleRoot: _project.scaleRoot,
              accent: _accent.accent,
              accent2: _accent.accent2,
              statusMessage: _status,
              showCmd: _showCmd,
              revision: _revision,
              boxAnchor: _visualAnchor,
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _onTapAt(d.localPosition),
              onPanUpdate: (d) => _onPanAt(d.localPosition),
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: PianoRollPainter(scene),
              ),
            );
          },
        );
      case ViewMode.mixer:
        return MixerView(
          project: _project,
          layout: _layout,
          view: _view,
          focusManager: _focusManager,
          accent: _accent,
          onChannelChanged: _onMixerChannelChanged,
        );
      case ViewMode.arrangement:
        return ArrangementView(
          project: _project,
          layout: _layout,
          view: _view,
          focusManager: _focusManager,
          accent: _accent,
          tracks: _arrangeTracks,
          cursorTrack: _arrangeCursorTrack,
          cursorStep: _arrangeCursorStep,
          selecting: _arrangeSelecting,
          anchorTrack: _arrangeAnchorTrack,
          anchorStep: _arrangeAnchorStep,
          revision: _revision,
        );
      case ViewMode.pattern:
        return PatternView(
          project: _project,
          layout: _layout,
          view: _view,
          focusManager: _focusManager,
          accent: _accent,
          patterns: _patterns,
          selectedPatternIndex: _selectedPatternIndex,
          onPatternSelect: (i) => setState(() => _selectedPatternIndex = i),
          onPatternChanged: (p) => setState(() {}),
          onAddPattern: () => setState(() {
            _patterns.add(Pattern(name: 'Pattern ${_patterns.length + 1}', color: _accent.accent, steps: 16, pitchRange: 16));
            _selectedPatternIndex = _patterns.length - 1;
          }),
        );
      case ViewMode.sample:
        return BrowserView(
          project: _project,
          layout: _layout,
          view: _view,
          focusManager: _focusManager,
          accent: _accent,
          categories: _browserCategories,
          categoryIndex: _browserCategory,
          entries: _browserEntries,
          selectedIndex: _browserIndex,
          activeProgram: _project.track.instrument,
          onCategoryTap: (i) => setState(() {
            _browserCategory = i;
            _browserIndex = 0;
          }),
          onEntryTap: (i) => setState(() => _browserIndex = i),
        );
      case ViewMode.automation:
        return AutomationView(
          project: _project,
          layout: _layout,
          view: _view,
          focusManager: _focusManager,
          accent: _accent,
          lanes: _autoLanes,
          laneIndex: _autoLaneIndex,
          cursorStep: _autoStep,
          cursorValue: _autoValue,
          onLaneTap: (i) => setState(() => _autoLaneIndex = i),
        );
      case ViewMode.help:
        return _buildPlaceholderView('${_view.label} view coming soon…');
    }
  }

  void _onMixerChannelChanged(MixerChannel ch) {
    // TODO: Wire to audio engine
  }

  Widget _buildPlaceholderView(String msg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasW = constraints.maxWidth.floor();
        _canvasH = constraints.maxHeight.floor();
        return Center(
          child: Text(msg, style: DawFonts.ui.copyWith(color: DawColors.textMuted)),
        );
      },
    );
  }

  // --------------------------------------------------------------- toolbar
  Widget _buildToolbar() {
    return Container(
      height: DawLayout.toolbarH,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Row(
        children: [
          Text('VIMDAW',
              style: DawFonts.display(size: 13, spacing: 2.4)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_project.name} · ${_project.track.name}',
              overflow: TextOverflow.ellipsis,
              style: DawFonts.body(size: 11, color: DawColors.textFaint),
            ),
          ),
          Text(
              '${theory.noteNames[_project.scaleRoot]} ${_project.scaleName}',
              style: DawFonts.body(size: 11, color: DawColors.textFaint)),
          const SizedBox(width: 16),
          Text('${_project.bpm} BPM',
              style: DawFonts.mono(size: 11, color: DawColors.textDim)),
          const SizedBox(width: 16),
          _transportIcon(AppIcons.stop, _stop),
          const SizedBox(width: 12),
          _transportIcon(
            _playing ? AppIcons.pause : AppIcons.play,
            _togglePlay,
            active: _playing,
          ),
        ],
      ),
    );
  }

  Widget _transportIcon(IconData icon, VoidCallback onTap,
      {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 20,
        color: active ? _accent.accent : DawColors.textDim,
      ),
    );
  }

  // -------------------------------------------------------------- tab bar
  Widget _buildTabs() {
    return SizedBox(
      height: DawLayout.tabsH,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final v in ViewMode.values) _viewTab(v),
              ],
            ),
          ),
          _iconToggle(
            AppIcons.ghost,
            _ghostOn,
            () => _handleAction(DawAction.toggleGhost),
          ),
          const SizedBox(width: 14),
          _iconToggle(AppIcons.palette, false, _cyclePalette),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _viewTab(ViewMode v) {
    final active = _view == v;
    return GestureDetector(
      onTap: () => _setView(v),
      child: Container(
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          v.label,
          style: DawFonts.body(
            size: 11,
            weight: active ? FontWeight.w700 : FontWeight.w500,
            spacing: 0.6,
            color: active ? DawColors.text : DawColors.textFaint,
          ),
        ),
      ),
    );
  }

  Widget _iconToggle(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 17,
        color: active ? _accent.accent : DawColors.textFaint,
      ),
    );
  }

  // ------------------------------------------------------------- status bar
  Widget _buildStatusBar() {
    final err = _statusError;
    final msg = _status.isEmpty ? _defaultStatus : _status;
    final cmdMode = _pointer.mode == InputMode.command;
    return Container(
      height: DawLayout.statusH,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Row(
        children: [
          _modeBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: cmdMode
                ? Row(
                    children: [
                      Text(':',
                          style: DawFonts.mono(
                              size: 13,
                              weight: FontWeight.w800,
                              color: _accent.accent)),
                      const SizedBox(width: 4),
                      Text(_commandBuffer,
                          style: DawFonts.mono(size: 13, color: DawColors.text)),
                      if (_blinkOn)
                        Container(
                          width: 8,
                          height: 15,
                          margin: const EdgeInsets.only(left: 2),
                          color: _accent.accent,
                        ),
                    ],
                  )
                : Text(
                    msg,
                    overflow: TextOverflow.ellipsis,
                    style: DawFonts.body(
                      size: 12,
                      color: err ? DawColors.error : DawColors.textDim,
                    ),
                  ),
          ),
          if (!cmdMode && _showCmd.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(_showCmd,
                style: DawFonts.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: _accent.accent)),
          ],
          const SizedBox(width: 12),
          Text(_positionString(),
              style: DawFonts.mono(size: 12, color: DawColors.textFaint)),
        ],
      ),
    );
  }

  String get _defaultStatus =>
      'h j k l move · i draw · x erase · v visual · : command';

  Widget _modeBadge() {
    final active = _pointer.mode != InputMode.normal;
    return Text(
      _pointer.mode.label,
      style: DawFonts.mono(
        size: 11,
        weight: FontWeight.w700,
        color: active ? DawColors.text : DawColors.textFaint,
      ),
    );
  }

  String _positionString() {
    final bar = _pointer.col ~/ _project.stepsPerBar + 1;
    final beat =
        (_pointer.col % _project.stepsPerBar) ~/ _project.stepsPerBeat + 1;
    final pc = ((_pointer.pitch % 12) + 12) % 12;
    const names = [
      'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
    ];
    return '$bar.$beat  ${names[pc]}${(_pointer.pitch ~/ 12) - 1}';
  }

  // ------------------------------------------------------------ accessory
  Widget _buildAccessory() {
    return Container(
      height: DawLayout.accessoryH,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DawColors.borderSoft)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        children: [
          _key('ESC', 'esc'),
          _key('TAB', 'tab'),
          _key('CTRL', 'ctrl', active: _grabActive),
          _key('ALT', 'alt', active: _stickyAlt),
          _key('SHIFT', 'shift', active: _stickyShift),
          _key('', 'left', icon: AppIcons.arrowLeft),
          _key('', 'up', icon: AppIcons.arrowUp),
          _key('', 'down', icon: AppIcons.arrowDown),
          _key('', 'right', icon: AppIcons.arrowRight),
          _key('', 'home', icon: AppIcons.home),
          _key('', 'end', icon: AppIcons.end),
          _key('', 'command', icon: AppIcons.command),
          _key('', 'palette', icon: AppIcons.palette),
        ],
      ),
    );
  }

  Widget _key(String label, String action,
      {bool active = false, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => _handleAccessory(action),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? _accent.accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? _accent.accent : DawColors.border,
            ),
          ),
          child: icon != null
              ? Icon(icon,
                  size: 16,
                  color: active ? _accent.accent : DawColors.textDim)
              : Text(
                  label,
                  style: DawFonts.body(
                    size: 12,
                    weight: FontWeight.w600,
                    spacing: 0.5,
                    color: active ? _accent.accent : DawColors.textDim,
                  ),
                ),
        ),
      ),
    );
  }
}
