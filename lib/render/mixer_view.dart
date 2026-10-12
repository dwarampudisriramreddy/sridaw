import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/daw_input.dart';
import '../model/project.dart';
import '../ui/daw_theme.dart';
import '../ui/focus_manager.dart' as focus_mgr;
import 'roll_layout.dart';

/// Each channel strip in the mixer.
class MixerChannel {
  final String name;
  final Color color;
  double gain = 0.0; // dB, -60..+12
  double pan = 0.0; // -1..1
  bool mute = false;
  bool solo = false;
  bool recArm = false;
  final List<double> sends = [0.0, 0.0]; // send levels 0..1
  int? program; // MIDI program
  int? bank; // MIDI bank

  MixerChannel({required this.name, required this.color});
}

class MixerView extends StatefulWidget {
  final Project project;
  final RollLayout layout;
  final ViewMode view;
  final focus_mgr.FocusManager focusManager;
  final DawAccent accent;
  final ValueChanged<MixerChannel>? onChannelChanged;

  const MixerView({
    super.key,
    required this.project,
    required this.layout,
    required this.view,
    required this.focusManager,
    required this.accent,
    this.onChannelChanged,
  });

  @override
  State<MixerView> createState() => _MixerViewState();
}

class _MixerViewState extends State<MixerView> {
  late final List<MixerChannel> _channels;

  @override
  void initState() {
    super.initState();
    // Create channels: master + one per track
    _channels = [
      MixerChannel(name: 'MASTER', color: const Color(0xFF666666)),
      MixerChannel(name: 'Track 1', color: const Color(0xFF4A90D9)),
      MixerChannel(name: 'Track 2', color: const Color(0xFFE67E22)),
      MixerChannel(name: 'Track 3', color: const Color(0xFF27AE60)),
      MixerChannel(name: 'Track 4', color: const Color(0xFFE74C3C)),
      MixerChannel(name: 'Track 5', color: const Color(0xFF8E44AD)),
      MixerChannel(name: 'Track 6', color: const Color(0xFF16A085)),
      MixerChannel(name: 'Track 7', color: const Color(0xFFD35400)),
      MixerChannel(name: 'Track 8', color: const Color(0xFF2C3E50)),
    ];
  }

