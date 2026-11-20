import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../data/furniture_model_library.dart';
import '../../data/placement_reticle.dart';

// AR focus target. Searching: four corner brackets breathe around a small
// dot. Ready: the brackets close into one solid ring with a "+" — tap to
// place — tinted like the zone it sits on (green floor, blue wall), with a
// soft landing shadow on the floor. Warnings wear amber with a "!".
class PlacementReticle extends StatefulWidget {
  const PlacementReticle({
    super.key,
    required this.state,
    required this.label,
    required this.intent,
  });

  final ReticleState state;

  final String label;

  final PlacementType intent;

  @override
  State<PlacementReticle> createState() => _PlacementReticleState();
}

class _PlacementReticleState extends State<PlacementReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final locked = state.status == ReticleStatus.locked;
    final distWarn = state.status == ReticleStatus.tooFar ||
        state.status == ReticleStatus.tooClose;
    final warn = distWarn || state.status == ReticleStatus.tooSmall;
    // Grows gently with distance so it stays legible on the floor without
    // ballooning up close (1.0 at 0.7 m, +0.25 per extra metre).
    final d = state.distanceM;
    var size = 52.0;
    if (d != null) {
      final factor = d < 0.7 ? d / 0.7 : 0.25 * d + 0.825;
      size = (52 * factor).clamp(40.0, 72.0);
    }
    final color = locked
        ? (widget.intent == PlacementType.wall
            ? const Color(0xFF2196F3)
            : AppColors.accentLight)
        : warn
            ? AppColors.warning
            : Colors.white;
    final mode = locked
        ? _Mode.locked
        : warn
            ? _Mode.warn
            : _Mode.search;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          key: const Key('placement-reticle'),
          tween: Tween(end: locked ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (_, lock, __) => AnimatedBuilder(
            animation: _breath,
            builder: (_, __) => CustomPaint(
              size: Size.square(size + 16),
              painter: _ReticlePainter(
                lock: lock.clamp(0.0, 1.2),
                breath: locked ? 0 : _breath.value,
                color: color,
                mode: mode,
                floor: widget.intent != PlacementType.wall,
              ),
            ),
          ),
        ),
        if (widget.label.isNotEmpty) ...[
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: locked
                  ? color.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: locked ? FontWeight.w600 : FontWeight.w400,
                color: locked
                    ? Colors.white
                    : warn
                        ? AppColors.warning
                        : Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _Mode { search, locked, warn }

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({
    required this.lock,
    required this.breath,
    required this.color,
    required this.mode,
    required this.floor,
  });

  final double lock;
  final double breath;
  final Color color;
  final _Mode mode;
  final bool floor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width / 2 - 8;
    final l = lock.clamp(0.0, 1.0);
    // Brackets sit wide and breathe while searching, close in when locked.
    final r = base * (1.0 + 0.08 * breath) * (1 - 0.18 * l);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 + 0.6 * l
      ..strokeCap = StrokeCap.round;

    if (floor && l > 0) {
      // Landing shadow: a flattened ellipse reads as "on the floor".
      canvas.drawOval(
          Rect.fromCenter(
              center: c.translate(0, r * 0.95),
              width: r * 1.6 * l,
              height: r * 0.38 * l),
          Paint()..color = Colors.black.withValues(alpha: 0.22 * l));
    }

    // Corner brackets: arcs of the ring that grow into a full circle as the
    // target locks (gap shrinks to zero).
    final gap = (math.pi / 2) * 0.55 * (1 - l);
    final sweep = math.pi / 2 - gap;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < 4; i++) {
      final start = -math.pi * 3 / 4 + i * math.pi / 2 - sweep / 2;
      canvas.drawArc(rect, start, sweep, false, shadow);
      canvas.drawArc(rect, start, sweep, false, stroke);
    }

    if (l > 0) {
      canvas.drawCircle(
          c, r - 2, Paint()..color = color.withValues(alpha: 0.22 * l));
      // "+" = tap to place here.
      final arm = r * 0.34 * l;
      final plus = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c.translate(-arm, 0), c.translate(arm, 0), plus);
      canvas.drawLine(c.translate(0, -arm), c.translate(0, arm), plus);
    } else if (mode == _Mode.warn) {
      final p = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c.translate(0, -r * 0.32), c.translate(0, r * 0.08), p);
      canvas.drawCircle(c.translate(0, r * 0.3), 2.2, Paint()..color = color);
    } else {
      canvas.drawCircle(c, 3.4, Paint()..color = Colors.black38);
      canvas.drawCircle(c, 2.6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.lock != lock ||
      old.breath != breath ||
      old.color != color ||
      old.mode != mode ||
      old.floor != floor;
}
