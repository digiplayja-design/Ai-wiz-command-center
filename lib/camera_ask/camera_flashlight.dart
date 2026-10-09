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
  bool enabled = false;
  bool changing = false;
  bool _closed = false;

  Future<void> toggle() async {
    if (_closed || !supported || changing) return;
    final next = !enabled;
    changing = true;
    try {
      await apply(next);
      if (_closed) return;
      // Browsers may silently ignore optional constraints. Read the actual
      // setting before claiming that the light was switched on or off.
      if (readEnabled() != next) {
        throw StateError('The camera did not confirm the flashlight setting.');
      }
      enabled = next;
    } finally {
      changing = false;
    }
  }

  void close() {
    _closed = true;
    enabled = false;
    changing = false;
  }
}
