import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../input/daw_input.dart';
import '../model/project.dart';
import '../ui/daw_theme.dart';
import '../ui/focus_manager.dart' as focus_mgr;
import 'roll_layout.dart';

/// A single pattern (clip) that can be triggered in the arrangement.
class Pattern {
  final String name;
  final Color color;
  final int steps; // 16th-note steps
  final int pitchRange; // number of rows
  final List<List<bool>> grid; // [pitch][step] = on/off
  final List<int> velocities; // flat array [pitch * steps + step] = velocity (0-127)

  Pattern({
    required this.name,
    required this.color,
    required this.steps,
    required this.pitchRange,
    List<List<bool>>? grid,
    List<int>? velocities,
  }) : grid = grid ?? List.generate(pitchRange, (_) => List.filled(steps, false)),
       velocities = velocities ?? List.filled(pitchRange * steps, 100);

  bool get(int pitch, int step) => grid[pitch][step];
  void set(int pitch, int step, bool value) => grid[pitch][step] = value;

  int velocity(int pitch, int step) => velocities[pitch * steps + step];
  void setVelocity(int pitch, int step, int v) => velocities[pitch * steps + step] = v.clamp(0, 127);

  Pattern copyWith({String? name, Color? color, int? steps}) => Pattern(
    name: name ?? this.name,
    color: color ?? this.color,
    steps: steps ?? this.steps,
    pitchRange: pitchRange,
    grid: grid.map((row) => List<bool>.from(row)).toList(),
    velocities: List<int>.from(velocities),
  );
}

class PatternView extends StatefulWidget {
  final Project project;
  final RollLayout layout;
  final ViewMode view;
  final focus_mgr.FocusManager focusManager;
  final DawAccent accent;
  final List<Pattern> patterns;
  final int selectedPatternIndex;
  final ValueChanged<int> onPatternSelect;
  final void Function(Pattern)? onPatternChanged;
  final void Function()? onAddPattern;

  const PatternView({
    super.key,
    required this.project,
    required this.layout,
    required this.view,
    required this.focusManager,
    required this.accent,
    required this.patterns,
    required this.selectedPatternIndex,
    required this.onPatternSelect,
    this.onPatternChanged,
    this.onAddPattern,
  });

  @override
  State<PatternView> createState() => _PatternViewState();
}

class _PatternViewState extends State<PatternView> {
  late final GridPointer _localPointer;
  int _stepsPerPage = 16;
  int _pageOffset = 0;
  int _viewLowPitch = 60; // MIDI pitch at top of view
  int _pitchRange = 16; // visible rows

  // Current editing state
  bool _drawMode = false;
  bool _velocityMode = false;
  int _lastVelocity = 100;

  @override
  void initState() {
    super.initState();
    _localPointer = GridPointer(pitch: 60, col: 0);
    widget.focusManager.register(_focusNode, widget.view);
  }

  final FocusNode _focusNode = FocusNode();

  Pattern get _currentPattern => widget.patterns[widget.selectedPatternIndex];

  void _toggleCell(int pitch, int step) {
    final pat = _currentPattern;
    final newVal = !pat.get(pitch, step);
    pat.set(pitch, step, newVal);
    if (newVal) pat.setVelocity(pitch, step, _lastVelocity);
    widget.onPatternChanged?.call(pat);
    setState(() {});
  }

  void _setVelocity(int pitch, int step, int v) {
    final pat = _currentPattern;
    pat.setVelocity(pitch, step, v);
    _lastVelocity = v;
    widget.onPatternChanged?.call(pat);
    setState(() {});
  }

