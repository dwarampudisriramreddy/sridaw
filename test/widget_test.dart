import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:sridaw/input/daw_input.dart';
import 'package:sridaw/main.dart';
import 'package:sridaw/render/arrangement_view.dart';
import 'package:sridaw/render/automation_view.dart';
import 'package:sridaw/render/browser_view.dart';
import 'package:sridaw/render/piano_roll_view.dart';
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

    // Step off the demo note (pitch 60, col 0) onto an empty pitch.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(painter().scene.mode.label, 'VISUAL');
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
    '7': LogicalKeyboardKey.digit7,
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

    // `i` inserts a single-step clip (no count).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pump();
    expect(tracks[3].clips, hasLength(1));
    expect(tracks[3].clips.first.length, 1);

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

    // Pointer starts on the demo C4 (pitch 60, start 0).
    await runCommand(tester, 'chord major');
    final notes = painter().scene.project.track.notes;
    expect(notes.where((n) => n.pitch == 64 && n.start == 0), hasLength(1));
    expect(notes.where((n) => n.pitch == 67 && n.start == 0), hasLength(1));
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
}
