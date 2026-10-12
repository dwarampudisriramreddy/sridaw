import 'package:flutter/material.dart';

import '../input/daw_input.dart';
import '../model/project.dart';
import '../ui/daw_theme.dart';
import '../ui/focus_manager.dart' as focus_mgr;
import 'roll_layout.dart';

/// A clip on the arrangement timeline.
class ArrangementClip {
  final String name;
  int trackIndex;
  int start; // in 16th-note steps
  int length; // in 16th-note steps
  final Color color;
  final String? sourcePatternId; // link to pattern
  bool selected = false;

  ArrangementClip({
    required this.name,
    required this.trackIndex,
    required this.start,
    required this.length,
    required this.color,
    this.sourcePatternId,
  });

  int get end => start + length;

  ArrangementClip copyWith({
    int? trackIndex,
    int? start,
    int? length,
    bool? selected,
  }) => ArrangementClip(
    name: name,
    trackIndex: trackIndex ?? this.trackIndex,
    start: start ?? this.start,
    length: length ?? this.length,
    color: color,
    sourcePatternId: sourcePatternId,
  )..selected = selected ?? this.selected;
}

/// Track in the arrangement.
class ArrangementTrack {
  final String name;
  final Color color;
  final List<ArrangementClip> clips = [];
  bool mute = false;
  bool solo = false;
  bool recArm = false;
  double volume = 0.0; // dB
  double pan = 0.0;

  ArrangementTrack({required this.name, required this.color});
}

class ArrangementView extends StatefulWidget {
  final Project project;
  final RollLayout layout;
  final ViewMode view;
  final focus_mgr.FocusManager focusManager;
  final DawAccent accent;
  final List<ArrangementTrack> tracks;
  final int cursorTrack;
  final int cursorStep;
  final bool selecting;
  final int? anchorTrack;
  final int? anchorStep;
  final int revision;
  final VoidCallback? onAddTrack;
  final void Function(int trackIndex, ArrangementClip)? onClipTap;
  final void Function(int trackIndex, ArrangementClip, int newStart, int newLength)? onClipMoveResize;
  final void Function(int trackIndex, ArrangementClip)? onClipDelete;

  const ArrangementView({
    super.key,
    required this.project,
    required this.layout,
    required this.view,
    required this.focusManager,
    required this.accent,
    required this.tracks,
    this.cursorTrack = 0,
    this.cursorStep = 0,
    this.selecting = false,
    this.anchorTrack,
    this.anchorStep,
    this.revision = 0,
    this.onAddTrack,
    this.onClipTap,
    this.onClipMoveResize,
    this.onClipDelete,
  });

  @override
  State<ArrangementView> createState() => _ArrangementViewState();
}

class _ArrangementViewState extends State<ArrangementView> {
  List<ArrangementTrack> get _tracks => widget.tracks;

  int _barWidth = 120; // pixels per bar (4 beats = 16 steps)
  int _trackHeight = 80;
  int _headerWidth = 180;
  int _rulerHeight = 32;

  int get _totalSteps => widget.project.totalSteps;
  int get _bars => (_totalSteps / widget.project.stepsPerBar).ceil();

