import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Makes horizontal shelves usable with touch, mouse/trackpad, desktop wheels
/// and TV/keyboard controls.
class HorizontalScroller extends StatefulWidget {
  const HorizontalScroller({
    super.key,
    required this.builder,
    this.showControls = false,
    this.scrollStep = 520,
  });

  final Widget Function(ScrollController controller) builder;
  final bool showControls;
  final double scrollStep;

  @override
  State<HorizontalScroller> createState() => _HorizontalScrollerState();
}

class _HorizontalScrollerState extends State<HorizontalScroller> {
  final ScrollController _controller = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncControls);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControls());
  }

  @override
  void didUpdateWidget(covariant HorizontalScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControls());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncControls)
      ..dispose();
    super.dispose();
  }

  void _syncControls() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final back = position.pixels > position.minScrollExtent + 1;
    final forward = position.pixels < position.maxScrollExtent - 1;
    if (back == _canScrollBack && forward == _canScrollForward) return;
    setState(() {
      _canScrollBack = back;
      _canScrollForward = forward;
    });
  }

  Future<void> _scrollBy(double delta) async {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (_controller.offset + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent || !_controller.hasClients) return;

    // A normal desktop mouse wheel reports vertical delta even when the
    // content is horizontal. Translate it so shelves do not feel stuck.
    if (signal.scrollDelta.dx.abs() < 0.5 && signal.scrollDelta.dy != 0) {
      final position = _controller.position;
      final target = (_controller.offset + signal.scrollDelta.dy)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = Listener(
      onPointerSignal: _handlePointerSignal,
      child: widget.builder(_controller),
    );

    if (!widget.showControls) return list;

    return Stack(
      fit: StackFit.expand,
      children: [
        list,
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton.filledTonal(
              tooltip: 'Scroll left',
              onPressed:
                  _canScrollBack ? () => _scrollBy(-widget.scrollStep) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton.filledTonal(
              tooltip: 'Scroll right',
              onPressed: _canScrollForward
                  ? () => _scrollBy(widget.scrollStep)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ),
      ],
    );
  }
}
