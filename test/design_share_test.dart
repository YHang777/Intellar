import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/furniture_model_library.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/design_share.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/shared_design_screen.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

FurniturePlacement _f(String id, String icon, {String? modelUrl, double? heightCm}) =>
    FurniturePlacement(
      id: id,
      name: id,
      iconName: icon,
      x: 10,
      y: 20,
      width: 100,
      height: 80,
      rotation: 90,
      modelUrl: modelUrl,
      heightCm: heightCm,
    );

RoomDesign _design({String id = 'd1'}) => RoomDesign(
      id: id,
      name: 'Lounge',
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      furniture: [
        _f('a', 'lounge_chair'),
        _f('b', 'rug'),
        _f('c', 'sofa', modelUrl: 'https://x.supabase.co/m.glb', heightCm: 88),
        _f('d', 'sofa', modelUrl: '/data/user/0/local.glb'),
      ],
      walls: const [Offset(0, 0), Offset(400, 0), Offset(400, 500), Offset(0, 500)],
      detectedItems: const [],
      imagePath: '/data/user/0/photo.jpg',
      floorFinishColor: 0xFFAA8866,
      createdAt: DateTime.utc(2026, 11, 19),
      updatedAt: DateTime.utc(2026, 11, 19),
      userId: 'owner-uid',
    );

void main() {
  test('every piece carries a model the browser can load, or none', () {
    final items = sharedSceneOf(_design())['items'] as List;
    final model = {for (final i in items) i['id']: i['model']};
    expect(model['a'],
        'assets/models/${ArFurnitureLibrary.forIconName('lounge_chair').modelFile}');
    expect(model['b'], isNull, reason: 'generated on the phone: browser draws a box');
    expect(model['c'], 'https://x.supabase.co/m.glb');
    expect(model['d'], isNotNull,
        reason: 'a phone-local path is never shared; the catalog model stands in');
    expect(model['d'], startsWith('assets/models/'));
    final c = items.firstWhere((i) => i['id'] == 'c');
    expect(c['heightCm'], closeTo(88, 1e-9));
    expect(c['widthCm'], 100);
    expect(c['depthCm'], 80);
    expect(c['rotation'], 90);
  });

  test('the shared copy carries no owner details and opens unsaved', () {
    final json = sharedDesignJsonOf(_design());
    expect(json.containsKey('userId'), isFalse);
    expect(json.containsKey('imagePath'), isFalse);
    final back = designFromShared({'design': jsonDecode(jsonEncode(json))})!;
    expect(back.id, isEmpty);
    expect(back.userId, isEmpty);
    expect(back.furniture.length, 4);
    expect(back.walls.length, 4);
    expect(back.floorFinishColor, 0xFFAA8866);
    expect(designFromShared({'design': null}), isNull);
  });

  test('createLink sends the scene with the sign-in and returns the url', () async {
    late http.Request sent;
    final client = DesignShareClient(
      idTokenProvider: () async => 'tok',
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'token': 'abc', 'url': 'https://h/d/abc'}), 201);
      }),
    );
    expect(await client.createLink(_design()), 'https://h/d/abc');
    expect(sent.method, 'POST');
    expect(sent.url.path, endsWith('/api/shared-designs'));
    expect(sent.headers['Authorization'], 'Bearer tok');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['designId'], 'd1');
    expect((body['design'] as Map).containsKey('userId'), isFalse);

    final unsaved = jsonDecode((await () async {
      await client.createLink(_design(id: ''));
      return sent.body;
    }())) as Map<String, dynamic>;
    expect(unsaved.containsKey('designId'), isFalse);
  });

  test('sharing needs sign-in', () async {
    final client = DesignShareClient(
      idTokenProvider: () async => null,
      client: MockClient((_) async => http.Response('', 500)),
    );
    expect(() => client.createLink(_design()), throwsA(isA<DesignShareException>()));
  });

  testWidgets('a missing link says so instead of spinning', (tester) async {
    final client = DesignShareClient(
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    await tester.pumpWidget(MaterialApp(
      home: SharedDesignScreen(token: 'gone1234', client: client),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('shared-design-error')), findsOneWidget);
    expect(find.text('This shared design was not found.'), findsOneWidget);
  });
}
