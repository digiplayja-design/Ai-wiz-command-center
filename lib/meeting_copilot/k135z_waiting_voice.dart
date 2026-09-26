import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'k135z_capture_controller.dart';

class K135zWaitingClip {
  const K135zWaitingClip(this.text, this.audio);
  final String text;
  final Uint8List audio;
}

// Prepared in the background after opt-in. Failure only removes waiting speech;
// it must never delay enabling Nova or requesting her actual answer.
Future<List<K135zWaitingClip>> loadK135zWaitingVoice(K135zCaptureController capture) async {
  final binding = capture.responseBinding;
  if (binding == null) return const [];
  final context = Map<String, dynamic>.from(binding['context']);
  final headers = Map<String, String>.from(capture.headers());
  headers.removeWhere((k, _) => ['content-type', 'x-korlix-agent-id'].contains(k.toLowerCase()));
  headers['content-type'] = 'application/json';
  headers['x-korlix-agent-id'] = capture.agentId;
  final response = await capture.transport(method:'POST',
    uri:capture.baseUri.resolve('/api/k135z/zoom/workspace/waiting-voice'),
    headers:headers, body:{'context':context, 'enabled':true})
    .timeout(const Duration(seconds:35));
  if (response.statusCode != 200 || utf8.encode(response.body).length > 350000) return const [];
  final decoded = jsonDecode(response.body);
  final voice = decoded is Map && decoded['ok'] == true ? decoded['waitingVoice'] : null;
  if (voice is! Map || voice['context'] is! Map || !mapEquals(voice['context'], context) ||
      voice['clips'] is! List || (voice['clips'] as List).length != 2) return const [];
  final clips = <K135zWaitingClip>[];
  for (final clip in voice['clips']) {
    if (clip is! Map || clip['text'] is! String || (clip['text'] as String).trim().isEmpty ||
        (clip['text'] as String).length > 120 || clip['mimeType'] != 'audio/mpeg' || clip['audio'] is! String) return const [];
    final audio = base64Decode(clip['audio']);
    if (audio.length < 64 || audio.length > 120000 ||
        !((audio[0] == 73 && audio[1] == 68 && audio[2] == 51) ||
          (audio[0] == 255 && (audio[1] & 224) == 224))) return const [];
    clips.add(K135zWaitingClip(clip['text'], audio));
  }
  return clips;
}
