import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_spoken_replies.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;
import 'k135z_quick_start_test.dart' show binding, clips, flush, PriorityPlayer;
import 'k135z_spoken_replies_test.dart' show SpokenFixture, SpokenPlayer;

void main() {
  test('pause keeps audio open and resume ignores questions heard while paused', () async {
    final f = SpokenFixture();
    addTearDown(f.dispose);
    await f.spoken.enable();
    f.capture.say('Nova, unfinished question');
    f.spoken.pause();
    expect(f.spoken.enabled, true);
    expect(f.spoken.userPaused, true);
    expect(f.player.ready, true);
    expect(f.player.stops, 0);
    expect(f.capture.fastTranscript, false);
    await f.ask('Nova, do not answer this paused question?');
    expect(f.calls, isEmpty);
    await f.spoken.returnToPage(userGesture: true);
    expect(f.player.enables, 1);
    expect(f.capture.fastTranscript, true);
    f.now += 5000;
    await f.spoken.tick();
    expect(f.calls, isEmpty);
    await f.ask();
    expect(f.calls.single['wakeSequence'], 3);
    expect(f.player.plays, 1);
  });

  test('an interrupted answer cannot play even if it completes after Resume', () async {
    final f = SpokenFixture();
    addTearDown(f.dispose);
    await f.spoken.enable();
    f.hold = Completer<void>();
    final old = f.ask();
    await flush();
    f.spoken.pause();
    await f.spoken.returnToPage(userGesture: true);
    f.hold!.complete();
    await old;
    expect(f.player.plays, 0);
    expect(f.spoken.busy, false);
    expect(f.spoken.answer, isNull);
    await f.ask();
    expect(f.player.plays, 1);
  });

  for (final waiting in [true, false]) {
    test('Silence interrupts ${waiting ? 'waiting speech' : 'answer audio'} without closing audio', () async {
      final player = PriorityPlayer();
      final f = SpokenFixture(player: player, waitingVoice: clips);
      addTearDown(f.dispose);
      await f.spoken.enable();
      await flush();
      if (waiting) f.hold = Completer<void>();
      final reply = f.ask();
      await flush();
      if (waiting) { f.now += 1000; await f.spoken.tick(); }
      expect(player.plays, 1);
      f.spoken.pause();
      expect(player.interrupts, greaterThan(0));
      expect(player.ready, true);
      expect(f.spoken.playing, false);
      expect(f.spoken.waitingSpeaking, false);
      if (waiting) f.hold!.complete();
      await reply;
      expect(player.plays, 1);
      expect(f.spoken.userPaused, true);
      expect(f.spoken.message, contains('paused'));
    });
  }

  test('browser return keeps explicit pause without another Start or consent', () async {
    final f = CaptureFixture(), player = SpokenPlayer();
    final b = binding(f, player);
    addTearDown(() { b.dispose(); f.c.dispose(); });
    await b.initialize();
    await b.startNova();
    b.response.pause();
    b.leavePage(keepVoiceActive: true);
    await b.returnToPage();
    expect(b.capture.statusLabel, 'Listening');
    expect(b.response.spoken.userPaused, true);
    expect(b.response.spoken.suspended, true);
    await b.response.spoken.returnToPage(userGesture: true);
    expect(f.calls.where((x) => x == 'start').length, 1);
    expect(f.calls.where((x) => x == 'consent').length, 1);
    expect(player.enables, 1);
    expect(b.response.spoken.userPaused, false);
    b.response.pause();
    await b.stopListening();
    await b.response.spoken.returnToPage(userGesture: true);
    expect(b.response.spoken.enabled, false);
    expect(b.response.spoken.canResume, false);
  });

  test('expired background capture recovers but explicit voice pause survives', () async {
    final f = CaptureFixture(), player = SpokenPlayer();
    final voice = K135zSpokenReplies(capture: f.c, cancelRequest: () {},
      beforeEnable: () {}, player: player, watch: false,
      loadWaitingVoice: () async => const [], milliseconds: () => f.now);
    addTearDown(() { voice.dispose(); f.c.dispose(); });
    await f.start();
    await voice.enable();
    voice.pause();
    f.c.leavePage();
    voice.leavePage(keepVoiceActive: true);
    f.now = 10000;
    await f.c.tick();
    expect(f.calls, contains('renew'));
    f.now = 40000;
    f.row['validForMs'] = 0;
    f.captureActive = false;
    await f.c.tick();
    expect(await f.c.returnToPage(), true);
    await voice.returnToPage();
    await voice.tick();
    expect(voice.enabled, true);
    expect(voice.userPaused, true);
    expect(player.plays, 0);
    await voice.returnToPage(userGesture: true);
    expect(voice.suspended, false);
  });

  test('permission changes invalidate a paused voice session', () async {
    for (final change in <void Function(SpokenFixture)>[
      (f) => f.capture.active = false,
      (f) => f.capture.binding['authorityRevision'] = 2,
      (f) => f.capture.binding['context']['meetingUuid'] = 'other',
    ]) {
      final f = SpokenFixture();
      await f.spoken.enable();
      f.spoken.pause();
      change(f);
      f.capture.changed();
      await f.spoken.returnToPage(userGesture: true);
      expect(f.spoken.enabled, false);
      expect(f.spoken.canResume, false);
      f.dispose();
    }
  });

  test('a blocked browser audio context unlocks only on the explicit Resume tap', () async {
    final f = SpokenFixture();
    addTearDown(f.dispose);
    await f.spoken.enable();
    f.spoken.pause();
    f.player.ready = false;
    await f.spoken.returnToPage();
    expect(f.player.enables, 1);
    expect(f.spoken.userPaused, true);
    await f.spoken.returnToPage(userGesture: true);
    expect(f.player.enables, 2);
    expect(f.spoken.suspended, false);
  });

  test('Silence during automatic recovery cancels that recovery', () async {
    final f = SpokenFixture();
    addTearDown(f.dispose);
    await f.spoken.enable();
    f.spoken.leavePage();
    f.player.holdResume = Completer<void>();
    final returning = f.spoken.returnToPage();
    f.spoken.pause();
    f.player.holdResume!.complete();
    await returning;
    expect(f.spoken.userPaused, true);
    expect(f.spoken.suspended, true);
    await f.spoken.returnToPage();
    expect(f.spoken.userPaused, true);
    expect(f.player.plays, 0);
  });
}
