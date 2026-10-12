/// Pure-Dart project model. No Flutter/Material imports so it can be reused by
/// the command parser, the audio scheduler and unit tests alike.
library;

enum TrackType { synth, drum, sampler }

/// A note on a piano-roll / pattern grid. [start] and [len] are in 16th-note
/// steps; [pitch] is a MIDI note number (60 = C4).
class Note {
  int pitch;
  int start;
  int len;
  int vel; // 0..127

  Note({required this.pitch, required this.start, required this.len, this.vel = 100});

  int get end => start + len;
  bool contains(int otherStart) => otherStart >= start && otherStart < end;

  Note copy() => Note(pitch: pitch, start: start, len: len, vel: vel);
}

class Track {
  String name;
  TrackType type;
  int colorIndex;
  int instrument; // GM program for the existing engine
  int channel;
  bool mute;
  bool solo;
  int volume; // 0..127
  int pan; // -64..63
  List<Note> notes;

  Track({
    required this.name,
    this.type = TrackType.synth,
    this.colorIndex = 5,
    this.instrument = 0,
    this.channel = 0,
    this.mute = false,
    this.solo = false,
    this.volume = 100,
    this.pan = 0,
    List<Note>? notes,
  }) : notes = notes ?? [];

  int get program => instrument;
}

/// The whole song. Kept intentionally small for M1/M2; patterns, automation and
/// buses arrive in later milestones.
class Project {
  String name;
  int bpm;
  int stepsPerBeat; // 16th notes -> 4
  int beatsPerBar;
  int totalBars;
  List<Track> tracks;
  int activeTrack;
  final Set<Note> selection;

  /// Harmonic context for the whole project: a root pitch-class (0 = C) and a
  /// scale name from `music_theory.scales`.
  int scaleRoot;
  String scaleName;

  Project({
    this.name = 'Untitled',
    this.bpm = 120,
    this.stepsPerBeat = 4,
    this.beatsPerBar = 4,
    this.totalBars = 4,
    List<Track>? tracks,
    this.activeTrack = 0,
    this.scaleRoot = 0,
    this.scaleName = 'Major',
  })  : tracks = tracks ?? [Track(name: 'Track 1')],
        selection = {};

  int get stepsPerBar => stepsPerBeat * beatsPerBar;
  int get totalSteps => stepsPerBar * totalBars;

  Track get track => tracks[activeTrack];

  /// All notes from every track except the active one (painted as ghosts).
  Iterable<({int trackIndex, Note note})> get ghostNotes sync* {
    for (var t = 0; t < tracks.length; t++) {
      if (t == activeTrack) continue;
      for (final n in tracks[t].notes) {
        yield (trackIndex: t, note: n);
      }
    }
  }

  Note? noteAt(int pitch, int start) {
    for (final n in track.notes) {
      if (n.pitch == pitch && n.contains(start)) return n;
    }
    return null;
  }

  /// A tiny demo song so the roll is not empty on first launch.
  static Project demo() {
    final p = Project(name: 'Demo', totalBars: 4);
    final lead = p.tracks.first;
    lead.name = 'Lead';
    lead.instrument = 80;
    lead.colorIndex = 5;
    lead.notes = [
      Note(pitch: 60, start: 0, len: 4, vel: 100),
      Note(pitch: 64, start: 4, len: 4, vel: 90),
      Note(pitch: 67, start: 8, len: 4, vel: 110),
      Note(pitch: 72, start: 12, len: 4, vel: 120),
      Note(pitch: 67, start: 20, len: 2, vel: 80),
      Note(pitch: 64, start: 24, len: 8, vel: 95),
    ];
    p.tracks.add(Track(
      name: 'Bass',
      instrument: 32,
      colorIndex: 6,
      channel: 1,
      notes: [
        Note(pitch: 36, start: 0, len: 8, vel: 100),
        Note(pitch: 43, start: 16, len: 8, vel: 100),
      ],
    ));
    return p;
  }
}
