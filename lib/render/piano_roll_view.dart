import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../input/daw_input.dart';
import '../model/project.dart';
import '../music_theory.dart' as theory;
import '../ui/daw_theme.dart';
import 'roll_layout.dart';

/// Everything the roll painter needs for one frame. The painter is a pure
/// function of this state, which keeps repaints cheap and tests deterministic.
class RollScene {
  final Project project;
  final GridPointer pointer;
  final RollLayout layout;
  final ViewMode view;
  final InputMode mode;
  final bool blinkOn;
  final int playCol;
  final bool isPlaying;
  final bool ghostOn;
  final bool showScale;
  final String scaleName;
  final int scaleRoot;
  final Color accent;
  final Color accent2;
  final String statusMessage;
  final String showCmd;
  final int revision;

  /// Corner a visual/box selection was anchored at, if any. The painter draws
  /// the live rectangle from this corner to the pointer.
  final ({int pitch, int col})? boxAnchor;

  const RollScene({
    required this.project,
    required this.pointer,
    required this.layout,
    required this.view,
    required this.mode,
    required this.blinkOn,
    required this.playCol,
    required this.isPlaying,
    required this.ghostOn,
    required this.showScale,
    required this.scaleName,
    required this.scaleRoot,
    required this.accent,
    required this.accent2,
    required this.statusMessage,
    required this.showCmd,
    required this.revision,
    this.boxAnchor,
  });
}

/// Native-resolution piano-roll renderer: crisp vector geometry, a real piano
/// keyboard gutter, a bar/beat ruler and modern note blocks.
class PianoRollPainter extends CustomPainter {
  final RollScene scene;

  PianoRollPainter(this.scene);

  late RollLayout _l;

  static const List<String> _names = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _l = scene.layout;

    canvas.drawRect(Offset.zero & size, Paint()..color = DawColors.rollBg);

