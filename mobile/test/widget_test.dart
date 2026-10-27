import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_messenger/main.dart';

void main() {
  testWidgets('Firebase setup screen explains required configuration',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FirebaseSetupApp());
    expect(find.text('Finish Firebase setup'), findsOneWidget);
    expect(find.textContaining('Configure Firebase for this target'), findsOneWidget);
  });
}
