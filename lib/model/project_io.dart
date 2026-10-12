import 'dart:convert';
import 'dart:io';

import 'project.dart';

/// Simple JSON serializer/deserializer for [Project].
/// No external packages are required.
class ProjectIO {
  /// Extension for sridaw project files.
  static const String extension = 'sridaw';

  static Map<String, dynamic> _trackToJson(Track track) {
    return {
      'name': track.name,
      'type': track.type.name,
      'colorIndex': track.colorIndex,
      'instrument': track.instrument,
      'channel': track.channel,
      'mute': track.mute,
      'solo': track.solo,
      'volume': track.volume,
      'pan': track.pan,
      'notes': track.notes.map(_noteToJson).toList(),
    };
  }

  static Track _trackFromJson(Map<String, dynamic> json) {
    return Track(
      name: json['name'] as String? ?? 'Track',
      type: TrackType.values.firstWhere(
        (t) => t.name == (json['type'] as String? ?? 'synth'),
        orElse: () => TrackType.synth,
      ),
      colorIndex: json['colorIndex'] as int? ?? 5,
      instrument: json['instrument'] as int? ?? 0,
      channel: json['channel'] as int? ?? 0,
      mute: json['mute'] as bool? ?? false,
      solo: json['solo'] as bool? ?? false,
      volume: json['volume'] as int? ?? 100,
      pan: json['pan'] as int? ?? 0,
      notes: ((json['notes'] as List<dynamic>?) ?? [])
          .map((e) => _noteFromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Map<String, dynamic> _noteToJson(Note note) {
    return {
      'pitch': note.pitch,
      'start': note.start,
      'len': note.len,
      'vel': note.vel,
    };
  }

  static Note _noteFromJson(Map<String, dynamic> json) {
    return Note(
      pitch: json['pitch'] as int? ?? 60,
      start: json['start'] as int? ?? 0,
      len: json['len'] as int? ?? 4,
      vel: json['vel'] as int? ?? 100,
    );
  }

  /// Convert [project] to a JSON-serializable map.
  static Map<String, dynamic> toJson(Project project) {
    return {
      'name': project.name,
      'bpm': project.bpm,
      'stepsPerBeat': project.stepsPerBeat,
      'beatsPerBar': project.beatsPerBar,
      'totalBars': project.totalBars,
      'tracks': project.tracks.map(_trackToJson).toList(),
      'activeTrack': project.activeTrack,
      'scaleRoot': project.scaleRoot,
      'scaleName': project.scaleName,
      'selection': project.selection.map(_noteToJson).toList(),
    };
  }

  /// Create a [Project] from JSON.
  static Project fromJson(Map<String, dynamic> json) {
    final project = Project(
      name: json['name'] as String? ?? 'Untitled',
      bpm: json['bpm'] as int? ?? 120,
      stepsPerBeat: json['stepsPerBeat'] as int? ?? 4,
      beatsPerBar: json['beatsPerBar'] as int? ?? 4,
      totalBars: json['totalBars'] as int? ?? 4,
      activeTrack: json['activeTrack'] as int? ?? 0,
      scaleRoot: json['scaleRoot'] as int? ?? 0,
      scaleName: json['scaleName'] as String? ?? 'Major',
    );

    project.tracks.clear();
    final tracks = (json['tracks'] as List<dynamic>?) ?? [];
    for (final t in tracks) {
      project.tracks.add(_trackFromJson(t as Map<String, dynamic>));
    }
    if (project.tracks.isEmpty) {
      project.tracks.add(Track(name: 'Track 1'));
    }
    project.selection.clear();
    final sel = (json['selection'] as List<dynamic>?) ?? [];
    for (final s in sel) {
      final n = _noteFromJson(s as Map<String, dynamic>);
      project.selection.add(n);
    }
    return project;
  }

  /// Write [project] to [path].
  static Future<void> saveToFile(Project project, String path) async {
    final file = File(path);
    final json = jsonEncode(toJson(project));
    await file.writeAsString(json, flush: true);
  }

  /// Load a project from [path].
  static Future<Project> loadFromFile(String path) async {
    final file = File(path);
    final text = await file.readAsString();
    final map = jsonDecode(text) as Map<String, dynamic>;
    return fromJson(map);
  }

  /// Save to a file with the default .sridaw extension.
  static Future<void> save(Project project, String directory, String name) async {
    final fileName = name.endsWith('.$extension') ? name : '$name.$extension';
    await saveToFile(project, '$directory/$fileName');
  }
}
