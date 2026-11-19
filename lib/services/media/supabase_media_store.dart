import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'media_store.dart';

// 3D models still live in the public Supabase bucket, but every write goes
// through our backend (/api/models): it checks the Firebase sign-in and that
// the listing is the caller's, then writes with the service key. The app no
// longer uploads with the public anon key, so the bucket can refuse anon
// writes.
class SupabaseMediaStore implements MediaStore {
  SupabaseMediaStore({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;

  static const Duration _timeout = Duration(seconds: 120);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  String get _apiBase =>
      '${AppConfig.verificationApiUrl.replaceAll(RegExp(r'/+$'), '')}/api/models';

  @override
  bool get isConfigured => AppConfig.verificationApiUrl.trim().isNotEmpty;

  // 'product_models/<productId>' → '<productId>'.
  static String? productIdOfPath(String remotePath) {
    final id = remotePath.split('/').last.replaceAll(RegExp(r'\.glb$'), '');
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ? id : null;
  }

  static String? productIdOfUrl(String url) {
    final m = RegExp(r'/storage/v1/object/public/[^/]+/product_models/([A-Za-z0-9_-]+)\.glb$')
        .firstMatch(url);
    return m?.group(1);
  }

  @override
  Future<String> uploadImageFile(
    File file,
    String remotePath, {
    void Function(double progress)? onProgress,
  }) {
    throw const MediaStoreException(
        'SupabaseMediaStore handles 3D models only — product photos go '
        'through CloudinaryMediaStore (see HybridMediaStore).');
  }

  @override
  Future<String> uploadModelBytes(Uint8List bytes, String remotePath) async {
    final id = productIdOfPath(remotePath);
    if (!isConfigured || id == null) {
      throw const MediaStoreException('3D model storage is not available.');
    }
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const MediaStoreException('Sign in to save 3D models.');
    }
    http.Response resp;
    try {
      resp = await _client
          .put(
            Uri.parse('$_apiBase/$id'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'model/gltf-binary',
            },
            body: bytes,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const MediaStoreException('3D model upload timed out');
    } on http.ClientException catch (e) {
      throw MediaStoreException('3D model upload network error: ${e.message}');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw MediaStoreException(
          '3D model upload refused (HTTP ${resp.statusCode}): '
          '${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');
    }
    final url = (jsonDecode(resp.body) as Map<String, dynamic>)['url'];
    if (url is! String || url.isEmpty) {
      throw const MediaStoreException('3D model upload returned no link');
    }
    return url;
  }

  @override
  Future<void> deleteByUrl(String url) async {
    final id = productIdOfUrl(url);
    if (!isConfigured || id == null) {
      debugPrint('[media] model delete skipped (foreign URL): $url');
      return;
    }
    try {
      final token = await _idTokenProvider();
      if (token == null || token.isEmpty) return;
      final resp = await _client.delete(Uri.parse('$_apiBase/$id'),
          headers: {'Authorization': 'Bearer $token'}).timeout(_timeout);
      debugPrint('[media] model delete $id: HTTP ${resp.statusCode}');
    } catch (e) {
      debugPrint('[media] model delete failed for $id: $e');
    }
  }
}
