import 'package:flutter_test/flutter_test.dart';

import 'package:local_hid/main.dart';

void main() {
  testWidgets('Renders the three top-level tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalHidApp());
    await tester.pump();
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
  });
}
