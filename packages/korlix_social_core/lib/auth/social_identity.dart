import 'dart:convert';
import 'dart:math';

String agentStudioKey() {
  final r = Random.secure(), b = List.generate(16, (_) => 0);
  for (var i = 0; i < 16; i++) {
    b[i] = r.nextInt(256);
  }
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

String agentAccountScope(Map<String, String> headers) {
  final token =
      headers.entries
          .where((h) => h.key.toLowerCase() == 'authorization')
          .map((h) => h.value)
          .firstOrNull ??
      '';
  try {
    final p = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(token.split(' ').last.split('.')[1]),
        ),
      ),
    );
    if (p['sub'] is String && p['session_id'] is String && p['iss'] is String) {
      return jsonEncode([p['iss'], p['sub'], p['session_id']]);
    }
  } catch (_) {}
  return token;
}
