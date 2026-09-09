// K136S-F5: controller + real microphone guard + routing integration, with fake devices/API.
import 'dart:async';
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
