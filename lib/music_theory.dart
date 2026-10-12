/// Music-theory helpers: scales, triads, chord detection.
///
/// All functions are pure/Dart-only so they work identically on native and web.
library;

const List<String> noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B'
];

const Map<String, List<int>> scales = {
  'Major': [0, 2, 4, 5, 7, 9, 11],
  'Natural Minor': [0, 2, 3, 5, 7, 8, 10],
  'Dorian': [0, 2, 3, 5, 7, 9, 10],
  'Phrygian': [0, 1, 3, 5, 7, 8, 10],
  'Lydian': [0, 2, 4, 6, 7, 9, 11],
  'Mixolydian': [0, 2, 4, 5, 7, 9, 10],
  'Locrian': [0, 1, 3, 5, 6, 8, 10],
  'Major Pentatonic': [0, 2, 4, 7, 9],
  'Minor Pentatonic': [0, 3, 5, 7, 10],
};

/// Returns [rootOffset(0), thirdOffset, fifthOffset] in semitones from the
/// scale's root, for the diatonic triad built on scale-degree index `i` (0-based).
List<int> triadForDegree(List<int> intervals, int i) {
  final L = intervals.length;
  int wrapped(int idx) => intervals[idx % L] + 12 * (idx ~/ L);
  final root = wrapped(i);
  final third = wrapped(i + 2);
  final fifth = wrapped(i + 4);
  return [0, third - root, fifth - root];
}

/// Chord-quality lookup from (third, fifth) semitone offsets.
String qualityLabel(int third, int fifth) {
  if (third == 3 && fifth == 7) return 'min';
  if (third == 4 && fifth == 7) return 'maj';
  if (third == 3 && fifth == 6) return 'dim';
  if (third == 4 && fifth == 8) return 'aug';
  return '—';
}

/// Auto-detect a chord name from note pitch-classes sharing one column.
const Map<String, String> chordShapes = {
  '0,4,7': '',
  '0,3,7': 'm',
  '0,3,6': '°',
  '0,4,8': '+',
  '0,2,7': 'sus2',
  '0,5,7': 'sus4',
  '0,4,7,11': 'maj7',
  '0,3,7,10': 'm7',
  '0,4,7,10': '7',
  '0,3,6,9': '°7',
};

String? detectChord(List<int> pitchClasses) {
  if (pitchClasses.length < 2) return null;
  final abs = List<int>.from(pitchClasses)..sort();
  final root = abs.first;
  final pcs = abs.map((a) => ((a - root) % 12 + 12) % 12).toSet().toList()..sort();
  final key = pcs.join(',');
  final suffix = chordShapes[key];
  final rootName = noteNames[((root % 12) + 12) % 12];
  return suffix != null ? '$rootName$suffix' : '$rootName?';
}

/// Compute the absolute (oct, n) pitches for a chord pad's triad.
List<({int oct, int n})> chordPitches(int rootNoteIndex, String scaleName, int degreeIndex) {
  final intervals = scales[scaleName] ?? scales['Major']!;
  final rootAbs = 5 * 12 + rootNoteIndex; // base octave 4 (C4 = MIDI 60)
  final out = <({int oct, int n})>[];
  for (final offset in triadForDegree(intervals, degreeIndex)) {
    final abs = rootAbs + offset;
    out.add((oct: abs ~/ 12, n: ((abs % 12) + 12) % 12));
  }
  return out;
}

/// Is a (oct, n) pitch inside the current scale (given root + scale name)?
bool isInScale(int oct, int n, int rootNoteIndex, String scaleName) {
  final intervals = scales[scaleName] ?? scales['Major']!;
  final rel = ((n - rootNoteIndex) % 12 + 12) % 12;
  return intervals.contains(rel);
}

/// Scale-degree number (1-based) for a pitch, or null if out of scale.
int? scaleDegree(int n, int rootNoteIndex, String scaleName) {
  final intervals = scales[scaleName] ?? scales['Major']!;
  final rel = ((n - rootNoteIndex) % 12 + 12) % 12;
  for (int i = 0; i < intervals.length; i++) {
    if (intervals[i] == rel) return i + 1;
  }
  return null;
}

