import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class Api {
  static const Duration _timeout = Duration(seconds: 15);
  static const _sentBytesKey = 'usage_api_sent_bytes';
  static const _receivedBytesKey = 'usage_api_received_bytes';
  static const _requestCountKey = 'usage_api_request_count';
  static const _inboxCursorKey = 'inbox_sync_cursor_v1';
  static const _inboxUserIdKey = 'inbox_sync_user_id_v1';
  static const _conversationCacheKey = 'inbox_conversations_v1';
  static int? _activeInboxUserId;
  static const _inboxCachePrefix = 'inbox_cache_v1_conversation_';
  static Future<void> _inboxSyncQueue = Future<void>.value();
  static Future<void> _trafficWriteQueue = Future<void>.value();

  /// Approximate API payload usage; excludes HTTP/TLS headers and WebSocket traffic.
  static Future<Map<String, int>> trafficUsage() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'sentBytes': prefs.getInt(_sentBytesKey) ?? 0,
      'receivedBytes': prefs.getInt(_receivedBytesKey) ?? 0,
      'requestCount': prefs.getInt(_requestCountKey) ?? 0,
    };
  }

  static Future<void> resetTrafficUsage() {
    _trafficWriteQueue = _trafficWriteQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_sentBytesKey, 0);
      await prefs.setInt(_receivedBytesKey, 0);
      await prefs.setInt(_requestCountKey, 0);
    });
    return _trafficWriteQueue;
  }

  static Future<void> _recordTraffic({required int sentBytes, required int receivedBytes}) {
    _trafficWriteQueue = _trafficWriteQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_sentBytesKey, (prefs.getInt(_sentBytesKey) ?? 0) + sentBytes);
        await prefs.setInt(_receivedBytesKey, (prefs.getInt(_receivedBytesKey) ?? 0) + receivedBytes);
        await prefs.setInt(_requestCountKey, (prefs.getInt(_requestCountKey) ?? 0) + 1);
      } catch (_) {
        // Usage metrics are best-effort and must never fail a message request.
      }
    });
    return _trafficWriteQueue;
  }

  static Future<String?> token() async =>
      (await SharedPreferences.getInstance()).getString('token');

  static Uri _uri(String path) {
    final base = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/${path.replaceFirst(RegExp(r'^/+'), '')}');
  }

  static Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final accessToken = await token();
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';

    late final http.Response response;
    try {
      if (method.toUpperCase() == 'POST') {
        final requestBody = jsonEncode(body ?? {});
        response = await http
            .post(_uri(path), headers: headers, body: requestBody)
            .timeout(_timeout);
        await _recordTraffic(sentBytes: utf8.encode(requestBody).length, receivedBytes: response.bodyBytes.length);
      } else if (method.toUpperCase() == 'GET') {
        response = await http.get(_uri(path), headers: headers).timeout(_timeout);
        await _recordTraffic(sentBytes: 0, receivedBytes: response.bodyBytes.length);
      } else if (method.toUpperCase() == 'DELETE') {
        response = await http.delete(_uri(path), headers: headers).timeout(_timeout);
        await _recordTraffic(sentBytes: 0, receivedBytes: response.bodyBytes.length);
      } else {
        throw ArgumentError.value(method, 'method', 'Supported methods: GET, POST, DELETE');
      }
    } on TimeoutException {
      throw Exception('The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw Exception('Cannot reach the Veyra server. Check your connection and API URL.');
    }

    final dynamic decoded;
    try {
      decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } on FormatException {
      throw Exception('The server returned an invalid response (${response.statusCode}).');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw Exception(detail?.toString() ?? 'Request failed (${response.statusCode}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('The server returned an unexpected response format.');
    }
    return decoded;
  }

  /// Ensure local inbox state is isolated per authenticated Veyra account.
  /// A user switch clears the prior account's cached messages and cursor on this device.
  static Future<int> prepareInboxAccount({bool forceRefresh = false}) async {
    if (!forceRefresh && _activeInboxUserId != null) return _activeInboxUserId!;
    final result = await request('/users/me/phone');
    final userId = result['id'];
    if (userId is! int || userId <= 0) {
      throw const FormatException('The server returned an invalid account identifier.');
    }
    final prefs = await SharedPreferences.getInstance();
    final previousUserId = prefs.getInt(_inboxUserIdKey);
    if (previousUserId != null && previousUserId != userId) {
      for (final key in prefs.getKeys().where((key) => key.startsWith(_inboxCachePrefix)).toList()) {
        await prefs.remove(key);
      }
      await prefs.remove(_inboxCursorKey);
      await prefs.remove(_conversationCacheKey);
    }
    await prefs.setInt(_inboxUserIdKey, userId);
    _activeInboxUserId = userId;
    return userId;
  }

  static Future<void> cacheConversations(List<dynamic> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = conversations.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    await prefs.setString(_conversationCacheKey, jsonEncode(normalized));
  }

  static Future<List<dynamic>> cachedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationCacheKey);
    if (raw == null || raw.isEmpty) return <dynamic>[];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : <dynamic>[];
    } on FormatException {
      return <dynamic>[];
    }
  }

  /// Return locally cached inbox messages for one conversation.
  static Future<List<Map<String, dynamic>>> cachedInbox(int conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_inboxCachePrefix$conversationId');
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } on FormatException {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _updateCachedDeliveryStatus(int conversationId, int messageId, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_inboxCachePrefix$conversationId';
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final cached = decoded.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
      final index = cached.indexWhere((value) => value['id'] == messageId);
      if (index < 0) return;
      cached[index]['delivery_status'] = status;
      await prefs.setString(key, jsonEncode(cached));
    } on FormatException {
      // A subsequent sync page can reconstruct the local cache.
    }
  }

  /// Recover missed deliveries with a durable cursor. Messages are persisted before acking,
  /// pages are idempotent, and message_id is the client deduplication key.
  static Future<int> syncInbox({int maxPages = 10}) {
    final completer = Completer<int>();
    _inboxSyncQueue = _inboxSyncQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await _syncInboxImpl(maxPages: maxPages));
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  static Future<int> _syncInboxImpl({required int maxPages}) async {
    await prepareInboxAccount();
    final prefs = await SharedPreferences.getInstance();
    var cursor = prefs.getInt(_inboxCursorKey) ?? 0;
    var totalSaved = 0;
    for (var pageNumber = 0; pageNumber < maxPages; pageNumber++) {
      final page = await request('/inbox/sync?after_id=$cursor&limit=100');
      final rawItems = page['items'];
      if (rawItems is! List || rawItems.isEmpty) break;
      final items = rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      final touched = <int>{};
      for (final item in items) {
        final conversationId = item['conversation_id'];
        final messageId = item['message_id'];
        if (conversationId is! int || messageId is! int) {
          throw const FormatException('Inbox response contains an invalid message identifier.');
        }
        final key = '$_inboxCachePrefix$conversationId';
        final rawCache = prefs.getString(key);
        List<Map<String, dynamic>> cached = <Map<String, dynamic>>[];
        if (rawCache != null) {
          try {
            final decoded = jsonDecode(rawCache);
            if (decoded is List) {
              cached = decoded.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
            }
          } on FormatException {
            // A corrupt local cache is replaced from the server page below.
          }
        }
        final existingIndex = cached.indexWhere((value) => value['id'] == messageId);
        if (existingIndex < 0) {
          final encrypted = item['ciphertext'] is String;
          cached.add(<String, dynamic>{
            'id': messageId,
            'delivery_id': item['delivery_id'],
            'conversation_id': conversationId,
            'sender_id': item['sender_id'],
            'body': encrypted ? '[Encrypted message]' : (item['body'] ?? ''),
            'is_encrypted': encrypted,
            'created_at': item['created_at'],
            'delivery_status': item['status'] ?? 'pending',
          });
          totalSaved++;
        } else {
          cached[existingIndex]['delivery_id'] = item['delivery_id'];
          cached[existingIndex]['delivery_status'] = item['status'] ?? cached[existingIndex]['delivery_status'] ?? 'pending';
        }
        cached.sort((a, b) => ((a['id'] as int?) ?? 0).compareTo((b['id'] as int?) ?? 0));
        // Keep the local cache bounded. Full history can be paged from the server later.
        if (cached.length > 500) cached = cached.sublist(cached.length - 500);
        await prefs.setString(key, jsonEncode(cached));
        touched.add(conversationId);
      }

      // Only acknowledge after each item in this page has been safely cached. If any ack fails,
      // cursor isn't advanced, so the same page is retried and deduped on the next sync.
      for (final item in items) {
        if (item['status'] == 'pending' && item['delivery_id'] is int) {
          final acknowledgement = await request('/inbox/deliveries/${item['delivery_id']}/ack', method: 'POST', body: {'status': 'delivered'});
          final conversationId = item['conversation_id'];
          final messageId = item['message_id'];
          final acknowledgedStatus = acknowledgement['status'];
          if (conversationId is int && messageId is int && acknowledgedStatus is String) {
            await _updateCachedDeliveryStatus(conversationId, messageId, acknowledgedStatus);
          }
        }
      }
      final nextCursor = page['next_after_id'];
      if (nextCursor is! int || nextCursor < cursor) {
        throw const FormatException('Inbox cursor from server is invalid.');
      }
      await prefs.setInt(_inboxCursorKey, nextCursor);
      cursor = nextCursor;
      if (page['has_more'] != true || touched.isEmpty) break;
    }
    return totalSaved;
  }

  static Future<String> exchangeFirebaseToken(
    String idToken, {
    String? displayName,
  }) async {
    final result = await request(
      '/auth/firebase/exchange',
      method: 'POST',
      body: {
        'id_token': idToken,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
    final accessToken = result['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw Exception('The server did not return a valid access token.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', accessToken);
    await prepareInboxAccount(forceRefresh: true);
    return accessToken;
  }

  static Future<List<dynamic>> getList(String path) async {
    final accessToken = await token();
    late final http.Response response;
    try {
      response = await http
          .get(
            _uri(path),
            headers: {
              'Accept': 'application/json',
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(_timeout);
      await _recordTraffic(sentBytes: 0, receivedBytes: response.bodyBytes.length);
    } on TimeoutException {
      throw Exception('The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw Exception('Cannot reach the Veyra server. Check your connection and API URL.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = 'Request failed (${response.statusCode}).';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } on FormatException {
        // Keep the status-based error if the server response is not JSON.
      }
      throw Exception(detail);
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception('The server returned an invalid list response.');
    }
    if (decoded is! List<dynamic>) {
      throw Exception('The server returned an unexpected list response.');
    }
    return decoded;
  }
}
