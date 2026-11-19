import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../../config/app_config.dart';
import '../../../../models/room_design.dart';
import '../../ar/data/catalog_model_resolver.dart' show kGeneratedCatalogIcons;
import '../../ar/data/furniture_model_library.dart';
import 'planner_scene_bridge.dart' show plannerHeightMOf;

// Share a plan as a link (/d/<token>). The web viewer cannot read the app's
// catalogue, so every piece carries its resolved model and true height.

String? sharedModelRefOf(FurniturePlacement f) {
  final own = f.modelUrl?.trim() ?? '';
  if (own.startsWith('https://') || own.startsWith('assets/models/')) return own;
  if (!kGeneratedCatalogIcons.contains(f.iconName) &&
      ArFurnitureLibrary.hasModelFor(f.iconName)) {
    return 'assets/models/${ArFurnitureLibrary.forIconName(f.iconName).modelFile}';
  }
  return null;
}

Map<String, dynamic> sharedSceneOf(RoomDesign d) => {
      'name': d.name,
      'roomType': d.roomType,
      'room': {
        'widthCm': d.widthCm,
        'heightCm': d.heightCm,
        'walls': [for (final p in d.walls) [p.dx, p.dy]],
        'interiorWalls': [
          for (final c in d.interiorWalls) [for (final p in c) [p.dx, p.dy]],
        ],
        'floorColor': d.floorFinishColor,
        'wallColor': d.wallFinishColor,
        'floorType': d.floorFinishType,
        'wallType': d.wallFinishType,
      },
      'items': [
        for (final f in d.furniture)
          {
            'id': f.id,
            'name': f.name,
            'iconName': f.iconName,
            'x': f.x,
            'y': f.y,
            'widthCm': f.width,
            'depthCm': f.height,
            'heightCm': plannerHeightMOf(f) * 100,
            'rotation': f.rotation,
            'elevationCm': f.elevationCm ?? 0,
            'model': sharedModelRefOf(f),
            'productId': f.productId,
          },
      ],
    };

// The app's own JSON, minus anything that identifies the owner or points at
// files on their phone.
Map<String, dynamic> sharedDesignJsonOf(RoomDesign d) =>
    Map.of(d.toJson())
      ..remove('userId')
      ..remove('imagePath');

// A shared plan opens as a fresh, unsaved copy: saving it makes the viewer's
// own design, never touches the sharer's.
RoomDesign? designFromShared(Map<String, dynamic> body) {
  final raw = body['design'];
  if (raw is! Map) return null;
  final d = RoomDesign.fromJson(Map<String, dynamic>.from(raw));
  return d.copyWith(id: '', userId: '');
}

class DesignShareException implements Exception {
  const DesignShareException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DesignShareClient {
  DesignShareClient({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;
  static const Duration _timeout = Duration(seconds: 30);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  String get _base =>
      '${AppConfig.verificationApiUrl.replaceAll(RegExp(r'/+$'), '')}/api/shared-designs';

  Future<String> createLink(RoomDesign d) async {
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const DesignShareException('Sign in to share your design.');
    }
    final resp = await _client
        .post(
          Uri.parse(_base),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            if (d.id.isNotEmpty) 'designId': d.id,
            'scene': sharedSceneOf(d),
            'design': sharedDesignJsonOf(d),
          }),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw const DesignShareException(
          'Could not create a share link. Please try again.');
    }
    final url = (jsonDecode(resp.body) as Map<String, dynamic>)['url'];
    if (url is! String || url.isEmpty) {
      throw const DesignShareException(
          'Could not create a share link. Please try again.');
    }
    return url;
  }

  Future<RoomDesign?> open(String token) async {
    final resp = await _client
        .get(Uri.parse('$_base/${Uri.encodeComponent(token)}'))
        .timeout(_timeout);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw const DesignShareException(
          'Could not open the shared design. Please try again.');
    }
    return designFromShared(jsonDecode(resp.body) as Map<String, dynamic>);
  }
}
