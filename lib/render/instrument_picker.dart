import 'package:flutter/material.dart';

import '../model/gm_instruments.dart';
import '../ui/daw_theme.dart';

/// Tap-to-load General MIDI picker opened from the toolbar's instrument chip.
///
/// The keyboard path (`:inst <name>` and the browser on CTRL+5) stays where
/// it is; this is the pointer equivalent for touch devices, where typing a
/// program number is not an option.
class InstrumentPicker extends StatefulWidget {
  final int activeProgram;
  final bool activeDrum;
  final Color accent;
  final void Function(GmInstrument instrument) onSelected;

  const InstrumentPicker({
    super.key,
    required this.activeProgram,
    this.activeDrum = false,
    required this.accent,
    required this.onSelected,
  });

  @override
  State<InstrumentPicker> createState() => _InstrumentPickerState();
}

class _InstrumentPickerState extends State<InstrumentPicker> {
  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<GmInstrument> get _matches {
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) return allInstruments;
    final number = int.tryParse(q);
    return [
      for (final e in allInstruments)
        if (e.name.toLowerCase().contains(q) ||
            e.family.toLowerCase().contains(q) ||
            (number != null &&
                (e.program == number || e.program + 1 == number)))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entries = _matches;
    return Container(
      width: 360,
      height: 460,
      decoration: BoxDecoration(
        color: DawColors.surface,
        borderRadius: BorderRadius.circular(DawLayout.radius),
        border: Border.all(color: DawColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('INSTRUMENT', style: DawFonts.display(size: 12, spacing: 1.6)),
          const SizedBox(height: 10),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            style: DawFonts.mono(size: 11, color: DawColors.text),
            decoration: InputDecoration(
              hintText: 'filter by name or program number',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
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
                borderSide: BorderSide(color: DawColors.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'no match',
                      style: DawFonts.mono(
                        size: 11,
                        color: DawColors.textFaint,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      final active =
                          e.drum == widget.activeDrum &&
                          e.program == widget.activeProgram;
                      return InkWell(
                        key: Key('inst-${e.drum ? 'kit-' : ''}${e.program}'),
                        onTap: () => widget.onSelected(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 7,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: DawColors.borderSoft),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 34,
                                child: Text(
                                  '${e.program + 1}',
                                  style: DawFonts.mono(
                                    size: 10,
                                    color: active
                                        ? _accentColor
                                        : DawColors.textFaint,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  e.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: DawFonts.body(
                                    size: 11,
                                    weight: active
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: active
                                        ? _accentColor
                                        : DawColors.text,
                                  ),
                                ),
                              ),
                              Text(
                                e.family,
                                style: DawFonts.mono(
                                  size: 9,
                                  color: DawColors.textFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color get _accentColor => widget.accent;
}
