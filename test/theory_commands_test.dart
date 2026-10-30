import 'package:flutter_test/flutter_test.dart';
import 'package:sridaw/model/project.dart';
import 'package:sridaw/theory/theory_commands.dart' as tc;

List<Note> notes(List<(int pitch, int start)> pairs, {int len = 4}) => [
      for (final (pitch, start) in pairs)
        Note(pitch: pitch, start: start, len: len),
    ];

void main() {
  group('progression parsing', () {
    test('roman numerals map to diatonic roots', () {
      final chords = tc.parseProgression('I V vi IV',
          keyRoot: 0, scaleName: 'Major');
      expect(chords.map((c) => c.rootPc), [0, 7, 9, 5]);
      expect(chords[2].offsets, [0, 3, 7]);
    });

    test('lead-sheet symbols are absolute', () {
      final chords = tc.parseProgression('C Am F G',
          keyRoot: 2, scaleName: 'Major');
      expect(chords.map((c) => c.rootPc), [0, 9, 5, 7]);
      expect(chords[1].offsets, [0, 3, 7]);
    });

    test('named progressions expand', () {
      final pop = tc.parseProgression('pop', keyRoot: 0, scaleName: 'Major');
      expect(pop.length, 4);
      final canon = tc.parseProgression('canon', keyRoot: 0, scaleName: 'Major');
      expect(canon.length, 8);
    });

    test('sevenths follow case (ii7 = m7, V7 = dominant)', () {
      final chords = tc.parseProgression('ii7 V7 Imaj7',
          keyRoot: 0, scaleName: 'Major');
      expect(chords[0].offsets, [0, 3, 7, 10]);
      expect(chords[1].offsets, [0, 4, 7, 10]);
      expect(chords[2].offsets, [0, 4, 7, 11]);
    });

    test('unknown quality throws', () {
      expect(
        () => tc.parseProgression('Czzz', keyRoot: 0, scaleName: 'Major'),
        throwsA(isA<tc.TheoryError>()),
      );
    });
  });

  group('voicing', () {
    test('progressionNotes lays one bar per chord', () {
      final chords = tc.parseProgression('I V', keyRoot: 0, scaleName: 'Major');
      final out = tc.progressionNotes(chords, startCol: 16, barLen: 16);
      expect(out.every((n) => n.len == 16), isTrue);
      expect(out.where((n) => n.start == 16), isNotEmpty);
      expect(out.where((n) => n.start == 32), isNotEmpty);
    });

    test('voice leading keeps the next chord near the previous', () {
      final chords = tc.parseProgression('I V vi IV',
          keyRoot: 0, scaleName: 'Major');
      final v = tc.progressionVoicings(chords, centre: 60);
      for (var i = 1; i < v.length; i++) {
        final a = v[i - 1].reduce((x, y) => x + y) / v[i - 1].length;
        final b = v[i].reduce((x, y) => x + y) / v[i].length;
        expect((a - b).abs(), lessThan(12));
      }
    });

    test('inversions raise the lowest voices', () {
      final chord = notes([(60, 0), (64, 0), (67, 0)]);
      final first = tc.invertChordNotes(chord, 1);
      expect((first.map((n) => n.pitch).toList()..sort()), [64, 67, 72]);
    });
  });

  group('generators', () {
    test('bass writes root + fifth per bar', () {
      final chords = tc.parseProgression('I V', keyRoot: 0, scaleName: 'Major');
      final out = tc.bassNotes(chords,
          startCol: 0, barLen: 16, stepsPerBeat: 4);
      expect(out.length, 4);
      expect(out[0].pitch % 12, 0);
      expect(out[1].pitch - out[0].pitch, 7);
    });

    test('walking bass fills the bar', () {
      final chords = tc.parseProgression('I', keyRoot: 0, scaleName: 'Major');
      final out = tc.bassNotes(chords,
          startCol: 0, barLen: 16, stepsPerBeat: 4, walking: true);
      expect(out.length, 4);
      expect(out.every((n) => n.len == 4), isTrue);
    });

    test('arpeggio repeats the figure', () {
      final out = tc.arpeggioNotes([60, 64, 67],
          startCol: 0, pattern: 'up', repeat: 2);
      expect(out.length, 6);
      expect(out[3].pitch, 60);
    });

    test('melody stays in scale and inside the bars', () {
      final out = tc.generateMelody(
        keyRoot: 0,
        scaleName: 'Major',
        startCol: 0,
        bars: 2,
        stepsPerBar: 16,
        stepsPerBeat: 4,
        contour: 'arch',
        seed: 7,
      );
      expect(out, isNotEmpty);
      final pcs = out.map((n) => n.pitch % 12).toSet();
      expect(pcs.difference({0, 2, 4, 5, 7, 9, 11}), isEmpty);
      expect(out.every((n) => n.end <= 32), isTrue);
    });

    test('sequence transposes diatonically', () {
      final motif = notes([(60, 0), (62, 2)]);
      final out = tc.sequenceNotes(
        motif,
        startCol: 0,
        times: 2,
        degreeStep: 2,
        keyRoot: 0,
        scaleName: 'Major',
      );
      expect(out.length, 4);
      expect(out.first.pitch, 64);
      expect(out.first.start, 6);
    });

    test('harmonize adds a diatonic third', () {
      final out = tc.harmonizeNotes(notes([(60, 0)]),
          keyRoot: 0, scaleName: 'Major');
      expect(out.single.pitch, 64);
    });

    test('snapToScale fixes chromatic notes', () {
      final out = tc.snapToScale(notes([(61, 0)]),
          keyRoot: 0, scaleName: 'Major');
      expect(out.single.pitch % 12, anyOf(0, 2));
    });

    test('cadences return two chords', () {
      for (final type in ['pac', 'hc', 'dc', 'pc']) {
        final out = tc.cadenceProgression(type,
            keyRoot: 0, scaleName: 'Major');
        expect(out.length, 2, reason: type);
      }
    });
  });

  group('strum', () {
    test('lays one bar per chord and repeats the pattern', () {
      final chords = tc.parseProgression('i v iv',
          keyRoot: 0, scaleName: 'Natural Minor');
      final out = tc.strumProgression(
        chords,
        startCol: 0,
        barLen: 16,
        pattern: 'd-uu-u',
      );
      expect(out, isNotEmpty);
      for (var bar = 0; bar < 3; bar++) {
        final base = bar * 16;
        expect(out.where((n) => n.start == base), isNotEmpty,
            reason: 'downstroke in bar $bar');
        expect(out.where((n) => n.start == base + 1), isEmpty,
            reason: 'rest in bar $bar');
        expect(out.where((n) => n.start == base + 2), isNotEmpty,
            reason: 'upstroke in bar $bar');
      }
      // Upstrokes drop the lowest voice, so they stack fewer notes.
      expect(
        out.where((n) => n.start == 2).length,
        lessThan(out.where((n) => n.start == 0).length),
      );
    });

    test('a single hit with a bar-length step is a block chord', () {
      final chords = tc.parseProgression('I',
          keyRoot: 0, scaleName: 'Major');
      final out = tc.strumProgression(
        chords,
        startCol: 0,
        barLen: 16,
        pattern: 'd',
        stepLen: 16,
      );
      expect(out, hasLength(3));
      expect(out.every((n) => n.start == 0 && n.len == 16), isTrue);
    });

    test('muted hits are shorter and quieter', () {
      final chords = tc.parseProgression('I',
          keyRoot: 0, scaleName: 'Major');
      final out = tc.strumProgression(
        chords,
        startCol: 0,
        barLen: 16,
        pattern: 'x',
        stepLen: 16,
      );
      expect(out.every((n) => n.len == 1), isTrue);
      expect(out.every((n) => n.vel < 100), isTrue);
    });

    test('unknown strum characters throw', () {
      final chords = tc.parseProgression('I',
          keyRoot: 0, scaleName: 'Major');
      expect(
        () => tc.strumProgression(chords,
            startCol: 0, barLen: 16, pattern: 'd-z'),
        throwsA(isA<tc.TheoryError>()),
      );
    });
  });

  group('analysis', () {
    test('names and roman-analyses a C major triad', () {
      final text = tc.analyzeChord([60, 64, 67],
          keyRoot: 0, scaleName: 'Major');
      expect(text, contains('C'));
      expect(text, contains('I'));
    });

    test('flags chromatic chords', () {
      final text = tc.analyzeChord([61, 65, 68],
          keyRoot: 0, scaleName: 'Major');
      expect(text, contains('chromatic'));
    });
  });

  group('pattern library', () {
    test('all three libraries are populated', () {
      expect(tc.libraryFor('c').length, 150);
      expect(tc.libraryFor('m').length, 150);
      expect(tc.libraryFor('b').length, 150);
    });

    test('lookup by id, number, title and section', () {
      final byId = tc.findPattern('c', 'C001');
      expect(byId, isNotNull);
      expect(byId!.id, 'c001');
      expect(tc.findPattern('c', '1')?.id, 'c001');
      expect(tc.findPattern('b', 'b001'), isNotNull);
    });

    test('patternNotes starts at the cursor and transposes to the key', () {
      final pattern = tc.findPattern('c', 'c001')!;
      final out = tc.patternNotes(pattern, startCol: 16, keyRoot: 2);
      final firstNotes =
          pattern.steps.firstWhere((s) => s.notes.isNotEmpty).notes;
      expect(out, isNotEmpty);
      expect(out.every((n) => n.start >= 16), isTrue);
      expect(out.first.pitch % 12, (firstNotes.first + 2) % 12);
    });

    test('drum patterns are not transposed', () {
      final pattern = tc.findPattern('b', 'b001')!;
      final out = tc.patternNotes(pattern, startCol: 0, keyRoot: 5);
      final firstNotes =
          pattern.steps.firstWhere((s) => s.notes.isNotEmpty).notes;
      expect(out.first.pitch, firstNotes.first);
    });
  });
}
