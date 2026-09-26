import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_spoken_panel.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;
import 'k135z_spoken_replies_test.dart' show SpokenFixture;

void main() {
  test('brief window switch keeps listening and does not restart the stream', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose); await f.start();
    f.c.leavePage(); expect(f.c.statusLabel, 'Listening');
    f.now = 10000; await f.c.tick(); expect(f.calls, contains('renew'));
    final before = f.calls.length; await f.c.returnToPage();
    expect(f.calls.skip(before), ['status']); expect(f.c.statusLabel, 'Listening');
  });
  test('expired capture recovers the same consented session automatically on return', () async {
    final f = CaptureFixture(); addTearDown(f.c.dispose); await f.start();
    f.c.leavePage(); f.now = 40000; f.row['validForMs'] = 0; f.captureActive = false;
    await f.c.tick(); final before = f.calls.length; await f.c.returnToPage();
    expect(f.calls.skip(before), ['status','status','pause','consent','start']);
    expect(f.c.statusLabel, 'Listening'); expect(f.c.meetingUuid, 'meeting');
  });
  test('Stop, Pause, revoked consent, another session and sign-out cannot auto-start', () async {
    for (final action in ['stop','pause','revoke','remote-stop','remote-pause','remote-revoke','meeting','sign-out']) {
      final f = CaptureFixture(); await f.start(); f.c.leavePage();
      switch (action) {
        case 'stop': await f.c.stop();
        case 'pause': await f.c.pause();
        case 'revoke': await f.c.setConsent(false);
        case 'remote-stop': f.row['snapshot']['revision']++; f.row['snapshot']['state'] = 'stopped';
        case 'remote-pause': f.row['snapshot']['revision']++; f.row['snapshot']['state'] = 'paused';
        case 'remote-revoke': f.row['authorityRevision']++; f.row['authority']['listeningAuthorized'] = false;
        case 'meeting': f.row['snapshot']['context']['meetingUuid'] = 'different';
        case 'sign-out': f.current = false;
      }
      final before = f.calls.length; await f.c.returnToPage();
      expect(f.calls.skip(before).where((x) => ['start','consent','bind'].contains(x)), isEmpty, reason:action);
      f.c.dispose();
    }
  });
  test('voice opt-in survives window switch and skips all questions heard while away', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.spoken.leavePage(); f.player.ready = false;
    f.capture.say('Nova, old question while away?'); await f.spoken.tick();
    expect(f.spoken.enabled, true); expect(f.spoken.suspended, true); expect(f.calls, isEmpty);
    await f.spoken.returnToPage(); expect(f.spoken.suspended, false); expect(f.player.enables, 1);
    f.now = 5000; await f.spoken.tick(); expect(f.calls, isEmpty);
    await f.ask(); expect(f.player.plays, 1); expect(f.calls.single['wakeSequence'], 2);
  });
  test('late answer cannot play after leaving; Stop while away never resumes voice', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.hold = Completer<void>(); final reply = f.ask(); await Future<void>.delayed(Duration.zero);
    f.spoken.leavePage(); f.hold!.complete(); await reply; expect(f.player.plays, 0);
    f.spoken.stop(); await f.spoken.returnToPage(); expect(f.spoken.enabled, false);
  });
  test('return does not restore voice in a changed meeting or lost listening session', () async {
    for (final changed in [false,true]) {
      final f = SpokenFixture(); await f.spoken.enable(); f.spoken.leavePage();
      if (changed) { f.capture.binding['context']['meetingUuid'] = 'other'; }
      else { f.capture.active = false; }
      await f.spoken.returnToPage(); expect(f.spoken.enabled, false); expect(f.player.plays, 0);
      f.dispose();
    }
  });
  testWidgets('browser audio blocking offers one Resume voice tap without restarting listening', (tester) async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.spoken.leavePage(); f.player.resumeAllowed = false; await f.spoken.returnToPage();
    expect(f.spoken.enabled, true); expect(f.spoken.needsAudioTap, true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:K135zSpokenPanel(spoken:f.spoken))));
    await tester.tap(find.text('Resume voice')); await tester.pumpAndSettle();
    expect(f.spoken.suspended, false); expect(f.player.enables, 2); expect(f.calls, isEmpty);
  });
  test('provider failures leave voice enabled for the next question', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.errorCode = 'K135Z_RESPONSE_PROVIDER_FAILED'; await f.ask();
    expect(f.spoken.enabled, true); expect(f.player.plays, 0);
    expect(f.spoken.message, contains('still on'));
    f.errorCode = null; f.now += 5000; await f.spoken.tick(); await f.ask();
    expect(f.player.plays, 1);
  });
  test('an audio interruption preserves opt-in and shows Resume voice', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.player.ready = false; await f.spoken.tick();
    expect(f.spoken.enabled, true); expect(f.spoken.needsAudioTap, true);
    await f.spoken.returnToPage(userGesture:true); expect(f.spoken.suspended, false);
  });
  test('another window switch while resuming cannot reactivate voice in the background', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable(); f.spoken.leavePage();
    f.player.holdResume = Completer<void>(); final returning = f.spoken.returnToPage();
    f.spoken.leavePage(); f.player.holdResume!.complete(); await returning;
    expect(f.spoken.suspended, true); expect(f.spoken.busy, false);
    f.player.holdResume = null; await f.spoken.returnToPage(); expect(f.spoken.suspended, false);
  });
  test('completed spoken questions dispatch after 700ms', () async {
    final f = SpokenFixture(); addTearDown(f.dispose); await f.spoken.enable();
    f.capture.say('Nova, what did we decide?'); f.now = 699; await f.spoken.tick(); expect(f.calls, isEmpty);
    f.now = 700; await f.spoken.tick(); expect(f.calls.length, 1);
  });
}
