/// Music-theory driven composition helpers.
///
/// Pure Dart (no Flutter imports) so it can be unit-tested and reused by the
/// command parser. Everything here turns a compact textual instruction into
/// [Note]s on the project grid.
///
/// The vocabulary follows the course in `my-e-books/music theory`:
/// roman-numeral progressions, voice leading, figured-bass inversions,
/// sequences, cadences, harmonisation, motifs and the three pattern
/// libraries (chords / melodies / rhythms).
library;

import 'dart:math' as math;

import '../model/project.dart';
import '../music_theory.dart' as mt;
import 'pattern_library.dart';

// ---------------------------------------------------------------------------
// Keys and chord symbols
// ---------------------------------------------------------------------------

const Map<String, int> _letterPc = {
  'C': 0,
  'D': 2,
  'E': 4,
  'F': 5,
  'G': 7,
  'A': 9,
  'B': 11,
};

/// Parse a note name (`C`, `F#`, `Bb`) into a pitch class 0..11.
int? parseRoot(String s) {
  if (s.isEmpty) return null;
  final letter = _letterPc[s[0].toUpperCase()];
  if (letter == null) return null;
  var pc = letter;
  for (var i = 1; i < s.length; i++) {
    final c = s[i];
    if (c == '#' || c == '♯') {
      pc += 1;
    } else if (c == 'b' || c == '♭') {
      // Only treat a trailing 'b' as a flat; `Bb` is valid, `B` alone is not.
      if (i == s.length - 1) pc -= 1;
    }
  }
  return ((pc % 12) + 12) % 12;
}

/// Common qualities used by roman numerals and lead-sheet symbols.
const Map<String, List<int>> chordQualities = {
  '': [0, 4, 7],
  'm': [0, 3, 7],
  'dim': [0, 3, 6],
  '°': [0, 3, 6],
  'o': [0, 3, 6],
  'aug': [0, 4, 8],
  '+': [0, 4, 8],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'M7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'dim7': [0, 3, 6, 9],
  '°7': [0, 3, 6, 9],
  'm7b5': [0, 3, 6, 10],
  'ø7': [0, 3, 6, 10],
  '6': [0, 4, 7, 9],
  'm6': [0, 3, 7, 9],
  'add9': [0, 4, 7, 14],
  '9': [0, 4, 7, 10, 14],
  'maj9': [0, 4, 7, 11, 14],
  'm9': [0, 3, 7, 10, 14],
};

class ChordSpec {
  final int rootPc;
  final List<int> offsets;
  final String label;
  const ChordSpec(this.rootPc, this.offsets, this.label);
}

class TheoryError implements Exception {
  final String message;
  TheoryError(this.message);
  @override
  String toString() => message;
}

const Map<String, List<String>> namedProgressions = {
  'pop': ['I', 'V', 'vi', 'IV'],
  '50s': ['I', 'vi', 'IV', 'V'],
  'doowop': ['I', 'vi', 'IV', 'V'],
  'axis': ['vi', 'IV', 'I', 'V'],
  'royalroad': ['IV', 'V', 'iii', 'vi'],
  'canon': ['I', 'V', 'vi', 'iii', 'IV', 'I', 'IV', 'V'],
  'jazz': ['ii7', 'V7', 'Imaj7'],
  '251': ['ii7', 'V7', 'Imaj7'],
  'ii-v-i': ['ii7', 'V7', 'Imaj7'],
  'blues': ['I7', 'I7', 'I7', 'I7', 'IV7', 'IV7', 'I7', 'I7', 'V7', 'IV7', 'I7', 'V7'],
  'turnaround': ['I', 'vi', 'ii', 'V'],
  'andalusian': ['i', 'VII', 'VI', 'V'],
  'plagal': ['IV', 'I'],
  'descending': ['I', 'vii', 'vi', 'V'],
  'epic': ['i', 'VI', 'III', 'VII'],
  'minor-pop': ['i', 'VI', 'III', 'VII'],
  'sad': ['i', 'iv', 'VI', 'V'],
  'circle': ['vi', 'ii', 'V', 'I'],
  'hexatonic': ['I', 'iii', 'IV', 'V'],
};

final RegExp _romanRe = RegExp(r'^([b#]?)([ivIV]+)(.*)$');
final RegExp _symbolRe = RegExp(r'^([A-Ga-g])([#b]?)(.*)$');

