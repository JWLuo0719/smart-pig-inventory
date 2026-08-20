import 'package:flutter_test/flutter_test.dart';

import 'package:smart_pig_inventory/main.dart';

void main() {
  testWidgets('mounts the product application shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PigInventoryApp());

    expect(find.byType(PigInventoryApp), findsOneWidget);
  });
}
