import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'project.dart';
import 'project_io.dart';

class SavedProject {
  final String name;
  final String path;
  final DateTime modified;

  const SavedProject({
    required this.name,
    required this.path,
    required this.modified,
  });
}

class ProjectStoreException implements Exception {
  final String message;

  const ProjectStoreException(this.message);

  @override
  String toString() => message;
}

class ProjectStore {
  final Directory? _rootOverride;
  Directory? _cachedDirectory;

  ProjectStore({Directory? root}) : _rootOverride = root;

  Future<Directory> projectsDirectory() async {
    final cached = _cachedDirectory;
    if (cached != null) return cached;

    final Directory directory;
    if (_rootOverride != null) {
      directory = _rootOverride;
    } else {
      final documents = await getApplicationDocumentsDirectory();
      directory = Directory(p.join(documents.path, 'sridaw', 'projects'));
    }
    await directory.create(recursive: true);
    _cachedDirectory = directory;
    return directory;
  }

  Future<List<SavedProject>> list() async {
    final directory = await projectsDirectory();
    final projects = <SavedProject>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.${ProjectIO.extension}')) {
        continue;
      }
      final stat = await entity.stat();
      projects.add(
        SavedProject(
          name: p.basenameWithoutExtension(entity.path),
          path: entity.path,
          modified: stat.modified,
        ),
      );
    }
    projects.sort((a, b) => b.modified.compareTo(a.modified));
    return projects;
  }

  Future<String> pathFor(String name) async {
    final directory = await projectsDirectory();
    return p.join(directory.path, fileNameFor(name));
  }

  Future<String> save(Project project, {String? name}) async {
    final requested = name == null || name.trim().isEmpty ? project.name : name;
    final projectName = projectNameFor(requested);
    final path = await pathFor(projectName);
    project.name = projectName;
    await ProjectIO.saveToFile(project, path);
    return path;
  }

  Future<Project> load(String name) async {
    final path = await pathFor(name);
    final file = File(path);
    if (!await file.exists()) {
      throw ProjectStoreException(
        'no saved project named "${projectNameFor(name)}"',
      );
    }
    try {
      return await ProjectIO.loadFromFile(path);
    } on Object catch (error) {
      throw ProjectStoreException('could not open ${p.basename(path)}: $error');
    }
  }

  static String projectNameFor(String raw) {
    var name = raw.trim();
    final extension = '.${ProjectIO.extension}';
    if (name.toLowerCase().endsWith(extension)) {
      name = name.substring(0, name.length - extension.length);
    }
    name = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    name = name.replaceAll(RegExp(r'^\.+'), '').trim();
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) name = 'Untitled';
    if (name.length > 80) name = name.substring(0, 80).trim();
    return name.isEmpty ? 'Untitled' : name;
  }

  static String fileNameFor(String raw) =>
      '${projectNameFor(raw)}.${ProjectIO.extension}';
}