/// Parse a progression string. Tokens may be roman numerals (`I`, `vi`,
/// `V7`, `vii°`) or lead-sheet symbols (`C`, `Am7`, `F#dim`). Named
/// progressions (`pop`, `canon`, `blues`, ...) expand to numerals.
List<ChordSpec> parseProgression(
  String raw, {
  required int keyRoot,
  required String scaleName,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) throw TheoryError('empty progression');
  final named = namedProgressions[trimmed.toLowerCase()];
  final tokens = named ??
      trimmed
          .replaceAll(RegExp(r'[|,]'), ' ')
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
  final scale = mt.scales[scaleName] ?? mt.scales['Major']!;
  final out = <ChordSpec>[];
  for (final token in tokens) {
    final spec = _parseToken(token, keyRoot, scale);
    if (spec != null) out.add(spec);
  }
  if (out.isEmpty) throw TheoryError('no chords in "$raw"');
  return out;
}

ChordSpec? _parseToken(String token, int keyRoot, List<int> scale) {
  // `_romanRe` only matches optional accidental + I/V letters, so lead-sheet
  // symbols (`C`, `Am7`, `Bb`, `F#dim`) never collide with numerals.
  final rm = _romanRe.firstMatch(token);
  if (rm != null) {
    final accidental = rm.group(1) ?? '';
    final numerals = rm.group(2)!;
    final suffix = rm.group(3) ?? '';
    final degree = _romanToDegree(numerals);
    if (degree == null) throw TheoryError('bad roman numeral "$token"');
    final alter = accidental == '#' ? 1 : (accidental == 'b' ? -1 : 0);
    final idx = (degree - 1) % scale.length;
    final rootPc = ((keyRoot + scale[idx] + alter) % 12 + 12) % 12;
    final minorCase = numerals == numerals.toLowerCase();
    List<int>? offsets;
    if (suffix.isEmpty) {
      offsets = minorCase ? const [0, 3, 7] : const [0, 4, 7];
    } else if (suffix == '7' && minorCase) {
      offsets = const [0, 3, 7, 10];
    } else if (_isDimSuffix(suffix)) {
      offsets = degree == 7 ? const [0, 3, 6] : chordQualities['dim'];
    } else {
      offsets = _qualityFor(suffix);
    }
    if (offsets == null) throw TheoryError('unknown chord quality "$suffix"');
    return ChordSpec(rootPc, offsets, token);
  }

  // Lead-sheet chord (`C`, `Am7`, `Bb`).
  final sym = _symbolRe.firstMatch(token);
  if (sym == null) return null;
  final pc = parseRoot(sym.group(1)! + (sym.group(2) ?? ''));
  if (pc == null) return null;
  final suffix = sym.group(3) ?? '';
  final offsets = _qualityFor(suffix);
  if (offsets == null) throw TheoryError('unknown chord quality "$suffix"');
  return ChordSpec(pc, offsets, _chordLabel(pc, suffix));
}

bool _isDimSuffix(String s) =>
    s == '°' || s == 'o' || s == 'dim' || s == '°7' || s == 'o7';

List<int>? _qualityFor(String suffix) {
  if (suffix.isEmpty) return const [0, 4, 7];
  return chordQualities[suffix] ??
      chordQualities[suffix.toLowerCase()] ??
      chordQualities[suffix.toUpperCase()];
}

int? _romanToDegree(String numerals) {
  const map = {
    'I': 1,
    'II': 2,
    'III': 3,
    'IV': 4,
    'V': 5,
    'VI': 6,
    'VII': 7,
  };
  return map[numerals.toUpperCase()];
}

String _chordLabel(int pc, String suffix) => '${mt.noteNames[pc]}$suffix';

// ---------------------------------------------------------------------------
// Voicing and voice leading
// ---------------------------------------------------------------------------

double _avgDistance(List<int> voicing, int centre) {
  final avg = voicing.reduce((a, b) => a + b) / voicing.length;
  return (avg - centre).abs();
}

