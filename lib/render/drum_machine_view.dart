/// The drum machine: the piano-roll grid with a column of sound pads down
/// the left instead of piano keys. Rows are pads the player adds (kick,
/// snare, …), columns are 16th-note steps and a tap toggles a hit.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerScrollEvent;
import 'package:flutter/material.dart';

import '../input/daw_input.dart';
import '../model/drum_map.dart';
import '../model/project.dart';
import '../ui/daw_theme.dart';
import 'roll_layout.dart';

/// Gutter width for the drum machine's sound names.
const int drumGutterW = 96;

/// Everything the drum-machine painter needs for one frame.
class DrumScene {
  final Project project;
  final List<DrumPad> pads;
  final GridPointer pointer;
  final RollLayout layout;
  final Color accent;
  final Color accent2;
  final int playCol;
  final bool isPlaying;
  final bool blinkOn;
  final int revision;

  /// First pad drawn at the top of the grid (the gutter scrolls).
  final int padOffset;

  /// Pad row under the cursor, and the step column under it.
  final int cursorPad;
  final int cursorCol;

  const DrumScene({
    required this.project,
    required this.pads,
    required this.pointer,
    required this.layout,
    required this.accent,
    required this.accent2,
    required this.playCol,
    required this.isPlaying,
    required this.blinkOn,
    required this.revision,
    required this.padOffset,
    required this.cursorPad,
    required this.cursorCol,
  });

  int get padCount => pads.length;
  int get visibleRows => math.max(0, padCount - padOffset);
}

/// Vector renderer for the drum-machine surface: ruler, step grid, hit
/// blocks, cursor and playhead. The sound-name gutter is drawn by widgets on
/// top of this (see [DrumMachineView]).
class DrumMachinePainter extends CustomPainter {
  final DrumScene scene;

  DrumMachinePainter(this.scene);

  late RollLayout _l;

