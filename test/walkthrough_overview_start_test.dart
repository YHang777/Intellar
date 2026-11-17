import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_controller.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

RoomDesign _design({List<FurniturePlacement> furniture = const []}) =>
    RoomDesign(
      id: 'd',
      userId: 'u',
      name: 'Test',
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      furniture: furniture,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('an empty room starts in a corner looking at the centre', () {
    final ctl = WalkthroughController(design: _design())..startAtOverview();
    final toCentre = const Offset(200, 250) - ctl.walker;
    expect(toCentre.distance, greaterThan(200),
        reason: 'stands back from the middle to see the room');
    expect((ctl.heading - atan2(toCentre.dy, toCentre.dx)).abs(),
        lessThan(1e-9));
  });

  test('furniture in one corner is viewed from across the room', () {
    final sofa = FurniturePlacement(
      id: 's',
      name: 'Sofa',
      iconName: 'sofa',
      x: 300,
      y: 380,
      width: 90,
      height: 90,
    );
    final ctl = WalkthroughController(design: _design(furniture: [sofa]))
      ..startAtOverview();
    expect(ctl.walker.dx, lessThan(200));
    expect(ctl.walker.dy, lessThan(250));
    final toSofa = const Offset(345, 425) - ctl.walker;
    expect((ctl.heading - atan2(toSofa.dy, toSofa.dx)).abs(), lessThan(1e-9),
        reason: 'faces the furniture so it is on screen');
  });
}