  @override
  Widget build(BuildContext context) {
    final w = widget.layout.width.toDouble();
    final h = widget.layout.height.toDouble();
    // The scroll viewport is already inset by _headerWidth (see Positioned.fill
    // below), so the content must NOT add another header's worth of width or it
    // creates blank scroll space before bar 1.
    final contentWidth = _bars * _barWidth;

    return focus_mgr.FocusableWidget(
      key: const Key('arrangement-root'),
      view: widget.view,
      child: Container(
        width: w,
        height: h,
        color: DawColors.bg,
        child: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: Stack(
                children: [
                  // Scrollable timeline
                  Positioned.fill(
                    top: _rulerHeight.toDouble(),
                    left: _headerWidth.toDouble(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SizedBox(
                          width: contentWidth.toDouble(),
                          height: (_tracks.length * _trackHeight).toDouble(),
                          child: CustomPaint(
                            painter: _ArrangementPainter(
                              tracks: _tracks,
                              barWidth: _barWidth,
                              trackHeight: _trackHeight,
                              headerWidth: 0,
                              rulerHeight: _rulerHeight,
                              stepsPerBar: widget.project.stepsPerBar,
                              beatsPerBar: widget.project.beatsPerBar,
                              playheadPos: _playheadPos,
                              accent: widget.accent,
                              selection: _selectedClips,
                              cursorTrack: widget.cursorTrack,
                              cursorStep: widget.cursorStep,
                              selecting: widget.selecting,
                              anchorTrack: widget.anchorTrack,
                              anchorStep: widget.anchorStep,
                              revision: widget.revision,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Fixed ruler
                  Positioned(
                    top: 0,
                    left: _headerWidth.toDouble(),
                    right: 0,
                    height: _rulerHeight.toDouble(),
                    child: _buildRuler(),
                  ),
                  // Fixed track headers
                  Positioned(
                    top: _rulerHeight.toDouble(),
                    left: 0,
                    width: _headerWidth.toDouble(),
                    bottom: 0,
                    child: _buildTrackHeaders(),
                  ),
                  // Corner
                  Positioned(
                    top: 0,
                    left: 0,
                    width: _headerWidth.toDouble(),
                    height: _rulerHeight.toDouble(),
                    child: Container(
                      color: DawColors.panelBg,
                      child: Center(
                        child: Text('ARRANGE', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _playheadPos => 0; // TODO: wire to transport

  List<ArrangementClip> get _selectedClips {
    return _tracks.expand((t) => t.clips.where((c) => c.selected)).toList();
  }

Widget _buildToolbar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: DawColors.panelBg,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.add, size: 18), tooltip: 'Add Track', onPressed: widget.onAddTrack),
          const SizedBox(width: 8),
          Text('Bars: $_bars  Steps/Bar: ${widget.project.stepsPerBar}', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
          const Spacer(),
          Text('Zoom:', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 18),
            onPressed: _zoomOut,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 18),
            onPressed: _zoomIn,
          ),
        ],
      ),
    );
  }

  void _zoomOut() => setState(() => _barWidth = (_barWidth * 0.8).round().clamp(40, 300));
  void _zoomIn() => setState(() => _barWidth = (_barWidth * 1.25).round().clamp(40, 300));

  Widget _buildRuler() {
    return Container(
      height: _rulerHeight.toDouble(),
      color: DawColors.panelBg,
      child: CustomPaint(
        painter: _RulerPainter(
          bars: _bars,
          barWidth: _barWidth,
          beatsPerBar: widget.project.beatsPerBar,
          accent: widget.accent,
        ),
      ),
    );
  }

  Widget _buildTrackHeaders() {
    return Container(
      width: _headerWidth.toDouble(),
      color: DawColors.panelBg,
      child: ListView.builder(
        itemCount: _tracks.length,
        itemBuilder: (context, i) => _TrackHeader(
          track: _tracks[i],
          index: i,
          height: _trackHeight,
          accent: widget.accent,
          onMute: () => setState(() => _tracks[i].mute = !_tracks[i].mute),
          onSolo: () => setState(() => _tracks[i].solo = !_tracks[i].solo),
          onRecArm: () => setState(() => _tracks[i].recArm = !_tracks[i].recArm),
        ),
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  final ArrangementTrack track;
  final int index;
  final int height;
  final DawAccent accent;
  final VoidCallback onMute;
  final VoidCallback onSolo;
  final VoidCallback onRecArm;

  const _TrackHeader({
    required this.track,
    required this.index,
    required this.height,
    required this.accent,
    required this.onMute,
    required this.onSolo,
    required this.onRecArm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height.toDouble(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${index + 1}', style: DawFonts.mono9.copyWith(color: DawColors.textMuted), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(track.name, style: DawFonts.uiBold.copyWith(color: track.color, fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
          _MiniButton(label: 'M', active: track.mute, color: Colors.red, onTap: onMute),
          const SizedBox(width: 4),
          _MiniButton(label: 'S', active: track.solo, color: Colors.yellow, onTap: onSolo),
          const SizedBox(width: 4),
          _MiniButton(label: 'R', active: track.recArm, color: Colors.red, onTap: onRecArm),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _MiniButton({required this.label, required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: active ? color : DawColors.bg,
          border: Border.all(color: active ? color : DawColors.border, width: 1),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(child: Text(label, style: DawFonts.mono9.copyWith(color: active ? Colors.black : DawColors.textMuted, fontSize: 9))),
      ),
    );
  }
}

class _ArrangementPainter extends CustomPainter {
  final List<ArrangementTrack> tracks;
  final int barWidth;
  final int trackHeight;
  final int headerWidth;
  final int rulerHeight;
  final int stepsPerBar;
  final int beatsPerBar;
  final int playheadPos;
  final DawAccent accent;
  final List<ArrangementClip> selection;
  final int cursorTrack;
  final int cursorStep;
  final bool selecting;
  final int? anchorTrack;
  final int? anchorStep;
  final int revision;

  const _ArrangementPainter({
    required this.tracks,
    required this.barWidth,
    required this.trackHeight,
    required this.headerWidth,
    required this.rulerHeight,
    required this.stepsPerBar,
    required this.beatsPerBar,
    required this.playheadPos,
    required this.accent,
    required this.selection,
    required this.cursorTrack,
    required this.cursorStep,
    required this.selecting,
    required this.anchorTrack,
    required this.anchorStep,
    this.revision = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = DawColors.borderSoft..strokeWidth = 0.5;
    final beatPaint = Paint()..color = DawColors.beatLine..strokeWidth = 0.5;
    final barPaint = Paint()..color = DawColors.barLine..strokeWidth = 1;

    // Draw grid lines
    final totalBars = (size.width - headerWidth) / barWidth;
    for (int bar = 0; bar <= totalBars; bar++) {
      final x = headerWidth.toDouble() + bar * barWidth.toDouble();
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), bar % 4 == 0 ? barPaint : (bar % 2 == 0 ? beatPaint : gridPaint));
    }

    // Horizontal track separators
    for (int t = 1; t < tracks.length; t++) {
      final y = t * trackHeight.toDouble();
      canvas.drawLine(Offset(headerWidth.toDouble(), y), Offset(size.width, y), gridPaint);
    }

    // Draw clips
    for (int ti = 0; ti < tracks.length; ti++) {
      final track = tracks[ti];
      final trackY = ti * trackHeight;
      for (final clip in track.clips) {
        final clipX = headerWidth + (clip.start / stepsPerBar) * barWidth;
        final clipW = (clip.length / stepsPerBar) * barWidth;
        final rect = Rect.fromLTWH(clipX, trackY + 2, clipW, trackHeight - 4);

        final clipPaint = Paint()
          ..color = clip.selected ? accent.accent : clip.color
          ..style = PaintingStyle.fill;
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        canvas.drawRRect(rrect, clipPaint);

        // Clip border
        final borderPaint = Paint()
          ..color = clip.selected ? accent.accent2 : clip.color.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = clip.selected ? 2 : 1;
        canvas.drawRRect(rrect, borderPaint);

        // Clip name (skip for sub-12px slivers)
        if (rect.width >= 12) {
          final textPainter = TextPainter(
            text: TextSpan(text: clip.name, style: DawFonts.mono9.copyWith(color: clip.selected ? Colors.black : DawColors.text)),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          );
          textPainter.layout(maxWidth: rect.width - 8);
          textPainter.paint(canvas, Offset(rect.left + 4, rect.top + (rect.height - textPainter.height) / 2));
        }

        // Loop brackets if looped
        if (clip.length > stepsPerBar * 4) {
          final bracketPaint = Paint()
            ..color = DawColors.textFaint
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;
          canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, 6), bracketPaint);
          canvas.drawLine(rect.topRight, rect.topRight.translate(0, 6), bracketPaint);
        }
      }
    }

    // Playhead
    if (playheadPos >= 0) {
      final x = headerWidth.toDouble() + (playheadPos / stepsPerBar) * barWidth.toDouble();
      final playheadPaint = Paint()..color = accent.accent..strokeWidth = 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), playheadPaint);
      // Playhead triangle
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x - 6, 12)
        ..lineTo(x + 6, 12)
        ..close();
      canvas.drawPath(path, Paint()..color = accent.accent);
    }

    // Box selection rectangle (CTRL drag over clips)
    if (selecting && anchorTrack != null && anchorStep != null) {
      final aT = anchorTrack!;
      final aS = anchorStep!;
      final loT = aT < cursorTrack ? aT : cursorTrack;
      final hiT = aT > cursorTrack ? aT : cursorTrack;
      final loS = aS < cursorStep ? aS : cursorStep;
      final hiS = aS > cursorStep ? aS : cursorStep;
      final x0 = headerWidth + (loS / stepsPerBar) * barWidth;
      final x1 = headerWidth + ((hiS + 1) / stepsPerBar) * barWidth;
      final y0 = loT * trackHeight.toDouble();
      final y1 = (hiT + 1) * trackHeight.toDouble();
      final box = Rect.fromLTRB(x0, y0, x1, y1);
      canvas.drawRect(box, Paint()..color = accent.accent.withValues(alpha: 0.14));
      canvas.drawRect(
        box,
        Paint()
          ..color = accent.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Keyboard cursor
    final cx = headerWidth + (cursorStep / stepsPerBar) * barWidth;
    final cy = cursorTrack * trackHeight.toDouble();
    final cursorRect = Rect.fromLTWH(
      cx,
      cy,
      barWidth / stepsPerBar,
      trackHeight.toDouble(),
    );
    canvas.drawRect(
      cursorRect,
      Paint()..color = accent.accent.withValues(alpha: 0.10),
    );
    canvas.drawRect(
      cursorRect,
      Paint()
        ..color = accent.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Cursor flag on the ruler line
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = accent.accent.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrangementPainter old) =>
      old.revision != revision ||
      old.playheadPos != playheadPos ||
      old.cursorTrack != cursorTrack ||
      old.cursorStep != cursorStep ||
      old.selecting != selecting ||
      old.anchorTrack != anchorTrack ||
      old.anchorStep != anchorStep ||
      old.selection.length != selection.length;
}

class _RulerPainter extends CustomPainter {
  final int bars;
  final int barWidth;
  final int beatsPerBar;
  final DawAccent accent;

   _RulerPainter({required this.bars, required this.barWidth, required this.beatsPerBar, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = DawFonts.mono9.copyWith(color: DawColors.textMuted);
    for (int bar = 0; bar < bars; bar++) {
      final x = bar * barWidth.toDouble();
      // Bar number
      final tp = TextPainter(text: TextSpan(text: '${bar + 1}', style: textStyle), textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(x + 4, 4));
      // Beat marks
      for (int beat = 1; beat < beatsPerBar; beat++) {
        final bx = x + (beat / beatsPerBar) * barWidth;
        canvas.drawLine(Offset(bx, 16), Offset(bx, size.height), Paint()..color = DawColors.stepLine..strokeWidth = 0.5);
      }
      // Bar line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = DawColors.barLine..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.bars != bars || old.barWidth != barWidth;
}