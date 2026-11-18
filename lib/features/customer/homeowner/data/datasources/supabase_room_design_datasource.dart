import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../../../config/app_config.dart';
import '../../../../../models/room_design.dart';

// Saved designs go through our backend (/api/designs), never straight to
// Supabase: the app's anon key is public, so with direct access anyone could
// read or change every user's designs. The backend checks the Firebase
// sign-in and only ever touches the caller's own rows. Rows keep the table's
// snake_case shape, so the mapping below is unchanged.
class SupabaseRoomDesignDatasource {
  SupabaseRoomDesignDatasource({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;
  static const Duration _timeout = Duration(seconds: 30);
  static const Duration pollInterval = Duration(seconds: 5);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  String get _baseUrl =>
      '${AppConfig.verificationApiUrl.replaceAll(RegExp(r'/+$'), '')}/api/designs';

  bool get isConfigured => AppConfig.verificationApiUrl.trim().isNotEmpty;

  Future<Map<String, String>> _headers() async {
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to see your saved designs.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> createDesign({
    required String designId,
    required Map<String, dynamic> data,
  }) async {
    final body = {
      'id': designId,
      ..._toRow(data),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _post(body);
  }

  Future<void> updateDesign(
    String designId,
    Map<String, dynamic> data,
  ) async {
    final body = {
      ..._toRow(data),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _patch(designId, body);
  }

  // PostgREST rejects unknown columns, so the model's camelCase toJson
  // keys must be mapped to the table's snake_case columns. Walls and the
  // finish fields live inside the furniture JSONB ({items, walls, finishes})
  // — the table has no columns for them and anon cannot migrate the schema.
  Map<String, dynamic> _toRow(Map<String, dynamic> data) {
    final hasFinishes = data.containsKey('floorFinishType') ||
        data.containsKey('floorFinishColor') ||
        data.containsKey('wallFinishType') ||
        data.containsKey('wallFinishColor');
    return {
      if (data.containsKey('name')) 'name': data['name'],
      if (data.containsKey('roomType')) 'room_type': data['roomType'],
      if (data.containsKey('widthCm')) 'width_cm': data['widthCm'],
      if (data.containsKey('heightCm')) 'height_cm': data['heightCm'],
      if (data.containsKey('furniture') ||
          data.containsKey('walls') ||
          data.containsKey('interiorWalls') ||
          hasFinishes)
        'furniture': {
          'items': data['furniture'] ?? [],
          'walls': data['walls'] ?? [],
          if (data['interiorWalls'] != null)
            'interiorWalls': data['interiorWalls'],
          if (hasFinishes)
            'finishes': {
              if (data['floorFinishType'] != null)
                'floorType': data['floorFinishType'],
              if (data['floorFinishColor'] != null)
                'floorColor': data['floorFinishColor'],
              if (data['wallFinishType'] != null)
                'wallType': data['wallFinishType'],
              if (data['wallFinishColor'] != null)
                'wallColor': data['wallFinishColor'],
            },
        },
      if (data.containsKey('detectedItems'))
        'detected_items': data['detectedItems'],
      if (data.containsKey('imagePath')) 'image_path': data['imagePath'],
      if (data.containsKey('userId')) 'user_id': data['userId'],
    };
  }

  Future<void> deleteDesign(String designId) async {
    await _delete(designId);
  }

  // userId is kept for callers; the backend reads it from the sign-in.
  Future<List<RoomDesign>> getDesigns(String userId) async {
    final resp = await _client
        .get(Uri.parse(_baseUrl), headers: await _headers())
        .timeout(_timeout);
    _checkError(resp);
    final List json = (jsonDecode(resp.body) as Map)['designs'] as List? ?? [];
    return json.map((e) {
      final map = _fromRow(e);
      return RoomDesign.fromJson(map);
    }).toList();
  }

  Stream<List<RoomDesign>> watchDesigns(String userId) async* {
    yield await getDesigns(userId);
    await for (final _
        in Stream.periodic(pollInterval).asyncExpand((_) async* {
      yield await getDesigns(userId);
    })) {
      yield await getDesigns(userId);
    }
  }

  Future<RoomDesign?> getDesign(String designId) async {
    final resp = await _client
        .get(Uri.parse('$_baseUrl/${Uri.encodeComponent(designId)}'),
            headers: await _headers())
        .timeout(_timeout);
    if (resp.statusCode == 404) return null;
    _checkError(resp);
    final row = (jsonDecode(resp.body) as Map)['design'];
    if (row is! Map<String, dynamic>) return null;
    return RoomDesign.fromJson(_fromRow(row));
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  // TimeoutException / http.ClientException / SocketException are left
  // to propagate — userMessage() maps each to a plain sentence at the
  // call site (wrapping them here would flatten every failure into the
  // generic fallback).
  Future<void> _post(Map<String, dynamic> body) async {
    // user_id is set by the backend from the sign-in, never from here.
    final resp = await _client
        .post(Uri.parse(_baseUrl),
            headers: await _headers(),
            body: jsonEncode(Map.of(body)..remove('user_id')))
        .timeout(_timeout);
    _checkError(resp);
  }

  Future<void> _patch(String id, Map<String, dynamic> body) async {
    final resp = await _client
        .patch(Uri.parse('$_baseUrl/${Uri.encodeComponent(id)}'),
            headers: await _headers(),
            body: jsonEncode(Map.of(body)..remove('user_id')))
        .timeout(_timeout);
    _checkError(resp);
  }

  Future<void> _delete(String id) async {
    final resp = await _client
        .delete(Uri.parse('$_baseUrl/${Uri.encodeComponent(id)}'),
            headers: await _headers())
        .timeout(_timeout);
    _checkError(resp);
  }

  void _checkError(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String? message;
      try {
        message = ((jsonDecode(resp.body) as Map)['error'] as Map?)?['message']
            as String?;
      } catch (_) {}
      throw Exception(message ?? 'Saved designs error (HTTP ${resp.statusCode}).');
    }
  }

  Map<String, dynamic> _fromRow(Map<String, dynamic> row) {
    return {
      'id': row['id']?.toString() ?? '',
      'name': row['name']?.toString() ?? 'Untitled Design',
      'roomType': row['room_type']?.toString() ?? 'living_room',
      'widthCm': row['width_cm'],
      'heightCm': row['height_cm'],
      'furniture': row['furniture'],
      'walls': row['walls'],
      'detectedItems': row['detected_items'],
      'imagePath': row['image_path'],
      'createdAt': row['created_at']?.toString(),
      'updatedAt': row['updated_at']?.toString(),
      'userId': row['user_id']?.toString() ?? '',
    };
  }
}
