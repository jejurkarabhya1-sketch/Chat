import 'dart:async';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Best-effort push setup. Messaging remains usable if the user declines permission
/// or push configuration is incomplete; the durable inbox remains authoritative.
class PushNotifications {
  PushNotifications._();
  static bool _initialized = false;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static const _deviceIdKey = 'veyra_push_device_id';
  static const _webVapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;

      final token = kIsWeb
          ? await messaging.getToken(vapidKey: _webVapidKey.isEmpty ? null : _webVapidKey)
          : await messaging.getToken();
      if (token != null && token.isNotEmpty) await _register(token);

      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((freshToken) async {
        try {
          if (freshToken.isNotEmpty) await _register(freshToken);
        } catch (_) {
          // The next app launch retries token registration.
        }
      });
    } catch (_) {
      // Push is optional and must never prevent login or chat UI from loading.
    }
  }

  static Future<void> unregister() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _initialized = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(_deviceIdKey);
      if (deviceId != null) {
        await Api.request('/users/me/push-devices/${Uri.encodeComponent(deviceId)}', method: 'DELETE');
      }
    } catch (_) {
      // Best-effort cleanup; server can prune invalid tokens after FCM responses.
    }
  }

  static Future<void> _register(String token) async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      final random = Random.secure();
      final suffix = List<int>.generate(20, (_) => random.nextInt(16))
          .map((n) => n.toRadixString(16)).join();
      deviceId = 'device-$suffix';
      await prefs.setString(_deviceIdKey, deviceId);
    }
    await Api.request('/users/me/push-devices', method: 'POST', body: {
      'device_id': deviceId,
      'token': token,
      'platform': kIsWeb ? 'web' : 'android',
    });
  }
}