/// Pick the inversion/octave of [chord] closest to [previous] (voice leading)
/// or nearest [centre] when there is nothing to lead from.
List<int> voiceChord(ChordSpec chord, {List<int>? previous, int centre = 60}) {
  final candidates = <List<int>>[];
  final rootPc = ((chord.rootPc % 12) + 12) % 12;
  for (var oct = 2; oct <= 6; oct++) {
    final base = rootPc + 12 * oct;
    for (var inv = 0; inv < chord.offsets.length; inv++) {
      final voiced = <int>[];
      for (var i = 0; i < chord.offsets.length; i++) {
        final idx = (inv + i) % chord.offsets.length;
        var p = base + chord.offsets[idx];
        if (idx < inv) p += 12;
        voiced.add(p);
      }
      voiced.sort();
      if (voiced.first < 36 || voiced.last > 96) continue;
      candidates.add(voiced);
    }
  }
  if (candidates.isEmpty) return [60 + rootPc];
  if (previous == null || previous.isEmpty) {
    candidates.sort((a, b) =>
        _avgDistance(a, centre).compareTo(_avgDistance(b, centre)));
    return candidates.first;
  }
  int cost(List<int> v) {
    var sum = 0;
    for (final p in v) {
      var best = 999;
      for (final q in previous) {
        final d = (p - q).abs();
        if (d < best) best = d;
      }
      sum += best;
    }
    return sum * 100 + _avgDistance(v, centre).round();
  }

  candidates.sort((a, b) => cost(a).compareTo(cost(b)));
  return candidates.first;
}

