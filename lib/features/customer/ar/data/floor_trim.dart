import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

// Depth points between these heights above the floor are walls, doors and
// tall furniture. Starting at 0.8 m keeps bags, bottles, sofa seats and the
// user's own legs from cutting the floor (device 2026-11-20: a 0.25 m band
// trimmed the floor back to a bag 0.7 m away).
const double kObstacleMinAboveFloorM = 0.8;
const double kObstacleMaxAboveFloorM = 1.8;

// Free floor around the camera, per viewing direction, from obstacle
// points: the floor ends where the first solid thing stands. ARCore floor
// polygons (and the synthetic stand-in) run past the wall line before any
// wall is detected, so the green climbed the wall for the first seconds
// (device recording 2026-11-20: floor painted at 9.9 s, first wall fit at
// 15.5 s). The depth points see the wall from the start.
class FloorFreeSpace {
  FloorFreeSpace._(this.camera, this._bins, this.binRad);

  final Vector3 camera;
  final List<double?> _bins;
  final double binRad;

  static FloorFreeSpace? fromObstacles({
    required Vector3 camera,
    required Iterable<Vector3> obstacles,
    double binDeg = 4,
    int minPoints = 3,
    double minDistM = 0.8,
  }) {
    final binRad = binDeg * math.pi / 180;
    final n = (2 * math.pi / binRad).ceil();
    final dists = List.generate(n, (_) => <double>[]);
    for (final p in obstacles) {
      final dx = p.x - camera.x;
      final dz = p.z - camera.z;
      final d = math.sqrt(dx * dx + dz * dz);
      if (d < minDistM) continue;
      dists[_bin(dx, dz, binRad, n)].add(d);
    }
    var any = false;
    final bins = List<double?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final b = dists[i];
      if (b.length < minPoints) continue;
      b.sort();
      // Near percentile: the wall face, not points that leaked behind it.
      bins[i] = b[(b.length * 0.2).floor()];
      any = true;
    }
    if (!any) return null;
    return FloorFreeSpace._(camera, bins, binRad);
  }

  static int _bin(double dx, double dz, double binRad, int n) {
    var a = math.atan2(dz, dx);
    if (a < 0) a += 2 * math.pi;
    return (a / binRad).floor() % n;
  }

  // Floor-plane regions BEHIND the first obstacle in each direction (from
  // the obstacle out to [reachM]) — subtracted from the painted floor with
  // a path boolean. Bending the floor outline instead folded it over itself
  // when the camera was outside the floor and the fill punched holes.
  List<List<Vector3>> cutRegions(double floorY, {double reachM = 8}) {
    final out = <List<Vector3>>[];
    final n = _bins.length;
    Vector3 at(double ang, double r) => Vector3(
        camera.x + math.cos(ang) * r, floorY, camera.z + math.sin(ang) * r);
    var i = 0;
    while (i < n) {
      if (_bins[i] == null) {
        i++;
        continue;
      }
      final start = i;
      while (i < n && _bins[i] != null) {
        i++;
      }
      final inner = <Vector3>[];
      for (var b = start; b < i; b++) {
        final d = _bins[b]!;
        inner
          ..add(at(b * binRad, d))
          ..add(at((b + 1) * binRad, d));
      }
      final outer = [
        at(i * binRad, reachM),
        at(start * binRad, reachM),
      ];
      out.add([...inner, ...outer]);
    }
    return out;
  }

  double? limitFor(double dx, double dz) =>
      _bins[_bin(dx, dz, binRad, _bins.length)];

  // Densify the outline, then pull every vertex that lies beyond the first
  // obstacle in its direction back onto it. Directions with no obstacle
  // evidence are untouched.
  List<Vector3> trim(List<Vector3> polygon, {double stepM = 0.15}) {
    if (polygon.length < 3) return polygon;
    final dense = <Vector3>[];
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final len = (b - a).length;
      final steps = math.max(1, (len / stepM).ceil());
      for (var s = 0; s < steps; s++) {
        dense.add(a + (b - a) * (s / steps));
      }
    }
    var changed = false;
    final out = <Vector3>[];
    for (final v in dense) {
      final dx = v.x - camera.x;
      final dz = v.z - camera.z;
      final d = math.sqrt(dx * dx + dz * dz);
      final lim = limitFor(dx, dz);
      if (lim != null && d > lim && d > 1e-6) {
        final k = lim / d;
        out.add(Vector3(camera.x + dx * k, v.y, camera.z + dz * k));
        changed = true;
      } else {
        out.add(v);
      }
    }
    return changed ? out : polygon;
  }
}
