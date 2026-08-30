import 'package:flutter_test/flutter_test.dart';
import 'package:sridaw/main.dart';

void main() {
  testWidgets('DAW app renders the four-tab portrait shell', (WidgetTester tester) async {
    await tester.pumpWidget(const DawApp());
    await tester.pumpAndSettle();

    // Bottom tab bar labels.
    expect(find.text('TIMELINE'), findsWidgets);
    expect(find.text('KEYS'), findsWidgets);
    expect(find.text('MIXER'), findsWidgets);
    expect(find.text('FX'), findsWidgets);

    // Transport.
    expect(find.text('BPM'), findsOneWidget);

    // Default tab (Timeline) shows the seeded track headers.
    expect(find.text('Keys'), findsWidgets);
    expect(find.text('Bass'), findsWidgets);

    // Switch to the Piano Roll tab and confirm it builds without error.
    await tester.tap(find.text('KEYS'));
    await tester.pumpAndSettle();
    expect(find.text('Major'), findsWidgets); // scale dropdown
  });
}
