import 'package:flutter_test/flutter_test.dart';
import 'package:sridaw/main.dart';

void main() {
  testWidgets('DAW app renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const DawApp());
    // Verify the new DAW layout is present.
    expect(find.text('SRI DAW'), findsOneWidget);
    expect(find.text('PHRASES'), findsOneWidget);
    expect(find.text('TRACKS'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    // Vertical piano roll should be visible on the Phrases tab (Keys track).
    expect(find.text('PLAY PHRASE'), findsOneWidget);
    // Tracks tab shows the first track with pre-filled phrases.
    await tester.tap(find.text('TRACKS'));
    await tester.pumpAndSettle();
    expect(find.text('Keys'), findsAtLeastNWidgets(1));
  });
}
