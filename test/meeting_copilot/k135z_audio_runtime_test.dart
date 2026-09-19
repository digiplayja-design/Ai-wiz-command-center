import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;

void main() {
  test('production transport delivers audio levels and retains request guards', () async {
    final fixture = CaptureFixture();
    final requests = <http.Request>[];
    await http.runWithClient(() async {
      final binding = K135zZoomRuntimeBinding(launch: K135zZoomLaunch(
        agentId: 'agent', backendBaseUri: Uri.parse('https://api.example.test'),
        headersBuilder: () => {'authorization': 'Bearer offline'}, isCurrent: () => true));
      try {
        await binding.capture.refreshAudio();
        expect(requests, isEmpty);
        await binding.capture.selectMeeting('meeting');
        await binding.capture.setConsent(true);
        await binding.capture.start();
        expect(binding.capture.statusLabel, 'Listening');
        await binding.capture.refreshAudio();
        expect(requests.last.url.path, '/api/k135z/zoom/workspace/audio-level');
        expect(binding.capture.audioLevel, .65);
        expect(binding.capture.audioReceived, isTrue);
        await binding.capture.refreshTranscript();
        expect(binding.capture.transcriptLines.single.text, 'Meeting caption');

        final count = requests.length;
        for (final url in [
          'https://other.example.test/api/k135z/zoom/workspace/audio-level',
          'https://api.example.test/api/k135z/zoom/workspace/unrecognized',
        ]) {
          await expectLater(binding.capture.transport(method: 'POST', uri: Uri.parse(url),
            headers: {'authorization': 'Bearer offline'}, body: <String,dynamic>{}),
            throwsStateError);
        }
        expect(requests.length, count);
        await binding.capture.pause();
        expect(binding.capture.audioLevel, 0);
        final pausedCount = requests.length;
        await binding.capture.refreshAudio();
        expect(requests.length, pausedCount);
      } finally { binding.dispose(); }
    }, () => MockClient((request) async {
      requests.add(request);
      final response = await fixture.c.transport(method: request.method, uri: request.url,
        headers: request.headers, body: jsonDecode(request.body));
      return http.Response(response.body, response.statusCode,
        headers: {'content-type': 'application/json'});
    }));
    fixture.c.dispose();
  });
}
