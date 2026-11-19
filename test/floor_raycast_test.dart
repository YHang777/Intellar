import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/wall_raycast.dart';
import 'package:vector_math/vector_math_64.dart';

PlaneQuad _floor({double cx = 0, double cz = -2, double size = 2}) => PlaneQuad(
      center: Vector3(cx, 0, cz),
      yaw: 0,
      extentX: size,
      extentZ: size,
      vertical: false,
      kind: PlaneQuadKind.floor,
    );

void main() {
  final eye = Vector3(0, 1.4, 0);

  test('a ray aimed down at painted floor hits it at the floor height', () {
    final dir = (Vector3(0, 0, -2) - eye).normalized();
    final h = raycastFloor(origin: eye, dir: dir, floors: [_floor()], floorY: 0);
    expect(h, isNotNull);
    expect(h!.point.y, 0);
    expect(h.point.z, closeTo(-2, 1e-6));
  });

  test('outside the painted floor, or looking up, there is no hit', () {
    final away = (Vector3(5, 0, -2) - eye).normalized();
    expect(raycastFloor(origin: eye, dir: away, floors: [_floor()], floorY: 0),
        isNull);
    expect(
        raycastFloor(
            origin: eye, dir: Vector3(0, 0.2, -1).normalized(), floors: [_floor()], floorY: 0),
        isNull);
  });

  test('walls never count as floor', () {
    final wall = PlaneQuad(
      center: Vector3(0, 0, -2),
      yaw: 0,
      extentX: 2,
      extentZ: 2,
      vertical: true,
      kind: PlaneQuadKind.wall,
    );
    final dir = (Vector3(0, 0, -2) - eye).normalized();
    expect(raycastFloor(origin: eye, dir: dir, floors: [wall], floorY: 0), isNull);
  });
}
