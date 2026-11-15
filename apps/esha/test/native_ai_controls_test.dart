import 'dart:async';
import 'dart:convert';

import 'package:esha_by_korlix/app_controller.dart';
import 'package:esha_by_korlix/models.dart';
import 'package:esha_by_korlix/services/korlix_api.dart';
import 'package:esha_by_korlix/services/purchases.dart';
import 'package:esha_by_korlix/services/vanity_sync.dart';
import 'package:esha_by_korlix/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'fixtures.dart';

class UnusedStore implements InAppPurchase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedSecureStore extends MemoryStore {
  Completer<void>? beforePendingWrite;
  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith('esha.consultation.pending.') &&
        beforePendingWrite != null) {
      await beforePendingWrite!.future;
    }
    await super.write(key, value);
  }
}

class AiFixture {
  final secure = DelayedSecureStore(), local = MemoryStore();
  late final EshaController controller;
  late final KorlixApi api;
  String account = accountA;
  bool failConsult = false;
  int reportStatus = 202;
  Json reportResponse = {'ok': true, 'reportId': 'korlix_report_test-receipt'};
  final List<Json> questions = [], reports = [];
  Json get membership => {
    'consultationEnabled': true,
    'membership': {
      'active': true,
      'verificationFresh': true,
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
    },
    'allowance': {'configured': true, 'limit': 20, 'remaining': 18},
  };
  http.Response reply(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);

  Future<void> start() async {
    api = KorlixApi(
      config: fixtureConfig(),
      secureStorage: secure,
      localStorage: local,
      platform: 'unsupported',
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/signin') {
          return reply(authPayload(account));
        }
        if (request.url.path.startsWith('/rest/v1/')) {
          if (request.method == 'GET') return reply([]);
          final data = object(jsonDecode(request.body));
          return reply([
            {'state': data['state'], 'version': 1},
          ]);
        }
        if (request.url.path == '/api/esha/consult') {
          final body = object(jsonDecode(request.body));
          questions.add(body);
          if (failConsult) {
            return reply({
              'error': 'Response unavailable',
              'code': 'consultation_unavailable',
            }, 503);
          }
          return reply({
            'requestId': body['requestId'],
            'answer': 'Try a soft satin lip with a light gloss.',
            'usage': {'configured': true, 'limit': 20, 'remaining': 17},
          });
        }
        if (request.url.path == '/api/report-output') {
          reports.add(object(jsonDecode(request.body)));
          return reply(reportResponse, reportStatus);
        }
        return reply(membership);
      }),
    );
    controller = EshaController(
      catalog: fixtureCatalog(),
      api: api,
      sync: VanitySync(gateway: api, storage: local),
      purchases: EshaPurchases(api, store: UnusedStore()),
    );
    await controller.signIn('person@example.test', 'not-a-real-password');
    await controller.purchases.refresh();
    controller.initializing = false;
  }

  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    controller.dispose();
  }
}

