import 'package:flutter/material.dart';

import '../input/daw_input.dart';
import '../model/project.dart';
import '../ui/daw_theme.dart';
import '../ui/focus_manager.dart' as focus_mgr;
import 'roll_layout.dart';

/// A single breakpoint on an automation lane. `value` is 0..127 (MIDI).
class AutomationPoint {
  final int step;
  int value;

  AutomationPoint({required this.step, required this.value});
}

/// One automatable parameter for a track.
class AutomationLane {
  final String name;
  final Color color;
  final List<AutomationPoint> points;

  AutomationLane({required this.name, required this.color, List<AutomationPoint>? points})
      : points = points ?? [];

  /// Sorted copy of the points, left to right.
  List<AutomationPoint> get sorted {
    final list = [...points]..sort((a, b) => a.step.compareTo(b.step));
    return list;
  }

  AutomationPoint? get current {
    if (points.isEmpty) return null;
    return points.last;
  }

  void put(int step, int value) {
    final v = value.clamp(0, 127);
    final existing = points.where((p) => p.step == step).toList();
    if (existing.isNotEmpty) {
      existing.first.value = v;
    } else {
      points.add(AutomationPoint(step: step, value: v));
    }
  }

  void removeNear(int step) {
    if (points.isEmpty) return;
    AutomationPoint? best;
    int bestDist = 1 << 30;
    for (final p in points) {
      final d = (p.step - step).abs();
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    if (best != null) points.remove(best);
  }
}

/// Keyboard-driven automation editor. The value graph scrolls horizontally over
/// the project length; a crosshair cursor sits at (step, value) and is moved by
/// the central key handler (see `AppShell`).
class AutomationView extends StatefulWidget {
  final Project project;
  final RollLayout layout;
  final ViewMode view;
  final focus_mgr.FocusManager focusManager;
  final DawAccent accent;
  final List<AutomationLane> lanes;
  final int laneIndex;
  final int cursorStep;
  final int cursorValue;
  final void Function(int laneIndex)? onLaneTap;

  const AutomationView({
    super.key,
    required this.project,
    required this.layout,
    required this.view,
    required this.focusManager,
    required this.accent,
    required this.lanes,
    required this.laneIndex,
    required this.cursorStep,
    required this.cursorValue,
    this.onLaneTap,
  });

  @override
  State<AutomationView> createState() => _AutomationViewState();
}

class _AutomationViewState extends State<AutomationView> {
  static const int _stepW = 14;

  int get _totalSteps => widget.project.totalSteps;
  int get _stepsPerBar => widget.project.stepsPerBar;

