import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sridaw/main.dart';

void main() {
  testWidgets('no layout overflow or paint errors in any view (800x600)', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VimDawApp());
    await tester.pump();

    final digits = <int, LogicalKeyboardKey>{
      1: LogicalKeyboardKey.digit1,
      2: LogicalKeyboardKey.digit2,
      4: LogicalKeyboardKey.digit4,
      5: LogicalKeyboardKey.digit5,
      6: LogicalKeyboardKey.digit6,
    };

    Future<void> go(int d) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(digits[d]!);
      await tester.sendKeyUpEvent(digits[d]!);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final e = tester.takeException();
      expect(e, isNull, reason: 'view $d threw: $e');
    }

    for (final d in [2, 4, 5, 6, 1]) {
      await go(d);
    }
  });
}