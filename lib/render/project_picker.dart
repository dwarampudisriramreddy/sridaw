import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/project_store.dart';
import '../ui/daw_theme.dart';

enum ProjectPickerAction { open, save }

class ProjectPickerResult {
  final ProjectPickerAction action;
  final String name;

  const ProjectPickerResult(this.action, this.name);
}

class ProjectPicker extends StatefulWidget {
  final ProjectStore store;
  final String currentName;
  final Color accent;

  const ProjectPicker({
    super.key,
    required this.store,
    required this.currentName,
    required this.accent,
  });

  @override
  State<ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<ProjectPicker> {
  late final TextEditingController _name = TextEditingController(
    text: widget.currentName,
  );
  late Future<List<SavedProject>> _projects = widget.store.list();
  late final Future<String> _folder = widget.store.projectsDirectory().then(
    (directory) => directory.path,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context)
        .pop(ProjectPickerResult(ProjectPickerAction.save, name));
  }

  void _open(SavedProject project) {
    Navigator.of(context)
        .pop(ProjectPickerResult(ProjectPickerAction.open, project.name));
  }

  void _reload() {
    setState(() {
      _projects = widget.store.list();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('project-picker'),
        width: math.min(430, screen.width - 24),
        height: math.min(540, screen.height - 60),
        decoration: BoxDecoration(
          color: DawColors.surface,
          borderRadius: BorderRadius.circular(DawLayout.radius),
          border: Border.all(color: DawColors.border),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PROJECTS',
                    style: DawFonts.display(size: 12, spacing: 1.6),
                  ),
                ),
                GestureDetector(
                  key: const Key('project-close'),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.close,
                    size: 17,
                    color: DawColors.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            FutureBuilder<String>(
              future: _folder,
              builder: (context, snapshot) => Text(
                snapshot.data ?? 'app internal storage',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DawFonts.mono(size: 8.5, color: DawColors.textFaint),
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel('SAVE CURRENT PROJECT'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('project-name-field'),
                    controller: _name,
                    onSubmitted: (_) => _save(),
                    textInputAction: TextInputAction.done,
                    style: DawFonts.mono(size: 11, color: DawColors.text),
                    cursorColor: widget.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'project name',
                      hintStyle: DawFonts.mono(
                        size: 11,
                        color: DawColors.textFaint,
                      ),
                      filled: true,
                      fillColor: DawColors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: DawColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: DawColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: widget.accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  key: const Key('project-save'),
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: widget.accent),
                    ),
                    child: Text(
                      'SAVE',
                      style: DawFonts.mono(size: 10, color: widget.accent),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _sectionLabel('OPEN SAVED PROJECT')),
                GestureDetector(
                  key: const Key('project-refresh'),
                  onTap: _reload,
                  child: const Icon(
                    Icons.refresh,
                    size: 15,
                    color: DawColors.textFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: FutureBuilder<List<SavedProject>>(
                future: _projects,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'E: ${snapshot.error}',
                      style: DawFonts.mono(size: 10, color: DawColors.error),
                    );
                  }
                  final projects = snapshot.data ?? const <SavedProject>[];
                  if (projects.isEmpty) {
                    return Center(
                      child: Text(
                        'no saved projects yet',
                        style: DawFonts.body(
                          size: 11,
                          color: DawColors.textFaint,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: projects.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 5),
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return GestureDetector(
                        key: Key('project-open-${project.name}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _open(project),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: DawColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: DawColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.music_note,
                                size: 15,
                                color: DawColors.textDim,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DawFonts.mono(
                                    size: 11,
                                    color: DawColors.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _dateLabel(project.modified),
                                style: DawFonts.mono(
                                  size: 8.5,
                                  color: DawColors.textFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'tap a project to open it in the roll',
              style: DawFonts.body(size: 9.5, color: DawColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: DawFonts.display(size: 10, spacing: 2, color: DawColors.textDim),
  );

  String _dateLabel(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
