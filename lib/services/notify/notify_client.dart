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
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken,
        _baseUrl = baseUrl;

  static NotifyClient instance = NotifyClient();

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;
  final String? _baseUrl;

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

  Future<bool> send(String path, Map<String, Object?> body) async {
    try {
      final base = (_baseUrl ?? AppConfig.verificationApiUrl).trim();
      if (base.isEmpty) return false;
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
          .timeout(const Duration(seconds: 15));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      debugPrint('[notify] $path skipped: $e');
      return false;
    }
  }
}
