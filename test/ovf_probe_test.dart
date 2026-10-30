import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sridaw/main.dart';

void main() {
  final sizes = <String, Size>{
    '800x600': const Size(800, 600),
    '700x500': const Size(700, 500),
    '640x480': const Size(640, 480),
    '412x915': const Size(412, 915),
    '915x412': const Size(915, 412),
    '390x844': const Size(390, 844),
    '360x640': const Size(360, 640),
    '320x568': const Size(320, 568),
  };
  final digits = <int, LogicalKeyboardKey>{
    1: LogicalKeyboardKey.digit1,
    2: LogicalKeyboardKey.digit2,
    3: LogicalKeyboardKey.digit3,
    4: LogicalKeyboardKey.digit4,
    5: LogicalKeyboardKey.digit5,
    6: LogicalKeyboardKey.digit6,
    7: LogicalKeyboardKey.digit7,
  };

  for (final entry in sizes.entries) {
    testWidgets('probe ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final old = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);

      await tester.pumpWidget(const VimDawApp());
      await tester.pump();

      for (final d in [1, 2, 3, 4, 5, 6, 7]) {
        errors.clear();
        FlutterError.onError = errors.add;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(digits[d]!);
        await tester.sendKeyUpEvent(digits[d]!);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        // Restore the real handler before asserting so a failure is reported
        // by the test framework rather than swallowed by the collector.
        FlutterError.onError = old;
        expect(
          errors,
          isEmpty,
          reason:
              '${entry.key} view $d overflowed: '
              '${errors.map((e) => e.toString()).join('\n')}',
        );
      }
    });
  }
}
