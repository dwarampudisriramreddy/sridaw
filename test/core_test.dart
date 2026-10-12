import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sridaw/core/palette.dart';
import 'package:sridaw/core/pixel_font.dart';
import 'package:sridaw/input/daw_input.dart';
import 'package:sridaw/model/project.dart';
import 'package:sridaw/render/roll_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('palette', () {
    test('registry exposes six 16-colour palettes', () {
      expect(PixelPalette.names.length, 6);
      for (final name in PixelPalette.names) {
        expect(PixelPalette.byName(name).colors.length, 16, reason: name);
      }
    });

    test('velocity maps into the note band', () {
      const p = PixelPalette.vimdaw;
      expect(p.velocityShade(0), inInclusiveRange(9, 15));
      expect(p.velocityShade(127), inInclusiveRange(9, 15));
      expect(p.velocityShade(127), greaterThan(p.velocityShade(0)));
    });
  });

  group('font', () {
    test('measure accounts for the inter-glyph gap', () {
      expect(font5x7.measure('A'), 5);
      expect(font5x7.measure('AB'), 11);
      expect(font3x5.measure('A'), 3);
    });

    test('drawing unknown glyphs falls back to a box instead of throwing', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => font5x7.draw(canvas, '\u2603', 0, 0, const ui.Color(0xFFFFFFFF)),
        returnsNormally,
      );
      recorder.endRecording();
    });
  });

  group('project', () {
    test('demo project has bars, notes and ghost notes', () {
      final p = Project.demo();
      expect(p.totalSteps, p.stepsPerBar * p.totalBars);
      expect(p.track.notes, isNotEmpty);
      expect(p.ghostNotes, isNotEmpty);
    });

    test('noteAt finds a note under the cursor', () {
      final p = Project(name: 't');
      p.track.notes.add(Note(pitch: 60, start: 4, len: 4));
      expect(p.noteAt(60, 4), isNotNull);
      expect(p.noteAt(60, 7), isNotNull);
      expect(p.noteAt(60, 8), isNull);
      expect(p.noteAt(59, 4), isNull);
    });
  });

  group('roll layout', () {
    const l = RollLayout(viewLowPitch: 48, viewCol: 0, width: 400, height: 500);

    test('grid sits inside the canvas and has rows/columns', () {
      expect(l.gridX + l.gridW, lessThanOrEqualTo(l.width));
      expect(l.gridY + l.gridH, lessThanOrEqualTo(l.height));
      expect(l.rows, greaterThan(0));
      expect(l.cols, greaterThan(0));
    });

    test('pitch <-> y and col <-> x round-trip', () {
      for (var pitch = l.viewLowPitch; pitch <= l.topPitch; pitch++) {
        expect(l.pitchForY(l.yForPitch(pitch)), pitch);
      }
      for (var col = l.viewCol; col < l.viewCol + l.cols; col++) {
        expect(l.colForX(l.xForCol(col)), col);
      }
    });

    test('inGrid rejects the ruler and gutter', () {
      expect(l.inGrid(l.gridX + 1, l.gridY + 1), isTrue);
      expect(l.inGrid(1, l.gridY + 1), isFalse);
      expect(l.inGrid(l.gridX + 1, 1), isFalse);
    });
  });

  group('grid pointer', () {
    test('count defaults to one and parses digits', () {
      final p = GridPointer();
      expect(p.countValue, 1);
      p.count = '8';
      expect(p.countValue, 8);
    });

    test('mode labels are stable', () {
      expect(InputMode.normal.label, 'NORMAL');
      expect(InputMode.visualLine.label, 'V-LINE');
    });
  });
}
