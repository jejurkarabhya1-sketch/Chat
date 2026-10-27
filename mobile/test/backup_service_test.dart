import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veyra_messenger/backup_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'inbox_sync_user_id_v1': 42,
      'inbox_sync_cursor_v1': 9,
      'inbox_conversations_v1': jsonEncode([{'id': 3, 'title': 'Test'}]),
      'inbox_cache_v1_conversation_3': jsonEncode([
        {'id': 11, 'conversation_id': 3, 'body': '[Encrypted message]'}
      ]),
      'app_language': 'mr',
      'data_saver_enabled': true,
      'token': 'must-not-be-included',
      'push_device_token': 'must-not-be-included',
    });
  });

  test('backup is encrypted and restore replaces only backed-up local cache', () async {
    final bytes = await BackupService.createBackup('a-very-long-backup-passphrase');
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(envelope['format'], BackupService.format);
    expect(utf8.decode(bytes), isNot(contains('must-not-be-included')));
    expect(utf8.decode(bytes), isNot(contains('[Encrypted message]')));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('inbox_cache_v1_conversation_3', '[]');
    await prefs.setString('inbox_cache_v1_conversation_8', '[]');
    await prefs.setString('token', 'current-login-token');

    await BackupService.restoreBackup(Uint8List.fromList(bytes), 'a-very-long-backup-passphrase');

    expect(prefs.getString('inbox_cache_v1_conversation_3'), contains('Encrypted message'));
    expect(prefs.containsKey('inbox_cache_v1_conversation_8'), isFalse);
    expect(prefs.getInt('inbox_sync_cursor_v1'), 0); // forces full server inbox recovery
    expect(prefs.getString('app_language'), 'mr');
    expect(prefs.getBool('data_saver_enabled'), isTrue);
    expect(prefs.getString('token'), 'current-login-token');
  });

  test('wrong passphrase does not mutate local cache', () async {
    final bytes = await BackupService.createBackup('a-very-long-backup-passphrase');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('inbox_cache_v1_conversation_3', 'preserve-me');

    await expectLater(
      BackupService.restoreBackup(Uint8List.fromList(bytes), 'incorrect-backup-passphrase'),
      throwsA(isA<FormatException>()),
    );
    expect(prefs.getString('inbox_cache_v1_conversation_3'), 'preserve-me');
  });

  test('restore rejects a backup belonging to a different account', () async {
    final bytes = await BackupService.createBackup('a-very-long-backup-passphrase');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('inbox_sync_user_id_v1', 99);

    await expectLater(
      BackupService.restoreBackup(Uint8List.fromList(bytes), 'a-very-long-backup-passphrase'),
      throwsA(isA<FormatException>()),
    );
  });
}
