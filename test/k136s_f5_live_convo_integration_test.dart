// K136S-F5: controller + real microphone guard + routing integration, with fake devices/API.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_character_stage.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/live_convo/k136s_learning_panel.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_test_screen.dart';
import 'k136s_learning_panel_test.dart' as old;

class DelayedApi extends old.FakeApi {
  Completer<K136sApiResult>? grantWait, previewWait, requestWait, confirmWait;
  @override
  Future<K136sApiResult> grant({required String agentId,required String vaultPassword}) =>
    grantWait?.future ?? super.grant(agentId:agentId,vaultPassword:vaultPassword);
  @override
  Future<K136sApiResult> preview({required String agentId,required String proposedText,required String grant}) =>
    previewWait?.future ?? super.preview(agentId:agentId,proposedText:proposedText,grant:grant);
  @override
  Future<K136sApiResult> approveRequest({required String sessionId,required String agentId,required String contentHash,required bool elevated,required String grant}) =>
    requestWait?.future ?? super.approveRequest(sessionId:sessionId,agentId:agentId,contentHash:contentHash,elevated:elevated,grant:grant);
  @override
  Future<K136sApiResult> approveConfirm({required String sessionId,required String agentId,required String contentHash,required String approvalToken,required String channel,required Map<String,dynamic> preview,required String grant}) =>
    confirmWait?.future ?? super.approveConfirm(sessionId:sessionId,agentId:agentId,contentHash:contentHash,approvalToken:approvalToken,channel:channel,preview:preview,grant:grant);
}
class Flow {
  Flow({Future<bool> Function(bool)? mute,Future<K136sRefreshReceipt?> Function()? refresh}) {
    c=K136sLearningController(api:api,agentId:'general',liveSessionId:'live-1',ready:true,principalScope:'user-one',now:()=>now,
      setMuted:mute ?? (_) async => true,
      refreshContext:refresh ?? () async => const K136sRefreshReceipt(agentId:'general',liveSessionId:'live-2',contextRestored:true));
  }
  final DelayedApi api=DelayedApi();
  late final K136sLearningController c;
  DateTime now=DateTime.utc(2026,9,9);
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<void> auth() async {c.onUserTranscript('Nova, learn this');await settle();expect(c.state,K136sLearningState.authRequired);}
  Future<void> capture() async {await auth();await c.submitVaultPassword('fixture-only');expect(c.state,K136sLearningState.capturing);}
  Future<void> preview() async {await capture();c.onUserTranscript('Acme prefers mornings.');await c.endCapture();expect(c.state,K136sLearningState.previewReady);}
  Future<void> approve() async {await preview();await c.requestConfirmation();expect(c.state,K136sLearningState.confirmationRequired);}
  Future<void> verified() async {await approve();await c.confirm(channel:'typed');expect(c.state,K136sLearningState.verified);}
}
void main() {
  _readinessScreenTests();
  test('F5 production screen compiles and binds agent, context, guard, and receipt-based refresh',() {
    expect(KorlixLiveConvoTestScreen,isNotNull);
    final s=File('lib/live_convo/korlix_live_convo_test_screen.dart').readAsStringSync();
    expect(RegExp(r'agentId\s*:\s*_activeAgent\.id').hasMatch(s),isTrue);
    expect(RegExp(r'agentId\s*:\s*widget\.characterId').hasMatch(s),isFalse);
    expect(s,contains('K136sMicrophoneGuard('));expect(s,contains('_k136sRouteTranscript(transcript,itemId.trim())'));
    expect(s,contains('contextRestored:true'));expect(s,contains('_k136sConnectedPeer'));
    expect(s,contains('identical(_k136sContextReadyChannel,_dataChannel)'));
    expect(s,contains('k136sRefreshTicket:ticket'));expect(s,contains('_k136sController?.invalidate()'));
  });
  test('F5 selected agent, not character, is used for every request; switching invalidates pending learning',() async {
    final f=Flow();await f.approve();
    expect(f.api.calls.every((call)=>call.args['agentId']=='general'),isTrue);
    f.c.bindContext(agentId:'custom_nova',liveSessionId:'live-1',ready:true,principalScope:'user-one');
    await f.settle();expect(f.c.state,K136sLearningState.cancelled);expect(f.c.hasGrant,isFalse);
    f.c.reset();await f.capture();expect(f.api.calls.last.args['agentId'],'custom_nova');f.c.dispose();
  });
  test('F5 a delayed grant cannot revive a cancelled operation',() async {
    final f=Flow();await f.auth();f.api.grantWait=Completer<K136sApiResult>();
    final pending=f.c.submitVaultPassword('fixture-only');await f.c.cancel();
    f.api.grantWait!.complete(f.api.grantResult);await pending;
    expect(f.c.state,K136sLearningState.cancelled);expect(f.c.hasGrant,isFalse);f.c.dispose();
  });
  test('F5 timeout while a grant is pending is enforced and late success ignored',() async {
    final f=Flow();await f.auth();f.api.grantWait=Completer<K136sApiResult>();
    final pending=f.c.submitVaultPassword('fixture-only');f.now=f.now.add(const Duration(minutes:3));f.c.tick();
    f.api.grantWait!.complete(f.api.grantResult);await pending;
    expect(f.c.state,K136sLearningState.expired);expect(f.c.hasGrant,isFalse);f.c.dispose();
  });
  test('F5 late preview is discarded after provider-session replacement',() async {
    final f=Flow();await f.capture();f.api.previewWait=Completer<K136sApiResult>();f.c.onUserTranscript('A harmless preference.');
    final pending=f.c.endCapture();
    f.c.bindContext(agentId:'general',liveSessionId:'live-2',ready:true,principalScope:'user-one');
    f.api.previewWait!.complete(old.FakeApi.previewFor('A harmless preference.'));await pending;
    expect(f.c.preview,isNull);expect(f.c.state,K136sLearningState.cancelled);f.c.dispose();
  });
  test('F5 a delayed approval cannot attach to a different signed-in user',() async {
    final f=Flow();await f.preview();f.api.requestWait=Completer<K136sApiResult>();final pending=f.c.requestConfirmation();
    f.c.bindContext(agentId:'general',liveSessionId:'live-1',ready:true,principalScope:'user-two');
    f.api.requestWait!.complete(f.api.approveRequestResult);await pending;await f.c.confirm(channel:'typed');
    expect(f.c.state,K136sLearningState.cancelled);expect(f.api.calls.where((c)=>c.name=='approveConfirm'),isEmpty);f.c.dispose();
  });
  test('F5 cancellation after dispatch reports an unknown result, never undone or verified',() async {
    final f=Flow();await f.approve();f.api.confirmWait=Completer<K136sApiResult>();final pending=f.c.confirm(channel:'typed');
    await f.c.cancel();f.api.confirmWait!.complete(f.api.approveConfirmResult);await pending;
    expect(f.c.state,K136sLearningState.cancelled);expect(f.c.lastCode,'WRITE_OUTCOME_UNKNOWN');expect(f.c.memoryId,isNull);f.c.dispose();
  });
  test('F5 network uncertainty does not automatically retry a consumed approval',() async {
    final f=Flow();await f.approve();f.api.approveConfirmResult=const K136sApiResult(0,{});
    await f.c.confirm(channel:'typed');await f.c.confirm(channel:'typed');
    expect(f.c.lastCode,'WRITE_OUTCOME_UNKNOWN');expect(f.api.calls.where((c)=>c.name=='approveConfirm').length,1);f.c.dispose();
  });
  test('F5 microphone failure or false receipt never opens authentication',() async {
    for(final throws in [false,true]) {
      final f=Flow(mute:(m) async {if(m&&throws) throw StateError('fixture');return !m;});
      f.c.onUserTranscript('Nova learn this');await f.settle();
      expect(f.c.state,K136sLearningState.rejected);expect(f.c.lastCode,'MIC_PROTECTION_FAILED');expect(f.c.micMuted,isFalse);f.c.dispose();
    }
  });
  test('F5 delayed mute and cancellation cannot expose a stale password panel',() async {
    final gate=Completer<bool>();final f=Flow(mute:(m)=>m?gate.future:Future<bool>.value(true));
    f.c.onUserTranscript('Nova learn this');await f.settle();
    expect(f.c.state,K136sLearningState.triggered);final cancelled=f.c.cancel();
    gate.complete(true);await cancelled;await f.settle();
    expect(f.c.state,K136sLearningState.cancelled);expect(f.c.micMuted,isFalse);f.c.dispose();
  });
  test('F5 reauthentication also waits for confirmed mute before displaying password entry',() async {
    final gate=Completer<bool>();var delay=false;
    final f=Flow(mute:(m)=>m&&delay?gate.future:Future<bool>.value(true));
    await f.capture();f.api.previewResult=const K136sApiResult(401,{'code':'EXPIRED'});f.c.onUserTranscript('A preference.');
    delay=true;final pending=f.c.endCapture();await f.settle();expect(f.c.state,K136sLearningState.triggered);
    gate.complete(true);await pending;expect(f.c.state,K136sLearningState.authRequired);expect(f.c.micMuted,isTrue);f.c.dispose();
  });
  test('F5 all audio tracks must be disabled and the original mute state is restored',() async {
    final owner=Object();final enabled=[true,false];
    final guard=K136sMicrophoneGuard(identity:()=>owner,tracks:()=>List<K136sMicTrack>.generate(2,(i)=>K136sMicTrack(
      readEnabled:()=>enabled[i],writeEnabled:(v)=>enabled[i]=v,nativeMute:(_)async{})));
    expect(await guard.setMuted(true),isTrue);expect(enabled,[false,false]);
    expect(await guard.setMuted(false),isTrue);expect(enabled,[true,false]);
  });
  test('F5 missing or uncontrollable tracks fail closed',() async {
    for(final empty in [false,true]) {
      final owner=Object();final guard=K136sMicrophoneGuard(identity:()=>owner,tracks:()=>empty?<K136sMicTrack>[]:[
        K136sMicTrack(readEnabled:()=>true,writeEnabled:(_){},nativeMute:(_)async{})]);
      expect(await guard.setMuted(true),isFalse);
    }
  });
  test('F5 releasing an old microphone lease never enables a replacement stream',() async {
    Object? owner=Object();var oldEnabled=true;var newEnabled=false;
    var current=[K136sMicTrack(readEnabled:()=>oldEnabled,writeEnabled:(v)=>oldEnabled=v,nativeMute:(_)async{})];
    final guard=K136sMicrophoneGuard(identity:()=>owner,tracks:()=>current);
    expect(await guard.setMuted(true),isTrue);owner=Object();
    current=[K136sMicTrack(readEnabled:()=>newEnabled,writeEnabled:(v)=>newEnabled=v,nativeMute:(_)async{})];
    expect(await guard.setMuted(false),isTrue);expect(newEnabled,isFalse);
  });
  test('F5 a current connection and explicit learning trigger are required',() async {
    final f=Flow();f.c.bindContext(agentId:'general',liveSessionId:'live-1',ready:false,principalScope:'user-one');
    await f.settle();f.c.onUserTranscript('Nova learn this');expect(f.c.state,K136sLearningState.idle);expect(f.api.calls,isEmpty);f.c.dispose();
  });
  test('F5 normal email/docs routing is unchanged; one confirmation is never consumed by two workflows',() async {
    final f=Flow();expect(k136sRouteVoiceTurn(f.c,'Confirm',otherWorkflowPending:true),isFalse);
    expect(k136sRouteVoiceTurn(f.c,'Nova learn this',otherWorkflowPending:true),isFalse);
    expect(k136sRouteVoiceTurn(f.c,'Nova learn this',otherWorkflowPending:false),isTrue);await f.settle();
    expect(k136sRouteVoiceTurn(f.c,'confirm',otherWorkflowPending:true),isTrue);expect(f.api.calls,isEmpty);f.c.dispose();
  });
  test('F5 refresh requires a new session, the same agent, and confirmed context restoration',() async {
    for(final receipt in <K136sRefreshReceipt?>[null,
      const K136sRefreshReceipt(agentId:'general',liveSessionId:'live-1',contextRestored:true),
      const K136sRefreshReceipt(agentId:'other',liveSessionId:'live-2',contextRestored:true),
      const K136sRefreshReceipt(agentId:'general',liveSessionId:'live-2',contextRestored:false)]) {
      final f=Flow(refresh:()async=>receipt);await f.verified();await f.c.refreshNovaContext();
      expect(f.c.contextRefreshed,isFalse);expect(f.c.lastCode,'CONTEXT_REFRESH_FAILED');f.c.dispose();
    }
  });
  test('F5 refresh rejects concurrent clicks and ignores success after context change',() async {
    final gate=Completer<K136sRefreshReceipt?>();var count=0;
    final f=Flow(refresh:(){count++;return gate.future;});await f.verified();
    final pending=f.c.refreshNovaContext();await f.c.refreshNovaContext();expect(count,1);
    f.c.bindContext(agentId:'custom_other',liveSessionId:'live-3',ready:true,principalScope:'user-one');
    gate.complete(const K136sRefreshReceipt(agentId:'general',liveSessionId:'live-2',contextRestored:true));await pending;
    expect(f.c.contextRefreshed,isFalse);f.c.dispose();
  });
  test('F5 confirmed refresh adopts its new live-session binding without another save',() async {
    final f=Flow();await f.verified();await f.c.refreshNovaContext();
    expect(f.c.contextRefreshed,isTrue);expect(f.c.liveSessionId,'live-2');
    expect(f.api.calls.where((c)=>c.name=='approveConfirm').length,1);f.c.dispose();
  });
  testWidgets('F5 authentication blocks background controls and context changes remove the private field',(tester)async{
    final f=Flow();var backgroundTaps=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:K136sLearningOverlay(controller:f.c,
      child:SizedBox.expand(child:Align(alignment:Alignment.topCenter,child:TextButton(
        key:const Key('background-control'),onPressed:()=>backgroundTaps++,child:const Text('Background control'))))))));
    f.c.onUserTranscript('Nova learn this');await tester.pump();await tester.pump();
    expect(find.byKey(const Key('k136s_vault_password')),findsOneWidget);
    await tester.tap(find.byKey(const Key('background-control')),warnIfMissed:false);expect(backgroundTaps,0);
    await tester.enterText(find.byKey(const Key('k136s_vault_password')),'fixture-only');
    f.c.invalidate();await tester.pump();await tester.pump();
    expect(find.byKey(const Key('k136s_vault_password')),findsNothing);
    await tester.pumpWidget(const SizedBox());f.c.dispose();
  });
}