Future<void> settle() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live AI requires explicit account consent and optional preferences stay excluded', () async {
    final f = AiFixture();
    await f.start();
    addTearDown(f.close);
    expect(f.controller.aiSharingConsented, isFalse);
    await f.controller.ask('Which lip finish should I try?');
    expect(f.questions, isEmpty);
    expect(f.controller.hasPendingQuestion, isFalse);
    expect(f.controller.chatError, contains('OpenAI'));
    f.controller.setAiSharingConsent(true);
    await f.controller.ask('Which lip finish should I try?');
    expect(f.questions, hasLength(1));
    expect(f.questions.single['question'], 'Which lip finish should I try?');
    expect(f.questions.single.containsKey('preferences'), isFalse);
    expect(f.controller.chat.last.requestId, f.questions.single['requestId']);
    expect(f.controller.chat.last.prompt, f.questions.single['question']);
  });

  test('withdrawing consent pauses saved retries without changing their request identity', () async {
    final f = AiFixture();
    await f.start();
    addTearDown(f.close);
    f.controller.setAiSharingConsent(true);
    f.failConsult = true;
    await f.controller.ask('Recommend a lip pairing.');
    final original = jsonEncode(f.questions.single);
    expect(f.controller.hasPendingQuestion, isTrue);
    f.controller.setAiSharingConsent(false);
    await f.controller.retryQuestion();
    expect(f.questions, hasLength(1));
    expect(f.controller.hasPendingQuestion, isTrue);
    await f.controller.signOut();
    await f.controller.signIn('person@example.test', 'not-a-real-password');
    expect(f.controller.aiSharingConsented, isFalse);
    expect(f.controller.hasPendingQuestion, isTrue);
    await f.controller.retryQuestion();
    expect(f.questions, hasLength(1));
    f.controller.setAiSharingConsent(true);
    f.failConsult = false;
    await f.controller.retryQuestion();
    expect(f.questions, hasLength(2));
    expect(jsonEncode(f.questions.last), original);
    expect(f.controller.hasPendingQuestion, isFalse);
    await f.controller.signOut();
    f.account = accountB;
    await f.controller.signIn('other@example.test', 'not-a-real-password');
    expect(f.controller.aiSharingConsented, isFalse);
    expect(f.controller.chat, isEmpty);
  });

  test(
    'withdrawal during secure request persistence prevents provider dispatch',
    () async {
      final f = AiFixture();
      await f.start();
      addTearDown(f.close);
      f.controller.setAiSharingConsent(true);
      final gate = Completer<void>();
      f.secure.beforePendingWrite = gate;
      final ask = f.controller.ask('A simple body-care routine?');
      await settle();
      f.controller.setAiSharingConsent(false);
      gate.complete();
      await ask;
      expect(f.questions, isEmpty);
      expect(f.controller.hasPendingQuestion, isTrue);
    },
  );

  test('reports use the selected answer and paired question and require a real receipt', () async {
    final f = AiFixture();
    await f.start();
    addTearDown(f.close);
    f.controller.setAiSharingConsent(true);
    await f.controller.ask('Which lip finish should I try?');
    final turn = f.controller.chat.last;
    f.reportResponse = {'ok': true};
    await expectLater(
      f.controller.reportAnswer(
        turn,
        reason: 'Unsafe advice',
        details: 'Please review.',
      ),
      throwsA(
        isA<EshaException>().having(
          (e) => e.code,
          'code',
          'REPORT_UNCONFIRMED',
        ),
      ),
    );
    expect(f.controller.reportReceiptFor(turn), isNull);
    f.reportResponse = {
      'ok': true,
      'reportId': 'korlix_report_real-fixture-reference',
    };
    final receipt = await f.controller.reportAnswer(
      turn,
      reason: 'Unsafe advice',
      details: 'Please review.',
    );
    expect(receipt, 'korlix_report_real-fixture-reference');
    expect(f.reports.last, {
      'appArea': 'esha_by_korlix',
      'contentType': 'text',
      'contentId': turn.requestId,
      'outputSummary': turn.content,
      'prompt': 'Which lip finish should I try?',
      'reason': 'Unsafe advice',
      'details': 'Please review.',
      'appVersion': '1.0.0+1',
      'platform': 'unsupported',
    });
    await f.controller.signOut();
    f.account = accountB;
    await f.controller.signIn('other@example.test', 'not-a-real-password');
    await expectLater(
      f.controller.reportAnswer(turn, reason: 'Other', details: ''),
      throwsA(isA<EshaException>()),
    );
    expect(f.reports, hasLength(2));
  });

  test(
    'long report evidence is a bounded disclosed excerpt of the actual answer',
    () async {
      final f = AiFixture();
      await f.start();
      addTearDown(f.close);
      final turn = ChatTurn(
        'assistant',
        List.filled(12000, '💄').join(),
        requestId: '11111111-1111-4111-8111-111111111111',
        prompt: List.filled(3000, '💄').join(),
      );
      f.controller.chat = [turn];
      final evidence = f.controller.reportEvidence(turn);
      expect(evidence.shortened, isTrue);
      expect(turn.content.startsWith(evidence.answer), isTrue);
      expect(turn.prompt!.startsWith(evidence.question), isTrue);
      expect(
        utf8.encode(jsonEncode(evidence.answer)).length,
        lessThanOrEqualTo(20000),
      );
      expect(
        utf8.encode(jsonEncode(evidence.question)).length,
        lessThanOrEqualTo(4000),
      );
    },
  );

  testWidgets(
    'report dialog sends only on explicit tap and keeps errors visible',
    (tester) async {
      final f = AiFixture();
      await f.start();
      addTearDown(f.close);
      f.controller.setAiSharingConsent(true);
      await f.controller.ask('Which lip finish should I try?');
      final turn = f.controller.chat.last;
      f.reportStatus = 503;
      f.reportResponse = {
        'ok': false,
        'error': 'Reports are temporarily unavailable.',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => ReportAnswerDialog(
                    controller: f.controller,
                    turn: turn,
                    evidence: f.controller.reportEvidence(turn),
                  ),
                ),
                child: const Text('Open report'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open report'));
      await tester.pumpAndSettle();
      expect(f.reports, isEmpty);
      expect(find.textContaining('Nothing is sent until'), findsOneWidget);
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(f.reports, hasLength(1));
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(f.controller.reportReceiptFor(turn), isNull);
      f.reportStatus = 202;
      f.reportResponse = {
        'ok': true,
        'reportId': 'korlix_report_dialog-reference',
      };
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(f.reports, hasLength(2));
      expect(
        f.controller.reportReceiptFor(turn),
        'korlix_report_dialog-reference',
      );
      expect(find.text('Send report'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.close();
    },
  );
}