  void _notifyChange(MixerChannel ch) {
    widget.onChannelChanged?.call(ch);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.layout.width;
    final h = widget.layout.height;

    return focus_mgr.FocusableWidget(
      key: const Key('mixer-root'),
      view: widget.view,
      child: Container(
        width: w.toDouble(),
        height: h.toDouble(),
        color: DawColors.bg,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: List.generate(_channels.length, (i) => _buildChannelStrip(i)),
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
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: DawColors.panelBg,
      child: Row(
        children: [
          Text('MIXER', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                _headerCell('GAIN', 80),
                _headerCell('PAN', 60),
                _headerCell('M', 24),
                _headerCell('S', 24),
                _headerCell('R', 24),
                _headerCell('SEND A', 70),
                _headerCell('SEND B', 70),
                _headerCell('PROG', 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(text, style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted), textAlign: TextAlign.center),
    );
  }

  Widget _buildChannelStrip(int index) {
    final ch = _channels[index];
    final isMaster = index == 0;
    final focusNode = FocusNode();

    return focus_mgr.FocusableWidget(
      key: Key('channel-$index'),
      view: widget.view,
      focusNode: focusNode,
      onFocus: () => widget.focusManager.register(focusNode, widget.view),
      onBlur: () => widget.focusManager.unregister(focusNode),
      child: Container(
        width: isMaster ? 140 : 110,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: DawColors.panelBg,
          border: Border.all(color: ch.color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Name
            Text(
              ch.name,
              style: DawFonts.uiBold.copyWith(color: ch.color, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Gain fader
            _Fader(
              value: ch.gain,
              min: -60,
              max: 12,
              label: 'dB',
              color: ch.color,
              onChanged: (v) => setState(() {
                ch.gain = v;
                _notifyChange(ch);
              }),
            ),
            // Pan knob
            _Knob(
              value: (ch.pan + 1) / 2,
              label: ch.pan == 0 ? 'C' : (ch.pan < 0 ? 'L${(ch.pan.abs() * 100).round()}' : 'R${(ch.pan * 100).round()}'),
              color: ch.color,
              onChanged: (v) => setState(() {
                ch.pan = (v * 2) - 1;
                _notifyChange(ch);
              }),
            ),
            // M/S/R buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ToggleButton(label: 'M', active: ch.mute, color: Colors.red, onTap: () => setState(() => ch.mute = !ch.mute)),
                _ToggleButton(label: 'S', active: ch.solo, color: Colors.yellow, onTap: () => setState(() => ch.solo = !ch.solo)),
                _ToggleButton(label: 'R', active: ch.recArm, color: Colors.red, onTap: () => setState(() => ch.recArm = !ch.recArm)),
              ],
            ),
            // Sends
            Row(
              children: [
                _MiniFader(value: ch.sends[0], label: 'A', color: Colors.cyan, onChanged: (v) => setState(() => ch.sends[0] = v)),
                _MiniFader(value: ch.sends[1], label: 'B', color: Colors.purple, onChanged: (v) => setState(() => ch.sends[1] = v)),
              ],
            ),
            // Program selector
            _ProgramSelect(
              program: ch.program,
              bank: ch.bank,
              onChanged: (p, b) => setState(() { ch.program = p; ch.bank = b; _notifyChange(ch); }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: DawColors.panelBg,
      child: Row(
        children: [
          Text('Master', style: DawFonts.uiBold.copyWith(color: widget.accent.accent)),
          const Spacer(),
          Text('CPU: 12%', style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
        ],
      ),
    );
  }
}

/// Vertical fader with dB scale.
class _Fader extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String label;
  final Color color;
  final ValueChanged<double> onChanged;

  const _Fader({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_Fader> createState() => _FaderState();
}

class _FaderState extends State<_Fader> {
  late double _dragValue;

  @override
  void initState() {
    super.initState();
    _dragValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    const trackHeight = 120.0;
    final norm = (_dragValue - widget.min) / (widget.max - widget.min);
    final thumbTop = trackHeight * (1 - norm);

    return SizedBox(
      width: 40,
      height: trackHeight + 24,
      child: Stack(
        children: [
          // Track
          Center(
            child: Container(
              width: 8,
              height: trackHeight,
              decoration: BoxDecoration(
                color: DawColors.bg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: DawColors.border),
              ),
            ),
          ),
          // Fill
          Center(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 8,
                height: trackHeight * norm,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          // Thumb
          Positioned(
            left: 0,
            right: 0,
            top: thumbTop - 8,
            child: Center(
              child: GestureDetector(
                onVerticalDragUpdate: (d) {
                  final newNorm = (_dragValue - widget.min) / (widget.max - widget.min) - d.delta.dy / 120;
                  setState(() => _dragValue = (widget.min + newNorm.clamp(0.0, 1.0) * (widget.max - widget.min)).roundToDouble());
                  widget.onChanged(_dragValue);
                },
                child: Container(
                  width: 24,
                  height: 16,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.black26),
                  ),
                ),
              ),
            ),
          ),
          // Value label
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Text('${_dragValue.round()}${widget.label}', style: DawFonts.mono10.copyWith(color: widget.color), textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

/// Rotary knob widget.
class _Knob extends StatefulWidget {
  final double value; // 0..1
  final String label;
  final Color color;
  final ValueChanged<double> onChanged;

  const _Knob({required this.value, required this.label, required this.color, required this.onChanged});

  @override
  State<_Knob> createState() => _KnobState();
}

class _KnobState extends State<_Knob> {
  double _angle = 0;

  @override
  void initState() {
    super.initState();
    _angle = widget.value * 270 - 135; // -135 to +135
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: GestureDetector(
        onVerticalDragUpdate: (d) {
          setState(() {
            _angle = (_angle - d.delta.dy * 2).clamp(-135.0, 135.0);
            widget.onChanged((_angle + 135) / 270);
          });
        },
        child: CustomPaint(
          size: const Size(60, 60),
          painter: _KnobPainter(angle: _angle, color: widget.color),
          child: Center(
            child: Text(widget.label, style: DawFonts.mono10.copyWith(color: widget.color)),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double angle;
  final Color color;

  _KnobPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Track
    final trackPaint = Paint()
      ..color = DawColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -135 * math.pi / 180,
      270 * math.pi / 180,
      false,
      trackPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -135 * math.pi / 180,
      (angle + 135) * math.pi / 180,
      false,
      valuePaint,
    );

    // Indicator line
    final indicatorPaint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final rad = (angle + 90) * math.pi / 180;
    canvas.drawLine(
      center,
      center + Offset(math.cos(rad) * (radius - 6), math.sin(rad) * (radius - 6)),
      indicatorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => oldDelegate is _KnobPainter && oldDelegate.angle != angle;
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _ToggleButton({required this.label, required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: active ? color : DawColors.bg,
          border: Border.all(color: active ? color : DawColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(
          child: Text(label, style: DawFonts.uiBold.copyWith(color: active ? Colors.black : DawColors.textMuted, fontSize: 10)),
        ),
      ),
    );
  }
}

class _MiniFader extends StatelessWidget {
  final double value;
  final String label;
  final Color color;
  final ValueChanged<double> onChanged;

  const _MiniFader({required this.value, required this.label, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 80,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(child: Container(width: 4, color: DawColors.border)),
                Center(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(width: 4, height: 56 * value, color: color),
                  ),
                ),
              ],
            ),
          ),
          Text(label, style: DawFonts.mono10.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _ProgramSelect extends StatelessWidget {
  final int? program;
  final int? bank;
  final void Function(int?, int?) onChanged;

  const _ProgramSelect({required this.program, required this.bank, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('B:', style: DawFonts.mono10.copyWith(color: DawColors.textMuted)),
        _tinyField(bank?.toString() ?? '—', (v) => onChanged(program, int.tryParse(v))),
        const SizedBox(width: 4),
        Text('P:', style: DawFonts.mono10.copyWith(color: DawColors.textMuted)),
        _tinyField(program?.toString() ?? '—', (v) => onChanged(int.tryParse(v), bank)),
      ],
    );
  }

  Widget _tinyField(String text, ValueChanged<String> onSubmitted) {
    return SizedBox(
      width: 32,
      height: 20,
      child: TextField(
        textAlign: TextAlign.center,
        style: DawFonts.mono10,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: DawColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: DawColors.border)),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}