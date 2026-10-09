/// Flashlight state for one camera track. The capture screen owns and stops the
/// track; closing this session prevents late changes from affecting a new one.
class CameraFlashlight {
  CameraFlashlight({
    required Object? capability,
    required this.apply,
    required this.readEnabled,
  }) : supported =
           capability == true ||
           (capability is Iterable &&
               capability.contains(true) &&
               capability.contains(false));

  final bool supported;
  final Future<void> Function(bool) apply;
  final bool? Function() readEnabled;
  // The last accepted command determines the next on/off action. A browser's
  // reported setting may lag behind the physical light or be unavailable.
  bool enabled = false;
  bool? reportedEnabled;
  bool changing = false;
  bool _closed = false;

  Future<void> toggle() async {
    if (_closed || !supported || changing) return;
    final next = !enabled;
    changing = true;
    try {
      await apply(next);
      if (_closed) return;
      enabled = next;
      try {
        reportedEnabled = readEnabled();
      } catch (_) {
        reportedEnabled = null;
      }
    } finally {
      changing = false;
    }
  }

  void close() {
    _closed = true;
    enabled = false;
    reportedEnabled = null;
    changing = false;
  }
}
