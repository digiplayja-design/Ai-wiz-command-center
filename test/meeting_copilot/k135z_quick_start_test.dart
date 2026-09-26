import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_startup_panel.dart';
import '../../lib/meeting_copilot/k135z_waiting_voice.dart';
import '../../lib/meeting_copilot/k135z_zoom_runtime_binding.dart';
import '../../lib/meeting_copilot/korlix_zoom_connection_client.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;
import 'k135z_spoken_replies_test.dart' show SpokenFixture, SpokenPlayer, SpokenCapture;

final audio = Uint8List.fromList([73,68,51,...List.filled(100,0)]);
Future<List<K135zWaitingClip>> clips() async => [
  K135zWaitingClip("I'm on it.", audio),
  K135zWaitingClip("I'm still working through that.", audio),
];
Future<void> flush() => Future<void>.delayed(Duration.zero);
class PriorityPlayer extends SpokenPlayer {
  Completer<void>? waiting;
  int interrupts = 0;
  bool failWaiting = false;
  @override Future<void> play(Uint8List bytes) async {
    plays++;
    if (plays == 1) {
      if (failWaiting) throw StateError('Optional audio unavailable');
      waiting = Completer<void>();
      await waiting!.future;
    }
  }
  @override void interrupt() {
    interrupts++;
    if (waiting != null && !waiting!.isCompleted) waiting!.complete();
  }
}
K135zZoomRuntimeBinding binding(CaptureFixture f, SpokenPlayer player) => K135zZoomRuntimeBinding(
  launch:K135zZoomLaunch(agentId:'agent',backendBaseUri:Uri.parse('https://api.example.test'),
    headersBuilder:() => {'authorization':'Bearer offline'},isCurrent:() => f.current),
  transport:f.c.transport, spokenPlayer:player);

