import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;

void main() {
  test('one explicit tap binds, consents and starts; Stop and restart each take one action', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose); f.missing = true;
    await f.c.listenTo('meeting');
    expect(f.calls, ['status','bind','consent','start']);
    expect(f.c.statusLabel, 'Listening');
    await f.c.stop();
    expect(f.c.statusLabel, 'Stopped'); expect(f.c.consent, isFalse);
    final before = f.calls.length;
    await f.c.listenTo('meeting');
    expect(f.calls.skip(before), ['status','bind','consent','start']);
    expect(f.c.statusLabel, 'Listening');
  });
  test('the screenshot conflict recovers through one Start or one Stop', () async {
    for (final start in [true, false]) {
      final f = CaptureFixture(); addTearDown(f.c.dispose);
      f.row['snapshot']['context']['meetingUuid'] = 'previous';
      await f.c.selectMeeting('meeting');
      expect(f.c.statusLabel, 'Session unconfirmed'); expect(f.c.canStop, isTrue);
      final before = f.calls.length;
      if (start) {
        await f.c.listenTo('meeting');
        expect(f.calls.skip(before), ['status','stop','bind','consent','start']);
        expect(f.c.meetingUuid, 'meeting'); expect(f.c.statusLabel, 'Listening');
      } else {
        await f.c.stop(); expect(f.calls.skip(before), ['status','stop']);
        expect(f.c.statusLabel, 'Stopped');
      }
    }
  });
  test('failed old-session Stop never binds or starts a replacement', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose);
    f.row['snapshot']['context']['meetingUuid'] = 'previous'; f.stopCode = 503;
    await f.c.listenTo('meeting');
    expect(f.calls, ['status','stop']); expect(f.c.statusLabel, 'Session unconfirmed');
    expect(f.c.canStop, isTrue);
  });
  test('Stop reads a persisted session even before local selection', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose);
    expect(f.c.canStop, isTrue); await f.c.stop();
    expect(f.calls, ['status','stop']); expect(f.c.statusLabel, 'Stopped');
  });
  test('failed status never sends a mutation; Stop does not renew after failure', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose); await f.start();
    f.statusCode = 503; final before = f.calls.length;
    await f.c.stop(); f.now = 10000; await f.c.tick();
    expect(f.calls.skip(before), ['status']); expect(f.c.consent, isFalse);
    await f.c.listenTo('meeting'); expect(f.calls.last, 'status');
    expect(f.c.statusLabel, 'Session unconfirmed');
  });
  test('pending, uncertain and foreign-agent sessions cannot be started', () async {
    for (final issue in ['pending','uncertain','foreign']) {
      final f = CaptureFixture(); addTearDown(f.c.dispose);
      if (issue == 'foreign') { f.row['snapshot']['context']['agentId'] = 'other'; }
      else { f.row[issue] = true; }
      await f.c.listenTo('meeting'); expect(f.calls, ['status']);
      expect(f.c.statusLabel, isNot('Listening'));
    }
  });
  test('duplicate Start does not repeat commands and hiding cancels a late Start', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose); f.hold = Completer<void>();
    final first = f.c.listenTo('meeting'); await Future<void>.delayed(Duration.zero);
    await f.c.listenTo('meeting'); expect(f.calls, ['status','consent']);
    f.c.suspend(); f.hold!.complete(); await first;
    expect(f.calls, isNot(contains('start')));
    await f.c.resume(); expect(f.calls.last, 'status');
  });
  test('discovery chooses the sole meeting without binding; multiple meetings need a choice', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose);
    final b = K135zZoomRuntimeBinding(launch:K135zZoomLaunch(agentId:'agent',
      backendBaseUri:Uri.parse('https://api.example.test'),
      headersBuilder:() => {'authorization':'Bearer offline'}, isCurrent:() => true), transport:f.c.transport);
    addTearDown(b.dispose);
    await b.initialize(); expect(f.calls, isEmpty);
    expect(b.listeningMeeting?.uuid, 'meeting'); expect(b.canStartListening, isTrue);
    f.meetings.add({'id':'456','uuid':'second','topic':'Second','is_host':true});
    await b.initialize(); expect(b.listeningMeeting, isNull); expect(b.canStartListening, isFalse);
    await b.startListening(); expect(f.calls, isEmpty);
    b.chooseListeningMeeting('second'); await b.startListening();
    expect(b.capture.statusLabel, 'Listening'); expect(b.capture.meetingUuid, 'second');
    expect(f.calls, ['status','stop','bind','consent','start']);
  });
}
