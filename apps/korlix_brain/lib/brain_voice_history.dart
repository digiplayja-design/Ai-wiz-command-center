/// Transient context for a Pause/Resume cycle. This is never a memory write and
/// is discarded on Stop, a fresh conversation, or an account change.
class BrainVoiceHistory {
  final _entries = <Map<String, String>>[];
  int? _owner;

  void begin(int accountRevision, {bool fresh = false}) {
    if (fresh || _owner != accountRevision) _entries.clear();
    _owner = accountRevision;
  }

  bool belongsTo(int accountRevision) => _owner == accountRevision;

  void receive(Map<String, dynamic> event) {
    if (event['type'] != 'transcript') return;
    final role = switch (event['role']) {
      'you' => 'user',
      'rici' => 'assistant',
      _ => null,
    };
    final value = event['text'];
    if (role == null || value is! String || value.trim().isEmpty) return;
    var text = value.trim();
    if (text.length > 4000) text = text.substring(0, 4000);
    if (_entries.isNotEmpty && _entries.last['role'] == role &&
        _entries.last['text'] == text) return;
    _entries.add({'role': role, 'text': text});
    while (_entries.length > 16 ||
        _entries.fold<int>(0, (total, entry) => total + entry['text']!.length) > 12000) {
      _entries.removeAt(0);
    }
  }

  List<Map<String, String>> get context =>
      _entries.map((entry) => Map<String, String>.from(entry)).toList();

  void clear() {
    _entries.clear();
    _owner = null;
  }
}

/// Current GA emits item.added/item.done, while prior sessions use item.created.
/// Accept only the exact user text item sent by this connection before unmuting.
bool brainResumeAcknowledged(Map<String, dynamic> event, {
  required String id,
  required String text,
}) {
  if (!const {'conversation.item.added', 'conversation.item.done',
    'conversation.item.created'}.contains(event['type'])) return false;
  final item = event['item'];
  if (item is! Map || item['id'] != id || item['type'] != 'message' ||
      item['role'] != 'user' || item['status'] == 'incomplete') return false;
  final content = item['content'];
  return content is List && content.length == 1 && content.single is Map &&
      (content.single as Map)['type'] == 'input_text' &&
      (content.single as Map)['text'] == text;
}
