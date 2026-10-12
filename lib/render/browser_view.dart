import 'package:flutter/material.dart';

import '../input/daw_input.dart';
import '../model/gm_instruments.dart';
import '../model/project.dart';
import '../ui/daw_theme.dart';
import '../ui/focus_manager.dart' as focus_mgr;
import 'roll_layout.dart';

/// A keyboard-first instrument browser: pick a General MIDI family on the left,
/// move through the programs on the right, and load one onto the active track.
/// All navigation is driven from the central key handler (see `AppShell`).
class BrowserView extends StatelessWidget {
  final Project project;
  final RollLayout layout;
  final ViewMode view;
  final focus_mgr.FocusManager focusManager;
  final DawAccent accent;
  final List<String> categories;
  final int categoryIndex;
  final List<GmInstrument> entries;
  final int selectedIndex;
  final int activeProgram;
  final void Function(int categoryIndex)? onCategoryTap;
  final void Function(int entryIndex)? onEntryTap;

  const BrowserView({
    super.key,
    required this.project,
    required this.layout,
    required this.view,
    required this.focusManager,
    required this.accent,
    required this.categories,
    required this.categoryIndex,
    required this.entries,
    required this.selectedIndex,
    required this.activeProgram,
    this.onCategoryTap,
    this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = layout.width.toDouble();
    final h = layout.height.toDouble();
    final selected =
        (selectedIndex >= 0 && selectedIndex < entries.length)
            ? entries[selectedIndex]
            : null;

    return focus_mgr.FocusableWidget(
      key: const Key('browser-root'),
      view: view,
      child: Container(
        width: w,
        height: h,
        color: DawColors.bg,
        child: Column(
          children: [
            _buildHeader(selected),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCategories(),
                  Container(width: 1, color: DawColors.borderSoft),
                  Expanded(child: _buildEntryList()),
                  Container(width: 1, color: DawColors.borderSoft),
                  SizedBox(width: 200, child: _buildDetails(selected)),
                ],
              ),
            ),
            _buildFooter(selected),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(GmInstrument? selected) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Row(
        children: [
          Text('INSTRUMENTS', style: DawFonts.display(size: 12, spacing: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${project.track.name} · GM ${activeProgram.toString().padLeft(3, '0')} '
              '${gmProgramName(activeProgram)}',
              overflow: TextOverflow.ellipsis,
              style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Text('h/l family · j/k program · i load',
              style: DawFonts.uiSmall.copyWith(color: DawColors.textFaint)),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      width: 140,
      child: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final isSelected = i == categoryIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onCategoryTap?.call(i),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: isSelected
                  ? accent.accent.withValues(alpha: 0.18)
                  : (i.isEven ? DawColors.surface : Colors.transparent),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isSelected ? accent.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      categories[i],
                      overflow: TextOverflow.ellipsis,
                      style: DawFonts.ui.copyWith(
                        color:
                            isSelected ? DawColors.text : DawColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEntryList() {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final isSelected = i == selectedIndex;
        final isActive = e.program == activeProgram;
        final fg = isSelected ? Colors.black : DawColors.text;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onEntryTap?.call(i),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: isSelected
                ? accent.accent
                : (i.isEven ? DawColors.surface : Colors.transparent),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    e.program.toString().padLeft(3, '0'),
                    style: DawFonts.mono9.copyWith(
                      color: isSelected ? Colors.black : DawColors.textFaint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: DawFonts.uiSmall.copyWith(
                      color: fg,
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isActive)
                  Icon(Icons.check, size: 14, color: isSelected ? Colors.black : accent.accent),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetails(GmInstrument? selected) {
    return Container(
      color: DawColors.panelBg,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DETAILS', style: DawFonts.display(size: 10, spacing: 2)),
          const SizedBox(height: 12),
          if (selected != null) ...[
            Text(selected.name,
                style: DawFonts.ui.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _row('Family', selected.family),
            _row('Program', selected.program.toString()),
            _row('Bank', '0 (GM)'),
            _row('Channel', '${project.track.channel + 1}'),
            _row('Track', project.track.name),
            const Spacer(),
            Text('Loaded onto the active track',
                style: DawFonts.uiSmall.copyWith(color: DawColors.textFaint)),
          ] else
            Text('—', style: DawFonts.ui.copyWith(color: DawColors.textFaint)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: DawFonts.mono9.copyWith(color: DawColors.text)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(GmInstrument? selected) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Row(
        children: [
          Text('${entries.length} programs',
              style: DawFonts.uiSmall.copyWith(color: DawColors.textMuted)),
          const Spacer(),
          Text(
            selected == null ? '' : 'i · load ${selected.name}',
            style: DawFonts.uiSmall.copyWith(color: accent.accent),
          ),
        ],
      ),
    );
  }
}
