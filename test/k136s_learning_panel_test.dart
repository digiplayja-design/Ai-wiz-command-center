// K136S-F2 tests — controller transitions against a fake API, plus overlay/panel widget smoke tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wiz_command_center/live_convo/k136s_learning_panel.dart';

class ApiCall {
  ApiCall(this.name, this.args);
  final String name;
  final Map<String, dynamic> args;
}

class FakeApi extends K136sLearningApiBase {
  final List<ApiCall> calls = <ApiCall>[];
  K136sApiResult grantResult = const K136sApiResult(200, <String, dynamic>{'grant': 'g-1', 'passwordVersion': 3});
  K136sApiResult? previewResult;
  K136sApiResult approveRequestResult =
      const K136sApiResult(200, <String, dynamic>{'approvalToken': 'tok-1', 'approvalId': 'ap-1', 'elevated': false});
  K136sApiResult approveConfirmResult =
      const K136sApiResult(200, <String, dynamic>{'state': 'VERIFIED', 'memoryId': 'm-1', 'memoryKey': 'k136s:memory:preference:abc'});
  bool closed = false;

  static K136sApiResult previewFor(String text, {String type = 'MEMORY', String? category = 'preference', bool allowed = true, bool elevated = false, bool requiresQueue = false, List<String> violations = const <String>[]}) {
    return K136sApiResult(200, <String, dynamic>{
      'normalizedText': text,
      'contentHash': 'hash-${text.hashCode}',
      'classification': <String, dynamic>{'type': type, 'category': category, 'sensitivity': elevated ? 'medium' : 'low', 'expiresAt': null},
      'policy': <String, dynamic>{
        'allowed': allowed,
        'elevated': elevated,
        'requiresQueue': requiresQueue,
        'allowedChannels': elevated ? <String>['typed'] : <String>['voice', 'typed'],
        'violations': violations.map((String v) => <String, dynamic>{'code': v}).toList(),
      },
      'diff': <String, dynamic>{
        'changed': true,
        'ops': <Map<String, dynamic>>[<String, dynamic>{'op': 'insert', 'text': text}],
      },
    });
  }

  @override
  Future<K136sApiResult> grant({required String agentId, required String vaultPassword}) async {
    calls.add(ApiCall('grant', <String, dynamic>{'agentId': agentId, 'vaultPassword': vaultPassword}));
    return grantResult;
  }

  @override
  Future<K136sApiResult> preview({required String agentId, required String proposedText, required String grant}) async {
    calls.add(ApiCall('preview', <String, dynamic>{'agentId': agentId, 'proposedText': proposedText, 'grant': grant}));
    return previewResult ?? previewFor(proposedText);
  }

  @override
  Future<K136sApiResult> approveRequest({required String sessionId, required String agentId, required String contentHash, required bool elevated, required String grant}) async {
    calls.add(ApiCall('approveRequest', <String, dynamic>{'sessionId': sessionId, 'agentId': agentId, 'contentHash': contentHash, 'elevated': elevated, 'grant': grant}));
    return approveRequestResult;
  }

  @override
  Future<K136sApiResult> approveConfirm({required String sessionId, required String agentId, required String contentHash, required String approvalToken, required String channel, required Map<String, dynamic> preview, required String grant}) async {
    calls.add(ApiCall('approveConfirm', <String, dynamic>{'sessionId': sessionId, 'agentId': agentId, 'contentHash': contentHash, 'approvalToken': approvalToken, 'channel': channel, 'preview': preview, 'grant': grant}));
    return approveConfirmResult;
  }

  @override
  void close() {
    closed = true;
  }
}

class Harness {
  Harness({FakeApi? api}) : api = api ?? FakeApi() {
    controller = K136sLearningController(
      api: this.api,
      agentId: 'agent-1',
      setMuted: (bool m) async => muteCalls.add(m),
      refreshContext: () async => refreshCalls++,
      now: () => now,
    );
  }
  final FakeApi api;
  late final K136sLearningController controller;
  final List<bool> muteCalls = <bool>[];
  int refreshCalls = 0;
  DateTime now = DateTime.utc(2026, 9, 6, 12);
  void advance(Duration d) => now = now.add(d);

  Future<void> pump() async => Future<void>.delayed(Duration.zero);

  /// idle → trigger → typed vault → capturing
  Future<void> toCapturing() async {
    controller.onUserTranscript('Nova, learn this');
    await pump();
    expect(controller.state, K136sLearningState.authRequired);
    await controller.submitVaultPassword('correct-horse');
    expect(controller.state, K136sLearningState.capturing);
  }

