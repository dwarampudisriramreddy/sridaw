import 'package:flutter/material.dart';

import '../music_theory.dart' as theory;
import '../ui/daw_theme.dart';

/// Key/scale chooser opened from the toolbar's scale chip.
///
/// Changes apply as soon as a root, scale, or mode is tapped, so the roll
/// updates behind the dialog. The keyboard path stays available with
/// `:scale <root> [name]` and `:scale keys on|off`.
class ScalePicker extends StatefulWidget {
  final int activeRoot;
  final String activeScale;
  final bool keysOnly;
  final Color accent;
  final void Function(int root, String scale, bool keysOnly) onChanged;

  const ScalePicker({
    super.key,
    required this.activeRoot,
    required this.activeScale,
    required this.keysOnly,
    required this.accent,
    required this.onChanged,
  });

  @override
  State<ScalePicker> createState() => _ScalePickerState();
}

class _ScalePickerState extends State<ScalePicker> {
  late int _root = widget.activeRoot;
  late String _scale = widget.activeScale;
  late bool _keysOnly = widget.keysOnly;

  void _change({int? root, String? scale, bool? keysOnly}) {
    setState(() {
      if (root != null) _root = root;
      if (scale != null) _scale = scale;
      if (keysOnly != null) _keysOnly = keysOnly;
    });
    widget.onChanged(_root, _scale, _keysOnly);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      height: 470,
      decoration: BoxDecoration(
        color: DawColors.surface,
        borderRadius: BorderRadius.circular(DawLayout.radius),
        border: Border.all(color: DawColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'KEY & SCALE',
                  style: DawFonts.display(size: 12, spacing: 1.6),
                ),
              ),
              TextButton(
                key: const Key('scale-done'),
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: DawColors.text,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'DONE',
                  style: DawFonts.mono(size: 10, color: widget.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('KEY'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < theory.noteNames.length; i++)
                _choice(
                  key: Key('scale-root-${theory.noteNames[i]}'),
                  label: theory.noteNames[i],
                  active: i == _root,
                  onTap: () => _change(root: i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _sectionLabel('SCALE'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in theory.scales.keys)
                _choice(
                  key: Key('scale-name-$name'),
                  label: name,
                  active: name == _scale,
                  onTap: () => _change(scale: name),
                ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            key: const Key('scale-keys-toggle'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _change(keysOnly: !_keysOnly),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _keysOnly
                    ? widget.accent.withValues(alpha: 0.16)
                    : DawColors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _keysOnly ? widget.accent : DawColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _keysOnly ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                    color: _keysOnly ? widget.accent : DawColors.textFaint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SCALE KEYS ONLY',
                          style: DawFonts.mono(
                            size: 10,
                            color: _keysOnly ? widget.accent : DawColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _keysOnly
                              ? 'rows follow the scale · chromatic notes hidden'
                              : 'show every chromatic key',
                          style: DawFonts.uiSmall.copyWith(
                            color: DawColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: DawFonts.display(size: 10, spacing: 2, color: DawColors.textDim),
  );

  Widget _choice({
    required Key key,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? widget.accent.withValues(alpha: 0.2)
              : DawColors.surfaceAlt,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: active ? widget.accent : DawColors.border),
        ),
        child: Text(
          label,
          style: DawFonts.mono(
            size: 10,
            color: active ? widget.accent : DawColors.text,
          ),
        ),
      ),
    );
  }
}
