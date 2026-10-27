import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veyra_messenger/api.dart';
import 'package:veyra_messenger/storage_settings.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'usage_api_sent_bytes': 512,
      'usage_api_received_bytes': 2048,
      'usage_api_request_count': 3,
    });
  });

  testWidgets('storage screen shows usage counters and can reset them',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StorageDataScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Network usage'), findsOneWidget);
    expect(find.text('512 B'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final resetButton = find.text('Reset counters');
    await tester.ensureVisible(resetButton);
    await tester.pumpAndSettle();
    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    final usage = await Api.trafficUsage();
    expect(usage['sentBytes'], 0);
    expect(usage['receivedBytes'], 0);
    expect(usage['requestCount'], 0);
  });

  testWidgets('data saver preference persists on the device',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StorageDataScreen()));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const ValueKey('dataSaverSwitch'));
    expect(switchFinder, findsOneWidget);
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('data_saver_enabled'), isTrue);
  });
}
