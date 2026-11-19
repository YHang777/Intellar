import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/models/room_design.dart';
import 'package:interior_design_recommendation/services/material_scan_service.dart';

void main() {
  testWidgets('a reviewed scan applies the ticked furniture and the finishes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: RoomScannerScreen(
          existingDesign: RoomDesign(
            id: '',
            name: 'Room',
            roomType: 'living_room',
            widthCm: 500,
            heightCm: 500,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            userId: '',
          ),
        ),
      ),
    ));
    await tester.pump();
    final dynamic state = tester.state(find.byType(RoomScannerScreen));

    state.debugShowScanResult(const RoomMaterialScan(
      floorType: FloorFinishType.woodPlanks,
      floorColorArgb: 0xFFC8A27A,
      wallType: WallFinishType.paint,
      wallColorArgb: 0xFFEDE8E0,
      items: ['Sofa', 'Armchair'],
    ));
    await tester.pump();

    expect(find.text('Scan your room'), findsOneWidget);
    expect(find.byKey(const Key('scan-item-Sofa')), findsOneWidget);
    // Untick the armchair: only the sofa should be placed.
    await tester.tap(find.byKey(const Key('scan-item-Armchair')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan-apply')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final placed = (state.debugFurniture as List).map((f) => f.name).toList();
    expect(placed, ['Sofa']);
    final design = state.debugApplyMaterialScan(const RoomMaterialScan()) as RoomDesign;
    expect(design.floorFinishType, 'woodPlanks');
    expect(design.wallFinishType, 'paint');
    expect(find.byKey(const Key('scan-apply')), findsNothing, reason: 'back in the planner');
    await tester.pump(const Duration(seconds: 5));
  });
}
