import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_log.dart';
import '../ui/daw_theme.dart';

/// In-app log console. Newest entries appear first so the most recent failure
/// is visible without scrolling.
class DebugView extends StatelessWidget {
  const DebugView({super.key});

  Color _colorFor(AppLogLevel level) => switch (level) {
    AppLogLevel.debug => DawColors.textFaint,
    AppLogLevel.info => DawColors.textDim,
    AppLogLevel.warning => DawColors.warn,
    AppLogLevel.error => DawColors.error,
  };

  String _copyText(List<AppLogEntry> entries) =>
      entries.reversed.map((e) => e.line).join('\n');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLog.instance,
      builder: (context, _) {
        final entries = AppLog.instance.entries;
        return Container(
          key: const Key('debug-console'),
          color: DawColors.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: DawColors.borderSoft),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'DEBUG CONSOLE',
                      style: DawFonts.display(
                        size: 12,
                        weight: FontWeight.w700,
                        spacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${entries.length}/${AppLog.maxEntries} · newest first',
                      style: DawFonts.body(
                        size: 10,
                        color: DawColors.textFaint,
                      ),
                    ),
                    const Spacer(),
                    _DebugAction(
                      key: const Key('debug-copy'),
                      label: 'COPY',
                      enabled: entries.isNotEmpty,
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: _copyText(entries)),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _DebugAction(
                      key: const Key('debug-clear'),
                      label: 'CLEAR',
                      enabled: entries.isNotEmpty,
                      onTap: AppLog.instance.clear,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          'No logs yet. Errors, debugPrint output and keyboard '
                          'events will appear here.',
                          textAlign: TextAlign.center,
                          style: DawFonts.body(
                            size: 11,
                            color: DawColors.textFaint,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[entries.length - 1 - index];
                          return _LogRow(
                            key: ValueKey(
                              '${entry.time.microsecondsSinceEpoch}-$index',
                            ),
                            entry: entry,
                            color: _colorFor(entry.level),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({super.key, required this.entry, required this.color});

  final AppLogEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DawColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            entry.line,
            style: DawFonts.mono(
              size: 11,
              weight: FontWeight.w500,
              color: color,
            ),
          ),
          if (entry.stack != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                entry.stack.toString().trimRight(),
                style: DawFonts.mono(
                  size: 9,
                  weight: FontWeight.w400,
                  color: DawColors.textFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DebugAction extends StatelessWidget {
  const _DebugAction({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? DawColors.border : DawColors.borderSoft,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: DawFonts.body(
            size: 10,
            weight: FontWeight.w700,
            spacing: 0.6,
            color: enabled ? DawColors.textDim : DawColors.textFaint,
          ),
        ),
      ),
    );
  }
}