void main() {
  test('Start Nova unlocks audio immediately, then starts listening and voice in one action', () async {
    final f=CaptureFixture(), player=SpokenPlayer()..holdEnable=Completer<void>();
    final b=binding(f,player);addTearDown(b.dispose);addTearDown(f.c.dispose);
    await b.initialize();expect(f.calls,isEmpty);
    final start=b.startNova();expect(player.enables,1);expect(b.response.spoken.starting,true);
    await b.startNova();expect(player.enables,1);
    await flush();expect(f.calls,contains('start'));expect(b.response.spoken.enabled,false);
    player.holdEnable!.complete();await start;
    expect(b.capture.statusLabel,'Listening');expect(b.response.spoken.enabled,true);
    expect(f.calls.where((x)=>x=='consent').length,1);
    expect(f.calls.where((x)=>x=='start').length,1);
    expect(f.calls,contains('transcript'));expect(player.plays,0);
    await b.stopListening();expect(b.response.spoken.enabled,false);expect(b.capture.statusLabel,'Stopped');
  });
  test('existing listening enables voice without another consent or start', () async {
    final f=CaptureFixture(), b=binding(f,SpokenPlayer());
    addTearDown(b.dispose);addTearDown(f.c.dispose);
    await b.initialize();await b.startListening();final count=f.calls.length;
    await b.startNova();expect(b.response.spoken.enabled,true);
    expect(f.calls.skip(count).where((x)=>['consent','start','bind'].contains(x)),isEmpty);
  });
  test('multiple meetings require a choice; failed consent never enables voice', () async {
    final f=CaptureFixture(), player=SpokenPlayer();
    f.meetings.add({'id':'456','uuid':'second','topic':'Second','is_host':true});
    final b=binding(f,player);addTearDown(b.dispose);addTearDown(f.c.dispose);
    await b.initialize();await b.startNova();expect(player.enables,0);expect(f.calls,isEmpty);
    b.chooseListeningMeeting('second');f.consentCode=403;await b.startNova();
    expect(b.response.spoken.enabled,false);expect(player.ready,false);expect(f.calls, isNot(contains('start')));
  });
  test('choosing another meeting offers a new Start Nova with fresh session consent', () async {
    final f=CaptureFixture(), b=binding(f,SpokenPlayer());
    addTearDown(b.dispose);addTearDown(f.c.dispose);
    await b.initialize();await b.startNova();expect(b.canStartNova,false);
    f.meetings.add({'id':'456','uuid':'second','topic':'Second','is_host':true});
    await b.loadMeetings();b.chooseListeningMeeting('second');expect(b.canStartNova,true);
    final count=f.calls.length;await b.startNova();
    expect(f.calls.skip(count).where((x)=>['stop','bind','consent','start'].contains(x)),
      ['stop','bind','consent','start']);
    expect(b.capture.meetingUuid,'second');expect(b.response.spoken.enabled,true);
  });
  test('fast caption polling stays single-flight and stops accelerating when voice is off', () async {
    final f=CaptureFixture();addTearDown(f.c.dispose);await f.start();
    f.c.fastTranscript=true;f.now=499;await f.c.tick();expect(f.calls, isNot(contains('transcript')));
    f.previewHold=Completer<void>();f.now=500;final poll=f.c.tick();await flush();
    f.now=1000;await f.c.tick();expect(f.calls.where((x)=>x=='transcript').length,1);
    f.previewHold!.complete();await poll;f.previewHold=null;
    f.now=1500;await f.c.tick();expect(f.calls.where((x)=>x=='transcript').length,2);
    f.c.fastTranscript=false;f.now=2000;await f.c.tick();expect(f.calls.where((x)=>x=='transcript').length,2);
  });
  test('Stop or permission change during audio activation cannot arm a late voice', () async {
    for (final stop in [true,false]) {
      final f=SpokenFixture();addTearDown(f.dispose);
      f.player.holdEnable=Completer<void>();final start=f.spoken.enable();await flush();
      if(stop) { f.spoken.stop(); } else { f.capture.binding['authorityRevision']=2;f.capture.changed(); }
      f.player.holdEnable!.complete();await start;expect(f.spoken.enabled,false);
      await f.ask();expect(f.player.plays,0);
    }
  });
  test('finished questions dispatch at 700ms; fragments retain their longer pause', () async {
    final f=SpokenFixture();addTearDown(f.dispose);await f.spoken.enable();
    f.capture.say('Nova, what is next?');f.now=699;await f.spoken.tick();expect(f.calls,isEmpty);
    f.now=700;await f.spoken.tick();expect(f.calls.length,1);
    f.now+=5000;f.capture.say('Nova, help me plan');f.now+=700;await f.spoken.tick();expect(f.calls.length,1);
    f.capture.say('the next meeting');f.now+=1599;await f.spoken.tick();expect(f.calls.length,1);
    f.now++;await f.spoken.tick();expect(f.calls.length,2);expect(f.calls.last['endSequence'],3);
  });
  test('short answers skip waiting speech entirely', () async {
    final f=SpokenFixture(waitingVoice:clips);addTearDown(f.dispose);await f.spoken.enable();await flush();
    await f.ask();f.now+=10000;await f.spoken.tick();
    expect(f.player.plays,1);expect(f.spoken.waitingSpeaking,false);
  });
  test('waiting speech is bounded to one acknowledgment and one follow-up', () async {
    final f=SpokenFixture(waitingVoice:clips);addTearDown(f.dispose);await f.spoken.enable();await flush();
    f.hold=Completer<void>();final reply=f.ask();await flush();
    f.now+=999;await f.spoken.tick();expect(f.player.plays,0);
    f.now++;await f.spoken.tick();await flush();expect(f.player.plays,1);
    f.now+=8000;await f.spoken.tick();await flush();expect(f.player.plays,2);
    f.now+=20000;await f.spoken.tick();expect(f.player.plays,2);
    f.hold!.complete();await reply;expect(f.player.plays,3);
  });
  test('actual answer interrupts waiting audio and never waits for its completion', () async {
    final f=SpokenFixture(player:PriorityPlayer(),waitingVoice:clips);
    // Use the fixture's player to observe the exact shared audio channel.
    final output=f.player as PriorityPlayer;addTearDown(f.dispose);
    await f.spoken.enable();await flush();f.hold=Completer<void>();final reply=f.ask();await flush();
    f.now+=1000;await f.spoken.tick();expect(output.plays,1);expect(f.spoken.waitingSpeaking,true);
    f.hold!.complete();await reply;
    expect(output.interrupts,1);expect(output.plays,2);expect(f.spoken.enabled,true);
    expect(f.spoken.waitingSpeaking,false);expect(f.spoken.message,contains('Reply finished'));
  });
  test('Stop, hide, permission changes and mute cancel chatter and reject late answers', () async {
    for (final action in ['stop','hide','permission','mute']) {
      final f=SpokenFixture(player:PriorityPlayer(),waitingVoice:clips);
      final player=f.player as PriorityPlayer;addTearDown(f.dispose);
      await f.spoken.enable();await flush();f.hold=Completer<void>();final reply=f.ask();await flush();
      f.now+=1000;await f.spoken.tick();expect(player.plays,1);
      switch(action) {
        case 'stop': f.spoken.stop();
        case 'hide': f.spoken.leavePage();
        case 'permission': f.capture.active=false;f.capture.changed();
        case 'mute': f.spoken.setSmallTalk(false);
      }
      expect(player.interrupts,greaterThanOrEqualTo(1));
      f.now+=20000;await f.spoken.tick();expect(player.plays,1);
      f.hold!.complete();await reply;
      expect(player.plays,action=='mute'?2:1);
    }
  });
  test('failed preparation or waiting playback never blocks an answer', () async {
    for(final prepareFails in [true,false]) {
      final player=prepareFails?SpokenPlayer():(PriorityPlayer()..failWaiting=true);
      final f=SpokenFixture(player:player,waitingVoice:prepareFails?() async=>throw StateError('offline'):clips);
      addTearDown(f.dispose);await f.spoken.enable();await flush();
      f.hold=Completer<void>();final reply=f.ask();await flush();
      f.now+=1000;await f.spoken.tick();await flush();
      f.hold!.complete();await reply;expect(f.spoken.enabled,true);expect(f.spoken.answer,contains('Friday'));
    }
  });
  test('late preparation cannot restore chatter after Stop', () async {
    final prepared=Completer<List<K135zWaitingClip>>();
    final f=SpokenFixture(waitingVoice:()=>prepared.future);addTearDown(f.dispose);
    await f.spoken.enable();f.spoken.stop();prepared.complete(await clips());await flush();
    expect(f.spoken.enabled,false);expect(f.player.plays,0);
  });
  test('switching away stops fast caption polling until voice resumes', () async {
    final f=SpokenFixture();addTearDown(f.dispose);await f.spoken.enable();
    expect(f.capture.fastTranscript,true);f.spoken.leavePage();expect(f.capture.fastTranscript,false);
    await f.spoken.returnToPage();expect(f.capture.fastTranscript,true);
  });
  test('small talk off avoids preparation; toggling on coalesces an in-flight warmup', () async {
    var loads=0;final prepared=Completer<List<K135zWaitingClip>>();
    final f=SpokenFixture(waitingVoice:(){loads++;return prepared.future;});addTearDown(f.dispose);
    f.spoken.setSmallTalk(false);await f.spoken.enable();expect(loads,0);
    f.spoken.setSmallTalk(true);expect(loads,1);
    f.spoken.setSmallTalk(false);f.spoken.setSmallTalk(true);expect(loads,1);
    prepared.complete(await clips());await flush();
  });
  test('waiting voice loader rejects foreign context and invalid audio', () async {
    for(final bad in ['context','audio','oversized','valid']) {
      final capture=SpokenCapture(({required String method,required Uri uri,required Map<String,String> headers,Object? body}) async {
        expect(uri.path,endsWith('/waiting-voice'));expect(headers['x-korlix-agent-id'],'agent');
        final b=body as Map;expect(b.keys.toSet(),{'context','enabled'});
        return KorlixZoomTransportResponse(statusCode:200,body:jsonEncode({'ok':true,'waitingVoice':{
          'context':bad=='context'?{...b['context'],'meetingUuid':'other'}:b['context'],
          'clips':List.generate(2,(_)=>{'text':'One moment.','mimeType':'audio/mpeg',
            'audio':base64Encode(bad=='audio'?[1,2,3]:bad=='oversized'?List.filled(120001,0):audio)})}}));
      });addTearDown(capture.dispose);
      final result=await loadK135zWaitingVoice(capture);expect(result.length,bad=='valid'?2:0);
    }
  });
  for(final width in [390.0,1024.0]) {
    testWidgets('Start Nova and stop controls are clear at width $width', (tester) async {
      tester.view.physicalSize=Size(width,900);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final f=CaptureFixture(), b=binding(f,SpokenPlayer());
      await b.initialize();
      await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:Scaffold(body:SingleChildScrollView(
        child:AnimatedBuilder(animation:b,builder:(_,__)=>K135zStartupPanel(binding:b))))));
      expect(find.text('Start Nova').hitTestable(),findsOneWidget);
      expect(find.text('Stop listening').hitTestable(),findsOneWidget);
      expect(find.text('Silence Nova').hitTestable(),findsOneWidget);
      await tester.tap(find.text('Start Nova'));await tester.pumpAndSettle();
      expect(b.response.spoken.enabled,true);expect(find.text('Nova is on'),findsOneWidget);
      await tester.tap(find.text('Silence Nova'));await tester.pumpAndSettle();
      expect(b.response.spoken.enabled,false);expect(b.capture.statusLabel,'Listening');
      expect(find.text('Start Nova').hitTestable(),findsOneWidget);expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox());b.dispose();f.c.dispose();
    });
  }
}