  @override
  void paint(Canvas canvas, Size size) {
    _l = scene.layout;
    final l = _l;

    canvas.drawRect(Offset.zero & size, Paint()..color = DawColors.rollBg);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
      l.gridX.toDouble(),
      l.gridY.toDouble(),
      l.gridW.toDouble(),
      l.gridH.toDouble(),
    ));
    _drawRows(canvas);
    _drawColumns(canvas);
    _drawNotes(canvas);
    _drawPlayhead(canvas);
    _drawCursor(canvas);
    canvas.restore();

    _drawRuler(canvas);

    // Hard edge between the pads and the grid.
    canvas.drawRect(
      Rect.fromLTWH(l.gridX - 1, 0, 1, size.height),
      Paint()..color = DawColors.border,
    );
  }

  // ------------------------------------------------------------ background
  void _drawRows(Canvas canvas) {
    final l = _l;
    final gx = l.gridX.toDouble();
    final gw = l.gridW.toDouble();
    final h = RollLayout.cellH.toDouble();
    final padRows = scene.visibleRows;

    for (var i = 0; i < l.rows; i++) {
      final y = l.gridY + i * h;
      final isPad = i < padRows;
      // Rows with no pad behind them read as "nothing to hit here".
      final row = !isPad
          ? const Color(0xFF0A0A0C)
          : i.isEven
              ? DawColors.rowWhite
              : DawColors.rowBlack;
      canvas.drawRect(Rect.fromLTWH(gx, y, gw, h), Paint()..color = row);
      canvas.drawRect(
        Rect.fromLTWH(gx, y, gw, 1),
        Paint()
          ..color = isPad ? DawColors.rowLine : const Color(0xFF141417),
      );
    }
  }

  // ------------------------------------------------------------ columns
  void _drawColumns(Canvas canvas) {
    final l = _l;
    final stepPerBeat = scene.project.stepsPerBeat;
    final stepPerBar = scene.project.stepsPerBar;
    final gridTop = l.gridY.toDouble();
    final gridH = l.gridH.toDouble();

    for (var c = 0; c <= l.cols; c++) {
      final col = l.viewCol + c;
      final x = l.xForCol(col).toDouble();
      final color = col % stepPerBar == 0
          ? DawColors.barLine
          : col % stepPerBeat == 0
              ? DawColors.beatLine
              : DawColors.stepLine;
      canvas.drawRect(Rect.fromLTWH(x, gridTop, 1, gridH), Paint()..color = color);
    }
  }

  // ---------------------------------------------------------------- hits
  void _drawNotes(Canvas canvas) {
    final l = _l;
    final cellW = RollLayout.cellW.toDouble();
    final cellH = RollLayout.cellH.toDouble();
    final first = scene.padOffset;
    final last = math.min(scene.padCount, first + l.rows);

    void block(int pitch, double y, Color body, {required bool outline}) {
      for (final note in scene.project.track.notes) {
        if (note.pitch != pitch) continue;
        if (note.start + note.len <= l.viewCol ||
            note.start >= l.viewCol + l.cols + 1) {
          continue;
        }
        final x = l.xForCol(note.start).toDouble();
        final w = math.max(cellW - 2, note.len * cellW - 2);
        final rect = Rect.fromLTWH(x + 1, y + 1.5, w, cellH - 3);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        canvas.drawRRect(rrect, Paint()..color = body);
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outline ? 2 : 1
            ..color = outline ? scene.accent2 : DawColors.noteEdge,
        );
      }
    }

    for (var i = 0; i < last - first; i++) {
      final padIndex = first + i;
      final pitch = scene.pads[padIndex].pitch;
      final y = l.gridY + i * cellH;
      final selected = scene.project.selection.any((n) => n.pitch == pitch);
      final body = selected ? scene.accent : DawColors.noteBody;
      block(pitch, y, body, outline: selected);
    }
  }

  // ------------------------------------------------------------- playhead
  void _drawPlayhead(Canvas canvas) {
    final l = _l;
    final x = l.xForCol(scene.playCol).toDouble();
    if (x < l.gridX || x > l.gridX + l.gridW) return;
    canvas.drawRect(
      Rect.fromLTWH(
        x,
        l.gridY.toDouble(),
        1.5,
        l.gridH.toDouble(),
      ),
      Paint()..color = scene.isPlaying ? DawColors.playhead : DawColors.border,
    );
  }

  // --------------------------------------------------------------- cursor
  void _drawCursor(Canvas canvas) {
    final l = _l;
    final color = scene.accent;
    final gridTop = l.gridY.toDouble();
    final gridH = l.gridH.toDouble();
    final gridLeft = l.gridX.toDouble();
    final gridW = l.gridW.toDouble();
    final cellW = RollLayout.cellW.toDouble();
    final cellH = RollLayout.cellH.toDouble();

    // Step band down the whole grid.
    final cx = l.xForCol(scene.cursorCol).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(cx, gridTop, cellW, gridH),
      Paint()..color = color.withValues(alpha: 0.06),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx, gridTop, 1.5, gridH),
      Paint()..color = color.withValues(alpha: 0.5),
    );

    final row = scene.cursorPad - scene.padOffset;
    if (scene.cursorPad < 0 ||
        scene.cursorPad >= scene.padCount ||
        row < 0 ||
        row >= l.rows) {
      return;
    }
    final cy = l.gridY + row * cellH;
    canvas.drawRect(
      Rect.fromLTWH(gridLeft, cy, gridW, cellH),
      Paint()..color = color.withValues(alpha: 0.06),
    );
    canvas.drawRect(
      Rect.fromLTWH(gridLeft, cy, gridW, 1.5),
      Paint()..color = color.withValues(alpha: 0.5),
    );
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

  // ---------------------------------------------------------------- ruler
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
      if (x < l.gridX) continue;
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

  void _text(
    Canvas canvas,
    String text,
    double x,
    double y, {
    required Color color,
    double size = 12,
    FontWeight weight = FontWeight.w500,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant DrumMachinePainter old) =>
      old.scene.revision != scene.revision ||
      old.scene.blinkOn != scene.blinkOn ||
      old.scene.accent != scene.accent ||
      old.scene.playCol != scene.playCol ||
      old.scene.isPlaying != scene.isPlaying ||
      old.scene.padOffset != scene.padOffset ||
      old.scene.cursorPad != scene.cursorPad ||
      old.scene.cursorCol != scene.cursorCol ||
      old.scene.padCount != scene.padCount ||
      old.scene.layout.width != scene.layout.width ||
      old.scene.layout.height != scene.layout.height;
}

