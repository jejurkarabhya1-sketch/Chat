import 'package:flutter/foundation.dart';

class AppConfig {
  // Override per target with --dart-define=API_BASE_URL=... .
  // Android emulator uses 10.0.2.2; browser development uses localhost.
  static const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  // Plaintext chat is disabled by default. Enable only for isolated local demos
  // with --dart-define=ALLOW_PLAINTEXT_MESSAGES=true and the matching backend flag.
  static const allowPlaintextMessages = bool.fromEnvironment(
    'ALLOW_PLAINTEXT_MESSAGES',
    defaultValue: false,
  );
  static String get apiBaseUrl => _configuredApiBaseUrl.isNotEmpty
      ? _configuredApiBaseUrl
      : (kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000');

  static String get wsBaseUrl => apiBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
}
