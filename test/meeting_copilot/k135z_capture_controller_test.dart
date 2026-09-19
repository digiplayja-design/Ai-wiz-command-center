import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_capture_controller.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';

void check(bool ok) { if (!ok) throw StateError('Gate6N assertion failed'); }
class CaptureFixture {
  int now = 0, cancels = 0;
  bool current = true, failRenew = false, badReply = false, captureActive = true;
  Completer<void>? hold;
  bool missing = false;
  Completer<void>? previewHold;
  Map<String,dynamic>? previewOverride;
  int previewCode = 200;

  int consentLatency = 0;
  final calls = <String>[];
  Map<String, dynamic> row = {
    'snapshot': {'schemaVersion':1, 'context':{'tenantId':'user','userId':'user','agentId':'agent',
      'sessionId':'session','meetingUuid':'meeting','streamId':null,'generation':1},
      'revision':0,'state':'ready','hostAuthorized':false,'listeningAuthorized':false,'activeSeconds':0,'capabilities':{'canSpeak':false}},
    'authority':{'context':{},'viewerAuthorized':true,'hostAuthorized':false,'listeningAuthorized':false},
    'bindingRevision':1,'authorityRevision':0,'validForMs':0,'pending':false,'uncertain':false,'captureActive':false,
  };
  late final K135zCaptureController c;
  CaptureFixture() {
    row['authority']['context'] = row['snapshot']['context'];
    c = K135zCaptureController(agentId:'agent',baseUri:Uri.parse('https://api.example.test'),
      headers:() => {'authorization':'Bearer offline'},isCurrent:() => current,
      cancelRequests:() {cancels++;},milliseconds:() => now,watch:false,
      transport:({required String method, required Uri uri, required Map<String,String> headers, Object? body}) async {
        check(method == 'POST' && headers['authorization'] == 'Bearer offline' && headers['x-korlix-agent-id'] == 'agent');
        final b = body as Map<String,dynamic>, action = (b['action'] ?? uri.path.split('/').last) as String;
        calls.add(action);
        if (action == 'transcript') {
          if (previewHold != null) await previewHold!.future;
          return KorlixZoomTransportResponse(statusCode:previewCode,body:jsonEncode({'ok':true,'transcript':previewOverride ?? {
            'schemaVersion':1,'context':b['context'],'windowId':'a'*32,'revision':1,
            'lines':[{'sequence':1,'speaker':'Host','text':'Meeting caption','providerTimestamp':10,'startTs':1,'endTs':10}],
            'truncated':false,'persisted':false,'coverage':'partial'}}));
        }
        if (action == 'status' && missing) return const KorlixZoomTransportResponse(statusCode:409,
          body:'{"ok":false,"error":{"code":"K135Z_WORKSPACE_BINDING_MISMATCH"}}');
        if (action == 'bind') {check(b['expectedBindingRevision'] == 0 && b['meetingUuid'] == 'meeting'); missing = false;}
        if (action == 'consent') now += consentLatency;
        if (action == 'consent' && hold != null) await hold!.future;
        if (action == 'renew' && failRenew) return const KorlixZoomTransportResponse(statusCode:503, body:'{}');
        if (['consent','renew','revoke'].contains(action)) {
          if (action != 'renew') row['authorityRevision']++;
          row['authority']['hostAuthorized'] = action != 'revoke';
          row['authority']['listeningAuthorized'] = action != 'revoke';
          row['validForMs'] = action == 'revoke' ? 0 : 30000;
        }
        if (['start','pause','stop'].contains(action)) {
          check(b['expectedSnapshotRevision'] == row['snapshot']['revision']);
          row['snapshot'] = {...row['snapshot'], 'context':{...row['snapshot']['context'], 'streamId':'stream'},
            'revision':row['snapshot']['revision']+1,'state':{'start':'listening','pause':'paused','stop':'stopped'}[action],
            'hostAuthorized':true,'listeningAuthorized':true};
          row['authority']['context'] = row['snapshot']['context'];
          row['captureActive'] = action == 'start';
          return KorlixZoomTransportResponse(statusCode:200, body:jsonEncode({'ok':true,'reply':{
            'schemaVersion':1,'operation':badReply ? {...b['operation'],'requestId':'wrong'} : b['operation'],
            'action':action,'outcome':{'kind':'acknowledged','snapshot':row['snapshot']}}}));
        }
        if (action == 'status' && row['snapshot']['state'] == 'listening') row['captureActive'] = captureActive;
        return KorlixZoomTransportResponse(statusCode:200,body:jsonEncode({'ok':true,'workspace':row}));
      });
  }
  Future<void> start() async { await c.selectMeeting('meeting'); await c.setConsent(true); await c.start(); }
}
void main() {
  gate6pTests();
  test('Gate6N first selection binds the exact meeting with revision zero', () async {
    final f = CaptureFixture(); try {
      f.missing = true; await f.c.selectMeeting('meeting');
      check(f.calls.join(',') == 'status,bind' && f.c.statusLabel == 'Ready' && !f.c.canStart);
    } finally {f.c.dispose();}
  });
  test('Gate6N consent response latency consumes the lease before Start', () async {
    final f = CaptureFixture(); try {
      f.consentLatency = 30001; await f.start();
      check(!f.calls.contains('start') && f.c.statusLabel == 'Session unconfirmed');
    } finally {f.c.dispose();}
  });
  test('Gate6N duplicate Start clicks dispatch a single consent and command', () async {
    final f = CaptureFixture(); try {
      await f.c.selectMeeting('meeting'); await f.c.setConsent(true); f.hold = Completer<void>();
      final a = f.c.start(); await f.c.start(); f.hold!.complete(); await a;
      check(f.calls.where((x) => x == 'consent').length == 1 && f.calls.where((x) => x == 'start').length == 1);
    } finally {f.c.dispose();}
  });
  test('Gate6N requires explicit consent and acknowledges Start Pause Stop', () async {
    final f = CaptureFixture(); try {
      await f.c.selectMeeting('meeting'); check(!f.c.canStart); await f.c.start(); check(f.calls.length == 1);
      await f.c.setConsent(true); await f.c.start(); check(f.c.statusLabel == 'Listening');
      check(f.calls.join(',') == 'status,consent,start'); await f.c.pause(); check(f.c.statusLabel == 'Paused' && !f.c.consent);
      await f.c.setConsent(true); await f.c.start(); await f.c.stop(); check(f.c.statusLabel == 'Stopped' && !f.c.canStart);
    } finally {f.c.dispose();}
  });
  test('Gate6N renews every ten seconds without changing authority revision', () async {
    final f = CaptureFixture(); try {
      await f.start(); f.now = 10000; await f.c.tick();
      check(f.calls.last == 'renew' && f.row['authorityRevision'] == 1 && f.c.statusLabel == 'Listening');
      await f.c.tick(); check(f.calls.where((x) => x == 'renew').length == 1);
    } finally {f.c.dispose();}
  });
  test('Gate6N failed renewal requires manual recovery and never retries', () async {
    final f = CaptureFixture(); try {
      await f.start(); f.failRenew = true; f.now = 10000; await f.c.tick(); final n = f.calls.length;
      f.now = 20000; await f.c.tick(); check(f.calls.length == n && f.c.statusLabel == 'Session unconfirmed' && !f.c.canStart);
    } finally {f.c.dispose();}
  });
  test('Gate6N backgrounding during consent prevents a late Start', () async {
    final f = CaptureFixture(); try {
      await f.c.selectMeeting('meeting'); await f.c.setConsent(true); f.hold = Completer<void>();
      final pending = f.c.start(); await Future<void>.delayed(Duration.zero); f.c.suspend();
      f.hold!.complete(); await pending; check(!f.calls.contains('start') && !f.c.canStart && f.cancels > 0);
      f.c.resume(); check(f.c.statusLabel == 'Session unconfirmed');
    } finally {f.c.dispose();}
  });
  test('Gate6N disposal during consent prevents late command and notifications', () async {
    final f = CaptureFixture(); await f.c.selectMeeting('meeting'); await f.c.setConsent(true);
    f.hold = Completer<void>(); final pending = f.c.start(); await Future<void>.delayed(Duration.zero);
    f.c.dispose(); f.hold!.complete(); await pending; check(!f.calls.contains('start'));
  });
  test('Gate6N wrong operation correlation cannot display Listening', () async {
    final f = CaptureFixture(); try {f.badReply = true; await f.start(); check(f.c.statusLabel == 'Session unconfirmed');}
    finally {f.c.dispose();}
  });
  test('Gate6N inactive SDK status stops renewal and displays interrupted', () async {
    final f = CaptureFixture(); try {
      await f.start(); f.captureActive = false; f.now = 5000; await f.c.tick(); check(f.c.statusLabel == 'Capture interrupted');
      f.now = 10000; await f.c.tick(); check(!f.calls.contains('renew'));
    } finally {f.c.dispose();}
  });
  test('Gate6N expiration cannot revive consent or claim Listening', () async {
    final f = CaptureFixture(); try {
      await f.start(); f.row['validForMs'] = 0; f.now = 30001; await f.c.tick();
      check(f.c.statusLabel == 'Capture interrupted' && !f.calls.contains('renew') && !f.c.consent);
    } finally {f.c.dispose();}
  });
  test('Gate6N withdrawing consent calls revoke and prevents renewal', () async {
    final f = CaptureFixture(); try {
      await f.start(); await f.c.setConsent(false); check(f.calls.last == 'revoke' && !f.c.consent);
      f.now = 10000; await f.c.tick(); check(!f.calls.contains('renew') && f.c.statusLabel != 'Listening');
    } finally {f.c.dispose();}
  });
  test('Gate6N agent change invalidates before any next request', () async {
    final f = CaptureFixture(); try {
      await f.start(); final n = f.calls.length; f.current = false; await f.c.tick(); await f.c.stop();
      check(f.calls.length == n && f.c.statusLabel == 'Session unconfirmed');
    } finally {f.c.dispose();}
  });
  test('Gate6N reconnecting to an existing session never auto renews', () async {
    final f = CaptureFixture(); try {
      await f.start(); f.c.suspend(); f.c.resume(); await f.c.refresh(); f.now = 10000; await f.c.tick();
      check(!f.calls.contains('renew') && !f.c.consent);
    } finally {f.c.dispose();}
  });
  test('Gate6N foreign context and uncertain state disable controls', () async {
    final f = CaptureFixture(); try {
      f.row['uncertain'] = true; await f.c.selectMeeting('meeting'); await f.c.setConsent(true); check(!f.c.canStart);
      f.row['snapshot']['context']['agentId'] = 'another'; await f.c.refresh(); check(f.c.statusLabel == 'Session unconfirmed');
    } finally {f.c.dispose();}
  });
}

