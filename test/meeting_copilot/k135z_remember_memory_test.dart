import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/live_convo/k136s_learning_panel.dart';
import '../../lib/meeting_copilot/k135z_remember_memory.dart';
import '../../lib/meeting_copilot/k135z_spoken_panel.dart';
import 'k135z_spoken_replies_test.dart' show SpokenFixture;

class MemoryApi extends K136sLearningApiBase {
  final calls = <String>[];
  final confirmations = <Map>[];
  String? draft;
  int grantStatus = 200;
  bool allowed = true, wrongAgent = false, malformed = false;
  Completer<void>? holdApproval, holdConfirm;
  K136sApiResult? result;
  static final hash = 'a' * 64;
  @override Future<K136sApiResult> grant({required String agentId, required String vaultPassword}) async {
    calls.add('grant');
    return K136sApiResult(grantStatus, {'grant':'private-grant','agentId':wrongAgent ? 'other' : agentId});
  }
  @override Future<K136sApiResult> preview({required String agentId, required String proposedText, required String grant}) async {
    calls.add('preview'); draft = proposedText;
    return K136sApiResult(200, {'normalizedText':proposedText,'contentHash':malformed ? 'bad' : hash,
      'classification':{'type':'MEMORY','category':'fact','sensitivity':'low','expiresAt':null},
      'policy':{'allowed':allowed,'elevated':false,'requiresQueue':false,'allowedChannels':['typed']},'diff':{}});
  }
  @override Future<K136sApiResult> approveRequest({required String sessionId, required String agentId,
    required String contentHash, required bool elevated, required String grant}) async {
    calls.add('approval'); if (holdApproval != null) await holdApproval!.future;
    return const K136sApiResult(200, {'approvalToken':'one-use'});
  }
  @override Future<K136sApiResult> approveConfirm({required String sessionId, required String agentId,
    required String contentHash, required String approvalToken, required String channel,
    required Map<String,dynamic> preview, required String grant}) async {
    calls.add('confirm'); confirmations.add({'agent':agentId,'text':preview['normalizedText'],'channel':channel});
    if (holdConfirm != null) await holdConfirm!.future;
    return result ?? K136sApiResult(200, {'state':'VERIFIED','contentHash':contentHash,
      'memoryId':'saved-id','memoryKey':'k136s:memory:fact:test'});
  }
}
void main() {
  late MemoryApi api;
  late K135zRememberMemory memory;
  String? binding;
  late DateTime now;
  setUp(() {
    api = MemoryApi(); binding = 'meeting-1'; now = DateTime.utc(2026,9,20);
    memory = K135zRememberMemory(api:api, agentId:'nova', currentBinding:() => binding, now:() => now);
  });
  tearDown(() => memory.dispose());
  Future<void> prepared() async { memory.propose('Launch is October 15.','NOVA'); await memory.prepare('typed-secret'); }
  test('proposal cannot save until vault preview and explicit owner confirmation', () async {
    memory.propose('Launch is October 15.','NOVA'); await memory.save(); expect(api.calls,isEmpty);
    await memory.prepare(''); expect(api.calls,isEmpty);
    await memory.prepare('typed-secret'); expect(api.calls,['grant','preview']); expect(memory.phase,'preview');
    await memory.save(); expect(api.calls,['grant','preview','approval','confirm']);
    expect(api.confirmations.single,{'agent':'nova','text':'Launch is October 15.','channel':'typed'});
    expect(memory.phase,'saved'); expect(memory.message,contains('verified'));
    await memory.save(); expect(api.confirmations,hasLength(1));
  });
  test('edits require a new preview and an expired vault requires unlock', () async {
    await prepared(); memory.edit('Launch is October 20.'); await memory.save();
    expect(api.confirmations,isEmpty); await memory.prepare(''); expect(api.draft,contains('20'));
    now = now.add(const Duration(seconds:51)); await memory.save();
    expect(api.confirmations,isEmpty); expect(memory.phase,'editing'); expect(memory.needsUnlock,true);
    await memory.prepare('typed-again'); await memory.save(); expect(api.confirmations.single['text'],contains('20'));
  });
  test('wrong password, wrong agent, denied policy, or malformed preview cannot save', () async {
    for (final mode in ['password','agent','policy','malformed']) {
      memory.cancel(); api.grantStatus = mode == 'password' ? 401 : 200;
      api.wrongAgent = mode == 'agent'; api.allowed = mode != 'policy'; api.malformed = mode == 'malformed';
      await prepared(); await memory.save(); expect(api.confirmations,isEmpty);
    }
  });
  test('double tap saves once; context change during approval prevents commit', () async {
    await prepared(); api.holdApproval = Completer<void>(); final pending = memory.save();
    await memory.save(); binding = 'another-meeting'; memory.checkContext();
    api.holdApproval!.complete(); await pending; expect(api.calls.where((x) => x == 'approval'),hasLength(1));
    expect(api.confirmations,isEmpty); expect(memory.visible,false);
  });
  test('late success after cancellation is never presented as saved', () async {
    await prepared(); api.holdConfirm = Completer<void>(); final pending = memory.save();
    await Future<void>.delayed(Duration.zero); memory.cancel();
    api.holdConfirm!.complete(); await pending;
    expect(memory.phase,'unconfirmed'); expect(memory.message,contains('Check Agent Hub'));
  });
  test('network failure or mismatched receipt never claims successful saving or retries', () async {
    for (final r in [const K136sApiResult(0,{}), const K136sApiResult(200,{'state':'VERIFIED'})]) {
      memory.cancel(); api.result = r; await prepared(); await memory.save();
      expect(memory.phase,'unconfirmed'); final count = api.confirmations.length;
      await memory.save(); expect(api.confirmations,hasLength(count));
    }
  });
  test('draft expires and a bare remember request must supply a fact', () async {
    memory.propose('','NOVA'); await memory.prepare('typed-secret'); expect(api.calls,isEmpty);
    now = now.add(const Duration(minutes:10)); memory.checkContext(); expect(memory.visible,false);
  });
  test('spoken proposal opens review; voice confirmation and repeated captions cannot write', () async {
    final f = SpokenFixture(learningApi:api); addTearDown(f.dispose);
    f.agent = {'id':'agent','name':'NOVA','memoryEnabled':true,'memoryCount':34};
    f.memoryRequest = {'text':'Launch is October 15.'};
    await f.spoken.enable(); await f.ask('Nova, remember this: Launch is October 15.');
    expect(f.spoken.memory.text,'Launch is October 15.'); expect(api.calls,isEmpty);
    f.capture.changed(); f.now += 9000; await f.ask('Nova, confirm');
    expect(f.calls,hasLength(1)); expect(api.calls,isEmpty);
    f.spoken.leavePage(); expect(f.spoken.memory.visible,false);
  });
  testWidgets('owner can unlock, review and save in the meeting; next proposal has fresh text', (tester) async {
    final f = SpokenFixture(learningApi:api); addTearDown(f.dispose);
    f.agent = {'id':'agent','name':'NOVA','memoryEnabled':true,'memoryCount':34};
    f.memoryRequest = {'text':'Launch is October 15.'};
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:K135zSpokenPanel(spoken:f.spoken)))));
    await f.spoken.enable(); await f.ask('Nova, remember this: Launch is October 15.'); await tester.pump();
    final password = find.byKey(const Key('nova-memory-password'));
    expect(tester.widget<TextField>(password).obscureText,true);
    await tester.enterText(password,'typed-secret');
    await tester.ensureVisible(find.byKey(const Key('nova-memory-preview')));
    await tester.tap(find.byKey(const Key('nova-memory-preview'))); await tester.pumpAndSettle();
    expect(api.calls,['grant','preview']);
    await tester.ensureVisible(find.byKey(const Key('nova-memory-save')));
    await tester.tap(find.byKey(const Key('nova-memory-save'))); await tester.pumpAndSettle();
    expect(f.spoken.memory.phase,'saved'); expect(api.confirmations.single['agent'],'agent');
    f.spoken.memory.propose('A different fact.','NOVA'); await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('nova-memory-text'))).controller!.text,'A different fact.');
    f.spoken.stop(); await tester.pumpAndSettle(); expect(find.byKey(const Key('nova-memory-password')),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
