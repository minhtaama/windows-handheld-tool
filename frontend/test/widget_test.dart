import 'package:flutter_test/flutter_test.dart';
import 'package:windows_handheld_tool/core/config.dart';
import 'package:windows_handheld_tool/main.dart';

void main() {
  testWidgets('Smoke test HandheldApp initialization', (WidgetTester tester) async {
    final config = ConfigManager();
    await tester.pumpWidget(HandheldApp(config: config));
    expect(find.byType(HandheldApp), findsOneWidget);
  });
}
