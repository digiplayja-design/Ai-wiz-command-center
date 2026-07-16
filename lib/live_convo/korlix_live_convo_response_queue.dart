class KorlixLiveConvoResponseRequest {
  const KorlixLiveConvoResponseRequest({
    required this.source,
    required this.dedupeKey,
    this.instructions,
  });

  final String source;
  final String dedupeKey;
  final String? instructions;
}

class KorlixLiveConvoResponseQueue {
  bool _busy = false;

  final List<KorlixLiveConvoResponseRequest> _pending =
      <KorlixLiveConvoResponseRequest>[];

  KorlixLiveConvoResponseRequest? _lastDispatched;

  bool get busy => _busy;

  int get pendingCount => _pending.length;

  KorlixLiveConvoResponseRequest? get lastDispatched => _lastDispatched;

  List<KorlixLiveConvoResponseRequest> get pendingRequests {
    return List<KorlixLiveConvoResponseRequest>.unmodifiable(_pending);
  }

  void markBusy() {
    _busy = true;
  }

  void markDispatched(KorlixLiveConvoResponseRequest request) {
    _lastDispatched = request;
    _busy = true;
  }

  void markResponseDone() {
    _busy = false;
    _lastDispatched = null;
  }

  bool enqueue(KorlixLiveConvoResponseRequest request) {
    final key = request.dedupeKey.trim();

    if (key.isNotEmpty) {
      if (_lastDispatched?.dedupeKey == key) {
        return false;
      }

      final alreadyPending = _pending.any(
        (pending) => pending.dedupeKey == key,
      );

      if (alreadyPending) {
        return false;
      }
    }

    _pending.add(request);

    return true;
  }

  void requeueFront(KorlixLiveConvoResponseRequest request) {
    final key = request.dedupeKey.trim();

    if (key.isNotEmpty) {
      _pending.removeWhere((pending) => pending.dedupeKey == key);
    }

    _pending.insert(0, request);
  }

  bool requeueLastDispatched() {
    final request = _lastDispatched;

    if (request == null) {
      return false;
    }

    requeueFront(request);
    _lastDispatched = null;
    _busy = true;

    return true;
  }

  KorlixLiveConvoResponseRequest? takeNextIfIdle() {
    if (_busy || _pending.isEmpty) {
      return null;
    }

    return _pending.removeAt(0);
  }

  void reset() {
    _busy = false;
    _pending.clear();
    _lastDispatched = null;
  }
}

bool korlixLiveConvoIsActiveResponseError(String message) {
  final normalized = message.trim().toLowerCase();

  return normalized.contains('active response in progress') ||
      normalized.contains('wait until the response is finished');
}
