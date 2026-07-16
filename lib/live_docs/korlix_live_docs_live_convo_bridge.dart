/// One finalized user turn captured from LIVE CONVO.
class KorlixLiveDocsCapturedTurn {
  const KorlixLiveDocsCapturedTurn({
    required this.text,
    required this.source,
    required this.timestamp,
    this.eventId,
  });

  final String text;
  final String source;
  final DateTime timestamp;
  final String? eventId;
}

/// Local-only collector used while a user discusses a document in LIVE CONVO.
///
/// This class does not call a backend, upload files, or start a document job.
class KorlixLiveDocsConversationBridge {
  bool _captureActive = false;

  final List<KorlixLiveDocsCapturedTurn> _capturedTurns =
      <KorlixLiveDocsCapturedTurn>[];

  final Set<String> _capturedEventIds = <String>{};

  bool get captureActive => _captureActive;

  bool get hasCapturedTurns => _capturedTurns.isNotEmpty;

  int get capturedTurnCount => _capturedTurns.length;

  List<KorlixLiveDocsCapturedTurn> get capturedTurns {
    return List<KorlixLiveDocsCapturedTurn>.unmodifiable(_capturedTurns);
  }

  void startCapture({bool clearExisting = false}) {
    if (clearExisting) {
      clearCapturedTurns();
    }

    _captureActive = true;
  }

  void stopCapture() {
    _captureActive = false;
  }

  void clearCapturedTurns() {
    _capturedTurns.clear();
    _capturedEventIds.clear();
  }

  bool captureUserTurn(
    String rawText, {
    required String source,
    String? eventId,
    DateTime? timestamp,
  }) {
    if (!_captureActive) {
      return false;
    }

    final text = rawText.trim();

    if (text.isEmpty) {
      return false;
    }

    final cleanSource = source.trim().isEmpty ? 'voice' : source.trim();
    final cleanEventId = eventId?.trim() ?? '';

    if (cleanEventId.isNotEmpty && !_capturedEventIds.add(cleanEventId)) {
      return false;
    }

    _capturedTurns.add(
      KorlixLiveDocsCapturedTurn(
        text: text,
        source: cleanSource,
        timestamp: (timestamp ?? DateTime.now()).toUtc(),
        eventId: cleanEventId.isEmpty ? null : cleanEventId,
      ),
    );

    return true;
  }

  String get combinedInstructions {
    final buffer = StringBuffer();

    for (var index = 0; index < _capturedTurns.length; index += 1) {
      final turn = _capturedTurns[index];

      if (index > 0) {
        buffer.writeln();
      }

      buffer.write('${index + 1}. [${turn.source}] ${turn.text}');
    }

    return buffer.toString();
  }

  String get suggestedTitle {
    if (_capturedTurns.isEmpty) {
      return '';
    }

    var text = _capturedTurns.first.text
        .replaceFirst(
          RegExp(r'^(camera|keyboard|voice)\s*:\s*', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final sentenceEnd = text.indexOf(RegExp(r'[.!?]'));

    if (sentenceEnd >= 12) {
      text = text.substring(0, sentenceEnd);
    }

    return _truncate(text, 72);
  }

  String get suggestedGoal {
    return _truncate(combinedInstructions, 4000);
  }

  static String _truncate(String value, int maximumLength) {
    final text = value.trim();

    if (text.length <= maximumLength) {
      return text;
    }

    return '${text.substring(0, maximumLength - 1).trimRight()}…';
  }
}