// The following regressions mount the production screen and use its actual Start,
// Pause/Resume, cleanup, RTC callbacks and learning overlay. Only I/O is faked.
// Diagnostic-only: expose missing fake members without supplying a result.
class _ReadinessObservedFake extends Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    debugPrint('F5_MISSING_FAKE_MEMBER=$runtimeType:${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _ReadinessTrack extends _ReadinessObservedFake implements rtc.MediaStreamTrack {
  @override
  bool enabled = true;
  int stops = 0;
  @override
  String get id => 'fixture-audio';
  @override
  String get kind => 'audio';
  @override
  Future<void> stop() async { enabled = false; stops++; }
}

class _ReadinessStream extends _ReadinessObservedFake implements rtc.MediaStream {
  final audio = _ReadinessTrack();
  int disposals = 0;
  @override
  List<rtc.MediaStreamTrack> getAudioTracks() => [audio];
  @override
  List<rtc.MediaStreamTrack> getTracks() => [audio];
  @override
  Future<void> dispose() async { disposals++; }
}

class _ReadinessChannel extends _ReadinessObservedFake implements rtc.RTCDataChannel {
  @override
  rtc.RTCDataChannelState state = rtc.RTCDataChannelState.RTCDataChannelConnecting;
  @override
  dynamic Function(rtc.RTCDataChannelState)? onDataChannelState;
  @override
  dynamic Function(rtc.RTCDataChannelMessage)? onMessage;
  int closes = 0;
  void open() {
    state = rtc.RTCDataChannelState.RTCDataChannelOpen;
    onDataChannelState?.call(state);
  }
  void transcript(String text, String id) {
    onMessage?.call(rtc.RTCDataChannelMessage(jsonEncode({
      'type': 'conversation.item.input_audio_transcription.completed',
      'transcript': text, 'item_id': id,
    })));
  }
  @override
  Future<void> send(rtc.RTCDataChannelMessage message) async {}
  @override
  Future<void> close() async {
    closes++;
    state = rtc.RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(state);
  }
}