String noteLabel(int oct, int n) => '${noteNames[((n % 12) + 12) % 12]}$oct';

const List<String> degreeFunctions = [
  'TONIC',
  'SUPERTONIC',
  'MEDIANT',
  'SUBDOMINANT',
  'DOMINANT',
  'SUBMEDIANT',
  'LEADING TONE',
];

String degreeFunctionLabel(int degreeIndex) {
  if (degreeIndex >= 0 && degreeIndex < degreeFunctions.length) {
    return degreeFunctions[degreeIndex];
  }
  return '';
}

// ---------------------------------------------------------------------------
// Helio-inspired harmonic-context helpers (display-only overlay logic).
// The key signature (root + scale) is the harmonic context for row
// highlighting, chord suggestions, and rescale. Nothing here claims Helio
// shows every label; it powers the optional theory overlay in the roll.
// ---------------------------------------------------------------------------

/// Fixed-do solfège syllables for a 7-note scale degree (0-based).
const List<String> solfege7 = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Ti'];

/// Solfège label for a pitch, or null when out of scale / non-heptatonic.
String? solfegeFor(int n, int rootNoteIndex, String scaleName) {
  final deg = scaleDegree(n, rootNoteIndex, scaleName);
  if (deg == null) return null;
  final intervals = scales[scaleName] ?? scales['Major']!;
  if (intervals.length != 7) return null;
  return solfege7[(deg - 1) % 7];
}

/// Roman-numeral label with conventional case/quality for major-type scales.
/// Falls back to plain upper numerals for other scale lengths.
String romanFor(int degree1Based, List<int> intervals, int degreeIndexForQuality) {
  const upper7 = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
  if (intervals.length != 7) return '$degree1Based';
  final offsets = triadForDegree(intervals, degreeIndexForQuality);
  final q = qualityLabel(offsets[1], offsets[2]);
  final base = upper7[(degree1Based - 1) % 7];
  switch (q) {
    case 'min':
      return base.toLowerCase();
    case 'dim':
      return '${base.toLowerCase()}°';
    case 'aug':
      return '$base+';
    default:
      return base;
  }
}

/// True when this pitch-class is the dominant (5th degree) of the key.
bool isDominantPc(int n, int rootNoteIndex, String scaleName) {
  final intervals = scales[scaleName] ?? scales['Major']!;
  if (intervals.length < 5) return false;
  final rel = ((n - rootNoteIndex) % 12 + 12) % 12;
  return rel == intervals[4];
}

/// True when this pitch-class is the tonic of the key.
bool isTonicPc(int n, int rootNoteIndex, String scaleName) {
  return (((n - rootNoteIndex) % 12) + 12) % 12 == 0;
}

/// Named chord shapes (semitone offsets from the tapped root) for the
/// double-tap chord tool. Independent of the key; the dialog reports
/// whether every tone sits in the current scale.
const Map<String, List<int>> namedChordShapes = {
  'Major': [0, 4, 7],
  'Minor': [0, 3, 7],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
  'dim': [0, 3, 6],
  'aug': [0, 4, 8],
};

/// True when every offset of a named chord sits inside the current scale.
bool chordInScale(
    int rootPc, List<int> offsets, int keyRoot, String scaleName) {
  final intervals = scales[scaleName] ?? scales['Major']!;
  for (final off in offsets) {
    final pc = (rootPc + off) % 12;
    final rel = ((pc - keyRoot) % 12 + 12) % 12;
    if (!intervals.contains(rel)) return false;
  }
  return true;
}

/// Map a pitch to the nearest pitch-class inside [targetIntervals] relative
/// to [targetRoot]. Used by the quick-rescale function.
int nearestInScalePc(int pc, int targetRoot, List<int> targetIntervals) {
  int best = targetRoot;
  int bestDist = 99;
  for (final iv in targetIntervals) {
    final cand = (targetRoot + iv) % 12;
    int d = (pc - cand).abs();
    d = d > 6 ? 12 - d : d;
    if (d < bestDist) {
      bestDist = d;
      best = cand;
    }
  }
  return best;
}