// ---------------------------------------------------------------- widgets
/// The drum-machine surface: grid + ruler under the pad gutter, an `+` button
/// in the corner and a scrollable column of sound pads down the left.
class DrumMachineView extends StatelessWidget {
  final DrumScene scene;
  final void Function(Offset local) onTapUp;
  final void Function(Offset local) onLongPressStart;
  final void Function(Offset local) onPanStart;
  final void Function(Offset local) onPanUpdate;
  final void Function(Offset local) onPanEnd;
  final void Function(PointerScrollEvent event) onPointerSignal;
  final void Function(int padIndex) onPadTap;
  final void Function(int padIndex) onPadRemove;
  final void Function(double deltaDy) onGutterScroll;
  final VoidCallback onAddPad;

  const DrumMachineView({
    super.key,
    required this.scene,
    required this.onTapUp,
    required this.onLongPressStart,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPointerSignal,
    required this.onPadTap,
    required this.onPadRemove,
    required this.onGutterScroll,
    required this.onAddPad,
  });

  @override
  Widget build(BuildContext context) {
    final l = scene.layout;
    final gutterW = l.gutterW.toDouble();
    final rulerH = RollLayout.rulerH.toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Grid + ruler.
        Positioned.fill(
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) onPointerSignal(e);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: (d) => onTapUp(d.localPosition),
              onLongPressStart: (d) => onLongPressStart(d.localPosition),
              onPanStart: (d) => onPanStart(d.localPosition),
              onPanUpdate: (d) => onPanUpdate(d.localPosition),
              onPanEnd: (d) => onPanEnd(d.localPosition),
              child: CustomPaint(
                size: Size.infinite,
                painter: DrumMachinePainter(scene),
              ),
            ),
          ),
        ),
        // Corner button: add another sound.
        Positioned(
          left: 0,
          top: 0,
          width: gutterW,
          height: rulerH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAddPad,
            child: Container(
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: DawColors.surface,
                border: Border(
                  right: BorderSide(color: DawColors.border),
                  bottom: BorderSide(color: DawColors.border),
                ),
              ),
              child: Text(
                '+ SOUND',
                style: DawFonts.mono(
                  size: 9,
                  weight: FontWeight.w700,
                  color: scene.accent,
                ),
              ),
            ),
          ),
        ),
        // Sound pads.
        Positioned(
          left: 0,
          top: rulerH,
          width: gutterW,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => onGutterScroll(d.delta.dy),
            child: Container(
              color: DawColors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < scene.visibleRows; i++)
                    _PadRow(
                      pad: scene.pads[scene.padOffset + i],
                      project: scene.project,
                      selected: scene.padOffset + i == scene.cursorPad,
                      accent: scene.accent,
                      onTap: () => onPadTap(scene.padOffset + i),
                      onRemove: () => onPadRemove(scene.padOffset + i),
                    ),
                  Expanded(child: _addHint()),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Inert pointer at the corner button — the grid itself never opens the
  /// picker, so a stray tap can't throw the dialog up mid-beat.
  Widget _addHint() {
    return Container(
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        '+ SOUND\nis top-left',
        textAlign: TextAlign.center,
        style: DawFonts.mono(
          size: 9,
          weight: FontWeight.w600,
          color: DawColors.textFaint,
          spacing: 0.4,
        ),
      ),
    );
  }
}