class _ReadinessSender extends _ReadinessObservedFake implements rtc.RTCRtpSender {}

class _ReadinessPeer extends _ReadinessObservedFake implements rtc.RTCPeerConnection {
  final channel = _ReadinessChannel();
  Completer<void>? answerGate;
  int closes = 0, disposals = 0, answers = 0;
  @override
  dynamic Function(rtc.RTCPeerConnectionState)? onConnectionState;
  @override
  dynamic Function(rtc.RTCIceConnectionState)? onIceConnectionState;
  @override
  dynamic Function(rtc.RTCIceGatheringState)? onIceGatheringState;
  @override
  dynamic Function(rtc.MediaStream)? onAddStream;
  @override
  dynamic Function(rtc.RTCTrackEvent)? onTrack;
  void connected() => onConnectionState?.call(rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected);
  void disconnected() => onConnectionState?.call(rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
  @override
  Future<rtc.RTCRtpSender> addTrack(rtc.MediaStreamTrack track, [rtc.MediaStream? stream]) async => _ReadinessSender();
  @override
  Future<rtc.RTCDataChannel> createDataChannel(String label, rtc.RTCDataChannelInit dataChannelDict) async => channel;
  @override
  Future<rtc.RTCSessionDescription> createOffer([Map<String, dynamic>? constraints]) async => rtc.RTCSessionDescription('v=0\r\n', 'offer');
  @override
  Future<void> setLocalDescription(rtc.RTCSessionDescription description) async {}
  @override
  Future<rtc.RTCIceGatheringState?> getIceGatheringState() async => rtc.RTCIceGatheringState.RTCIceGatheringStateComplete;
  @override
  Future<rtc.RTCSessionDescription?> getLocalDescription() async => rtc.RTCSessionDescription('v=0\r\n', 'offer');
  @override
  Future<void> setRemoteDescription(rtc.RTCSessionDescription description) async {
    answers++;
    connected();
    channel.open();
    if (answerGate != null) await answerGate!.future;
  }
  @override
  Future<void> close() async { closes++; }
  @override
  Future<void> dispose() async { disposals++; }
}

class _ReadinessIo extends K136sLiveConvoIo {
  final callbackFailures = <String>[];
  void expectCallback(Object? actual, Object? matcher) {
    try {
      // Device/network callbacks can run while WidgetTester.pump is active.
      expectSync(actual, matcher);
    } catch (error) {
      // Application error handling must not hide a fixture-contract failure.
      callbackFailures.add(error.toString());
      rethrow;
    }
  }
  final peers = <_ReadinessPeer>[];
  final streams = <_ReadinessStream>[];
  Completer<rtc.RTCPeerConnection>? peerGate;
  Completer<rtc.MediaStream>? micGate;
  Completer<void>? answerGate;
  Completer<http.Response>? responseGate;
  final requests = <http.Request>[];
  bool rejectSession = false;
  String principal = 'Bearer fixture';
  String character = 'yuna';
  @override
  Future<void> initializeRenderer(rtc.RTCVideoRenderer renderer) async {}
  @override
  void clearRenderer(rtc.RTCVideoRenderer renderer) {}
  @override
  Future<void> disposeRenderer(rtc.RTCVideoRenderer renderer) async {}
  @override
  Future<void> muteNative(bool muted, rtc.MediaStreamTrack track) async {}
  @override
  Future<void> prepareAudio() async {}
  @override
  Future<void> configureAudio() async {}
  @override
  Future<void> clearAudio() async {}
  @override
  Future<rtc.RTCPeerConnection> createPeer(Map<String, dynamic> configuration) {
    final pending = peerGate;
    peerGate = null;
    if (pending != null) return pending.future;
    final peer = _ReadinessPeer()..answerGate = answerGate;
    answerGate = null;
    peers.add(peer);
    return Future<rtc.RTCPeerConnection>.value(peer);
  }
  @override
  Future<rtc.MediaStream> microphone(Map<String, dynamic> constraints) {
    final pending = micGate;
    micGate = null;
    if (pending != null) return pending.future;
    final stream = _ReadinessStream();
    streams.add(stream);
    return Future<rtc.MediaStream>.value(stream);
  }
  http.Response response(http.Request request) => http.Response(
    rejectSession ? 'fixture connection refused' : 'v=0\r\n',
    rejectSession ? 503 : 200,
    request: request,
    headers: {
      'x-korlix-live-convo-session-id': 'fixture-${requests.length}',
      'x-korlix-live-convo-max-seconds': '600',
      'x-korlix-live-convo-max-responses': '100',
    },
  );
  @override
  Future<http.Response> connect(Uri uri, Map<String, String> headers, String sdp) {
    expectCallback(uri.host, 'k136s.invalid');
    final request = http.Request('POST', uri)..headers.addAll(headers)..body = sdp;
    requests.add(request);
    final pending = responseGate;
    responseGate = null;
    return pending?.future ?? Future<http.Response>.value(response(request));
  }
}

KorlixLiveConvoCharacterStage _stage(WidgetTester tester) =>
    tester.widget<KorlixLiveConvoCharacterStage>(find.byType(KorlixLiveConvoCharacterStage));
K136sLearningController _screenController(WidgetTester tester) =>
    tester.widget<K136sLearningOverlay>(find.byType(K136sLearningOverlay)).controller!;
Future<void> _screenAction(WidgetTester tester, {bool pause = false}) async {
  // The stage's callback may be declared void; its actual screen callback is async.
  final dynamic stage = _stage(tester);
  if (pause) { await stage.onTogglePause(); } else { await stage.onStart(); }
}
Future<void> _pumpSteps(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) { await tester.pump(const Duration(milliseconds: 50)); }
}
Future<void> _finishAction(WidgetTester tester, Future<void> action) async {
  var done = false;
  final result = action.whenComplete(() { done = true; });
  for (var i = 0; i < 100 && !done; i++) { await tester.pump(const Duration(milliseconds: 25)); }
  expect(done, isTrue, reason: 'Actual screen lifecycle did not complete within fixture time.');
  await result;
}
Widget _readinessApp(_ReadinessIo io) => MaterialApp(home: Scaffold(body:
    KorlixLiveConvoTestScreen(key: const Key('readiness-screen'),
      backendBaseUrl: 'https://k136s.invalid', headersBuilder: () => {'Authorization': io.principal},
      characterId: io.character, language: 'en', k136sIo: io)));
