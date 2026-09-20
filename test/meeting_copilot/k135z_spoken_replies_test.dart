import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_capture_controller.dart';
import '../../lib/meeting_copilot/k135z_spoken_replies.dart';
import '../../lib/meeting_copilot/k135z_spoken_player.dart';
import '../../lib/meeting_copilot/k135z_spoken_panel.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';
import '../../lib/live_convo/k136s_learning_panel.dart';
import 'k135z_meeting_response_test.dart' show Capture;

class SpokenCapture extends Capture {
  SpokenCapture(super.send);
  String window = 'a' * 32;
  final lines = <K135zTranscriptPreviewLine>[];
  @override String? get transcriptWindowId => window;
  @override List<K135zTranscriptPreviewLine> get transcriptLines => lines;
  @override Future<void> prepareSpokenTranscript() async {}
  @override Future<void> refreshTranscript({bool automatic = false}) async {}
  void say(String text, {String speaker = 'Host'}) {
    lines.add(K135zTranscriptPreviewLine(sequence: lines.length + 1, speaker: speaker, text: text)); changed();
  }
}
class SpokenPlayer implements K135zSpokenPlayer {
  bool ready = false, supported = true;
  int plays = 0, stops = 0, enables = 0;
  bool resumeAllowed = true;
  Completer<void>? holdResume;
  Future<bool> resume() async { if (holdResume != null) await holdResume!.future; return ready = resumeAllowed; }
  void interrupt() {}
  Completer<void>? holdEnable, holdPlay;
  Future<void> enable() async { enables++; if (holdEnable != null) await holdEnable!.future; ready = true; }
  Future<void> play(Uint8List bytes) async { plays++; if (holdPlay != null) await holdPlay!.future; }
  void stop() { stops++; ready = false; }
}
class SpokenFixture {
  int now = 0, cancels = 0;
  final calls = <Map>[];
  final player = SpokenPlayer();
  Completer<void>? hold;
  bool bad = false;
  String? errorCode;
  Map<String, dynamic>? agent;
  Map<String, dynamic>? memoryRequest;
  late final SpokenCapture capture;
  late final K135zSpokenReplies spoken;
  SpokenFixture({K136sLearningApiBase? learningApi}) {
    capture = SpokenCapture(({required String method, required Uri uri, required Map<String,String> headers, Object? body}) async {
      expect(uri.path, endsWith('/spoken-reply'));
      expect(headers['x-korlix-agent-id'], 'agent');
      final b = body as Map; calls.add(b);
      if (hold != null) await hold!.future;
      if (errorCode != null) return KorlixZoomTransportResponse(statusCode:502,
        body:jsonEncode({'ok':false,'error':{'code':errorCode}}));
      return KorlixZoomTransportResponse(statusCode: 200, body: jsonEncode({'ok': true, 'reply': {
        'context': bad ? {...b['context'], 'meetingUuid': 'other'} : b['context'],
        'windowId':b['windowId'], 'wakeSequence':b['wakeSequence'], 'coverage':'partial',
        'text':'We agreed to review the draft Friday.', 'mimeType':'audio/mpeg',
        'audio':base64Encode([73,68,51,...List.filled(100,0)]),
        if (agent != null) 'agent': agent,
        if (memoryRequest != null) 'memoryRequest':memoryRequest,
      }}));
    });
    spoken = K135zSpokenReplies(capture: capture, cancelRequest: () { cancels++; },
      beforeEnable: () {}, player: player, learningApi:learningApi, milliseconds: () => now, watch: false);
  }
  Future<void> ask([String text = 'Nova, what did we decide?']) async {
    capture.say(text); now += 3000; await spoken.tick();
  }
  void dispose() { spoken.dispose(); capture.dispose(); }
}
void main() {
  test('shows the selected agent memory status and clears it on Stop', () async {
    final f = SpokenFixture(); addTearDown(f.dispose);
    f.agent = {'id':'agent','name':'NOVA','memoryEnabled':true,'memoryCount':34};
    await f.spoken.enable(); await f.ask();
    expect(f.spoken.memoryStatus, contains('34 saved memories'));
    f.spoken.stop(); expect(f.spoken.memoryStatus, isNull);
  });
  test('foreign agent metadata prevents playback', () async {
    final f = SpokenFixture(); addTearDown(f.dispose);
    f.agent = {'id':'other','name':'OTHER','memoryEnabled':true,'memoryCount':1};
    await f.spoken.enable(); await f.ask();
    expect(f.player.plays, 0); expect(f.spoken.answer, isNull);
  });
  testWidgets('reasoning can pass the old 35-second deadline and Stop still cancels it', (tester) async {
    final f = SpokenFixture(); addTearDown(f.dispose);
    await f.spoken.enable(); f.hold = Completer<void>(); final pending = f.ask();
    await tester.pump(const Duration(seconds:40));
    expect(f.spoken.busy, true); expect(f.spoken.enabled, true); expect(f.player.plays, 0);
    f.spoken.stop(); f.hold!.complete(); await pending;
    expect(f.player.plays, 0); expect(f.cancels, 1);
  });
  test('off by default; enabling skips historical questions then answers a fresh question', () async {
    final f = SpokenFixture(); addTearDown(f.dispose);
    f.capture.say('Nova, old question?'); await f.spoken.tick(); expect(f.calls, isEmpty);
    await f.spoken.enable(); expect(f.player.enables, 1); expect(f.capture.fastTranscript, true);
    f.now = 4000; await f.spoken.tick(); expect(f.calls, isEmpty);
    await f.ask(); expect(f.calls.length, 1); expect(f.calls.single['wakeSequence'], 2);
    expect(f.calls.single.containsKey('text'), false); expect(f.calls.single['enabled'], true);
    expect(f.player.plays, 1); expect(f.spoken.enabled, true); expect(f.spoken.answer, contains('Friday'));
  });
  test('gathers caption fragments from the same speaker and waits for a pause', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.capture.say('Hey Nova,'); f.now = 2000; await f.spoken.tick(); expect(f.calls, isEmpty);
    f.capture.say('what did we decide?'); f.now = 3500; await f.spoken.tick(); expect(f.calls, isEmpty);
    f.now = 5000; await f.spoken.tick(); expect(f.calls.single['endSequence'], 2);
  });
  test('incidental mentions do not trigger a reply', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    await f.ask('We should ask Nova later.'); expect(f.calls, isEmpty);
  });
  test('duplicate notifications and captions during playback/cooldown never queue replies', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.player.holdPlay = Completer<void>(); final answer = f.ask();
    await Future<void>.delayed(Duration.zero); expect(f.player.plays, 1);
    f.capture.say('Nova, echoed voice'); f.capture.changed();
    f.player.holdPlay!.complete(); await answer;
    f.capture.say('Nova, delayed echo'); f.now += 9000; await f.spoken.tick(); expect(f.calls.length, 1);
    await f.ask('Nova, another question?'); expect(f.calls.length, 2);
  });
  test('Stop during generation discards delayed audio and disables further replies', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.hold = Completer<void>(); final pending = f.ask();
    await Future<void>.delayed(Duration.zero); f.spoken.stop(); f.hold!.complete(); await pending;
    expect(f.player.plays, 0); expect(f.spoken.enabled, false); expect(f.capture.fastTranscript, false);
    expect(f.cancels, 1); await f.ask(); expect(f.calls.length, 1);
  });
  test('Stop during playback remains stopped after late completion', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.player.holdPlay = Completer<void>(); final pending = f.ask();
    await Future<void>.delayed(Duration.zero); f.spoken.stop();
    f.player.holdPlay!.complete(); await pending; expect(f.spoken.playing, false);
    expect(f.spoken.message, contains('off')); expect(f.player.ready, false);
  });
  test('permission, account, meeting and caption window changes disarm mode', () async {
    for (final change in <void Function(SpokenFixture)>[
      (f) => f.capture.active = false,
      (f) => f.capture.binding['authorityRevision'] = 2,
      (f) => f.capture.binding['context']['meetingUuid'] = 'other',
      (f) => f.capture.window = 'b' * 32,
    ]) {
      final f = SpokenFixture(); await f.spoken.enable(); change(f); f.capture.changed();
      expect(f.spoken.enabled, false); expect(f.capture.fastTranscript, false); f.dispose();
    }
  });
  test('invalid reply context never plays', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable(); f.bad = true;
    await f.ask(); expect(f.player.plays, 0); expect(f.spoken.enabled, false);
  });
  testWidgets('one enable tap starts mode; Stop is available during a reply', (tester) async {
    final f = SpokenFixture(); addTearDown(f.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: K135zSpokenPanel(spoken: f.spoken)))));
    await tester.tap(find.byKey(const Key('nova-enable-spoken'))); await tester.pumpAndSettle();
    expect(f.spoken.enabled, true); expect(find.text('Spoken replies on'), findsOneWidget);
    f.hold = Completer<void>(); final pending = f.ask(); await tester.pump();
    await tester.tap(find.byKey(const Key('nova-stop-spoken'))); await tester.pump();
    f.hold!.complete(); await pending; expect(f.player.plays, 0); expect(f.spoken.enabled, false);
    await tester.pumpAndSettle(); await tester.pumpWidget(const SizedBox());
  });
}
