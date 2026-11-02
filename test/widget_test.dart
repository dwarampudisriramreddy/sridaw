import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:sridaw/input/daw_input.dart';
import 'package:sridaw/main.dart';
import 'package:sridaw/model/project.dart';
import 'package:sridaw/render/arrangement_view.dart';
import 'package:sridaw/render/automation_view.dart';
import 'package:sridaw/render/browser_view.dart';
import 'package:sridaw/render/drum_machine_view.dart';
import 'package:sridaw/render/piano_roll_view.dart';
import 'package:sridaw/render/roll_layout.dart';
import 'package:sridaw/ui/daw_theme.dart';

void main() {
  // Keep the tests hermetic: no network font fetching (which schedules timers
  // that outlive the widget tree).
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('pixel shell builds and the pointer moves with h/l', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    expect(rollFinder, findsOneWidget);

    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    expect(painter().scene.pointer.col, 0);
    expect(painter().scene.mode.label, 'NORMAL');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(painter().scene.pointer.col, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(painter().scene.pointer.pitch, 59);

    // 'i' enters DRAW mode.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    expect(painter().scene.mode.label, 'DRAW');

    // Escape returns to NORMAL.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(painter().scene.mode.label, 'NORMAL');

    // Vim counts and the live showcmd: `8` then `l`.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
    await tester.pump();
    expect(painter().scene.showCmd, '8');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(painter().scene.showCmd, '8l');
  });

  testWidgets('draw seeds a note and h/j/k/l extends it', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;
    final project = painter().scene.project;

    // Step to an empty pitch and enter DRAW; a 1-step note is seeded.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();

    int len() => project.track.notes
        .firstWhere((n) => n.pitch == 61 && n.start == 0)
        .len;
    expect(len(), 1);

    // Each horizontal move extends the same note by one cell.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(len(), 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(len(), 3);
  });

  testWidgets('CTRL on an empty cell starts a rectangle box select',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    // Move off the home row first; the grid starts empty.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(painter().scene.mode.label, 'NORMAL');
    expect(painter().scene.boxAnchor, isNotNull);

    // Extend the box, then CTRL grabs whatever it covered.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(painter().scene.pointer.col, 1);
    expect(painter().scene.boxAnchor!.col, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  const charKeys = <String, LogicalKeyboardKey>{
    ' ': LogicalKeyboardKey.space,
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG,
    'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI,
    'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK,
    'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM,
    'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO,
    'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ,
    'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS,
    't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU,
    'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW,
    'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY,
    'z': LogicalKeyboardKey.keyZ,
    '-': LogicalKeyboardKey.minus,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };

  Future<void> runCommand(WidgetTester tester, String body) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.semicolon, character: ':');
    await tester.pump();
    for (final ch in body.split('')) {
      final key = charKeys[ch];
      if (key == null) continue;
      await tester.sendKeyDownEvent(key, character: ch);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

  Future<void> goToArrangement(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('arrangement i creates a clip and d deletes it',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    await goToArrangement(tester);

    expect(find.byType(ArrangementView), findsOneWidget);
    final tracks =
        tester.widget<ArrangementView>(find.byType(ArrangementView)).tracks;

    // Move to an empty track (index 3).
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
    }
    expect(tracks[3].clips, isEmpty);

    // `i` inserts a clip at the cursor.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pump();
    expect(tracks[3].clips, hasLength(1));

    // `d` deletes the clip under the cursor when nothing is selected.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD, character: 'd');
    await tester.pump();
    expect(tracks[3].clips, isEmpty);
  });

  testWidgets('arrangement CTRL box-selects clips and d deletes them',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    await goToArrangement(tester);

    final tracks =
        tester.widget<ArrangementView>(find.byType(ArrangementView)).tracks;
    final before = tracks[0].clips.length;

    // CTRL tap starts a box selection anchored at track 0 / step 0.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Extend the box so it covers the first clip, then end the selection.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(tracks[0].clips.where((c) => c.selected), isNotEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD, character: 'd');
    await tester.pump();
    expect(tracks[0].clips.length, lessThan(before));
  });

  testWidgets('arrangement i makes a 1-step clip and p toggles its roll',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    await goToArrangement(tester);

    final tracks =
        tester.widget<ArrangementView>(find.byType(ArrangementView)).tracks;

    // Move to an empty track (index 3).
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
    }
    expect(tracks[3].clips, isEmpty);

    // `i` inserts a clip sized to the target track's notes.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pump();
    expect(tracks[3].clips, hasLength(1));
    expect(tracks[3].clips.first.length, greaterThanOrEqualTo(1));

    // `p` opens the clip in the piano roll.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP, character: 'p');
    await tester.pump();
    expect(find.byType(ArrangementView), findsNothing);

    // `p` again returns to the arrangement.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP, character: 'p');
    await tester.pump();
    expect(find.byType(ArrangementView), findsOneWidget);
  });

  testWidgets('the :scale command sets the project key', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    await runCommand(tester, 'scale d minor');
    expect(painter().scene.project.scaleRoot, 2);
    expect(painter().scene.project.scaleName, 'Natural Minor');
  });

  testWidgets('the :chord command harmonises the note under the cursor',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    // The chord is built at the cursor (C4, col 0) on the empty grid.
    await runCommand(tester, 'chord major');
    final notes = painter().scene.project.track.notes;
    expect(notes.where((n) => n.pitch == 64 && n.start == 0), hasLength(1));
    expect(notes.where((n) => n.pitch == 67 && n.start == 0), hasLength(1));
  });

  testWidgets('theory commands lay down progressions, bass and beats',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    await runCommand(tester, 'prog pop');
    var notes = painter().scene.project.track.notes;
    for (final start in [16, 32, 48]) {
      expect(notes.where((n) => n.start == start), isNotEmpty,
          reason: 'bar at step $start');
    }

    await runCommand(tester, 'bass');
    notes = painter().scene.project.track.notes;
    expect(notes.where((n) => n.pitch < 48), isNotEmpty);

    await runCommand(tester, 'beat b001');
    notes = painter().scene.project.track.notes;
    expect(notes.where((n) => n.pitch == 36), isNotEmpty);
    expect(painter().scene.project.totalBars, greaterThanOrEqualTo(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('s enters strum mode and creates strummed chords',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(painter().scene.mode.label, 'COMMAND');

    for (final ch in 'i v iv d-uu-u'.split('')) {
      await tester.sendKeyDownEvent(
        ch == ' ' ? LogicalKeyboardKey.space : charKeys[ch]!,
        character: ch,
      );
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final notes = painter().scene.project.track.notes;
    for (final bar in [0, 16, 32]) {
      expect(notes.where((n) => n.start == bar), isNotEmpty,
          reason: 'downstroke in bar at $bar');
      expect(notes.where((n) => n.start == bar + 1), isEmpty,
          reason: 'rest in bar at $bar');
      expect(notes.where((n) => n.start == bar + 2), isNotEmpty,
          reason: 'upstroke in bar at $bar');
    }
    expect(painter().scene.mode.label, 'NORMAL');
  });

  testWidgets('ctrl+a selects every note and x cuts them', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;
    final project = painter().scene.project;

    // The demo project starts empty, so lay a chord down first.
    await runCommand(tester, 'chord major');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(project.selection.length, project.track.notes.length);

    // A single note under the cursor is cut into the yank buffer.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final note = project.noteAt(60, 0)!;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(project.track.notes.contains(note), isFalse);
    expect(project.selection, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(project.noteAt(60, 1), isNotNull);
  });

  testWidgets('d on an empty cell toggles erase mode', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    // Land on empty space, then arm erase mode.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(painter().scene.mode.label, 'ERASE');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(painter().scene.mode.label, 'NORMAL');
  });

  testWidgets('c then m builds a minor chord on the note', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    // Arm chord mode with 'c', then choose minor with 'm'.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC, character: 'c');
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM, character: 'm');
    await tester.pump();

    final notes = painter().scene.project.track.notes;
    expect(notes.where((n) => n.pitch == 63 && n.start == 0), hasLength(1));
    expect(notes.where((n) => n.pitch == 67 && n.start == 0), hasLength(1));
  });

  testWidgets('i on a selection cycles the note value (4 -> 8 steps)',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    // The demo song no longer writes notes for you: put a 1/4 note on the
    // home cell so there is something for CTRL to grab.
    painter().scene.project.track.notes
        .add(Note(pitch: 60, start: 0, len: 4, vel: 100));

    // CTRL-tap grabs the note under the cursor (C4, len 4 = 1/4 note).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pump();

    expect(painter().scene.project.noteAt(60, 0)!.len, 8);
  });

  testWidgets('] lengthens the note under the cursor', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    // The grid starts empty: drop the note this test lengthens.
    painter().scene.project.track.notes
        .add(Note(pitch: 60, start: 0, len: 4, vel: 100));
    final before =
        painter().scene.project.noteAt(60, 0)!.len;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.bracketRight,
        character: ']');
    await tester.pump();
    final after = painter().scene.project.noteAt(60, 0)!.len;
    expect(after, before + 1);
  });

  testWidgets('the roll fills the space between the chrome bars',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    final scene =
        (tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter)
            .scene;

    // Full width; height is the window minus the fixed chrome bars.
    expect(scene.layout.width, 400);
    expect(scene.layout.height, 800 - DawLayout.chromeH.toInt());
    expect(scene.layout.rows, greaterThan(0));
    expect(scene.layout.cols, greaterThan(0));
  });

  testWidgets('accessory strip and command line render without error',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    // ':' enters command mode; type a character then run it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.semicolon,
        character: ':');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH, character: 'h');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('instrument browser: j moves and i loads onto the track',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    // Ctrl+5 switches to the instrument browser (SAMPLE view).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byType(BrowserView), findsOneWidget);
    BrowserView browser() =>
        tester.widget<BrowserView>(find.byType(BrowserView));

    expect(browser().entries, hasLength(8));
    expect(browser().selectedIndex, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(browser().selectedIndex, 1);

    final program = browser().entries[1].program;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    expect(browser().activeProgram, program);
  });

  testWidgets('automation: i writes a breakpoint, d removes it',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    // Ctrl+6 switches to the automation view.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit6);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit6);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byType(AutomationView), findsOneWidget);
    AutomationView auto() =>
        tester.widget<AutomationView>(find.byType(AutomationView));

    final lane = auto().laneIndex;
    final step = auto().cursorStep;
    final value = auto().cursorValue;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    final pts = auto().lanes[lane].points;
    expect(pts, hasLength(1));
    expect(pts.first.step, step);
    expect(pts.first.value, value);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(auto().lanes[lane].points, isEmpty);
  });

  testWidgets('space toggles play/pause; quick re-press while stopped restarts from bar 1', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    expect(painter().scene.playCol, 0);
    expect(painter().scene.isPlaying, false);

    // Single space starts playback.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(painter().scene.isPlaying, true);

    // One step elapses (stepMs = 60000/120/4 = 125ms).
    await tester.pump(const Duration(milliseconds: 130));
    expect(painter().scene.playCol, 1);

    // Space pauses, keeping the position.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(painter().scene.isPlaying, false);
    expect(painter().scene.playCol, 1);

    // A quick re-press while stopped restarts from bar 1 (step 0).
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(painter().scene.isPlaying, true);
    expect(painter().scene.playCol, 0);

    // Playback advances again.
    await tester.pump(const Duration(milliseconds: 130));
    expect(painter().scene.playCol, 1);

    // Pause so no periodic timer is left pending.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(painter().scene.isPlaying, false);
    expect(painter().scene.playCol, 1);
  });

  testWidgets('roll touch: double-tap adds/selects, long-press deletes',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    final origin = tester.getTopLeft(rollFinder);
    final l = painter().scene.layout;
    Offset cell(int pitch, int col) => origin +
        Offset(
          l.xForCol(col) + RollLayout.cellW / 2,
          l.yForPitch(pitch) + RollLayout.cellH / 2,
        );

    Future<void> doubleTap(Offset p) async {
      final first = await tester.startGesture(p);
      await first.up();
      await tester.pump(const Duration(milliseconds: 40));
      final second = await tester.startGesture(p);
      await second.up();
      // Let the triple-tap window expire so the next tap starts fresh.
      await tester.pump(const Duration(milliseconds: 450));
    }

    // Double-tap an empty cell creates a note.
    await doubleTap(cell(61, 0));
    final added = painter().scene.project.noteAt(61, 0);
    expect(added, isNotNull);

    // Double-tap the note selects it.
    await doubleTap(cell(61, 0));
    expect(painter().scene.project.selection, contains(added));

    // A normal tap on empty space clears the selection.
    await tester.tapAt(cell(61, 3));
    await tester.pump();
    expect(painter().scene.project.selection, isEmpty);

    // Long-press the note deletes it.
    final press = await tester.startGesture(cell(61, 0));
    await tester.pump(const Duration(milliseconds: 700));
    await press.up();
    await tester.pump();
    expect(painter().scene.project.noteAt(61, 0), isNull);
  });

  testWidgets('roll touch: a double-tap-selected note can be dragged',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    final origin = tester.getTopLeft(rollFinder);
    final l = painter().scene.layout;
    Offset cell(int pitch, int col) => origin +
        Offset(
          l.xForCol(col) + RollLayout.cellW / 2,
          l.yForPitch(pitch) + RollLayout.cellH / 2,
        );

    // The grid starts empty: drop the note this test drags.
    final project = painter().scene.project;
    project.track.notes.add(Note(pitch: 60, start: 0, len: 4, vel: 100));
    final note = painter().scene.project.noteAt(60, 0)!;
    final beforePitch = note.pitch;
    final beforeStart = note.start;

    Future<void> doubleTap(Offset p) async {
      final first = await tester.startGesture(p);
      await first.up();
      await tester.pump(const Duration(milliseconds: 40));
      final second = await tester.startGesture(p);
      await second.up();
      // Let the triple-tap window expire so the next tap starts fresh.
      await tester.pump(const Duration(milliseconds: 450));
    }

    // Dragging an unselected note must not move it.
    expect(painter().scene.project.selection.contains(note), isFalse);
    final idle = await tester.startGesture(cell(60, 0));
    await idle.moveBy(Offset(
      2.0 * RollLayout.cellW,
      -2.0 * RollLayout.cellH,
    ));
    await idle.up();
    await tester.pump();
    expect(note.pitch, beforePitch);
    expect(note.start, beforeStart);

    await doubleTap(cell(60, 0));
    expect(painter().scene.project.selection, contains(note));

    // Drag up and to the right: the selected note follows the finger.
    final drag = await tester.startGesture(cell(60, 0));
    await tester.pump();
    await drag.moveBy(Offset(
      2.0 * RollLayout.cellW,
      -2.0 * RollLayout.cellH,
    ));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(note.pitch, greaterThan(beforePitch));
    expect(note.start, greaterThan(beforeStart));
    expect(painter().scene.project.selection, contains(note));
  });

  testWidgets('roll touch: triple-tap arms chord mode', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    final origin = tester.getTopLeft(rollFinder);
    final l = painter().scene.layout;
    Offset cell(int pitch, int col) => origin +
        Offset(
          l.xForCol(col) + RollLayout.cellW / 2,
          l.yForPitch(pitch) + RollLayout.cellH / 2,
        );

    for (var i = 0; i < 3; i++) {
      final tap = await tester.startGesture(cell(60, 0));
      await tap.up();
      await tester.pump(const Duration(milliseconds: 40));
    }

    // Chord mode is armed; "m" builds a C minor chord on the selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(painter().scene.project.noteAt(63, 0), isNotNull);
    expect(painter().scene.project.noteAt(67, 0), isNotNull);
  });

  testWidgets('roll touch: dragging the edges scrolls the view', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;

    final origin = tester.getTopLeft(rollFinder);
    final initial = painter().scene.layout;
    final low = initial.viewLowPitch;
    final col = initial.viewCol;

    // Drag the keyboard gutter down: scroll towards higher pitches.
    final vertical = await tester.startGesture(
      origin +
          Offset(20, RollLayout.rulerH.toDouble() + 4.0 * RollLayout.cellH),
    );
    await vertical.moveBy(Offset(0, 2.0 * RollLayout.cellH));
    await vertical.up();
    await tester.pump();
    expect(painter().scene.layout.viewLowPitch, low + 2);

    // Drag the ruler left: scroll forward in time.
    final horizontal = await tester.startGesture(
      origin + Offset(RollLayout.keyW.toDouble() + 4.0 * RollLayout.cellW, 5),
    );
    await horizontal.moveBy(Offset(-2.0 * RollLayout.cellW, 0));
    await horizontal.up();
    await tester.pump();
    expect(painter().scene.layout.viewCol, col + 2);
  });

  testWidgets('arrange touch: tap selects, double-tap opens the roll',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    // Ctrl+3 switches to the arrangement view.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byType(ArrangementView), findsOneWidget);
    ArrangementView arrange() =>
        tester.widget<ArrangementView>(find.byType(ArrangementView));
    final origin = tester.getTopLeft(find.byType(ArrangementView));

    // Tap the second track header (180px header, 40px toolbar, 32px ruler,
    // 80px per track).
    await tester.tapAt(origin + const Offset(90, 40 + 32 + 80 + 40));
    await tester.pump(const Duration(milliseconds: 400));
    expect(arrange().cursorTrack, 1);
    // Tap the first clip on track 1 and check it becomes selected.
    final clipPos = origin + const Offset(180 + 60, 40 + 32 + 40);
    await tester.tapAt(clipPos);
    await tester.pump();
    expect(arrange().cursorTrack, 0);
    expect(arrange().tracks[0].clips.first.selected, isTrue);

    // Wait past the double-tap window so the next two taps form a double-tap.
    await tester.pump(const Duration(milliseconds: 350));

    // Double-tap the clip opens its piano roll.
    final first = await tester.startGesture(clipPos);
    await first.up();
    await tester.pump(const Duration(milliseconds: 40));
    final second = await tester.startGesture(clipPos);
    await second.up();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byType(ArrangementView), findsNothing);
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    expect(rollFinder, findsOneWidget);
    final scene =
        (tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter)
            .scene;
    expect(scene.project.activeTrack, 0);
    expect(scene.pointer.col, 0);
  });

  testWidgets('drum machine: taps place hits and pads drive the cursor',
      (tester) async {
    // The drum tab sits directly after the roll tab.
    expect(ViewMode.values.take(2), [ViewMode.roll, ViewMode.drumMachine]);

    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    // Ctrl+2 opens the drum machine tab.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.text('DRUMS'), findsOneWidget);
    final gridFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DrumMachinePainter,
    );
    expect(gridFinder, findsOneWidget);

    DrumMachinePainter painter() =>
        tester.widget<CustomPaint>(gridFinder).painter! as DrumMachinePainter;
    final origin = tester.getTopLeft(gridFinder);
    final l = painter().scene.layout;
    Offset cell(int row, int col) => origin +
        Offset(
          l.xForCol(col) + RollLayout.cellW / 2,
          l.gridY + row * RollLayout.cellH + RollLayout.cellH / 2,
        );

    // Tap the first pad row on the first step: the kick lands and the track
    // becomes a GM drum track so playback agrees.
    await tester.tapAt(cell(0, 0));
    await tester.pump();
    final kick = painter().scene.pads[0].pitch;
    expect(painter().scene.project.noteAt(kick, 0), isNotNull);
    expect(painter().scene.project.track.channel, 9);

    // Tapping the same cell again takes the hit back out.
    await tester.tapAt(cell(0, 0));
    await tester.pump();
    expect(painter().scene.project.noteAt(kick, 0), isNull);

    // Tapping a sound name selects that row.
    await tester.tapAt(origin +
        Offset(
          l.gutterW / 2,
          l.gridY + 1 * RollLayout.cellH + RollLayout.cellH / 2,
        ));
    await tester.pump();
    expect(painter().scene.cursorPad, 1);
    expect(painter().scene.pointer.pitch, painter().scene.pads[1].pitch);

    // Keyboard: i drops a hit, d removes it, j walks down a pad.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    final snare = painter().scene.pads[1].pitch;
    expect(painter().scene.project.noteAt(snare, 0), isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(painter().scene.project.noteAt(snare, 0), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(painter().scene.cursorPad, 2);
    expect(painter().scene.pointer.pitch, painter().scene.pads[2].pitch);
  });

  testWidgets('drum machine: + SOUND adds a sound from the GM kit',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final gridFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DrumMachinePainter,
    );
    DrumMachinePainter painter() =>
        tester.widget<CustomPaint>(gridFinder).painter! as DrumMachinePainter;
    expect(find.text('SIDE STICK'), findsNothing);

    await tester.tap(find.text('+ SOUND'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('ADD SOUND'), findsOneWidget);
    expect(find.text('SIDE STICK'), findsOneWidget);

    await tester.tap(find.text('SIDE STICK'));
    await tester.pump();
    // Let the dialog finish closing so only the pad row is left.
    await tester.pump(const Duration(milliseconds: 400));

    expect(painter().scene.pads.map((p) => p.name),
        contains('SIDE STICK'));
    expect(find.text('SIDE STICK'), findsOneWidget);
    expect(find.text('ADD SOUND'), findsNothing);
  });

  testWidgets('toolbar instrument chip opens a picker and loads a sound',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;
    final project = painter().scene.project;
    expect(project.track.instrument, 0);

    await tester.tap(find.byKey(const Key('instrument-chip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('INSTRUMENT'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'square');
    await tester.pump();
    final row = find.byKey(const Key('inst-80'));
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pump();
    // Let the dialog close and the preview blip expire.
    await tester.pump(const Duration(milliseconds: 250));

    expect(project.track.instrument, 80);
    expect(find.text('INSTRUMENT'), findsNothing);
    expect(find.text('Lead 1 (square)'), findsWidgets);
    expect(
        find.text('inst Lead 1 (square) (program 81)'), findsOneWidget);
  });

  testWidgets('play schedules the project notes into the engine',
      (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();
    final rollFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    PianoRollPainter painter() =>
        tester.widget<CustomPaint>(rollFinder).painter! as PianoRollPainter;
    final project = painter().scene.project;

    // An empty grid: the transport says so instead of playing silence
    // while pretending something is running.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('PLAYING · no notes yet'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    project.track.notes
      ..add(Note(pitch: 60, start: 0, len: 4, vel: 100))
      ..add(Note(pitch: 64, start: 4, len: 4, vel: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('PLAYING · 2 note(s)'), findsOneWidget);

    // Pause so no periodic timer is left pending.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
  });

  testWidgets('help view documents the touch gestures', (tester) async {
    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.text('TOUCH'), findsOneWidget);
    expect(find.textContaining('double-tap'), findsWidgets);
    expect(find.textContaining('long-press'), findsWidgets);
  });
}
