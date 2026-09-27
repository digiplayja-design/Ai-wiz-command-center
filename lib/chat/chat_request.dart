bool korlixWantsNewImage(String text) {
  final value = text.trim();
  if (RegExp(
    r'^(?:please\s+|can you\s+|could you\s+)?(?:create|generate|make|design)\s+(?:me\s+)?(?:(?:a|an|the)\s+)?(?:list|plan|guide|tutorial|prompt|description|comparison|app|website)\b',
    caseSensitive: false,
  ).hasMatch(value))
    return false;
  return RegExp(
    r'^(?:please\s+|can you\s+|could you\s+)?(?:create|generate|draw|paint|design|make|imagine)\s+(?:me\s+)?(?:(?:a|an|the|some)\s+)?(?:\w+[ -]){0,4}(?:image|picture|photo|photograph|illustration|poster|logo|artwork|drawing|flyer|portrait)\b',
    caseSensitive: false,
  ).hasMatch(value);
}

/// Keep only selected-topic user/assistant messages, within the server budget.
List<Map<String, String>> korlixChatHistory(
  Iterable<Map<String, String>> messages,
) {
  final result = <Map<String, String>>[];
  var remaining = 96000;
  for (final message in messages.toList().reversed) {
    if (result.length == 16 || remaining == 0) break;
    if (!['user', 'assistant'].contains(message['role'])) continue;
    final text = (message['content'] ?? '').trim();
    if (text.isEmpty) continue;
    final limit = remaining < 12000 ? remaining : 12000;
    final content = text.length > limit ? text.substring(0, limit) : text;
    result.add({'role': message['role']!, 'content': content});
    remaining -= content.length;
  }
  return result.reversed.toList();
}
