import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_spoken_replies.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;
import 'k135z_quick_start_test.dart' show binding, clips, flush, PriorityPlayer;
import 'k135z_spoken_replies_test.dart' show SpokenFixture, SpokenPlayer;

void main() {
  test('hidden web page still answers new questions when audio is running', () async {
    final f = SpokenFixture();
    addTearDown(f.dispose);
    await f.spoken.enable();
    f.spoken.leavePage(keepVoiceActive: true);
    expect(f.spoken.enabled, true);
    expect(f.spoken.suspended, false);
    expect(f.capture.fastTranscript, true);
    await f.ask();
    expect(f.player.plays, 1);
    expect(f.cancels, 0);
  });

  test('a tab switch does not cancel waiting speech or the pending answer', () async {
    final player = PriorityPlayer();
    final f = SpokenFixture(player: player, waitingVoice: clips);
    addTearDown(f.dispose);
    await f.spoken.enable();
    await flush();
    f.hold = Completer<void>();
    final reply = f.ask();
    await flush();
    f.now += 1000;
    await f.spoken.tick();
    expect(f.spoken.waitingSpeaking, true);
    f.spoken.leavePage(keepVoiceActive: true);
    expect(player.interrupts, 0);
    expect(f.spoken.waitingSpeaking, true);
    f.hold!.complete();
    await reply;
    expect(player.plays, 2);
    expect(f.spoken.enabled, true);
  });

  test('returning from a running background session avoids a new Start or caption baseline', () async {
    final f = CaptureFixture();
    final player = SpokenPlayer();
    final b = binding(f, player);
    addTearDown(b.dispose);
    addTearDown(f.c.dispose);
    await b.initialize();
    await b.startNova();
    b.leavePage(keepVoiceActive: true);
    expect(b.response.spoken.suspended, false);
    final before = f.calls.length;
    await b.returnToPage();
    expect(f.calls.skip(before), ['status']);
    expect(player.enables, 1);
    expect(b.response.spoken.enabled, true);
    expect(b.capture.fastTranscript, true);
  });

  test('browser audio suspension still preserves opt-in and skips stale questions', () async {
    final f = SpokenFixture();
    addTearDown(f.dispose);
    await f.spoken.enable();
    f.spoken.leavePage(keepVoiceActive: true);
    f.player.ready = false;
    await f.spoken.tick();
    expect(f.spoken.enabled, true);
    expect(f.spoken.suspended, true);
    expect(f.capture.fastTranscript, false);
    f.capture.say('Nova, stale question while suspended?');
    await f.spoken.returnToPage();
    f.now += 5000;
    await f.spoken.tick();
    expect(f.calls, isEmpty);
    await f.ask();
    expect(f.calls.single['wakeSequence'], 2);
  });

  for (final tickBeforeReturn in [true, false]) {
    test('expired background capture restores voice; timer first: $tickBeforeReturn', () async {
      final f = CaptureFixture();
      final player = SpokenPlayer();
      final voice = K135zSpokenReplies(capture: f.c, cancelRequest: () {},
        beforeEnable: () {}, player: player, watch: false,
        loadWaitingVoice: () async => const [], milliseconds: () => f.now);
      addTearDown(() { voice.dispose(); f.c.dispose(); });
      await f.start();
      await voice.enable();
      f.c.leavePage();
      voice.leavePage(keepVoiceActive: true);
      f.now = 40000;
      f.row['validForMs'] = 0;
      f.captureActive = false;
      if (tickBeforeReturn) {
        await f.c.tick();
        expect(voice.suspended, true);
        expect(voice.enabled, true);
      }
      final restored = await f.c.returnToPage();
      expect(restored, true);
      expect(voice.enabled, true);
      expect(voice.suspended, true);
      await voice.returnToPage();
      expect(voice.suspended, false);
      expect(voice.enabled, true);
      expect(player.enables, 1);
      expect(f.c.canRecoverOnReturn, false);
      expect(f.calls.where((call) => call == 'start').length, 2);
    });
  }

  test('remote revocation while hidden stops voice and cannot recover', () async {
    final f = CaptureFixture();
    final voice = K135zSpokenReplies(capture: f.c, cancelRequest: () {},
      beforeEnable: () {}, player: SpokenPlayer(), watch: false,
      loadWaitingVoice: () async => const [], milliseconds: () => f.now);
    addTearDown(() { voice.dispose(); f.c.dispose(); });
    await f.start();
    await voice.enable();
    f.c.leavePage();
    voice.leavePage(keepVoiceActive: true);
    f.row['authorityRevision']++;
    f.row['authority']['listeningAuthorized'] = false;
    await f.c.refresh();
    expect(voice.enabled, false);
    expect(f.c.canRecoverOnReturn, false);
    expect(await f.c.returnToPage(), false);
    expect(f.calls.where((call) => call == 'start').length, 1);
  });

  test('Silence Nova while hidden cannot be undone by a pending reply or return', () async {
    final f = SpokenFixture();
    addTearDown(f.dispose);
    await f.spoken.enable();
    f.hold = Completer<void>();
    final reply = f.ask();
    await flush();
    f.spoken.leavePage(keepVoiceActive: true);
    f.spoken.stop();
    f.hold!.complete();
    await reply;
    await f.spoken.returnToPage();
    expect(f.player.plays, 0);
    expect(f.spoken.enabled, false);
  });
}
