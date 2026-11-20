import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'plane_overlay_math.dart';

// Persistent room walls. Raw wall quads (ARCore + cloud fits) come and go
// every few seconds and one physical wall arrives as 2–4 overlapping
// fragments (device round 5), so painted walls flickered, split and kept
// changing — and wall tiles had nothing stable to land on. Here every
// fragment on the same line folds into ONE wall per side: span grows only,
// the line is confirmed after it has been seen for [confirmAfter] and
// frozen after [freezeAfter] (hard-stick), and walls never vanish because a
// fit expired. Expects walls already Manhattan-snapped (see RoomAxis).
class RoomWalls {
  RoomWalls({
    // 3° made every slightly-off refit a NEW wall (duplicates 5° apart,
    // device 2026-11-20) instead of feeding the frozen wall's correction.
    this.maxYawDiffRad = 8 * math.pi / 180,
    this.maxOffsetM = 0.25,
    this.maxGapM = 0.5,
    this.confirmAfter = const Duration(milliseconds: 1000),
    this.freezeAfter = const Duration(seconds: 3),
    this.maxWalls = 24,
  });

  final double maxYawDiffRad;
  final double maxOffsetM;
  final double maxGapM;
  final Duration confirmAfter;
  final Duration freezeAfter;
  final int maxWalls;

  final List<_RoomWall> _walls = [];

  int get count => _walls.length;

  void clear() => _walls.clear();

  List<PlaneQuad> update(List<PlaneQuad> incoming,
      {double? baseY, DateTime? now}) {
    final t = now ?? DateTime.now();
    for (final q in incoming) {
      if (!q.vertical) continue;
      final obs = _Obs.of(q);
      if (obs == null) continue;
      _RoomWall? match;
      var bestD = double.infinity;
      for (final w in _walls) {
        final dd = w.distanceTo(obs, maxYawDiffRad, maxGapM);
        if (dd != null && dd < maxOffsetM && dd < bestD) {
          bestD = dd;
          match = w;
        }
      }
      if (match == null) {
        _walls.add(_RoomWall(obs, t));
      } else {
        match.absorb(obs, t, frozen: t.difference(match.firstSeen) >= freezeAfter);
      }
    }
    _mergeOverlapping();
    if (_walls.length > maxWalls) {
      _walls.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      _walls.removeRange(maxWalls, _walls.length);
    }
    return [
      for (final w in _walls)
        if (w.lastSeen.difference(w.firstSeen) >= confirmAfter)
          w.toQuad(baseY: baseY),
    ];
  }

  void _mergeOverlapping() {
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var i = 0; i < _walls.length; i++) {
        for (var j = i + 1; j < _walls.length; j++) {
          final a = _walls[i];
          final b = _walls[j];
          final dd = a.distanceTo(b.asObs(), maxYawDiffRad, 0);
          if (dd != null && dd < maxOffsetM) {
            a.mergeFrom(b);
            _walls.removeAt(j);
            merged = true;
            break outer;
          }
        }
      }
    }
  }
}

// One observation in canonical form: yaw folded into [0, π) so a wall seen
// from either side (flipped normal) lands on the same line.
class _Obs {
  _Obs(this.yaw, this.offset, this.s0, this.s1, this.yTop, this.weight);

  final double yaw;
  final double offset;
  final double s0;
  final double s1;
  final double yTop;
  final double weight;

  static _Obs? of(PlaneQuad q) {
    var yaw = q.yaw % math.pi;
    if (yaw < 0) yaw += math.pi;
    final n = Vector3(math.sin(yaw), 0, math.cos(yaw));
    final u = Vector3(math.cos(yaw), 0, -math.sin(yaw));
    final pts = planeQuadCorners(q);
    if (pts.length < 3) return null;
    var s0 = double.infinity, s1 = -double.infinity, top = -double.infinity;
    for (final p in pts) {
      final s = p.dot(u);
      if (s < s0) s0 = s;
      if (s > s1) s1 = s;
      if (p.y > top) top = p.y;
    }
    if (!(s1 > s0)) return null;
    return _Obs(yaw, q.center.dot(n), s0, s1, top,
        math.max(1e-3, q.extentX * q.extentZ));
  }
}

class _RoomWall {
  _RoomWall(_Obs o, DateTime t)
      : yaw = o.yaw,
        offset = o.offset,
        s0 = o.s0,
        s1 = o.s1,
        yTop = o.yTop,
        weight = o.weight,
        firstSeen = t,
        lastSeen = t;

  double yaw;
  double offset;
  double s0;
  double s1;
  double yTop;
  double weight;
  final DateTime firstSeen;
  DateTime lastSeen;

  // Frozen walls still accept a CONSISTENT correction: the first seconds
  // of a plain wall's depth points are the sparsest, and freezing on them
  // locked a wall 15 cm in front of the real one for the whole session
  // (device recording 2026-11-20). A jittery or one-off refit never builds
  // a 3 s streak, so the wall still hard-sticks against noise.
  final List<(DateTime, double, double)> _recent = [];
  static const _correctWindow = Duration(seconds: 3);
  static const _correctMinSpan = Duration(milliseconds: 2000);
  static const _correctOffsetM = 0.06;
  static const _correctYawRad = 1.5 * math.pi / 180;

