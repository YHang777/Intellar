import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';

// Announces actions the app performs directly in Firestore so the server can
// send notifications and keep the audit trail. Never blocks or fails the
// action itself: every call is fire-and-forget with a short timeout.
class NotifyClient {
  NotifyClient({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
    String? baseUrl,
    Duration retryDelay = const Duration(seconds: 3),
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken,
        _baseUrl = baseUrl,
        _retryDelay = retryDelay;

  static NotifyClient instance = NotifyClient();

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;
  final String? _baseUrl;
  final Duration _retryDelay;

  static Future<String?> _firebaseIdToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  void orderStatusChanged(String orderId) =>
      _fire('/api/notify/order-status', {'orderId': orderId});

  void quoteCreated(String quoteId) =>
      _fire('/api/notify/quote', {'quoteId': quoteId, 'event': 'created'});

  void quoteContacted(String quoteId) =>
      _fire('/api/notify/quote', {'quoteId': quoteId, 'event': 'contacted'});

  void productPublished(String productId) =>
      _fire('/api/notify/new-product', {'productId': productId});

  // The backend checks the listing really is on sale and only notifies once
  // per price, so calling this after every save is safe.
  void productViewed(String productId) =>
      _fire('/api/product-views', {'productId': productId});

  void productOnSale(String productId) =>
      _fire('/api/notify/promotion', {'productId': productId});

  void audit(
    String action, {
    String? targetType,
    String? targetId,
    Map<String, Object>? details,
  }) =>
      _fire('/api/audit', {
        'action': action,
        if (targetType != null) 'targetType': targetType,
        if (targetId != null) 'targetId': targetId,
        if (details != null && details.isNotEmpty) 'details': details,
      });

  void _fire(String path, Map<String, Object?> body) {
    unawaited(send(path, body));
  }

  // The free Render host can take ~30-50 s to wake, so the wait is generous.
  // One retry covers "still starting" replies and dropped connections; a
  // timeout is not retried because the server may already have acted on it.
  static const _timeout = Duration(seconds: 60);

  Future<bool> send(String path, Map<String, Object?> body) async {
    final base = (_baseUrl ?? AppConfig.verificationApiUrl).trim();
    if (base.isEmpty) return false;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await _idTokenProvider();
        if (token == null || token.isEmpty) return false;
        final resp = await _client
            .post(
              Uri.parse('$base$path'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(_timeout);
        if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
        final waking = resp.statusCode == 502 ||
            resp.statusCode == 503 ||
            resp.statusCode == 504;
        if (!waking) return false;
      } on TimeoutException catch (e) {
        debugPrint('[notify] $path timed out: $e');
        return false;
      } catch (e) {
        debugPrint('[notify] $path attempt ${attempt + 1} failed: $e');
      }
      if (attempt == 0) await Future<void>.delayed(_retryDelay);
    }
    return false;
  }
}
