import 'package:flutter_test/flutter_test.dart';

import 'package:sridaw/main.dart';

void main() {
  testWidgets('DAW app renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const DawApp());
    await tester.pump();

    expect(find.text('SRI DAW'), findsOneWidget);
    expect(find.text('16-STEP SEQUENCER'), findsOneWidget);
  });
}
