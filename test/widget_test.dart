import 'package:flutter_test/flutter_test.dart';

import 'package:sridaw/main.dart';

void main() {
  testWidgets('DAW app renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const DawApp());
    // Verify that our main view is rendered.
    expect(find.text('SYNC'), findsOneWidget);
    expect(find.text('MASTER'), findsOneWidget);
  });
}
