import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/floor_trim.dart';
import 'package:vector_math/vector_math_64.dart';

// A wall along z = 2 (camera at the origin, floor at y = -1.2): depth points
// on its face from 0.3 to 1.5 m above the floor.
List<Vector3> _wallPoints() => [
      for (var x = -1.5; x <= 1.5; x += 0.1)
        for (var y = -0.9; y <= 0.3; y += 0.3) Vector3(x, y, 2.0),
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
}