  _Obs asObs() => _Obs(yaw, offset, s0, s1, yTop, weight);

  double? distanceTo(_Obs o, double maxYaw, double maxGap) {
    var dy = (o.yaw - yaw).abs();
    if (dy > math.pi / 2) dy = math.pi - dy;
    if (dy > maxYaw) return null;
    // Folding across 0/π flips the normal, and with it the offset sign.
    final flipped = (o.yaw - yaw).abs() > math.pi / 2;
    final oOff = flipped ? -o.offset : o.offset;
    final os0 = flipped ? -o.s1 : o.s0;
    final os1 = flipped ? -o.s0 : o.s1;
    if (os0 > s1 + maxGap || os1 < s0 - maxGap) return null;
    return (oOff - offset).abs();
  }

  void absorb(_Obs o, DateTime t, {required bool frozen}) {
    final flipped = (o.yaw - yaw).abs() > math.pi / 2;
    final oOff = flipped ? -o.offset : o.offset;
    final os0 = flipped ? -o.s1 : o.s0;
    final os1 = flipped ? -o.s0 : o.s1;
    final oYaw = flipped ? (o.yaw > yaw ? o.yaw - math.pi : o.yaw + math.pi) : o.yaw;
    if (!frozen) {
      final w = o.weight / (weight + o.weight);
      offset += (oOff - offset) * w;
      yaw += (oYaw - yaw) * w;
      weight = math.min(weight + o.weight, 50);
    } else {
      _considerCorrection(oOff, oYaw, t);
    }
    s0 = math.min(s0, os0);
    s1 = math.max(s1, os1);
    yTop = math.max(yTop, o.yTop);
    lastSeen = t;
  }

  // Median of the last 3 s of readings: plain-wall fits scatter ±5-10 cm,
  // so a 'every reading agrees' streak kept restarting and a 20 cm error
  // took ~25 s to fix (device recording 2026-11-20). Wobble around the
  // frozen line keeps the median on it and splits the sides 50/50.
  void _considerCorrection(double oOff, double oYaw, DateTime t) {
    _recent.add((t, oOff, oYaw));
    _recent.removeWhere((e) => t.difference(e.$1) > _correctWindow);
    if (_recent.length < 6 ||
        t.difference(_recent.first.$1) < _correctMinSpan) {
      return;
    }
    double median(List<double> v) {
      final s = [...v]..sort();
      final n = s.length;
      return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
    }

    final offs = [for (final e in _recent) e.$2];
    final yaws = [for (final e in _recent) e.$3];
    final mOff = median(offs);
    final mYaw = median(yaws);
    final dOff = mOff - offset;
    final dYaw = mYaw - yaw;
    bool sameSide(List<double> v, double ref, double d) {
      final agree = v.where((x) => (x - ref) * d > 0).length;
      return agree >= v.length * 0.75;
    }

    var moved = false;
    if (dOff.abs() > _correctOffsetM && sameSide(offs, offset, dOff)) {
      offset = mOff;
      moved = true;
    }
    if (dYaw.abs() > _correctYawRad && sameSide(yaws, yaw, dYaw)) {
      yaw = mYaw;
      moved = true;
    }
    if (moved) _recent.clear();
  }

  void mergeFrom(_RoomWall b) {
    final o = b.asObs();
    final flipped = (o.yaw - yaw).abs() > math.pi / 2;
    final bOff = flipped ? -o.offset : o.offset;
    final w = b.weight / (weight + b.weight);
    offset += (bOff - offset) * w;
    weight = math.min(weight + b.weight, 50);
    s0 = math.min(s0, flipped ? -b.s1 : b.s0);
    s1 = math.max(s1, flipped ? -b.s0 : b.s1);
    yTop = math.max(yTop, b.yTop);
    if (b.lastSeen.isAfter(lastSeen)) lastSeen = b.lastSeen;
  }

  PlaneQuad toQuad({double? baseY}) {
    final n = Vector3(math.sin(yaw), 0, math.cos(yaw));
    final u = Vector3(math.cos(yaw), 0, -math.sin(yaw));
    final bottom = baseY ?? (yTop - 2.0);
    final top = math.max(yTop, bottom + 0.3);
    final mid = n * offset + u * ((s0 + s1) / 2);
    final center = Vector3(mid.x, (bottom + top) / 2, mid.z);
    Vector3 at(double s, double y) {
      final p = n * offset + u * s;
      return Vector3(p.x, y, p.z);
    }

    return PlaneQuad(
      center: center,
      yaw: yaw,
      extentX: s1 - s0,
      extentZ: top - bottom,
      vertical: true,
      kind: PlaneQuadKind.wall,
      polygon: [at(s0, bottom), at(s1, bottom), at(s1, top), at(s0, top)],
    );
  }
}
