import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../models/chat_session.dart';
import '../../../../../../models/product.dart';
import 'robot_avatar.dart';
import 'robot_chat_panel.dart';

class RobotAssistantHost extends StatefulWidget {
  const RobotAssistantHost({
    super.key,
    required this.child,
    required this.products,
    this.focusProduct,
    this.bottomClearance = 0,
    this.title,
    this.quickQuestions,
    this.robotSize = 56,
    this.edgeMargin = 12,
  });

  final Widget child;

  final List<Product> products;

  final Product? focusProduct;

  final double bottomClearance;

  final String? title;
  final List<String>? quickQuestions;
  final double robotSize;
  final double edgeMargin;

  @override
  State<RobotAssistantHost> createState() => _RobotAssistantHostState();
}

class _RobotAssistantHostState extends State<RobotAssistantHost> {
  Size _bounds = Size.zero;

  // While the page scrolls the robot tucks into its edge (only a sliver
  // shows, faded) so it never sits on top of card buttons mid-browse.
  bool _tucked = false;
  Timer? _untuck;

  @override
  void dispose() {
    _untuck?.cancel();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      _untuck?.cancel();
      if (!_tucked && _live == null) setState(() => _tucked = true);
    } else if (n is ScrollEndNotification) {
      _untuck?.cancel();
      _untuck = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _tucked) setState(() => _tucked = false);
      });
    }
    return false;
  }

  bool get _onLeftEdge => _posNow.dx + widget.robotSize / 2 < _bounds.width / 2;

  Offset? _pos;

  Offset? _live;

  final List<ChatMessage> _messages = [];

  Offset get _defaultPos => Offset(
        _bounds.width - widget.robotSize - widget.edgeMargin,
        _bounds.height -
            widget.bottomClearance -
            widget.robotSize -
            widget.edgeMargin * 2,
      );

  Offset get _posNow => _live ?? _pos ?? _defaultPos;

  double _clampAxis(double v, double min, double max) =>
      max <= min ? min : v.clamp(min, max).toDouble();

  Offset _clamp(Offset p) => Offset(
        _clampAxis(p.dx, widget.edgeMargin,
            _bounds.width - widget.robotSize - widget.edgeMargin),
        _clampAxis(
            p.dy,
            widget.edgeMargin,
            _bounds.height -
                widget.bottomClearance -
                widget.robotSize -
                widget.edgeMargin),
      );

  void _onPanStart(DragStartDetails _) {
    _untuck?.cancel();
    setState(() {
      _tucked = false;
      _live = _posNow;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _live = _clamp(_posNow + details.delta));
  }

  // Released anywhere, the robot snaps to the nearer side edge.
  void _commitDrag() {
    if (_live == null) return;
    setState(() {
      final p = _clamp(_posNow);
      final left = p.dx + widget.robotSize / 2 < _bounds.width / 2;
      _pos = Offset(
          left
              ? widget.edgeMargin
              : _bounds.width - widget.robotSize - widget.edgeMargin,
          p.dy);
      _live = null;
    });
  }

  Future<void> _openChat() async {
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RobotSheetFrame(
        child: RobotChatPanel(
          title: widget.title ??
              (widget.focusProduct != null
                  ? 'Ask about this product'
                  : 'Shopping assistant'),
          focusProduct: widget.focusProduct,
          products: widget.products,
          quickQuestions: widget.quickQuestions ??
              (widget.focusProduct != null
                  ? kProductDetailQuickQuestions
                  : kMarketplaceQuickQuestions),
          messages: _messages,
          onMessagesChanged: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _bounds = constraints.biggest;
      final p = _clamp(_posNow);
      final dragging = _live != null;
      // At rest only a sliver of the robot shows at the screen edge (a tab),
      // so it never covers card buttons; scrolling hides even more of it.
      final hidden = widget.robotSize * (_tucked ? 0.8 : 0.62);
      final x = dragging
          ? p.dx
          : _onLeftEdge
              ? -hidden
              : _bounds.width - widget.robotSize + hidden;
      return Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
          AnimatedPositioned(
            duration: dragging
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: x,
            top: p.dy,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _tucked ? 0.55 : 1,
              child: RepaintBoundary(
              child: GestureDetector(
                key: const ValueKey('robot-assistant'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openChat(),
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: (_) => _commitDrag(),
                onPanCancel: _commitDrag,
                child: Semantics(
                  button: true,
                  label: 'Shopping assistant, ask about products',
                  child: Tooltip(
                    message: 'Ask about products',
                    child: RobotAvatar(size: widget.robotSize),
                  ),
                ),
              ),
            ),
            ),
          ),
        ],
      );
    });
  }
}

class _RobotSheetFrame extends StatelessWidget {
  const _RobotSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final available =
        (mq.size.height - keyboard - 24).clamp(280.0, mq.size.height);
    final height = math.min(mq.size.height * 0.7, available);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(height: height, child: child),
    );
  }
}
