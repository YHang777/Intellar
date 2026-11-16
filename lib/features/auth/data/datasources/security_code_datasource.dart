import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../../config/app_config.dart';
import '../../../../core/utils/user_errors.dart';

class SecurityCodeException implements Exception, UserFacingException {
  const SecurityCodeException(this.message, {this.code, this.attemptsLeft});

  final String message;
  final String? code;
  final int? attemptsLeft;

  @override
  String get userMessage => message;

  @override
  String toString() => 'SecurityCodeException($code): $message';
}

class CodeSent {
  const CodeSent({required this.sentTo, this.expiresAt});

  final String sentTo;
  final DateTime? expiresAt;
}

class SecurityCodeDatasource {
  SecurityCodeDatasource({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;

  static const Duration _timeout = Duration(seconds: 20);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<CodeSent> sendLoginCode() async =>
      _codeSent(await _post('/api/account/2fa/send', const {}));

  Future<void> verifyLoginCode(String code) async {
    await _post('/api/account/2fa/verify', {'code': code});
  }

  Future<bool> setTwoFactor({required bool enabled, required String code}) async {
    final body = await _post(
        '/api/account/2fa/settings', {'enabled': enabled, 'code': code});
    return body['twoFactorEnabled'] == true;
  }

  Future<CodeSent> requestEmailChange(String newEmail) async => _codeSent(
      await _post('/api/account/email/change-request', {'newEmail': newEmail}));

  Future<String> confirmEmailChange(String code) async {
    final body =
        await _post('/api/account/email/change-confirm', {'code': code});
    final email = body['email'];
    if (email is String && email.isNotEmpty) return email;
    throw const SecurityCodeException(
        'Could not change your email. Please try again.');
  }

  CodeSent _codeSent(Map<String, dynamic> body) => CodeSent(
        sentTo: body['sentTo'] is String ? body['sentTo'] as String : '',
        expiresAt: body['expiresAt'] is String
            ? DateTime.tryParse(body['expiresAt'] as String)?.toLocal()
            : null,
      );

  Future<Map<String, dynamic>> _post(
      String path, Map<String, Object?> body) async {
    final base = AppConfig.verificationApiUrl.trim();
    if (base.isEmpty) {
      throw const SecurityCodeException(
          'Email codes are not available in this build.');
    }
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const SecurityCodeException('Please sign in first.');
    }
    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$base$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const SecurityCodeException(
          'The server took too long. Please try again.');
    } on http.ClientException catch (e) {
      debugPrint('[security-code] request failed: $e');
      throw const SecurityCodeException(
          'Could not reach the server. Check your connection and try again.');
    }

    Map<String, dynamic>? decoded;
    try {
      final raw = jsonDecode(resp.body);
      if (raw is Map<String, dynamic>) decoded = raw;
    } on FormatException {
      decoded = null;
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final error = decoded?['error'];
      String? message;
      String? code;
      int? attemptsLeft;
      if (error is Map) {
        if (error['message'] is String) message = error['message'] as String;
        if (error['code'] is String) code = error['code'] as String;
        final details = error['details'];
        if (details is Map && details['attemptsLeft'] is int) {
          attemptsLeft = details['attemptsLeft'] as int;
        }
      }
      if (code == 'VALIDATION_ERROR') message = 'Enter the 6-digit code.';
      if (resp.statusCode == 401) {
        message = 'Your session expired. Please sign in again.';
      }
      throw SecurityCodeException(
        (message == null || message.trim().isEmpty)
            ? 'Something went wrong. Please try again.'
            : message,
        code: code,
        attemptsLeft: attemptsLeft,
      );
    }
    return decoded ?? const {};
  }
}