void gate6pTests() {
  test('Gate6P preview requires a confirmed stream and returns immutable display lines', () async {
    final f = CaptureFixture(); try {
      await f.c.refreshTranscript(); check(f.calls.isEmpty); await f.start();
      await f.c.refreshTranscript(); check(f.c.transcriptLines.single.text == 'Meeting caption');
      check(f.c.transcriptLines.single.speaker == 'Host' && f.c.statusLabel == 'Listening');
      bool immutable = false; try {f.c.transcriptLines.clear();} catch (_) {immutable = true;} check(immutable);
      await f.c.refreshTranscript(); check(f.c.transcriptLines.length == 1);
    } finally {f.c.dispose();}
  });
  test('Gate6P rejected preview does not revoke consent and does not retry automatically', () async {
    final f = CaptureFixture(); try {
      await f.start(); f.previewCode = 503; await f.c.refreshTranscript();
      check(f.c.statusLabel == 'Listening' && f.c.consent && f.c.transcriptLines.isEmpty);
      final before = f.calls.where((x) => x == 'transcript').length;
      f.now = 6000; await f.c.tick(); f.now = 7000; await f.c.tick();
      check(f.calls.where((x) => x == 'transcript').length == before);
      f.previewCode = 200; await f.c.refreshTranscript(); check(f.c.transcriptLines.length == 1);
    } finally {f.c.dispose();}
  });
  test('Gate6P backgrounding and disposal discard late caption responses', () async {
    for (final dispose in [false,true]) {
      final f = CaptureFixture(); await f.start();f.previewHold = Completer<void>();
      final work = f.c.refreshTranscript(); await Future<void>.delayed(Duration.zero);
      if (dispose) {f.c.dispose();} else {f.c.suspend();}
      f.previewHold!.complete();await work;check(f.c.transcriptLines.isEmpty);
      if (!dispose) f.c.dispose();
    }
  });
  test('Gate6P rejects foreign context and fabricated persistence claims', () async {
    final f = CaptureFixture();try {
      await f.start();
      final base = {'schemaVersion':1,'context':f.row['snapshot']['context'],'windowId':'a'*32,'revision':0,
        'lines':[],'truncated':false,'persisted':false,'coverage':'partial'};
      for (final bad in [{...base,'context':{...f.row['snapshot']['context'],'agentId':'other'}},
          {...base,'persisted':true},{...base,'coverage':'complete'}]) {
        f.previewOverride = bad;await f.c.refreshTranscript();check(f.c.transcriptLines.isEmpty && f.c.transcriptMessage.contains('unavailable'));
      }
    } finally {f.c.dispose();}
  });
  test('Gate6P preview revision cannot go backward or change under the same revision', () async {
    final f = CaptureFixture();try {
      await f.start();await f.c.refreshTranscript();
      f.previewOverride = {'schemaVersion':1,'context':f.row['snapshot']['context'],'windowId':'a'*32,'revision':1,
        'lines':[],'truncated':false,'persisted':false,'coverage':'partial'};
      await f.c.refreshTranscript();check(f.c.transcriptLines.isEmpty);
      f.previewOverride!['revision'] = 0;await f.c.refreshTranscript();check(f.c.transcriptMessage.contains('unavailable'));
      f.previewOverride = null;await f.c.refreshTranscript();check(f.c.transcriptLines.length == 1);
    } finally {f.c.dispose();}
  });
  test('Gate6P polling captions runs after higher priority session checks', () async {
    final f = CaptureFixture();try {
      await f.start();f.now = 5000;await f.c.tick();check(f.calls.last == 'status');
      f.now = 6000;await f.c.tick();check(f.calls.last == 'transcript');
      f.now = 10000;await f.c.tick();check(f.calls.last == 'renew');
    } finally {f.c.dispose();}
  });
  test('Gate6P preview remains readable after Pause and Stop without sending Start', () async {
    final f = CaptureFixture();try {
      await f.start();await f.c.pause();await f.c.refreshTranscript();check(f.c.transcriptLines.length == 1);
      await f.c.stop();await f.c.refreshTranscript();check(f.c.statusLabel == 'Stopped' && f.c.transcriptLines.length == 1);
      check(f.calls.where((x) => x == 'start').length == 1);
    } finally {f.c.dispose();}
  });
  test('Gate6P identity loss hides cached captions immediately', () async {
    final f = CaptureFixture();try {
      await f.start();await f.c.refreshTranscript();f.current = false;
      check(f.c.transcriptLines.isEmpty && !f.c.canRefreshTranscript);
    } finally {f.c.dispose();}
  });
}