  @override
  Widget build(BuildContext context) {
    final w = widget.layout.width.toDouble();
    final h = widget.layout.height.toDouble();
    final lane = (widget.laneIndex >= 0 && widget.laneIndex < widget.lanes.length)
        ? widget.lanes[widget.laneIndex]
        : null;

    return focus_mgr.FocusableWidget(
      key: const Key('automation-root'),
      view: widget.view,
      child: Container(
        width: w,
        height: h,
        color: DawColors.bg,
        child: Column(
          children: [
            _buildHeader(lane),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLaneList(),
                  Container(width: 1, color: DawColors.borderSoft),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: (_totalSteps * _stepW).toDouble(),
                        height: h - 44 - 26,
                        child: CustomPaint(
                          painter: _AutomationPainter(
                            lane: lane,
                            stepsPerBar: _stepsPerBar,
                            beatsPerBar: widget.project.beatsPerBar,
                            stepW: _stepW,
                            totalSteps: _totalSteps,
                            cursorStep: widget.cursorStep,
                            cursorValue: widget.cursorValue,
                            accent: widget.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildFooter(lane),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AutomationLane? lane) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Row(
        children: [
          Text('AUTOMATION', style: DawFonts.display(size: 12, spacing: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${widget.project.track.name} · ${lane?.name ?? '—'}',
              overflow: TextOverflow.ellipsis,
              style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Text('h/l step · j/k value · [ ] lane · i point · d delete',
              style: DawFonts.uiSmall.copyWith(color: DawColors.textFaint)),
        ],
      ),
    );
  }

  Widget _buildLaneList() {
    return SizedBox(
      width: 130,
      child: ListView.builder(
        itemCount: widget.lanes.length,
        itemBuilder: (context, i) {
          final lane = widget.lanes[i];
          final isSelected = i == widget.laneIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onLaneTap?.call(i),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: isSelected
                  ? widget.accent.accent.withValues(alpha: 0.16)
                  : (i.isEven ? DawColors.surface : Colors.transparent),
              child: Row(
                children: [
                  Container(width: 8, height: 8, color: lane.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lane.name,
                      overflow: TextOverflow.ellipsis,
                      style: DawFonts.uiSmall.copyWith(
                        color: isSelected ? DawColors.text : DawColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (lane.points.isNotEmpty)
                    Text('${lane.points.length}',
                        style: DawFonts.mono9.copyWith(color: DawColors.textFaint)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter(AutomationLane? lane) {
    final cur = lane?.current;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Row(
        children: [
          Text('step ${widget.cursorStep} · value ${widget.cursorValue}',
              style: DawFonts.mono9.copyWith(color: DawColors.textMuted)),
          const Spacer(),
          Text(
            lane == null
                ? ''
                : '${lane.name} · ${lane.points.length} pts'
                    '${cur == null ? '' : ' · last ${cur.value}@${cur.step}'}',
            style: DawFonts.uiSmall.copyWith(color: accentColor(lane)),
          ),
        ],
      ),
    );
  }

  Color accentColor(AutomationLane? lane) => lane?.color ?? widget.accent.accent;
}

class _AutomationPainter extends CustomPainter {
  final AutomationLane? lane;
  final int stepsPerBar;
  final int beatsPerBar;
  final int stepW;
  final int totalSteps;
  final int cursorStep;
  final int cursorValue;
  final DawAccent accent;

  _AutomationPainter({
    required this.lane,
    required this.stepsPerBar,
    required this.beatsPerBar,
    required this.stepW,
    required this.totalSteps,
    required this.cursorStep,
    required this.cursorValue,
    required this.accent,
  });

  double _xFor(int step) => step * stepW.toDouble();
  double _yFor(int value, Size size) =>
      size.height - (value / 127.0) * size.height;

  @override
  void paint(Canvas canvas, Size size) {
    final barPaint = Paint()..color = DawColors.barLine..strokeWidth = 1;
    final beatPaint = Paint()..color = DawColors.beatLine..strokeWidth = 0.5;
    final stepPaint = Paint()..color = DawColors.borderSoft..strokeWidth = 0.5;

    for (int s = 0; s <= totalSteps; s++) {
      final x = _xFor(s);
      final inBar = s % stepsPerBar;
      final paint = inBar == 0
          ? barPaint
          : (inBar % (stepsPerBar ~/ beatsPerBar == 0 ? 1 : stepsPerBar ~/ beatsPerBar) == 0
              ? beatPaint
              : stepPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Quarter guides
    final guidePaint = Paint()..color = DawColors.borderSoft..strokeWidth = 0.5;
    for (final f in [0.25, 0.5, 0.75]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }

    final l = lane;
    if (l == null || l.points.isEmpty) {
      // No data: draw a flat line at the cursor value.
      final y = _yFor(cursorValue, size);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = (l?.color ?? accent.accent).withValues(alpha: 0.4)..strokeWidth = 1,
      );
    } else {
      final pts = l.sorted;
      final path = Path();
      final firstY = _yFor(pts.first.value, size);
      path.moveTo(0, firstY);
      path.lineTo(_xFor(pts.first.step), firstY);
      for (int i = 1; i < pts.length; i++) {
        final p = pts[i];
        path.lineTo(_xFor(p.step), _yFor(pts[i - 1].value, size));
        path.lineTo(_xFor(p.step), _yFor(p.value, size));
      }
      path.lineTo(_xFor(pts.last.step), _yFor(pts.last.value, size));
      path.lineTo(size.width, _yFor(pts.last.value, size));

      final line = Paint()
        ..color = l.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(path, line);

      // Breakpoints
      for (final p in pts) {
        final r = Rect.fromCenter(
          center: Offset(_xFor(p.step), _yFor(p.value, size)),
          width: 7,
          height: 7,
        );
        canvas.drawRect(r, Paint()..color = l.color);
        canvas.drawRect(
          r,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // Cursor crosshair
    final cx = _xFor(cursorStep);
    final cy = _yFor(cursorValue, size);
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()..color = accent.accent.withValues(alpha: 0.45)..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      Paint()..color = accent.accent.withValues(alpha: 0.25)..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()..color = accent.accent,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _AutomationPainter old) =>
      old.lane != lane ||
      old.cursorStep != cursorStep ||
      old.cursorValue != cursorValue ||
      old.totalSteps != totalSteps;
}