List<List<int>> progressionVoicings(List<ChordSpec> chords, {int centre = 60}) {
  final out = <List<int>>[];
  List<int>? previous;
  for (final chord in chords) {
    final v = voiceChord(chord, previous: previous, centre: centre);
    out.add(v);
    previous = v;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

/// Block-chord progression, one chord every [barLen] * [barsPerChord] steps.
List<Note> progressionNotes(
  List<ChordSpec> chords, {
  required int startCol,
  required int barLen,
  int barsPerChord = 1,
  int centre = 60,
  int vel = 100,
}) {
  final voicings = progressionVoicings(chords, centre: centre);
  final dur = math.max(1, barLen * barsPerChord);
  final notes = <Note>[];
  var col = startCol;
  for (final voicing in voicings) {
    for (final p in voicing) {
      notes.add(Note(
        pitch: p.clamp(0, 127),
        start: col,
        len: dur,
        vel: vel,
      ));
    }
    col += dur;
  }
  return notes;
}

/// Strum a chord progression.
///
/// [pattern] is a strum rhythm with one character per [stepLen] steps:
///
/// * `d` / `D` – downstroke (the full voicing)
/// * `u` / `U` – upstroke (drops the lowest voice)
/// * `x` / `X` – muted hit (short and quiet)
/// * `-`, `.`, `_` – rest
///
/// Uppercase hits are accented. Each chord lasts [barLen] steps and the
/// pattern repeats to fill the bar. Hits ring until the next attack.
List<Note> strumProgression(
  List<ChordSpec> chords, {
  required int startCol,
  required int barLen,
  String pattern = 'd',
  int stepLen = 1,
  int centre = 60,
  int vel = 100,
}) {
  if (chords.isEmpty) return const [];
  final p = pattern.replaceAll(RegExp(r'\s+'), '');
  if (p.isEmpty) throw TheoryError('empty strum pattern');
  for (final ch in p.split('')) {
    if (!'dDuUxX-._'.contains(ch)) {
      throw TheoryError('bad strum character "$ch" (use d u x or -)');
    }
  }
  final voicings = progressionVoicings(chords, centre: centre);
  final step = math.max(1, stepLen);
  final bar = math.max(1, barLen);
  final notes = <Note>[];
  for (var c = 0; c < voicings.length; c++) {
    final voicing = voicings[c];
    final barStart = startCol + c * bar;
    final barEnd = barStart + bar;
    final attacks = <({int col, String ch})>[];
    var col = barStart;
    var i = 0;
    while (col < barEnd) {
      final ch = p[i % p.length];
      if (!'-._'.contains(ch)) attacks.add((col: col, ch: ch));
      col += step;
      i++;
    }
    for (var a = 0; a < attacks.length; a++) {
      final at = attacks[a];
      final next = a + 1 < attacks.length ? attacks[a + 1].col : barEnd;
      final lower = at.ch.toLowerCase();
      final muted = lower == 'x';
      final up = lower == 'u';
      final accent = at.ch != lower;
      final tones = up && voicing.length > 2 ? voicing.sublist(1) : voicing;
      var len = math.max(1, next - at.col);
      if (muted) len = 1;
      final hitVel = muted
          ? (vel * 0.6).round()
          : (up ? vel - 12 : vel) + (accent ? 10 : 0);
      for (final pitch in tones) {
        notes.add(Note(
          pitch: pitch.clamp(0, 127),
          start: at.col,
          len: len,
          vel: hitVel.clamp(1, 127),
        ));
      }
    }
  }
  return notes;
}

/// Either one root/fifth pair per bar (`simple`) or a four-beat walking line.
List<Note> bassNotes(
  List<ChordSpec> chords, {
  required int startCol,
  required int barLen,
  required int stepsPerBeat,
  int octave = 2,
  bool walking = false,
}) {
  final notes = <Note>[];
  var col = startCol;
  final low = 12 * (octave + 1); // C2 = 36 when octave = 2
  for (var c = 0; c < chords.length; c++) {
    final chord = chords[c];
    final root = low + ((chord.rootPc % 12) + 12) % 12;
    if (walking) {
      final tones = chord.offsets.map((o) => root + o).toList();
      final next = chords[(c + 1) % chords.length];
      final nextRoot = low + ((next.rootPc % 12) + 12) % 12;
      final approach = nextRoot > root ? nextRoot - 1 : nextRoot + 1;
      final beats = math.max(1, barLen ~/ stepsPerBeat);
      final line = <int>[
        root,
        tones.length > 1 ? tones[1] : root,
        tones.length > 2 ? tones[2] : root,
      ];
      while (line.length < beats) {
        line.add(root + 12);
      }
      if (beats > 0) line[beats - 1] = approach;
      for (var b = 0; b < beats; b++) {
        notes.add(Note(
          pitch: line[b].clamp(0, 127),
          start: col + b * stepsPerBeat,
          len: stepsPerBeat,
          vel: 96,
        ));
      }
    } else {
      final half = math.max(1, barLen ~/ 2);
      notes.add(Note(pitch: root.clamp(0, 127), start: col, len: half, vel: 100));
      final fifth = root + 7;
      notes.add(Note(
        pitch: fifth.clamp(0, 127),
        start: col + half,
        len: math.max(1, barLen - half),
        vel: 92,
      ));
    }
    col += barLen;
  }
  return notes;
}

/// Arpeggiate [voicing]. [pattern]: up | down | updown | downup | alberti |
/// broken. [stepLen] is in 16th steps; [repeat] cycles the figure.
List<Note> arpeggioNotes(
  List<int> voicing, {
  required int startCol,
  int stepLen = 1,
  String pattern = 'up',
  int octaves = 1,
  int repeat = 1,
  int vel = 100,
}) {
  if (voicing.isEmpty) return const [];
  final base = voicing.toSet().toList()..sort();
  final spread = <int>[];
  for (var o = 0; o < math.max(1, octaves); o++) {
    for (final p in base) {
      spread.add(p + 12 * o);
    }
  }
  List<int> figure;
  switch (pattern.toLowerCase()) {
    case 'down':
      figure = spread.reversed.toList();
    case 'updown':
      figure = [...spread, ...spread.reversed.skip(1).take(spread.length - 1)];
    case 'downup':
      final down = spread.reversed.toList();
      figure = [...down, ...down.reversed.skip(1).take(down.length - 1)];
    case 'alberti':
      // root, fifth, third, fifth (using lowest, highest, middle)
      if (spread.length >= 3) {
        figure = [spread[0], spread[2], spread[1], spread[2]];
      } else {
        figure = spread;
      }
    case 'broken':
      figure = spread;
    default:
      figure = spread;
  }
  final notes = <Note>[];
  var col = startCol;
  for (var r = 0; r < math.max(1, repeat); r++) {
    for (final p in figure) {
      notes.add(Note(
        pitch: p.clamp(0, 127),
        start: col,
        len: stepLen,
        vel: vel,
      ));
      col += stepLen;
    }
  }
  return notes;
}

const List<List<int>> _rhythmCells = [
  [4, 4, 4, 4],
  [2, 2, 2, 2, 4, 4],
  [4, 2, 2, 4, 4],
  [8, 4, 4],
  [2, 2, 4, 8],
  [4, 4, 2, 2, 4],
  [2, 2, 2, 2, 2, 2, 4],
  [4, 8, 4],
  [2, 2, 8, 4],
  [16],
];

/// A scale-based melody with a chosen contour, deterministic per [seed].
List<Note> generateMelody({
  required int keyRoot,
  required String scaleName,
  required int startCol,
  required int bars,
  required int stepsPerBar,
  required int stepsPerBeat,
  String contour = 'arch',
  int seed = 1,
  int vel = 96,
}) {
  final intervals = mt.scales[scaleName] ?? mt.scales['Major']!;
  final rng = math.Random(seed);
  final lowPitch = 60 + keyRoot;
  final span = intervals.length * 2; // two octaves of scale degrees

  int pitchFor(double t) {
    double shape;
    switch (contour.toLowerCase()) {
      case 'up':
        shape = t;
      case 'down':
        shape = 1 - t;
      case 'wave':
        shape = 0.5 + 0.5 * math.sin(t * math.pi * 3);
      case 'random':
        shape = rng.nextDouble();
      case 'arch':
      default:
        shape = math.sin(t * math.pi);
    }
    var degree = (shape.clamp(0.0, 1.0) * (span - 1)).round();
    degree = degree.clamp(0, span - 1);
    final octave = degree ~/ intervals.length;
    final pc = intervals[degree % intervals.length];
    return lowPitch + pc + 12 * octave;
  }

  final notes = <Note>[];
  var col = startCol;
  var cell = 0;
  var processed = 0;
  var planned = 0;
  for (var bar = 0; bar < bars; bar++) {
    var barCol = 0;
    while (barCol < stepsPerBar) {
      final rhythm = _rhythmCells[cell % _rhythmCells.length];
      cell++;
      for (final len in rhythm) {
        if (barCol + len > stepsPerBar) break;
        final t = (processed == 0) ? 0.0 : (processed / (planned + 1)).clamp(0.0, 1.0);
        var pitch = pitchFor(t);
        if (processed == 0) pitch = lowPitch; // start on the tonic
        if (bar == bars - 1 && barCol + len >= stepsPerBar) {
          pitch = lowPitch + 12; // end on the tonic an octave up
        }
        notes.add(Note(
          pitch: pitch.clamp(0, 127),
          start: col + barCol,
          len: len,
          vel: vel,
        ));
        barCol += len;
        processed++;
        planned++;
      }
      if (barCol < stepsPerBar) {
        // Safety: make sure the bar is filled.
        final remain = stepsPerBar - barCol;
        notes.add(Note(
          pitch: pitchFor(barCol / stepsPerBar).clamp(0, 127),
          start: col + barCol,
          len: remain,
          vel: vel,
        ));
        barCol = stepsPerBar;
      }
    }
    col += stepsPerBar;
  }
  return notes;
}

/// Diatonic transposition by [steps] scale degrees (0 = unchanged).
int diatonicShift(int pitch, int steps, int keyRoot, List<int> intervals) {
  if (steps == 0) return pitch;
  final rel = pitch - keyRoot;
  final octave = (rel / 12).floor();
  final pc = ((rel % 12) + 12) % 12;
  var index = intervals.indexOf(pc);
  var chromatic = 0;
  if (index < 0) {
    // Out of scale: use the nearest lower degree and remember the offset.
    var best = 0;
    for (var i = 0; i < intervals.length; i++) {
      if (intervals[i] <= pc && intervals[i] >= intervals[best]) best = i;
    }
    index = best;
    chromatic = pc - intervals[best];
  }
  final target = index + steps;
  final len = intervals.length;
  final octShift = (target / len).floor();
  final newIndex = ((target % len) + len) % len;
  return keyRoot +
      intervals[newIndex] +
      12 * (octave + octShift) +
      chromatic;
}

/// Sequence a motif: [times] copies shifted by [degreeStep] scale degrees.
List<Note> sequenceNotes(
  List<Note> motif, {
  required int startCol,
  required int times,
  required int degreeStep,
  required int keyRoot,
  required String scaleName,
}) {
  if (motif.isEmpty) return const [];
  final intervals = mt.scales[scaleName] ?? mt.scales['Major']!;
  final span = motif.map((n) => n.end).reduce(math.max) -
      motif.map((n) => n.start).reduce(math.min);
  final origin = motif.map((n) => n.start).reduce(math.min);
  final out = <Note>[];
  for (var r = 1; r <= times; r++) {
    for (final n in motif) {
      out.add(Note(
        pitch: diatonicShift(n.pitch, degreeStep * r, keyRoot, intervals)
            .clamp(0, 127),
        start: startCol + span * r + (n.start - origin),
        len: n.len,
        vel: n.vel,
      ));
    }
  }
  return out;
}

/// Add a diatonic interval above (or below) each note. [degreeInterval] is in
/// scale degrees: 2 = third, 4 = fifth, 5 = sixth.
List<Note> harmonizeNotes(
  List<Note> notes, {
  required int keyRoot,
  required String scaleName,
  int degreeInterval = 2,
  bool below = false,
}) {
  final intervals = mt.scales[scaleName] ?? mt.scales['Major']!;
  final out = <Note>[];
  for (final n in notes) {
    final p = diatonicShift(
      n.pitch,
      below ? -degreeInterval : degreeInterval,
      keyRoot,
      intervals,
    ).clamp(0, 127);
    out.add(Note(pitch: p, start: n.start, len: n.len, vel: n.vel));
  }
  return out;
}

/// Figured-bass inversion: move the lowest [inversion] voices up an octave.
List<Note> invertChordNotes(List<Note> chord, int inversion) {
  if (chord.isEmpty) return const [];
  final sorted = [...chord]..sort((a, b) => a.pitch.compareTo(b.pitch));
  final n = inversion.clamp(0, sorted.length - 1);
  final out = <Note>[];
  for (var i = 0; i < sorted.length; i++) {
    final note = sorted[i];
    final pitch = i < n ? note.pitch + 12 : note.pitch;
    out.add(Note(
      pitch: pitch.clamp(0, 127),
      start: note.start,
      len: note.len,
      vel: note.vel,
    ));
  }
  return out;
}

/// Respace a chord into close position around its lowest note.
List<Note> closeVoicing(List<Note> chord) {
  if (chord.isEmpty) return const [];
  final sorted = [...chord]..sort((a, b) => a.pitch.compareTo(b.pitch));
  final low = sorted.first.pitch;
  final pcs = sorted.map((n) => n.pitch % 12).toSet().toList()..sort();
  final rebuilt = <int>[];
  for (final pc in pcs) {
    var p = low + (((pc - low) % 12) + 12) % 12;
    while (rebuilt.isNotEmpty && p <= rebuilt.last) {
      p += 12;
    }
    rebuilt.add(p);
  }
  final out = <Note>[];
  for (var i = 0; i < sorted.length; i++) {
    final src = sorted[i];
    final p = rebuilt[math.min(i, rebuilt.length - 1)];
    out.add(Note(pitch: p.clamp(0, 127), start: src.start, len: src.len, vel: src.vel));
  }
  return out;
}

/// Open (drop-2 style) voicing: lift alternate upper voices by an octave.
List<Note> openVoicing(List<Note> chord) {
  final closed = closeVoicing(chord);
  if (closed.length < 3) return closed;
  final out = <Note>[];
  for (var i = 0; i < closed.length; i++) {
    final n = closed[i];
    final lift = i > 0 && i.isEven ? 12 : 0;
    out.add(Note(
      pitch: (n.pitch + lift).clamp(0, 127),
      start: n.start,
      len: n.len,
      vel: n.vel,
    ));
  }
  return out;
}

List<Note> transposeNotes(List<Note> notes, int semitones) => notes
    .map((n) => Note(
          pitch: (n.pitch + semitones).clamp(0, 127),
          start: n.start,
          len: n.len,
          vel: n.vel,
        ))
    .toList();

List<Note> snapToScale(
  List<Note> notes, {
  required int keyRoot,
  required String scaleName,
}) {
  final intervals = mt.scales[scaleName] ?? mt.scales['Major']!;
  return notes.map((n) {
    final pc = n.pitch % 12;
    final target = mt.nearestInScalePc(pc, keyRoot, intervals);
    var delta = target - pc;
    if (delta > 6) delta -= 12;
    if (delta < -6) delta += 12;
    return Note(
      pitch: (n.pitch + delta).clamp(0, 127),
      start: n.start,
      len: n.len,
      vel: n.vel,
    );
  }).toList();
}

/// Cadence figures. Returns the chord specs to lay down.
List<ChordSpec> cadenceProgression(
  String type, {
  required int keyRoot,
  required String scaleName,
}) {
  final t = type.toLowerCase();
  final numerals = switch (t) {
    'pac' || 'iac' || 'ac' => 'V I',
    'hc' || 'half' => 'I V',
    'dc' || 'deceptive' => 'V vi',
    'pc' || 'plagal' => 'IV I',
    'phrygian' || 'phc' => 'iv6 V',
    _ => throw TheoryError('cadence: pac|iac|hc|dc|pc'),
  };
  return parseProgression(numerals,
      keyRoot: keyRoot, scaleName: scaleName);
}

/// Roman-numeral analysis of a chord (list of MIDI pitches).
String analyzeChord(
  List<int> pitches, {
  required int keyRoot,
  required String scaleName,
}) {
  if (pitches.isEmpty) return 'no notes';
  final pcs = pitches.map((p) => ((p % 12) + 12) % 12).toSet().toList()..sort();
  final name = mt.detectChord(pcs) ?? '?';
  final intervals = mt.scales[scaleName] ?? mt.scales['Major']!;
  final rootPc = pcs.first;
  final rel = ((rootPc - keyRoot) % 12 + 12) % 12;
  final degreeIndex = intervals.indexOf(rel);
  if (degreeIndex < 0) {
    return '$name · chromatic (not in ${mt.noteNames[keyRoot]} $scaleName)';
  }
  final roman = mt.romanFor(degreeIndex + 1, intervals, degreeIndex);
  final seventh = pcs.length >= 4 ? '7' : '';
  final fn = mt.degreeFunctionLabel(degreeIndex);
  return '$name = $roman$seventh · $fn';
}

// ---------------------------------------------------------------------------
// Pattern-library access
// ---------------------------------------------------------------------------

/// Normalise `c1` / `C001` / `c001` to a library id.
String normalizePatternId(String raw) {
  final m = RegExp(r'^([cCbBmM])\s*0*([0-9]+)$').firstMatch(raw.trim());
  if (m == null) return raw.toLowerCase();
  final kind = m.group(1)!.toLowerCase();
  final n = int.parse(m.group(2)!);
  return '$kind${n.toString().padLeft(3, '0')}';
}

List<LibPattern> libraryFor(String kind) {
  switch (kind.toLowerCase()) {
    case 'm':
    case 'melody':
    case 'motif':
      return melodyPatterns;
    case 'b':
    case 'beat':
    case 'rhythm':
    case 'drum':
    case 'drums':
      return rhythmPatterns;
    default:
      return chordPatterns;
  }
}

/// Find by id, or by the first title/section match (case-insensitive).
LibPattern? findPattern(String kind, String query) {
  final lib = libraryFor(kind);
  final id = normalizePatternId(query);
  for (final p in lib) {
    if (p.id == id) return p;
  }
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return null;
  int? numeric;
  if (RegExp(r'^[0-9]+$').hasMatch(q)) {
    numeric = int.tryParse(q);
  }
  if (numeric != null) {
    const prefix = {'m': 'm', 'b': 'b'};
    final pfx = prefix[kind] ?? 'c';
    return findPattern(kind, '$pfx$numeric');
  }
  for (final p in lib) {
    if (p.title.toLowerCase().contains(q) ||
        p.section.toLowerCase().contains(q)) {
      return p;
    }
  }
  return null;
}

/// Convert a library pattern to notes at [startCol]. Chord/melody patterns are
/// shifted into the project key unless [transpose] is false; drum patterns keep
/// their GM pitches.
List<Note> patternNotes(
  LibPattern pattern, {
  required int startCol,
  required int keyRoot,
  bool transpose = true,
}) {
  final shift = (pattern.drums || !transpose) ? 0 : keyRoot;
  final notes = <Note>[];
  var col = startCol;
  for (final step in pattern.steps) {
    final len = math.max(1, (step.dur / 32).round());
    for (var i = 0; i < step.notes.length; i++) {
      final vel = step.vel != null && i < step.vel!.length ? step.vel![i] : 100;
      notes.add(Note(
        pitch: (step.notes[i] + shift).clamp(0, 127),
        start: col,
        len: len,
        vel: vel.clamp(1, 127),
      ));
    }
    col += len;
  }
  return notes;
}
