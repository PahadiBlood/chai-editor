import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Cross-fade the painted outgoing document, never a second live editor tree.
/// Re-entering a cached document cannot duplicate its node GlobalKeys this way.
class DocumentSwitcher extends StatefulWidget {
  const DocumentSwitcher(
      {super.key, required this.identity, required this.child});
  final Object identity;
  final Widget child;
  @override
  State<DocumentSwitcher> createState() => _DocumentSwitcherState();
}

class _DocumentSwitcherState extends State<DocumentSwitcher> {
  final _boundary = GlobalKey();
  ui.Image? _previous;
  Animation<double>? _incoming;

  @override
  void didUpdateWidget(DocumentSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity == widget.identity) return;
    final retired = _previous;
    _previous = null;
    final render = _boundary.currentContext?.findRenderObject();
    if (render is RenderRepaintBoundary &&
        render.hasSize &&
        !render.debugNeedsPaint) {
      try {
        // Texture-backed snapshot handle; no await or file IO on note switching.
        _previous = render.toImageSync(
            pixelRatio: MediaQuery.devicePixelRatioOf(context));
      } catch (_) {
        // A document without a painted frame still appears without a blank frame.
      }
    }
    if (retired != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => retired.dispose());
    }
  }

  @override
  void dispose() {
    _previous?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        transitionBuilder: (child, animation) {
          if (child.key == ValueKey(widget.identity)) _incoming = animation;
          return FadeTransition(
              opacity: _previous == null
                  ? Tween<double>(begin: .85, end: 1).animate(animation)
                  : animation,
              child: child);
        },
        layoutBuilder: (current, outgoing) =>
            Stack(fit: StackFit.expand, children: [
          if (_previous != null && _incoming != null)
            IgnorePointer(
                child: FadeTransition(
                    opacity: ReverseAnimation(_incoming!),
                    child: RawImage(image: _previous, fit: BoxFit.fill))),
          if (current != null) current,
        ]),
        // Only this live subtree is laid out; outgoing entries are raster snapshots.
        child: SizedBox.expand(
            key: ValueKey(widget.identity),
            child: RepaintBoundary(key: _boundary, child: widget.child)),
      );
}
