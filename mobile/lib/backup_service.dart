import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted, portable backup of Veyra's local cached inbox and non-secret preferences.
/// Authentication tokens, push tokens, private keys, and server-side full history are never included.
class BackupService {
  static const format = 'VEYRA_BACKUP_V1';
  static const _iterations = 310000;
  static const _maxBackupBytes = 25 * 1024 * 1024;
  static const _conversationKey = 'inbox_conversations_v1';
  static const _cursorKey = 'inbox_sync_cursor_v1';
  static const _userIdKey = 'inbox_sync_user_id_v1';
  static const _inboxPrefix = 'inbox_cache_v1_conversation_';
  static const _preferenceKeys = <String>['app_language', 'data_saver_enabled'];

  static final _aes = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  static Future<Uint8List> createBackup(String passphrase) async {
    _validatePassphrase(passphrase);
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_userIdKey);
    if (userId == null || userId <= 0) {
      throw StateError('Sign in and sync your inbox before creating a backup.');
    }

    final localData = <String, dynamic>{
      _conversationKey: prefs.getString(_conversationKey),
      _cursorKey: prefs.getInt(_cursorKey) ?? 0,
      for (final key in prefs.getKeys().where((key) => key.startsWith(_inboxPrefix)))
        key: prefs.getString(key),
      for (final key in _preferenceKeys)
        if (prefs.containsKey(key)) key: prefs.get(key),
    };
    final payload = <String, dynamic>{
      'format': format,
      'schema_version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'account_id': userId,
      'data': localData,
    };
    final cleartext = utf8.encode(jsonEncode(payload));
    if (cleartext.length > _maxBackupBytes) {
      throw StateError('Backup is larger than the supported 25 MB limit.');
    }

    final random = Random.secure();
    final salt = _randomBytes(random, 16);
    final nonce = _randomBytes(random, 12);
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final encrypted = await _aes.encrypt(
      cleartext,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(format),
    );
    final envelope = <String, dynamic>{
      'format': format,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(encrypted.cipherText),
      'mac': base64Encode(encrypted.mac.bytes),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    if (bytes.length > _maxBackupBytes) {
      throw StateError('Backup is larger than the supported 25 MB limit.');
    }
    return bytes;
  }

  static Future<void> restoreBackup(Uint8List fileBytes, String passphrase) async {
    _validatePassphrase(passphrase);
    if (fileBytes.isEmpty || fileBytes.length > _maxBackupBytes) {
      throw const FormatException('Backup file is empty or exceeds the 25 MB limit.');
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(utf8.decode(fileBytes));
    } on FormatException {
      throw const FormatException('This is not a valid Veyra backup file.');
    }
    if (parsed is! Map<String, dynamic> ||
        parsed['format'] != format ||
        parsed['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        parsed['iterations'] != _iterations ||
        parsed['cipher'] != 'AES-256-GCM') {
      throw const FormatException('Unsupported or invalid backup format.');
    }

    final List<int> salt;
    final List<int> nonce;
    final List<int> cipherText;
    final List<int> mac;
    try {
      salt = base64Decode(parsed['salt'] as String);
      nonce = base64Decode(parsed['nonce'] as String);
      cipherText = base64Decode(parsed['ciphertext'] as String);
      mac = base64Decode(parsed['mac'] as String);
    } catch (_) {
      throw const FormatException('Backup file is incomplete or corrupted.');
    }
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Backup cryptographic metadata is invalid.');
    }

    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final List<int> cleartext;
    try {
      cleartext = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(format),
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('Incorrect passphrase or backup integrity check failed.');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(cleartext));
    } on FormatException {
      throw const FormatException('Decrypted backup payload is invalid.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['schema_version'] != 1 ||
        decoded['account_id'] is! int ||
        decoded['data'] is! Map<String, dynamic>) {
      throw const FormatException('Backup payload has an unsupported schema.');
    }

    final prefs = await SharedPreferences.getInstance();
    final activeUserId = prefs.getInt(_userIdKey);
    if (activeUserId == null || activeUserId != decoded['account_id']) {
      throw const FormatException('Sign in to the same Veyra account used to create this backup.');
    }
    final data = decoded['data'] as Map<String, dynamic>;
    final conversations = data[_conversationKey];
    final cursor = data[_cursorKey];
    if (conversations != null && conversations is! String) {
      throw const FormatException('Backup conversation cache is invalid.');
    }
    if (cursor is! int || cursor < 0) {
      throw const FormatException('Backup sync cursor is invalid.');
    }

    final cacheEntries = <String, String>{};
    for (final entry in data.entries) {
      if (entry.key.startsWith(_inboxPrefix)) {
        if (entry.value is! String) {
          throw const FormatException('Backup message cache is invalid.');
        }
        final conversationId = int.tryParse(entry.key.substring(_inboxPrefix.length));
        if (conversationId == null || conversationId <= 0) {
          throw const FormatException('Backup contains an invalid conversation identifier.');
        }
        // Parse each cache before touching existing local data.
        final cache = jsonDecode(entry.value as String);
        if (cache is! List || cache.length > 500) {
          throw const FormatException('Backup message cache has an invalid shape.');
        }
        cacheEntries[entry.key] = entry.value as String;
      }
    }
    if (conversations is String) {
      final parsedConversations = jsonDecode(conversations);
      if (parsedConversations is! List) {
        throw const FormatException('Backup conversation list is invalid.');
      }
    }

    // All parsing, authentication and account checks finish before replacing existing cache.
    for (final key in prefs.getKeys().where((key) => key.startsWith(_inboxPrefix)).toList()) {
      await prefs.remove(key);
    }
    if (conversations == null) {
      await prefs.remove(_conversationKey);
    } else {
      await prefs.setString(_conversationKey, conversations as String);
    }
    for (final entry in cacheEntries.entries) {
      await prefs.setString(entry.key, entry.value);
    }
    // Reset the cursor so a newly restored installation can recover the full durable server inbox.
    // Cached rows are deduplicated by message ID during sync.
    await prefs.setInt(_cursorKey, 0);
    for (final key in _preferenceKeys) {
      if (data.containsKey(key)) {
        final value = data[key];
        if (key == 'app_language' && value is String && {'en', 'mr', 'hi'}.contains(value)) {
          await prefs.setString(key, value);
        } else if (key == 'data_saver_enabled' && value is bool) {
          await prefs.setBool(key, value);
        }
      }
    }
  }

  static List<int> _randomBytes(Random random, int length) =>
      List<int>.generate(length, (_) => random.nextInt(256), growable: false);

  static void _validatePassphrase(String passphrase) {
    if (passphrase.trim().length < 10) {
      throw ArgumentError('Use a backup passphrase with at least 10 characters.');
    }
  }
}