Future<void> _withScreen(WidgetTester tester, Future<void> Function(_ReadinessIo io) body) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final io = _ReadinessIo();
  await http.runWithClient(() async {
    await tester.pumpWidget(_readinessApp(io));
    await _pumpSteps(tester, 2);
    try {
      await body(io);
    } catch (error, stack) {
      // Capture the screen BEFORE teardown, then preserve the original failure.
      final matches = find.byType(KorlixLiveConvoCharacterStage);
      final observation = <String, Object?>{
        'failureType': error.runtimeType.toString(),
        'sessionRequests': io.requests.length,
        'peersCreated': io.peers.length,
        'peerAnswers': io.peers.map((p) => p.answers).toList(),
        'peerCloses': io.peers.map((p) => p.closes).toList(),
        'streamsCreated': io.streams.length,
        'audioEnabled': io.streams.map((s) => s.audio.enabled).toList(),
      };
      if (matches.evaluate().length == 1) {
        final dynamic stage = tester.widget(matches);
        String inspect(Object? Function() getter) {
          try { return '${getter()}'; }
          catch (failure) { return 'UNAVAILABLE:${failure.runtimeType}'; }
        }
        observation.addAll(<String, Object?>{
          'status': inspect(() => stage.status),
          'startupError': inspect(() => stage.error),
          'connecting': inspect(() => stage.connecting),
          'connected': inspect(() => stage.connected),
          'paused': inspect(() => stage.paused),
          'events': inspect(() => stage.eventLog),
        });
      }
      debugPrint('F5_STARTUP_OBSERVATION=${jsonEncode(observation)}');
      Error.throwWithStackTrace(error, stack);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpSteps(tester);
    }
  }, () => MockClient((request) async {
    io.expectCallback(request.url.host, 'k136s.invalid');
    io.expectCallback(request.url.path, '/api/live-convo/usage');
    return http.Response('{"allowed":true}', 200);
  }));
  expect(tester.takeException(), isNull);
  expect(io.callbackFailures, isEmpty,
      reason: 'No callback assertion may be swallowed by screen error handling.');
}