class _PadRow extends StatelessWidget {
  final DrumPad pad;
  final Project project;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PadRow({
    required this.pad,
    required this.project,
    required this.selected,
    required this.accent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasNote = project.track.notes.any((n) => n.pitch == pad.pitch);
    Color bg = hasNote
        ? accent.withValues(alpha: 0.22)
        : DawColors.surfaceAlt;
    if (selected) bg = accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: (_) => onRemove(),
      child: Container(
        height: RollLayout.cellH.toDouble(),
        padding: const EdgeInsets.only(left: 7, right: 2),
        decoration: BoxDecoration(
          color: bg,
          border: const Border(
            bottom: BorderSide(color: DawColors.borderSoft),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                pad.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DawFonts.mono(
                  size: 8.5,
                  weight: FontWeight.w700,
                  color: selected ? const Color(0xE6000000) : DawColors.text,
                  spacing: 0.2,
                ),
              ),
            ),
            Text(
              '${pad.pitch}',
              style: DawFonts.mono(
                size: 7.5,
                weight: FontWeight.w500,
                color: selected
                    ? const Color(0x99000000)
                    : DawColors.textFaint,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: SizedBox(
                width: 13,
                height: RollLayout.cellH.toDouble(),
                child: Center(
                  child: Text(
                    '×',
                    style: DawFonts.mono(
                      size: 11,
                      weight: FontWeight.w700,
                      color: selected
                          ? const Color(0x99000000)
                          : DawColors.textFaint,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picker for the `+ SOUND` button: a free-form name/note row on top of the
/// full GM percussion list.
class DrumPadPicker extends StatefulWidget {
  final List<DrumPad> current;
  final void Function(DrumPad pad) onSelected;

  const DrumPadPicker({
    super.key,
    required this.current,
    required this.onSelected,
  });

  @override
  State<DrumPadPicker> createState() => _DrumPadPickerState();
}

class _DrumPadPickerState extends State<DrumPadPicker> {
  final TextEditingController _name = TextEditingController(text: 'KICK');
  final TextEditingController _note = TextEditingController(text: '36');

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _onPad(DrumPad pad) {
    widget.onSelected(pad);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final onMachine = {for (final p in widget.current) p.pitch};
    final seen = <int>{};

    return Container(
      width: 360,
      height: 440,
      decoration: BoxDecoration(
        color: DawColors.surface,
        borderRadius: BorderRadius.circular(DawLayout.radius),
        border: Border.all(color: DawColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ADD SOUND',
              style: DawFonts.display(size: 12, spacing: 1.6)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  style: DawFonts.mono(size: 11, color: DawColors.text),
                  decoration: _fieldDecoration('name'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _note,
                  keyboardType: TextInputType.number,
                  style: DawFonts.mono(size: 11, color: DawColors.text),
                  decoration: _fieldDecoration('note'),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final name = _name.text.trim().toUpperCase();
                  final note = int.tryParse(_note.text.trim());
                  if (name.isEmpty || note == null || note < 0 || note > 127) {
                    return;
                  }
                  _onPad(DrumPad(name, note.clamp(0, 127)));
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: DawColors.text.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: DawColors.border),
                  ),
                  child: Text('ADD',
                      style: DawFonts.mono(
                          size: 11,
                          weight: FontWeight.w700,
                          color: DawColors.text)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final pad in gmDrumPads)
                  if (seen.add(pad.pitch))
                    _gmRow(pad, onMachine.contains(pad.pitch)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gmRow(DrumPad pad, bool added) {
    return InkWell(
      onTap: () => _onPad(pad),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DawColors.borderSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                pad.name,
                style: DawFonts.mono(
                    size: 11,
                    color: added ? DawColors.textFaint : DawColors.text),
              ),
            ),
            Text('${pad.pitch}',
                style: DawFonts.mono(
                    size: 10, color: DawColors.textFaint)),
            const SizedBox(width: 8),
            Text(
              added ? 'ON' : 'ADD',
              style: DawFonts.mono(
                size: 10,
                weight: FontWeight.w700,
                color: added ? DawColors.ok : DawColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        hintStyle: DawFonts.mono(size: 11, color: DawColors.textFaint),
        filled: true,
        fillColor: DawColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: DawColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: DawColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: DawColors.text),
        ),
      );
}