  @override
  void dispose() {
    widget.focusManager.unregister(_focusNode);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.layout.width.toDouble();
    final h = widget.layout.height.toDouble();

    return focus_mgr.FocusableWidget(
      key: const Key('pattern-root'),
      view: widget.view,
      focusNode: _focusNode,
      onFocus: () => widget.focusManager.register(_focusNode, widget.view),
      onBlur: () => widget.focusManager.unregister(_focusNode),
      child: Container(
        width: w,
        height: h,
        color: DawColors.bg,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                children: [
                  _buildKeyboard(),
                  Expanded(
                    child: _buildGrid(),
                  ),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

Widget _buildHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: DawColors.panelBg,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'New Pattern',
            onPressed: widget.onAddPattern,
          ),
          const SizedBox(width: 8),
          // Pattern selector
          Expanded(
            child: DropdownButton<int>(
              value: widget.selectedPatternIndex,
              dropdownColor: DawColors.surface,
              style: DawFonts.ui.copyWith(color: DawColors.text),
              underline: const SizedBox(),
              items: List.generate(widget.patterns.length, (i) => DropdownMenuItem(
                value: i,
                child: Text(widget.patterns[i].name, style: DawFonts.ui),
              )),
              onChanged: (i) => i != null ? widget.onPatternSelect(i) : null,
            ),
          ),
          const SizedBox(width: 16),
          Text('Steps: ${_currentPattern.steps}', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
          const SizedBox(width: 16),
          _ModeButton(label: 'DRAW', active: _drawMode, onTap: () => setState(() => _drawMode = !_drawMode)),
          const SizedBox(width: 4),
          _ModeButton(label: 'VEL', active: _velocityMode, onTap: () => setState(() => _velocityMode = !_velocityMode)),
          const SizedBox(width: 4),
          _ModeButton(label: 'PLAY', active: false, onTap: () {}), // TODO: pattern preview
          const Spacer(),
          Text('Page ${_pageOffset ~/ _stepsPerPage + 1}', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: _canPageLeft ? _pageLeft : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: _canPageRight ? _pageRight : null,
          ),
        ],
      ),
    );
  }

Widget _buildKeyboard() {
    const keyWidth = 40.0;
    final pitchCount = _pitchRange;

    return Container(
      width: keyWidth,
      color: DawColors.panelBg,
      child: Stack(
        children: [
          // White keys
          Column(
            children: List.generate(pitchCount, (i) {
              final pitch = _viewLowPitch + pitchCount - 1 - i;
              final isBlack = _isBlackKey(pitch % 12);
              return Container(
                height: 32,
                width: keyWidth,
                decoration: BoxDecoration(
                  color: isBlack ? DawColors.keyBlack : DawColors.keyWhite,
                  border: Border.all(color: isBlack ? DawColors.keyBlack : DawColors.keyWhiteEdge),
                ),
                child: !isBlack ? Center(
                  child: Text(_noteName(pitch), style: DawFonts.mono9.copyWith(color: DawColors.keyLabel)),
                ) : null,
              );
            }),
          ),
          // Black keys overlay
          ...List.generate(pitchCount, (i) {
            final pitch = _viewLowPitch + pitchCount - 1 - i;
            if (!_isBlackKey(pitch % 12)) return const SizedBox(height: 32);
            return Positioned(
              top: i * 32.0 + 8,
              right: 4,
              child: Container(
                width: 24,
                height: 16,
                decoration: BoxDecoration(
                  color: DawColors.keyBlack,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.black),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final pattern = _currentPattern;
    final visibleSteps = math.min(_stepsPerPage, pattern.steps - _pageOffset);
    final cellW = 28.0;
    final cellH = 32.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: (visibleSteps * cellW).toDouble(),
            height: constraints.maxHeight,
            child: CustomPaint(
              size: Size(visibleSteps * cellW, constraints.maxHeight),
              painter: _PatternGridPainter(
                pattern: pattern,
                pageOffset: _pageOffset,
                stepsPerPage: _stepsPerPage,
                cellW: cellW,
                cellH: cellH,
                viewLowPitch: _viewLowPitch,
                pitchRange: _pitchRange,
                accent: widget.accent,
                drawMode: _drawMode,
                velocityMode: _velocityMode,
                pointer: _localPointer,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: DawColors.panelBg,
      child: Row(
        children: [
          Text('Velocity: $_lastVelocity', style: DawFonts.uiSmall.copyWith(color: widget.accent.accent)),
          const Spacer(),
          Slider(
            value: _lastVelocity.toDouble(),
            min: 1,
            max: 127,
            divisions: 126,
            onChanged: (v) => setState(() => _lastVelocity = v.round()),
          ),
          const SizedBox(width: 16),
          Text('Len: ${_currentPattern.steps}', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
        ],
      ),
    );
  }

  bool get _canPageLeft => _pageOffset >= _stepsPerPage;
  bool get _canPageRight => (_pageOffset + _stepsPerPage) < _currentPattern.steps;

  void _pageLeft() => setState(() => _pageOffset = (_pageOffset - _stepsPerPage).clamp(0, _currentPattern.steps - _stepsPerPage));
  void _pageRight() => setState(() => _pageOffset = (_pageOffset + _stepsPerPage).clamp(0, _currentPattern.steps - _stepsPerPage));

  bool _isBlackKey(int pc) => const [1, 3, 6, 8, 10].contains(pc);
  String _noteName(int pitch) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${names[pitch % 12]}${pitch ~/ 12 - 1}';
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00D4AA) : DawColors.surfaceHi,
          border: Border.all(color: active ? const Color(0xFF00D4AA) : DawColors.border),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: DawFonts.uiSmall.copyWith(color: active ? Colors.black : DawColors.text)),
      ),
    );
  }
}

class _PatternGridPainter extends CustomPainter {
  final Pattern pattern;
  final int pageOffset;
  final int stepsPerPage;
  final double cellW;
  final double cellH;
  final int viewLowPitch;
  final int pitchRange;
  final DawAccent accent;
  final bool drawMode;
  final bool velocityMode;
  final GridPointer pointer;

  const _PatternGridPainter({
    required this.pattern,
    required this.pageOffset,
    required this.stepsPerPage,
    required this.cellW,
    required this.cellH,
    required this.viewLowPitch,
    required this.pitchRange,
    required this.accent,
    required this.drawMode,
    required this.velocityMode,
    required this.pointer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = DawColors.borderSoft..strokeWidth = 0.5;
    final beatPaint = Paint()..color = DawColors.beatLine..strokeWidth = 1;
    final barPaint = Paint()..color = DawColors.barLine..strokeWidth = 1.5;

    // Grid lines
    final visibleSteps = math.min(stepsPerPage, pattern.steps - pageOffset);
    for (int s = 0; s <= visibleSteps; s++) {
      final x = s * cellW;
      final step = pageOffset + s;
      final paint = step % 16 == 0 ? barPaint : (step % 4 == 0 ? beatPaint : gridPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (int p = 1; p < pitchRange; p++) {
      canvas.drawLine(Offset(0, p * cellH), Offset(size.width, p * cellH), gridPaint);
    }

    // Cells
    for (int p = 0; p < pitchRange; p++) {
      final pitch = viewLowPitch + pitchRange - 1 - p;
      if (pitch < 0 || pitch >= 128) continue;
      for (int s = 0; s < visibleSteps; s++) {
        final step = pageOffset + s;
        if (step >= pattern.steps) break;
        final rect = Rect.fromLTWH(s * cellW, p * cellH, cellW, cellH);
        final on = pattern.get(pitch, step);

        // Cell background
        if (on) {
          final vel = pattern.velocity(pitch, step);
          final alpha = (vel / 127.0).clamp(0.3, 1.0);
          final fillPaint = Paint()..color = pattern.color.withValues(alpha: alpha);
          canvas.drawRect(rect.deflate(1), fillPaint);
        }

        // Velocity indicator (thin line at bottom)
        final vel = pattern.velocity(pitch, step);
        final velH = (vel / 127.0) * 4;
        canvas.drawRect(
          Rect.fromLTWH(rect.left + 1, rect.bottom - velH - 1, rect.width - 2, velH),
          Paint()..color = on ? Colors.white.withValues(alpha: 0.7) : DawColors.textFaint,
        );

        // Grid border
        canvas.drawRect(rect, gridPaint);
      }
    }

    // Pointer highlight
    final ptrX = (pointer.col - pageOffset) * cellW;
    final ptrY = (viewLowPitch + pitchRange - 1 - pointer.pitch) * cellH;
    if (ptrX >= 0 && ptrX < size.width && ptrY >= 0 && ptrY < size.height) {
      final ptrRect = Rect.fromLTWH(ptrX, ptrY, cellW, cellH);
      canvas.drawRect(ptrRect, Paint()..color = accent.accent..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternGridPainter old) => 
    old.pattern != pattern || old.pageOffset != pageOffset || old.pointer != pointer;
}