  Future<void> toPreview(String text) async {
    await toCapturing();
    controller.onUserTranscript(text);
    await controller.endCapture();
    expect(controller.state, K136sLearningState.previewReady);
  }

  Future<void> toConfirmation(String text) async {
    await toPreview(text);
    await controller.requestConfirmation();
    expect(controller.state, K136sLearningState.confirmationRequired);
  }
}

void main() {
  group('K136sLearningController', () {
    test('trigger phrase in user speech mutes the mic and shows the vault; unrelated speech is ignored', () async {
      final h = Harness();
      h.controller.onUserTranscript('so the invoice went out yesterday');
      expect(h.controller.state, K136sLearningState.idle);
      h.controller.onUserTranscript('Nova, learn this.');
      expect(h.controller.state, K136sLearningState.triggered);
      await h.pump();
      expect(h.controller.state, K136sLearningState.authRequired);
      expect(h.muteCalls, <bool>[true]);
      expect(h.controller.sessionId, isNotNull);
      expect(h.controller.isVisible, isTrue);
    });

    test('typed vault password: success unmutes and starts capturing; the password is forwarded once and not retained', () async {
      final h = Harness();
      await h.toCapturing();
      expect(h.muteCalls, <bool>[true, false]);
      expect(h.api.calls.where((ApiCall c) => c.name == 'grant').length, 1);
      expect(h.api.calls.first.args['vaultPassword'], 'correct-horse');
      expect(h.controller.passwordVersion, 3);
      expect(h.controller.hasGrant, isTrue);
      // nothing on the controller exposes the password
      expect(h.controller.toString().contains('correct-horse'), isFalse);
    });

    test('vault refusals keep the field up with the backend code: 401 incorrect, 429 locked, 409 not configured', () async {
      final h = Harness();
      h.controller.onUserTranscript('nova learn this');
      await h.pump();
      h.api.grantResult = const K136sApiResult(401, <String, dynamic>{'code': 'brain_vault_password_incorrect'});
      await h.controller.submitVaultPassword('wrong');
      expect(h.controller.state, K136sLearningState.authRequired);
      expect(h.controller.lastCode, 'brain_vault_password_incorrect');
      h.api.grantResult = const K136sApiResult(429, <String, dynamic>{'code': 'brain_vault_password_rate_limited', 'lockedUntil': 'later'});
      await h.controller.submitVaultPassword('wrong-again');
      expect(h.controller.lastCode, 'brain_vault_password_rate_limited');
      h.api.grantResult = const K136sApiResult(409, <String, dynamic>{'code': 'brain_vault_password_not_configured'});
      await h.controller.submitVaultPassword('x');
      expect(h.controller.lastCode, 'brain_vault_password_not_configured');
      expect(h.controller.hasGrant, isFalse);
      await h.controller.submitVaultPassword('');
      expect(h.controller.lastCode, 'PASSWORD_REQUIRED');
    });

    test('capture accumulates user speech; an end phrase is stripped and triggers the preview', () async {
      final h = Harness();
      await h.toCapturing();
      h.controller.onUserTranscript('Acme prefers morning calls');
      h.controller.onUserTranscript('and always confirm the callback number');
      expect(h.controller.capturedText, 'Acme prefers morning calls and always confirm the callback number');
      h.controller.onUserTranscript("that's all");
      await h.pump();
      await h.pump();
      expect(h.controller.state, K136sLearningState.previewReady);
      final preview = h.api.calls.firstWhere((ApiCall c) => c.name == 'preview');
      expect(preview.args['proposedText'], 'Acme prefers morning calls and always confirm the callback number');
      expect(preview.args['grant'], 'g-1');
      expect(h.controller.preview!.contentHash, isNotEmpty);
    });

    test('Done with nothing captured is refused; the capture limit is enforced', () async {
      final h = Harness();
      await h.toCapturing();
      await h.controller.endCapture();
      expect(h.controller.state, K136sLearningState.capturing);
      expect(h.controller.lastCode, 'EMPTY_CAPTURE');
      h.controller.onUserTranscript('x' * 3999);
      h.controller.onUserTranscript('more words here');
      expect(h.controller.lastCode, 'CAPTURE_LIMIT');
      expect(h.controller.capturedText.length, 3999);
    });

    test('policy-denied preview ends in REJECTED with the violation and unmutes', () async {
      final h = Harness();
      await h.toCapturing();
      h.api.previewResult = FakeApi.previewFor('Remember the client password is hunter2.', type: 'PROHIBITED', allowed: false, violations: <String>['PROHIBITED_TYPE']);
      h.controller.onUserTranscript('remember the client password is hunter2');
      await h.controller.endCapture();
      expect(h.controller.state, K136sLearningState.rejected);
      expect(h.controller.lastCode, 'PROHIBITED_TYPE');
      expect(h.muteCalls.last, isFalse);
    });

    test('approval request binds session + agent + contentHash + elevated flag and moves to confirmation', () async {
      final h = Harness();
      await h.toConfirmation('Acme prefers morning calls');
      final rq = h.api.calls.firstWhere((ApiCall c) => c.name == 'approveRequest');
      expect(rq.args['sessionId'], h.controller.sessionId);
      expect(rq.args['agentId'], 'agent-1');
      expect(rq.args['contentHash'], h.controller.preview!.contentHash);
      expect(rq.args['elevated'], isFalse);
      expect(h.controller.voiceConfirmAllowed, isTrue);
    });

    test('a spoken "confirm" completes a non-elevated change → VERIFIED; refresh calls the context hook once', () async {
      final h = Harness();
      await h.toConfirmation('Acme prefers morning calls');
      h.controller.onUserTranscript('Confirm.');
      await h.pump();
      await h.pump();
      expect(h.controller.state, K136sLearningState.verified);
      final cf = h.api.calls.firstWhere((ApiCall c) => c.name == 'approveConfirm');
      expect(cf.args['channel'], 'voice');
      expect(cf.args['approvalToken'], 'tok-1');
      expect((cf.args['preview'] as Map<String, dynamic>)['normalizedText'], 'Acme prefers morning calls');
      expect(h.controller.memoryId, 'm-1');
      await h.controller.refreshNovaContext();
      await h.controller.refreshNovaContext();
      expect(h.refreshCalls, 1);
      expect(h.controller.contextRefreshed, isTrue);
      h.controller.reset();
      expect(h.controller.state, K136sLearningState.idle);
      expect(h.controller.hasGrant, isFalse);
    });

    test('elevated change: voice is refused, a stale grant re-prompts the vault, typed + fresh grant succeeds', () async {
      final h = Harness();
      await h.toCapturing();
      h.api.previewResult = FakeApi.previewFor('Update the persona to be more formal.', type: 'PROFILE', category: 'persona', elevated: true);
      h.api.approveRequestResult = const K136sApiResult(200, <String, dynamic>{'approvalToken': 'tok-e', 'approvalId': 'ap-e', 'elevated': true});
      h.controller.onUserTranscript('update the persona to be more formal');
      await h.controller.endCapture();
      await h.controller.requestConfirmation();
      expect(h.controller.state, K136sLearningState.confirmationRequired);
      expect(h.controller.voiceConfirmAllowed, isFalse);
      // voice → refused, still waiting
      h.controller.onUserTranscript('confirm');
      await h.pump();
      expect(h.controller.state, K136sLearningState.confirmationRequired);
      expect(h.controller.lastCode, 'ELEVATED_REQUIRES_TYPED');
      // stale grant → re-auth, mic muted again, pending typed confirm
      h.advance(const Duration(seconds: 70));
      await h.controller.confirm(channel: 'typed');
      expect(h.controller.state, K136sLearningState.authRequired);
      expect(h.controller.pendingReauth, isTrue);
      expect(h.muteCalls.last, isTrue);
      await h.controller.submitVaultPassword('correct-horse');
      expect(h.controller.state, K136sLearningState.confirmationRequired);
      expect(h.muteCalls.last, isFalse);
      await h.controller.confirm(channel: 'typed');
      expect(h.controller.state, K136sLearningState.verified);
      expect(h.api.calls.last.args['channel'], 'typed');
    });

    test('410 on confirm returns to the preview with the approval cleared; 409 replay is REJECTED', () async {
      final h = Harness();
      await h.toConfirmation('Acme prefers morning calls');
      h.api.approveConfirmResult = const K136sApiResult(410, <String, dynamic>{'code': 'EXPIRED'});
      await h.controller.confirm(channel: 'typed');
      expect(h.controller.state, K136sLearningState.previewReady);
      expect(h.controller.lastCode, 'EXPIRED');
      h.api.approveConfirmResult = const K136sApiResult(200, <String, dynamic>{'approvalToken': 'tok-2', 'approvalId': 'ap-2', 'elevated': false});
      h.api.approveRequestResult = h.api.approveConfirmResult;
      await h.controller.requestConfirmation();
      h.api.approveConfirmResult = const K136sApiResult(409, <String, dynamic>{'code': 'ALREADY_CONSUMED'});
      await h.controller.confirm(channel: 'typed');
      expect(h.controller.state, K136sLearningState.rejected);
      expect(h.controller.lastCode, 'ALREADY_CONSUMED');
    });

    test('a grant that expires during capture re-prompts the vault and the preview resumes automatically', () async {
      final h = Harness();
      await h.toCapturing();
      h.controller.onUserTranscript('Acme prefers morning calls');
      h.api.previewResult = const K136sApiResult(401, <String, dynamic>{'code': 'EXPIRED'});
      await h.controller.endCapture();
      expect(h.controller.state, K136sLearningState.authRequired);
      expect(h.controller.lastCode, 'REAUTH_REQUIRED');
      expect(h.controller.capturedText, 'Acme prefers morning calls');
      h.api.previewResult = null;
      await h.controller.submitVaultPassword('correct-horse');
      expect(h.controller.state, K136sLearningState.previewReady);
    });

    test('cancel from any live state unmutes and clears secrets; a cancelled session can be reset', () async {
      final h = Harness();
      await h.toPreview('Acme prefers morning calls');
      await h.controller.cancel();
      expect(h.controller.state, K136sLearningState.cancelled);
      expect(h.controller.hasGrant, isFalse);
      expect(h.muteCalls.last, isFalse);
      await h.controller.cancel();
      expect(h.controller.state, K136sLearningState.cancelled);
      h.controller.reset();
      expect(h.controller.state, K136sLearningState.idle);
      h.controller.onUserTranscript('nova learn this');
      expect(h.controller.state, K136sLearningState.triggered);
    });

    test('timeouts: the vault field expires after 2 minutes, an approval after 120 s, the session after 10 minutes', () async {
      final h = Harness();
      h.controller.onUserTranscript('nova learn this');
      await h.pump();
      h.advance(const Duration(minutes: 2, seconds: 1));
      h.controller.tick();
      expect(h.controller.state, K136sLearningState.expired);
      await h.pump();
      expect(h.muteCalls.last, isFalse);

      final h2 = Harness();
      await h2.toConfirmation('Acme prefers morning calls');
      h2.advance(const Duration(seconds: 121));
      h2.controller.tick();
      expect(h2.controller.state, K136sLearningState.previewReady);
      expect(h2.controller.lastCode, 'EXPIRED');

      final h3 = Harness();
      await h3.toPreview('Acme prefers morning calls');
      h3.advance(const Duration(minutes: 10, seconds: 1));
      h3.controller.tick();
      expect(h3.controller.state, K136sLearningState.expired);
    });

    test('dispose closes the api and stops notifying', () {
      final h = Harness();
      h.controller.dispose();
      expect(h.api.closed, isTrue);
      h.controller.onUserTranscript('nova learn this');
      expect(h.controller.state, K136sLearningState.idle);
    });
  });

  group('K136sLearningOverlay', () {
    testWidgets('renders the child alone while idle and the panel with an obscured password field once triggered', (WidgetTester tester) async {
      final h = Harness();
      // The child must fill the surface (as the real stage does under the route's tight constraints);
      // a tiny child would shrink the passthrough Stack and starve the positioned panel of width.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: K136sLearningOverlay(
            controller: h.controller,
            child: const SizedBox.expand(child: Center(child: Text('stage'))),
          ),
        ),
      ));
      expect(find.text('stage'), findsOneWidget);
      expect(find.byKey(const Key('k136s_panel')), findsNothing);
      h.controller.onUserTranscript('Nova, learn this');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('k136s_panel')), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('k136s_vault_password')));
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      await tester.enterText(find.byKey(const Key('k136s_vault_password')), 'correct-horse');
      await tester.tap(find.byKey(const Key('k136s_unlock')));
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, K136sLearningState.capturing);
      // the vault field is gone once unlocked; nothing keeps the password
      expect(find.byKey(const Key('k136s_vault_password')), findsNothing);
      expect(find.byKey(const Key('k136s_done')), findsOneWidget);
      // unmount first (cancels the panel's ticker), then dispose the controller
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('a null controller renders only the child', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: K136sLearningOverlay(controller: null, child: Text('only'))));
      expect(find.text('only'), findsOneWidget);
    });
  });
}
