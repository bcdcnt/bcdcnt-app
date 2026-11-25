import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Lets the empty space beside a width-capped column scroll that column.
///
/// On wide desktop windows a feed is held to a readable width, so the rest
/// of the row is blank and a wheel or trackpad there did nothing (góp ý
/// 24/11). This fills the whole area it is given, and a scroll over the
/// blank part is handed to the first vertical list inside [child]; over the
/// child itself the list scrolls as usual.
class GapScroll extends StatefulWidget {
  const GapScroll({super.key, required this.child, this.maxWidth, this.alignment = Alignment.topLeft, this.target, this.skip});
  final Widget child;
  final double? maxWidth;
  final AlignmentGeometry alignment;

  /// Whole-layout mode: [child] is the full layout (fills the area as is)
  /// and [target] marks the column whose list the rest of the area scrolls.
  final GlobalKey? target;

  /// Points that should keep their own scrolling (e.g. a side column that
  /// is taller than the window). Wheel events there already go to the inner
  /// list when it can move; this is for trackpad swipes.
  final bool Function(Offset global)? skip;

  @override
  State<GapScroll> createState() => _GapScrollState();
}

class _GapScrollState extends State<GapScroll> {
  final _ownKey = GlobalKey();
  GlobalKey get _childKey => widget.target ?? _ownKey;
  VelocityTracker? _tracker;
  ScrollPosition? _pan; // the list a trackpad swipe in the gap is moving

  bool _overChild(Offset global) {
    final box = _childKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  ScrollPosition? _findList() {
    ScrollPosition? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        if (s.position.axis == Axis.vertical) { found = s.position; return; }
      }
      e.visitChildren(visit);
    }
    final ctx = _childKey.currentContext;
    if (ctx is Element) ctx.visitChildren(visit);
    return found;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _overChild(e.position)) return;
    final pos = _findList();
    if (pos == null) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      pos.pointerScroll((ev as PointerScrollEvent).scrollDelta.dy);
    });
  }

  void _onPanStart(PointerPanZoomStartEvent e) {
    if (_overChild(e.position) || (widget.skip?.call(e.position) ?? false)) return;
    _pan = _findList();
    if (_pan == null) return;
    if (_pan is ScrollPositionWithSingleContext) (_pan as ScrollPositionWithSingleContext).goIdle();
    _tracker = VelocityTracker.withKind(PointerDeviceKind.trackpad)..addPosition(e.timeStamp, Offset.zero);
  }

  void _onPanUpdate(PointerPanZoomUpdateEvent e) {
    final pos = _pan;
    if (pos == null) return;
    _tracker?.addPosition(e.timeStamp, e.pan);
    pos.pointerScroll(-e.panDelta.dy);
  }

  void _onPanEnd(PointerPanZoomEndEvent e) {
    final pos = _pan;
    _pan = null;
    if (pos is ScrollPositionWithSingleContext && _tracker != null) {
      pos.goBallistic(-_tracker!.getVelocity().pixelsPerSecond.dy);
    }
    _tracker = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.target != null) return _listen(widget.child);
    Widget child = KeyedSubtree(key: _ownKey, child: widget.child);
    if (widget.maxWidth != null) child = ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.maxWidth!), child: child);
    return _listen(SizedBox.expand(child: Align(alignment: widget.alignment, child: child)));
  }

  // Wheel events: an inner list that can move registers first (deepest in
  // the hit path), so this only takes the ones nothing else used.
  Widget _listen(Widget child) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onSignal,
      onPointerPanZoomStart: _onPanStart,
      onPointerPanZoomUpdate: _onPanUpdate,
      onPointerPanZoomEnd: _onPanEnd,
      child: child,
    );
  }
}
