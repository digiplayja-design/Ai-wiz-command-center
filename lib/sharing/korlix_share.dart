import 'package:flutter/widgets.dart';

/// A visible popover anchor is required when presenting the iPad share sheet.
/// Export services can use the current view; UI callers can anchor to a widget.
Rect korlixShareOrigin([BuildContext? context]) {
  final activeContext = context?.mounted == true ? context : null;
  final view = activeContext == null
      ? WidgetsBinding.instance.platformDispatcher.implicitView
      : View.maybeOf(activeContext);
  final size = view == null
      ? const Size(2, 2)
      : view.physicalSize / view.devicePixelRatio;
  final bounds = Offset.zero & size;
  final renderObject = activeContext?.findRenderObject();
  if (renderObject is RenderBox && renderObject.hasSize) {
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final visible = rect.intersect(bounds);
    if (visible.isFinite && !visible.isEmpty) return visible;
  }
  // Keep the entire anchor inside the window, including iPad split view.
  if (bounds.isFinite && size.width >= 1 && size.height >= 1) {
    return Rect.fromCenter(center: bounds.center, width: 1, height: 1);
  }
  return const Rect.fromLTWH(0, 0, 1, 1);
}
