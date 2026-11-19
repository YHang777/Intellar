import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/room_finishes.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_state_context.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

RoomDesign _room({String? floorType, int? floorColor, String? wallType, List<String> items = const []}) =>
    RoomDesign(
      id: 'd1',
      name: 'Lounge',
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      furniture: const [],
      walls: const [],
      detectedItems: items,
      floorFinishType: floorType,
      floorFinishColor: floorColor,
      wallFinishType: wallType,
      createdAt: DateTime(2026, 11, 19),
      updatedAt: DateTime(2026, 11, 19),
      userId: 'u',
    );

Map<String, dynamic>? _plan(RoomDesign d) => buildChatStateJson(
      cartRows: const [],
      cartCount: 0,
      cartSubtotal: 0,
      budget: null,
      orders: const [],
      plan: d,
      pendingPlacements: 0,
    )?['plan'] as Map<String, dynamic>?;

void main() {
  test('the scanned floor, walls and existing items reach the assistant', () {
    final wood = RoomFinishCatalog.colorsForFloor(FloorFinishType.woodPlanks).first;
    final plan = _plan(_room(
      floorType: FloorFinishType.woodPlanks.name,
      floorColor: wood.argb,
      wallType: WallFinishType.paint.name,
      items: const ['Couch', 'Television'],
    ))!;
    expect(plan['floor'],
        '${wood.name} ${RoomFinishCatalog.floorLabel(FloorFinishType.woodPlanks)}');
    expect(plan['walls'], RoomFinishCatalog.wallLabel(WallFinishType.paint));
    expect(plan['existingItems'], ['Couch', 'Television']);
  });

  test('nothing scanned: no invented finishes', () {
    final plan = _plan(_room())!;
    expect(plan.containsKey('floor'), isFalse);
    expect(plan.containsKey('walls'), isFalse);
    expect(plan.containsKey('existingItems'), isFalse);
    expect(scannedFloorOf(_room(floorType: 'marble')), isNull,
        reason: 'unknown finish names are dropped, not guessed');
  });
}
