import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/floor_trim.dart';
import 'package:vector_math/vector_math_64.dart';

// A wall along z = 2 (camera at the origin, floor at y = -1.2): depth points
// on its face from 0.9 to 1.8 m above the floor.
List<Vector3> _wallPoints() => [
      for (var x = -1.5; x <= 1.5; x += 0.1)
        for (var y = -0.3; y <= 0.6; y += 0.3) Vector3(x, y, 2.0),
    ];

// ARCore floor running 1.5 m past the wall line.
final _floor = [
  Vector3(-1.5, -1.2, -0.5),
  Vector3(1.5, -1.2, -0.5),
  Vector3(1.5, -1.2, 3.5),
  Vector3(-1.5, -1.2, 3.5),
];

void main() {
  test('floor stops at the wall the depth points see', () {
    final free = FloorFreeSpace.fromObstacles(
        camera: Vector3.zero(), obstacles: _wallPoints())!;
    final trimmed = free.trim(_floor);
    final maxZ = trimmed.map((v) => v.z).reduce(math.max);
    expect(maxZ, lessThanOrEqualTo(2.05),
        reason: 'no green beyond the wall line (was 3.5)');
    expect(trimmed.every((v) => v.y == -1.2), isTrue,
        reason: 'stays on the floor plane');
  });

  test('floor in directions with no obstacle is untouched', () {
    final free = FloorFreeSpace.fromObstacles(
        camera: Vector3.zero(), obstacles: _wallPoints())!;
    final behind = [
      Vector3(-1, -1.2, -0.5),
      Vector3(1, -1.2, -0.5),
      Vector3(1, -1.2, -2.5),
      Vector3(-1, -1.2, -2.5),
    ];
    expect(free.trim(behind), same(behind));
  });

  test('a couple of stray points do not cut the floor', () {
    final free = FloorFreeSpace.fromObstacles(
        camera: Vector3.zero(),
        obstacles: [Vector3(0, -0.5, 1.0), Vector3(0.6, -0.5, 1.0)]);
    expect(free, isNull);
  });

  test('a bag 0.7 m away (below 0.8 m tall) never cuts the floor', () {
    final bag = [
      for (var x = -0.2; x <= 0.2; x += 0.05)
        for (var y = -1.1; y <= -0.8; y += 0.1) Vector3(x, y, 0.7),
    ];
    final free = FloorFreeSpace.fromObstacles(
        camera: Vector3.zero(),
        obstacles: bag.where((p) =>
            p.y + 1.2 >= kObstacleMinAboveFloorM &&
            p.y + 1.2 <= kObstacleMaxAboveFloorM));
    expect(free, isNull);
  });

  test('cut regions start at the wall and cover the floor behind it', () {
    final free = FloorFreeSpace.fromObstacles(
        camera: Vector3.zero(), obstacles: _wallPoints())!;
    final cuts = free.cutRegions(-1.2);
    expect(cuts, isNotEmpty);
    for (final c in cuts) {
      final nearest = c
          .map((v) => math.sqrt(v.x * v.x + v.z * v.z))
          .reduce(math.min);
      expect(nearest, greaterThanOrEqualTo(1.95),
          reason: 'never cuts floor in front of the wall');
      expect(c.every((v) => v.y == -1.2), isTrue);
    }
  });
}