    if (scene.view == ViewMode.roll) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
        _l.gridX.toDouble(),
        _l.gridY.toDouble(),
        _l.gridW.toDouble(),
        _l.gridH.toDouble(),
      ));
      _drawRows(canvas);
      _drawColumns(canvas);
      _drawNotes(canvas);
      _drawBox(canvas);
      _drawPlayhead(canvas);
      _drawCursor(canvas);
      canvas.restore();
      _drawKeys(canvas);
      _drawRuler(canvas);
    } else if (scene.view == ViewMode.help) {
      _drawHelp(canvas, size);
    } else {
      _drawPlaceholder(canvas, size);
    }
  }

  // ------------------------------------------------------------- background
  // The roll is a plain cell grid: one drawn box per pitch row × 16th step.
  // Fill pass shades the rows; the line passes trace every cell border so the
  // grid reads precisely, with beats and bars emphasised.
  void _drawRows(Canvas canvas) {
    final l = _l;
    final intervals = theory.scales[scene.scaleName] ?? theory.scales['Major']!;
    final gx = l.gridX.toDouble();
    final gw = l.gridW.toDouble();
    final h = RollLayout.cellH.toDouble();

    for (var pitch = l.viewLowPitch; pitch <= l.topPitch; pitch++) {
      final y = l.yForPitch(pitch).toDouble();
      final pc = ((pitch % 12) + 12) % 12;
      final inScale =
          intervals.contains(((pc - scene.scaleRoot) % 12 + 12) % 12);
      final black = _isBlack(pc);

      Color row = black ? DawColors.rowBlack : DawColors.rowWhite;
      if (scene.showScale && inScale) row = DawColors.rowScale;

      canvas.drawRect(Rect.fromLTWH(gx, y, gw, h), Paint()..color = row);
    }

    // Row borders on exact cell boundaries (plus the bottom edge).
    for (var pitch = l.viewLowPitch - 1; pitch <= l.topPitch; pitch++) {
      final y = l.yForPitch(pitch).toDouble();
      final pc = ((pitch % 12) + 12) % 12;
      final isOctave = pc == 11 && pitch >= l.viewLowPitch;
      canvas.drawRect(
        Rect.fromLTWH(gx, y, gw, 1),
        Paint()..color = isOctave ? DawColors.octaveLine : DawColors.rowLine,
      );
    }
  }

  bool _isBlack(int pc) =>
      pc == 1 || pc == 3 || pc == 6 || pc == 8 || pc == 10;

  // ------------------------------------------------------------ column grid
  void _drawColumns(Canvas canvas) {
    final l = _l;
    final stepPerBeat = scene.project.stepsPerBeat;
    final stepPerBar = scene.project.stepsPerBar;
    final gridTop = l.gridY.toDouble();
    final gridH = l.gridH.toDouble();

    for (var c = 0; c <= l.cols; c++) {
      final col = l.viewCol + c;
      final x = l.xForCol(col).toDouble();
      final inBar = col % stepPerBar == 0;
      final inBeat = col % stepPerBeat == 0;

      final color = inBar
          ? DawColors.barLine
          : inBeat
              ? DawColors.beatLine
              : DawColors.stepLine;
      canvas.drawRect(
        Rect.fromLTWH(x, gridTop, 1, gridH),
        Paint()..color = color,
      );
    }
  }

  // ------------------------------------------------------------------ notes
  void _drawNotes(Canvas canvas) {
    if (scene.ghostOn) {
      for (final ghost in scene.project.ghostNotes) {
        _drawNote(canvas, ghost.note, ghost: true, selected: false);
      }
    }
    for (final note in scene.project.track.notes) {
      final selected = scene.project.selection.contains(note);
      _drawNote(canvas, note, ghost: false, selected: selected);
    }
  }

  void _drawNote(
    Canvas canvas,
    Note note, {
    required bool ghost,
    required bool selected,
  }) {
    final l = _l;
    if (note.pitch < l.viewLowPitch || note.pitch > l.topPitch) return;
    final x = l.xForCol(note.start).toDouble();
    final y = l.yForPitch(note.pitch).toDouble();
    final w = note.len * RollLayout.cellW.toDouble();
    final h = RollLayout.cellH - 3.0;
    if (x + w < l.gridX || x > l.gridX + l.gridW) return;

    final rect = Rect.fromLTWH(x + 1, y + 1.5, w - 2, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    if (ghost) {
      canvas.drawRRect(
        rrect,
        Paint()..color = DawColors.textFaint.withValues(alpha: 0.10),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = DawColors.textFaint.withValues(alpha: 0.4),
      );
      return;
    }

    // Flat body. Unselected notes dim when something else is selected so the
    // active selection reads clearly.
    final hasSelection = scene.project.selection.isNotEmpty;
    final body = selected ? scene.accent : DawColors.noteBody;
    final faded = hasSelection && !selected;
    canvas.drawRRect(
      rrect,
      Paint()..color = faded ? body.withValues(alpha: 0.45) : body,
    );

    // Selected notes get an accent halo plus a bright outline.
    if (selected) {
      canvas.drawRRect(
        rrect.inflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = scene.accent2.withValues(alpha: 0.9),
      );
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1
        ..color = selected ? DawColors.text : DawColors.noteEdge,
    );

    // Scale-degree label when the note is wide enough.
    if (w >= 22 && h >= 10) {
      _text(
        canvas,
        _noteLabel(note.pitch),
        x + 7,
        y + 3,
        color: body.computeLuminance() > 0.5
            ? const Color(0xCC000000)
            : const Color(0xE6FFFFFF),
        size: 9,
        weight: FontWeight.w600,
      );
    }
  }

  String _pitchName(int pitch) =>
      '${_names[((pitch % 12) + 12) % 12]}${(pitch ~/ 12) - 1}';

  /// Note label as a scale degree (`1`…`7`, with `b`/`#` for chromatic
  /// alterations) relative to the project key, falling back to the pitch name
  /// when the note has no relationship to the scale.
  String _noteLabel(int pitch) {
    final pc = ((pitch % 12) + 12) % 12;
    final deg = theory.scaleDegree(pc, scene.scaleRoot, scene.scaleName);
    if (deg != null) return '$deg';
    final flat = theory.scaleDegree(pc + 1, scene.scaleRoot, scene.scaleName);
    if (flat != null) return 'b$flat';
    final sharp = theory.scaleDegree(pc - 1, scene.scaleRoot, scene.scaleName);
    if (sharp != null) return '#$sharp';
    return _pitchName(pitch);
  }

  // ------------------------------------------------------------ box select
  void _drawBox(Canvas canvas) {
    final anchor = scene.boxAnchor;
    if (anchor == null) return;
    if (scene.mode != InputMode.visual &&
        scene.mode != InputMode.visualLine) {
      return;
    }
    final l = _l;
    final p0 = math.min(anchor.pitch, scene.pointer.pitch);
    final p1 = math.max(anchor.pitch, scene.pointer.pitch);
    final c0 = math.min(anchor.col, scene.pointer.col);
    final c1 = math.max(anchor.col, scene.pointer.col);
    final rect = Rect.fromLTRB(
      l.xForCol(c0).toDouble(),
      l.yForPitch(p1).toDouble(),
      l.xForCol(c1).toDouble() + RollLayout.cellW,
      l.yForPitch(p0).toDouble() + RollLayout.cellH,
    );
    final box = scene.accent2;
    canvas.drawRect(rect, Paint()..color = box.withValues(alpha: 0.18));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = box,
    );

    // Corner ticks so the dragged region reads even over empty cells.
    const tick = 7.0;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = box;
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft,
        rect.bottomRight]) {
      final sx = c.dx == rect.left ? 1.0 : -1.0;
      final sy = c.dy == rect.top ? 1.0 : -1.0;
      canvas.drawLine(c, c.translate(tick * sx, 0), stroke);
      canvas.drawLine(c, c.translate(0, tick * sy), stroke);
    }
  }

  // --------------------------------------------------------------- playhead
  void _drawPlayhead(Canvas canvas) {
    final l = _l;
    final x = l.xForCol(scene.playCol).toDouble();
    if (x < l.gridX || x > l.gridX + l.gridW) return;
    final gridTop = l.gridY.toDouble();
    final gridH = l.gridH.toDouble();

    final color = scene.isPlaying ? DawColors.playhead : DawColors.border;
    canvas.drawRect(
      Rect.fromLTWH(x, gridTop, 1.5, gridH),
      Paint()..color = color,
    );
  }

  // ----------------------------------------------------------------- cursor
  void _drawCursor(Canvas canvas) {
    final l = _l;
    final p = scene.pointer;
    final visual =
        scene.mode == InputMode.visual || scene.mode == InputMode.visualLine;
    final color = visual ? scene.accent2 : scene.accent;

    final gridTop = l.gridY.toDouble();
    final gridH = l.gridH.toDouble();
    final gridLeft = l.gridX.toDouble();
    final gridW = l.gridW.toDouble();
    final cellW = RollLayout.cellW.toDouble();
    final cellH = RollLayout.cellH.toDouble();

    // Column + row bands make the cursor position obvious at a glance.
    final cx = l.xForCol(p.col).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(cx, gridTop, cellW, gridH),
      Paint()..color = color.withValues(alpha: 0.06),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx, gridTop, 1.5, gridH),
      Paint()..color = color.withValues(alpha: 0.5),
    );

    if (p.pitch >= l.viewLowPitch && p.pitch <= l.topPitch) {
      final cy = l.yForPitch(p.pitch).toDouble();
      canvas.drawRect(
        Rect.fromLTWH(gridLeft, cy, gridW, cellH),
        Paint()..color = color.withValues(alpha: 0.06),
      );
      canvas.drawRect(
        Rect.fromLTWH(gridLeft, cy, gridW, 1.5),
        Paint()..color = color.withValues(alpha: 0.5),
      );

      // The cell under the pointer: filled + a bold blinking outline.
      canvas.drawRect(
        Rect.fromLTWH(cx + 1, cy + 1, cellW - 2, cellH - 2),
        Paint()..color = color.withValues(alpha: scene.blinkOn ? 0.28 : 0.14),
      );
      canvas.drawRect(
        Rect.fromLTWH(cx + 1, cy + 1, cellW - 2, cellH - 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: scene.blinkOn ? 1 : 0.5),
      );
    }
  }

  // ------------------------------------------------------------ piano keys
  void _drawKeys(Canvas canvas) {
    final l = _l;
    final keyW = RollLayout.keyW.toDouble();
    final height = l.height.toDouble();

    canvas.drawRect(
      Rect.fromLTWH(0, 0, keyW, height),
      Paint()..color = DawColors.surface,
    );

    for (var pitch = l.viewLowPitch; pitch <= l.topPitch; pitch++) {
      final y = l.yForPitch(pitch).toDouble();
      final pc = ((pitch % 12) + 12) % 12;
      final black = _isBlack(pc);
      final isRoot = pc == 0;
      final underCursor = pitch == scene.pointer.pitch;

      if (black) {
        final rect = Rect.fromLTWH(2, y + 1.5, keyW - 18, RollLayout.cellH - 3.0);
        final r = RRect.fromRectAndRadius(rect, const Radius.circular(2));
        canvas.drawRRect(
          r,
          Paint()..color = underCursor ? scene.accent : DawColors.keyBlack,
        );
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF0A0A0C),
        );
      } else {
        final rect = Rect.fromLTWH(1, y + 0.5, keyW - 6, RollLayout.cellH - 1.0);
        final r = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
        canvas.drawRRect(
          r,
          Paint()..color = underCursor ? scene.accent : DawColors.keyWhite,
        );
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = DawColors.keyWhiteEdge.withValues(alpha: 0.6),
        );
      }

      // Every key gets a vertical (rotated) note label so the narrow gutter
      // stays readable. C keys are emphasised.
      final labelColor = underCursor
          ? (black ? const Color(0xE6FFFFFF) : const Color(0xE6000000))
          : black
              ? DawColors.textFaint
              : (isRoot ? DawColors.keyLabel : DawColors.textFaint);
      _textVertical(
        canvas,
        _pitchName(pitch),
        black ? 21 : 13,
        y + RollLayout.cellH / 2,
        color: labelColor,
        size: isRoot ? 9.5 : 8.5,
        weight: isRoot ? FontWeight.w700 : FontWeight.w500,
      );
    }

    // Hard gutter edge separating the keys from the grid.
    canvas.drawRect(
      Rect.fromLTWH(keyW - 1, 0, 1, height),
      Paint()..color = DawColors.border,
    );
  }

  // ------------------------------------------------------------------ ruler
  void _drawRuler(Canvas canvas) {
    final l = _l;
    final width = l.width.toDouble();
    final rulerH = RollLayout.rulerH.toDouble();

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, rulerH),
      Paint()..color = DawColors.surfaceAlt,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, rulerH - 1, width, 1),
      Paint()..color = DawColors.border,
    );

    final stepPerBar = scene.project.stepsPerBar;
    final stepPerBeat = scene.project.stepsPerBeat;
    for (var c = 0; c <= l.cols; c++) {
      final col = l.viewCol + c;
      final x = l.xForCol(col).toDouble();
      if (x < RollLayout.keyW) continue;

      if (col % stepPerBar == 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, 3, 1, rulerH - 3),
          Paint()..color = DawColors.textDim,
        );
        _text(canvas, '${col ~/ stepPerBar + 1}', x + 5, 5,
            color: DawColors.text, size: 11, weight: FontWeight.w700);
      } else if (col % stepPerBeat == 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, 13, 1, rulerH - 13),
          Paint()..color = DawColors.textFaint,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(x, 17, 1, rulerH - 17),
          Paint()..color = DawColors.borderSoft,
        );
      }
    }

  }

  // ------------------------------------------------------------------ misc
  void _drawPlaceholder(Canvas canvas, Size size) {
    _text(canvas, scene.view.label, size.width / 2, size.height / 2 - 10,
        color: scene.accent, size: 18, weight: FontWeight.w700, center: true);
    _text(canvas, 'coming in a later milestone', size.width / 2,
        size.height / 2 + 12,
        color: DawColors.textFaint, size: 12, center: true);
  }

  void _drawHelp(Canvas canvas, Size size) {
    const lines = [
      ('h j k l', 'move pointer'),
      ('shift + move', 'beat / octave'),
      ('w / b', 'next / prev note'),
      ('0 / \$', 'bar start / end'),
      ('gg / G', 'lowest / highest'),
      ('i / space', 'draw · on a selection: cycle note value'),
      ('i (selected)', '1/32 1/16 1/8 1/4 1/2 1'),
      ('x', 'erase'),
      ('r', 'replace pitch'),
      ('CTRL', 'note/empty → grab/box · move · CTRL release'),
      ('c then M/m', 'chord mode: major / minor'),
      ('c then a/d/s/t', 'aug · dim · 7 · maj7'),
      ('[ / ]', 'shorter / longer note(s)'),
      ('v / V', 'visual select'),
      ('d / y / p', 'delete / yank / paste'),
      ('enter', 'play / pause'),
      ('.', 'stop'),
      ('u / ctrl+r', 'undo / redo'),
      (':', 'command line'),
      (':bpm N', 'tempo'),
      (':len N', 'note length'),
      (':scale D Minor', 'project key signature'),
      (':chord m7', 'harmonise selection (Major default)'),
      (':pal name', 'theme'),
      (':ctrl+1.1-E4,1.2-C4', 'box select · grab until CTRL'),
      ('ctrl + 1..7', 'switch view'),
      ('esc', 'back to normal'),
    ];
    var y = 18.0;
    for (final line in lines) {
      _text(canvas, line.$1, 20, y, color: scene.accent, size: 13);
      _text(canvas, line.$2, 170, y, color: DawColors.textDim, size: 13);
      y += 22;
      if (y > size.height - 20) break;
    }
    _text(canvas, 'VIMDAW — key reference', size.width / 2, size.height - 26,
        color: DawColors.textFaint, size: 11, center: true);
  }

  void _text(
    Canvas canvas,
    String text,
    double x,
    double y, {
    required Color color,
    double size = 12,
    FontWeight weight = FontWeight.w500,
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center ? x - tp.width / 2 : x, y));
  }

  /// Draws [text] rotated a quarter-turn (reading bottom-to-top), centred on
  /// (x, centerY). Used for the piano-key labels in the narrow key gutter.
  void _textVertical(
    Canvas canvas,
    String text,
    double x,
    double centerY, {
    required Color color,
    double size = 9,
    FontWeight weight = FontWeight.w500,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(x, centerY);
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PianoRollPainter old) =>
      old.scene.revision != scene.revision ||
      old.scene.blinkOn != scene.blinkOn ||
      old.scene.accent != scene.accent ||
      old.scene.playCol != scene.playCol ||
      old.scene.isPlaying != scene.isPlaying ||
      old.scene.layout.width != scene.layout.width ||
      old.scene.layout.height != scene.layout.height;
}
