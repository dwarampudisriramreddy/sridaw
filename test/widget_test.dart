import 'package:flutter_test/flutter_test.dart';
import 'package:sridaw/main.dart';

void main() {
  testWidgets('DAW app renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const DawApp());
    // Verify the new single-screen DAW layout is present.
    expect(find.text('SRI DAW'), findsOneWidget);
    expect(find.text('TRACKS'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    // Chord pads (Hooktheory style) are present by default.
    expect(find.text('I'), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    // The first track is shown and selected for the editor.
    expect(find.text('Keys'), findsAtLeastNWidgets(1));
    // Switching to KEYS mode shows the piano roll + PLAY button.
    await tester.tap(find.text('KEYS'));
    await tester.pumpAndSettle();
    expect(find.text('PLAY'), findsOneWidget);
  });
}
