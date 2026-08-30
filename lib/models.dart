import 'package:flutter/material.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Layout constants
// ---------------------------------------------------------------------------
const double kTrackHeaderWidth = 104.0;
const double kTimelineRowHeight = 46.0;
const double kBarWidth = 120.0;
const int kTimelineBars = 8;

const double kRollKeyWidth = 80.0;
const double kRollRowHeight = 22.0;
const double kColWidth = 27.0;
const int kRollCols = 32; // 2 bars of 16th notes

/// MIDI helper: C4 = 60 in the convention octave = (midi ~/ 12) - 1.
int octNToMidi(int oct, int n) => (oct + 1) * 12 + n;
({int oct, int n}) midiToOctN(int midi) => (oct: (midi ~/ 12) - 1, n: midi % 12);

// ---------------------------------------------------------------------------
// Note / Pattern / Track
// ---------------------------------------------------------------------------
class NoteEvent {
  final int oct;
  final int n; // 0–11 semitone
  int startCol; // 16th-note column index
  final int len; // length in columns
  bool chordRoot; // marks lowest note of a chord group

  NoteEvent({
    required this.oct,
    required this.n,
    required this.startCol,
    required this.len,
    this.chordRoot = false,
  });
}

class Pattern {
  final String id;
  int start; // bar index
  int len; // length in bars
  String label;
  int seed; // deterministic thumbnail dots when notes is empty
  List<NoteEvent> notes;

  Pattern({
    required this.id,
    required this.start,
    required this.len,
    required this.label,
    required this.seed,
    List<NoteEvent>? notes,
  }) : notes = notes ?? [];
}

enum TrackType { drum, synth, audio }

class Track {
  final String name;
  final TrackType type;
  final Color color;
  bool mute;
  bool solo;
  int instrument; // GM program number (for the audio engine)
  double vol;
  double pan;
  double peak;
  List<Pattern> patterns;

  Track({
    required this.name,
    required this.type,
    required this.color,
    this.mute = false,
    this.solo = false,
    this.instrument = 0,
    this.vol = 0.8,
    this.pan = 0.0,
    this.peak = 0.0,
    List<Pattern>? patterns,
  }) : patterns = patterns ?? [];
}

// ---------------------------------------------------------------------------
// Sample project
// ---------------------------------------------------------------------------
List<Track> sampleProject() {
  final teal = AppColors.teal;
  final purple = AppColors.purple;
  final amber = AppColors.amber;
  final red = AppColors.red;

  return [
    Track(
      name: 'Keys',
      type: TrackType.synth,
      color: teal,
      instrument: 0,
      patterns: [
        Pattern(
          id: 'k1',
          start: 0,
          len: 2,
          label: 'K1',
          seed: 11,
          notes: [
            NoteEvent(oct: 4, n: 0, startCol: 0, len: 4),
            NoteEvent(oct: 4, n: 4, startCol: 4, len: 4),
            NoteEvent(oct: 4, n: 7, startCol: 8, len: 4, chordRoot: true),
            NoteEvent(oct: 5, n: 0, startCol: 16, len: 4),
            NoteEvent(oct: 4, n: 4, startCol: 20, len: 4),
            NoteEvent(oct: 4, n: 7, startCol: 24, len: 4),
          ],
        ),
        Pattern(
          id: 'k2',
          start: 4,
          len: 2,
          label: 'K2',
          seed: 23,
          notes: [
            NoteEvent(oct: 4, n: 9, startCol: 0, len: 4),
            NoteEvent(oct: 4, n: 0, startCol: 4, len: 4, chordRoot: true),
            NoteEvent(oct: 4, n: 4, startCol: 8, len: 4),
            NoteEvent(oct: 5, n: 0, startCol: 16, len: 4),
          ],
        ),
      ],
    ),
    Track(
      name: 'Bass',
      type: TrackType.synth,
      color: teal,
      instrument: 32,
      patterns: [
        Pattern(
          id: 'b1',
          start: 0,
          len: 2,
          label: 'B1',
          seed: 31,
          notes: [
            NoteEvent(oct: 3, n: 0, startCol: 0, len: 8, chordRoot: true),
            NoteEvent(oct: 3, n: 7, startCol: 16, len: 8),
          ],
        ),
      ],
    ),
    Track(
      name: 'Strings',
      type: TrackType.synth,
      color: purple,
      instrument: 48,
      patterns: [
        Pattern(
          id: 's1',
          start: 2,
          len: 2,
          label: 'S1',
          seed: 47,
          notes: [
            NoteEvent(oct: 4, n: 0, startCol: 0, len: 16, chordRoot: true),
            NoteEvent(oct: 4, n: 4, startCol: 0, len: 16),
            NoteEvent(oct: 4, n: 7, startCol: 0, len: 16),
          ],
        ),
      ],
    ),
    Track(
      name: 'Brass',
      type: TrackType.synth,
      color: amber,
      instrument: 56,
      patterns: [
        Pattern(
          id: 'br1',
          start: 4,
          len: 2,
          label: 'BR1',
          seed: 59,
          notes: [
            NoteEvent(oct: 4, n: 7, startCol: 0, len: 8, chordRoot: true),
            NoteEvent(oct: 4, n: 11, startCol: 8, len: 8),
          ],
        ),
      ],
    ),
    Track(
      name: 'Lead',
      type: TrackType.synth,
      color: red,
      instrument: 80,
      patterns: [
        Pattern(
          id: 'l1',
          start: 0,
          len: 1,
          label: 'L1',
          seed: 71,
          notes: [
            NoteEvent(oct: 5, n: 0, startCol: 0, len: 2),
            NoteEvent(oct: 5, n: 4, startCol: 4, len: 2),
            NoteEvent(oct: 5, n: 7, startCol: 8, len: 4, chordRoot: true),
          ],
        ),
      ],
    ),
    Track(
      name: 'Perc',
      type: TrackType.drum,
      color: amber,
      instrument: 115,
      patterns: [
        Pattern(
          id: 'p1',
          start: 0,
          len: 4,
          label: 'P1',
          seed: 83,
          notes: [
            NoteEvent(oct: 2, n: 0, startCol: 0, len: 2, chordRoot: true),
            NoteEvent(oct: 2, n: 0, startCol: 8, len: 2),
            NoteEvent(oct: 2, n: 0, startCol: 16, len: 2),
            NoteEvent(oct: 2, n: 0, startCol: 24, len: 2),
          ],
        ),
      ],
    ),
  ];
}
