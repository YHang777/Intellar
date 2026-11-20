import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ArGuideStep { floor, walls, done }

// First-visit AR guide: a small animated scene shows WHAT to do (sweep the
// floor, then aim up at the walls) instead of a wall of text, a ring around
// the aim point fills with progress, and each finished step pops a check.
class ArFirstRunGuide extends StatefulWidget {
  const ArFirstRunGuide({
    super.key,
    required this.step,
    required this.progress,
    required this.onSkip,
  });

  final ArGuideStep step;

  final double progress;

  final VoidCallback onSkip;

  @override
  State<ArFirstRunGuide> createState() => _ArFirstRunGuideState();
}

class _ArFirstRunGuideState extends State<ArFirstRunGuide>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant ArFirstRunGuide old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) _burst.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _burst.dispose();
    super.dispose();
  }

  String get _caption => switch (widget.step) {
        ArGuideStep.floor => 'Sweep the floor slowly',
        ArGuideStep.walls => 'Now aim up at the walls',
        ArGuideStep.done => 'You’re all set',
      };

  String get _sub => switch (widget.step) {
        ArGuideStep.floor => 'Green appears where the floor is found',
        ArGuideStep.walls => 'A ✓ on an area means done — move on',
        ArGuideStep.done => 'Tap the green floor to place furniture',
      };

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Progress ring around the aim point.
        if (widget.step != ArGuideStep.done)
          Center(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.progress.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 400),
                builder: (_, p, __) => CustomPaint(
                  key: const Key('ar-guide-ring'),
                  size: const Size.square(104),
                  painter: _RingPainter(p,
                      widget.step == ArGuideStep.walls
                          ? const Color(0xFF42A5F5)
                          : const Color(0xFF4CAF50)),
                ),
              ),
            ),
          ),
        // Check burst when a step completes.
        Center(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (_, __) {
                final t = _burst.value;
                if (t == 0 || t == 1) return const SizedBox.shrink();
                final scale = Curves.elasticOut.transform(math.min(1, t * 1.6));
                final fade = t < 0.7 ? 1.0 : (1 - t) / 0.3;
                return Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.6 + 0.6 * scale,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 54),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // The animated scene card, under the top bar.
        Positioned(
          top: 64,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              key: const Key('ar-guide-card'),
              width: 236,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 150,
                    height: 92,
                    child: AnimatedBuilder(
                      animation: _loop,
                      builder: (_, __) => CustomPaint(
                        painter: _ScenePainter(widget.step, _loop.value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(widget.step),
                      children: [
                        Text(_caption,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(_sub,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Dot(active: true, done: widget.step != ArGuideStep.floor),
                      const SizedBox(width: 6),
                      _Dot(
                          active: widget.step != ArGuideStep.floor,
                          done: widget.step == ArGuideStep.done),
                      const Spacer(),
                      if (widget.step != ArGuideStep.done)
                        GestureDetector(
                          key: const Key('ar-guide-skip'),
                          onTap: widget.onSkip,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Text('Skip',
                                style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.done});

  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: active ? 18 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: done
            ? const Color(0xFF4CAF50)
            : active
                ? Colors.white
                : Colors.white38,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawArc(
        r,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.white24);
    if (progress <= 0) return;
    canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// Floor step: a phone sweeps over a perspective floor and the floor turns
// green behind it. Wall step: the phone tilts up and sweeps a hatched wall
// while chevrons point upward. Done: everything green with ticks.
class _ScenePainter extends CustomPainter {
  _ScenePainter(this.step, this.t);

  final ArGuideStep step;
  final double t;

  static const _green = Color(0xFF4CAF50);
  static const _blue = Color(0xFF42A5F5);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final floorTop = h * 0.58;
    final floor = Path()
      ..moveTo(w * 0.22, floorTop)
      ..lineTo(w * 0.78, floorTop)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final wall = Rect.fromLTWH(w * 0.22, h * 0.06, w * 0.56, floorTop - h * 0.06);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white38;

    final sweep = (math.sin(t * math.pi * 2) + 1) / 2; // 0..1..0
    if (step == ArGuideStep.floor) {
      // Green grows across the floor with the sweep.
      canvas.save();
      canvas.clipPath(floor);
      canvas.drawRect(Rect.fromLTWH(0, floorTop, w * (0.15 + 0.85 * t), h),
          Paint()..color = _green.withValues(alpha: 0.55));
      canvas.restore();
    } else {
      canvas.drawPath(floor, Paint()..color = _green.withValues(alpha: 0.55));
      _tick(canvas, Offset(w * 0.5, h * 0.82), 7);
    }
    canvas.drawPath(floor, line);
    for (var i = 1; i < 4; i++) {
      final y = floorTop + (h - floorTop) * i / 4;
      final inset = w * 0.22 * (1 - i / 4);
      canvas.drawLine(Offset(inset, y), Offset(w - inset, y), line);
    }

    if (step == ArGuideStep.floor) {
      canvas.drawRect(wall, line..color = Colors.white24);
      final x = w * (0.2 + 0.6 * sweep);
      _phone(canvas, Offset(x, h * 0.36), tilt: 0.9);
      _beam(canvas, Offset(x, h * 0.42), Offset(x, h * 0.86), w * 0.16);
    } else {
      final fill = step == ArGuideStep.done ? 1.0 : (0.2 + 0.8 * t);
      canvas.drawRect(
          Rect.fromLTWH(wall.left, wall.bottom - wall.height * fill, wall.width,
              wall.height * fill),
          Paint()..color = _blue.withValues(alpha: 0.45));
      canvas.save();
      canvas.clipRect(wall);
      final hatch = Paint()
        ..color = _blue.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = wall.left - wall.height; x < wall.right; x += 9) {
        canvas.drawLine(Offset(x, wall.bottom),
            Offset(x + wall.height, wall.top), hatch);
      }
      canvas.restore();
      canvas.drawRect(wall, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _blue);
      if (step == ArGuideStep.walls) {
        final y = h * (0.62 - 0.3 * sweep);
        _phone(canvas, Offset(w * 0.86, y), tilt: 0);
        _beam(canvas, Offset(w * 0.8, y), Offset(w * 0.6, y), w * 0.12,
            horizontal: true);
        // Chevrons drifting up.
        for (var i = 0; i < 2; i++) {
          final cy = h * (0.5 - 0.35 * ((t + i * 0.5) % 1));
          final a = 1 - ((t + i * 0.5) % 1);
          final p = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: a);
          canvas.drawPath(
              Path()
                ..moveTo(w * 0.08, cy + 6)
                ..lineTo(w * 0.14, cy)
                ..lineTo(w * 0.2, cy + 6),
              p);
        }
      } else {
        _tick(canvas, wall.center, 9);
      }
    }
  }

  void _phone(Canvas canvas, Offset c, {required double tilt}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, 1 - 0.45 * tilt);
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 18, height: 30),
        const Radius.circular(4));
    canvas.drawRRect(body, Paint()..color = Colors.white);
    canvas.drawRRect(
        body.deflate(2.5), Paint()..color = const Color(0xFF263238));
    canvas.restore();
  }

  void _beam(Canvas canvas, Offset from, Offset to, double spread,
      {bool horizontal = false}) {
    final path = Path()..moveTo(from.dx, from.dy);
    if (horizontal) {
      path
        ..lineTo(to.dx, to.dy - spread / 2)
        ..lineTo(to.dx, to.dy + spread / 2);
    } else {
      path
        ..lineTo(to.dx - spread / 2, to.dy)
        ..lineTo(to.dx + spread / 2, to.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.18));
  }

  void _tick(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = _green);
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.45, c.dy)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
          ..lineTo(c.dx + r * 0.5, c.dy - r * 0.35),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.t != t || old.step != step;
}
