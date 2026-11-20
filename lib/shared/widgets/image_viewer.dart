import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'product_image.dart';

// Full-screen photo viewer: pinch or double-tap to zoom, drag to look
// around, swipe between photos, swipe down or tap X to close. Returns the
// index the user ended on so the gallery behind can follow.
Future<int?> showImageViewer(
  BuildContext context, {
  required List<String> images,
  int initialIndex = 0,
  String? heroTag,
}) {
  return Navigator.of(context, rootNavigator: true).push<int>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => ImageViewer(
        images: images,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.heroTag,
  });

  final List<String> images;
  final int initialIndex;
  final String? heroTag;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final Map<int, TransformationController> _zoom = {};
  bool _zoomed = false;
  double _dragDy = 0;
  TapDownDetails? _doubleTapAt;

  TransformationController _controllerFor(int i) =>
      _zoom.putIfAbsent(i, () {
        final c = TransformationController();
        c.addListener(() {
          if (i != _index) return;
          final z = c.value.getMaxScaleOnAxis() > 1.01;
          if (z != _zoomed) setState(() => _zoomed = z);
        });
        return c;
      });

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_index);

  void _toggleZoom(int i) {
    final c = _controllerFor(i);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      c.value = Matrix4.identity();
      return;
    }
    final p = _doubleTapAt?.localPosition ?? Offset.zero;
    const s = 2.5;
    c.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.images.length;
    final fade = (1 - (_dragDy.abs() / 400)).clamp(0.4, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: Stack(
        children: [
          GestureDetector(
            // Swipe down to close — only when not zoomed, so panning a
            // zoomed photo never dismisses it.
            onVerticalDragUpdate:
                _zoomed ? null : (d) => setState(() => _dragDy += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (d) {
                    if (_dragDy.abs() > 120 ||
                        (d.primaryVelocity ?? 0).abs() > 900) {
                      _close();
                    } else {
                      setState(() => _dragDy = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragDy),
              child: PageView.builder(
                key: const Key('image-viewer-pages'),
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: n,
                onPageChanged: (i) {
                  _zoom[_index]?.value = Matrix4.identity();
                  setState(() {
                    _index = i;
                    _zoomed = false;
                  });
                },
                itemBuilder: (_, i) {
                  Widget img = ProductImage(
                    imageUrl: widget.images[i],
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorIconSize: 64,
                  );
                  if (widget.heroTag != null && i == widget.initialIndex) {
                    img = Hero(tag: widget.heroTag!, child: img);
                  }
                  return GestureDetector(
                    onDoubleTapDown: (d) => _doubleTapAt = d,
                    onDoubleTap: () => _toggleZoom(i),
                    child: InteractiveViewer(
                      transformationController: _controllerFor(i),
                      minScale: 1,
                      maxScale: 4,
                      child: Center(child: img),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('image-viewer-close'),
                    tooltip: 'Close',
                    onPressed: _close,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const Spacer(),
                  if (n > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('${_index + 1} / $n',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (!_zoomed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                child: Center(
                  child: Text('Pinch or double-tap to zoom',
                      style: GoogleFonts.poppins(
                          color: Colors.white60, fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