void _readinessScreenTests() {
  testWidgets('F5 readiness fixture: callback checks work during pumping and retain failures', (tester) async {
    final io = _ReadinessIo();
    var checked = false;
    final callback = Future<void>.microtask(() {
      io.expectCallback('k136s.invalid', 'k136s.invalid');
      checked = true;
    });
    await tester.pump();
    await callback;
    expect(checked, isTrue);
    expect(io.callbackFailures, isEmpty);
    expect(() => io.expectCallback('unexpected.invalid', 'k136s.invalid'),
        throwsA(isA<TestFailure>()));
    expect(io.callbackFailures, hasLength(1));
  });
  testWidgets('F5 readiness actual screen: startup cleanup then accepted connection opens protected vault', (tester) async {
    await _withScreen(tester, (io) async {
      final answer = Completer<void>();
      io.answerGate = answer;
      final started = _screenAction(tester);
      await _pumpSteps(tester);
      expect(io.peers.single.answers, 1);
      io.peers.single.channel.transcript('Nova learn this', 'too-early');
      await _pumpSteps(tester, 2);
      expect(_screenController(tester).state, K136sLearningState.idle);
      answer.complete();
      await _finishAction(tester, started);
      io.peers.single.channel.transcript('Nova learn this', 'valid-trigger');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsOneWidget);
      expect(io.streams.single.audio.enabled, isFalse);
      expect(_screenController(tester).micMuted, isTrue);
    });
  });
  testWidgets('F5 readiness actual screen: disconnect invalidates learning and reconnect requires a new trigger', (tester) async {
    await _withScreen(tester, (io) async {
      await _finishAction(tester, _screenAction(tester));
      final peer = io.peers.single;
      peer.channel.transcript('Nova learn this', 'before-disconnect');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsOneWidget);
      peer.disconnected();
      await _pumpSteps(tester, 2);
      expect(_screenController(tester).state, K136sLearningState.cancelled);
      expect(find.byKey(const Key('k136s_vault_password')), findsNothing);
      _screenController(tester).reset();
      peer.channel.transcript('Nova learn this', 'while-disconnected');
      await _pumpSteps(tester, 2);
      expect(_screenController(tester).state, K136sLearningState.idle);
      peer.connected();
      await _pumpSteps(tester, 2);
      peer.channel.transcript('Nova learn this', 'after-reconnect');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsOneWidget);
    });
  });
  testWidgets('F5 readiness actual screen: pause replacement ignores old connection and transcript callbacks', (tester) async {
    await _withScreen(tester, (io) async {
      await _finishAction(tester, _screenAction(tester));
      final oldPeer = io.peers.single;
      await _finishAction(tester, _screenAction(tester, pause: true));
      await _finishAction(tester, _screenAction(tester, pause: true));
      final newPeer = io.peers.last;
      expect(identical(oldPeer, newPeer), isFalse);
      oldPeer.connected();
      oldPeer.channel.transcript('Nova learn this', 'obsolete-transcript');
      oldPeer.disconnected();
      await _pumpSteps(tester, 2);
      expect(_stage(tester).connected, isTrue);
      expect(_screenController(tester).state, K136sLearningState.idle);
      newPeer.channel.transcript('Nova learn this', 'current-transcript');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsOneWidget);
    });
  });
  testWidgets('F5 readiness actual screen: delayed peer creation cannot replace or tear down a newer session', (tester) async {
    await _withScreen(tester, (io) async {
      final pendingPeer = Completer<rtc.RTCPeerConnection>();
      io.peerGate = pendingPeer;
      final first = _screenAction(tester);
      await _pumpSteps(tester, 2);
      expect(_stage(tester).connecting, isTrue);
      await _finishAction(tester, _screenAction(tester, pause: true));
      await _finishAction(tester, _screenAction(tester, pause: true));
      final obsolete = _ReadinessPeer();
      pendingPeer.complete(obsolete);
      await _finishAction(tester, first);
      expect(obsolete.closes, 1);
      expect(obsolete.disposals, 1);
      expect(io.peers.single.closes, 0);
      expect(_stage(tester).connected, isTrue);
      io.peers.single.channel.transcript('Nova learn this', 'after-stale-peer');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsOneWidget);
    });
  });
  testWidgets('F5 readiness actual screen: delayed SDP response is ignored after session replacement', (tester) async {
    await _withScreen(tester, (io) async {
      final pendingResponse = Completer<http.Response>();
      io.responseGate = pendingResponse;
      final first = _screenAction(tester);
      await _pumpSteps(tester, 2);
      expect(io.requests.length, 1);
      final oldPeer = io.peers.single;
      final oldRequest = io.requests.single;
      await _finishAction(tester, _screenAction(tester, pause: true));
      await _finishAction(tester, _screenAction(tester, pause: true));
      pendingResponse.complete(io.response(oldRequest));
      await _finishAction(tester, first);
      expect(oldPeer.answers, 0);
      expect(io.peers.last.closes, 0);
      expect(_stage(tester).connected, isTrue);
      io.peers.last.channel.transcript('Nova learn this', 'after-stale-answer');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsOneWidget);
    });
  });
  testWidgets('F5 readiness actual screen: account or widget context changes cannot revive the old session', (tester) async {
    await _withScreen(tester, (io) async {
      await _finishAction(tester, _screenAction(tester));
      expect(_stage(tester).connected, isTrue,
          reason: 'Account-change protection must be tested from a connected session.');
      final peer = io.peers.single;
      io.principal = 'Bearer other-fixture';
      await tester.pumpWidget(_readinessApp(io));
      await _pumpSteps(tester, 2);
      io.principal = 'Bearer fixture';
      await tester.pumpWidget(_readinessApp(io));
      peer.connected();
      peer.channel.transcript('Nova learn this', 'stale-account');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsNothing);
      io.character = 'jj';
      await tester.pumpWidget(_readinessApp(io));
      peer.channel.transcript('Nova learn this', 'stale-character');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsNothing);
    });
  });
  testWidgets('F5 readiness actual screen: failed startup stays disabled and a fresh connection can recover', (tester) async {
    await _withScreen(tester, (io) async {
      io.rejectSession = true;
      await _finishAction(tester, _screenAction(tester));
      expect(_stage(tester).connected, isFalse);
      final failedPeer = io.peers.single;
      failedPeer.connected();
      failedPeer.channel.transcript('Nova learn this', 'failed-start');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsNothing);
      io.rejectSession = false;
      await _finishAction(tester, _screenAction(tester));
      io.peers.last.channel.transcript('Nova learn this', 'recovered-start');
      await _pumpSteps(tester, 2);
      expect(find.byKey(const Key('k136s_vault_password')), findsOneWidget);
    });
  });
  testWidgets('F5 readiness actual screen: disposal stops late microphone resources without reopening the screen', (tester) async {
    await _withScreen(tester, (io) async {
      final pendingMicrophone = Completer<rtc.MediaStream>();
      io.micGate = pendingMicrophone;
      final starting = _screenAction(tester);
      await _pumpSteps(tester, 2);
      expect(io.peers.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpSteps(tester, 2);
      final obsoleteStream = _ReadinessStream();
      pendingMicrophone.complete(obsoleteStream);
      await _finishAction(tester, starting);
      expect(obsoleteStream.audio.stops, 1);
      expect(obsoleteStream.disposals, 1);
      expect(find.byType(KorlixLiveConvoTestScreen), findsNothing);
    });
  });
}
