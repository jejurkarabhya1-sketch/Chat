import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veyra_messenger/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('offline inbox cache is empty for an unseen conversation', () async {
    expect(await Api.cachedInbox(42), isEmpty);
  });

  test('offline conversation list is empty before first successful sync', () async {
    expect(await Api.cachedConversations(), isEmpty);
  });

  test('conversation cache can be restored after an offline launch', () async {
    final conversations = <dynamic>[
      <String, dynamic>{'id': 7, 'title': 'Family', 'member_ids': <int>[1, 2]},
    ];
    await Api.cacheConversations(conversations);
    final restored = await Api.cachedConversations();
    expect(restored, hasLength(1));
    expect(restored.single['id'], 7);
    expect(restored.single['title'], 'Family');
  });
}
