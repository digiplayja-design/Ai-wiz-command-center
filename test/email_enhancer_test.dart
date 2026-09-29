import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/email_enhancer/email_client.dart';
import 'package:ai_wiz_command_center/email_enhancer/email_model.dart';
import 'package:ai_wiz_command_center/email_enhancer/email_screen.dart';
import 'package:ai_wiz_command_center/email_enhancer/email_io.dart';
import 'social_test.dart' as social;
import 'social_invites_test.dart' as actions;
import 'agent_studio_test.dart' as fixtures;

const sample = EmailBrief(
  source:
      'Hi Jordan, can you confirm our meeting on October 2 at 10 AM? Thanks, Alex.',
  recipient: 'Jordan',
  goal: 'Confirm the meeting',
);
const enhanced = EnhancedEmail(
  subjects: [
    'Confirming our October 2 meeting',
    'Meeting confirmation: October 2',
    'Does October 2 at 10 AM work?',
  ],
  body:
      'Hi Jordan,\n\nCould you confirm our meeting on October 2 at 10 AM?\n\nThank you,\nAlex',
  changes: ['Made the request easier to find.', 'Added paragraph spacing.'],
  checks: ['Confirm the meeting time before sending.'],
);
String token(String id, {String session = 'one'}) =>
    'Bearer a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://example.test', 'sub': id, 'session_id': session})))}.b';

class MemoryDrafts implements EmailDraftStore {
  final data = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw Exception();
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw Exception();
    data[key] = value;
  }
}

class Files extends EmailEnhancerIo {
  final copies = <String>[], exports = <(String, String)>[];
  String? imported;
  @override
  Future<void> copy(String text) async {
    copies.add(text);
  }

  @override
  Future<void> export(String text, String extension, Rect origin) async {
    exports.add((text, extension));
  }

  @override
  Future<String?> importText() async => imported;
}

class Studio {
  Studio({MemoryDrafts? store}) : store = store ?? MemoryDrafts();
  final MemoryDrafts store;
  final changes = ValueNotifier(0);
  String authorization = token('owner');
  final requests = <Map<String, dynamic>>[];
  int status = 200;
  bool consent = true;
  Completer<http.Response>? pending;
  late final client = EmailEnhancerClient(
    baseUrl: 'https://api.example.test',
    headersBuilder: () => {'Authorization': authorization},
    sessionChanges: changes,
    store: store,
    client: MockClient((r) async {
      requests.add(jsonDecode(r.body));
      return pending?.future ??
          http.Response(
            jsonEncode(
              status == 200
                  ? {'result': enhanced.json}
                  : {'error': 'No credits remaining.'},
            ),
            status,
          );
    }),
  );
  final io = Files();
  Widget screen() => EmailEnhancerScreen(
    client: client,
    ensureConsent: () async => consent,
    io: io,
  );
  void close() {
    client.dispose();
    changes.dispose();
  }
}

EmailDraft draft(String id, {EmailVersion? version}) => EmailDraft(
  id: id,
  brief: sample,
  subject: 'A saved email',
  body: 'Email body',
  version: version,
  savedAt: '2026-09-29T12:00:00Z',
);
Future<void> generate(WidgetTester t, Studio f) async {
  await actions.reveal(t, find.byKey(const Key('email-source')));
  await t.enterText(find.byKey(const Key('email-source')), sample.source);
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('email-enhance')));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  test(
    'brief/result validation and Unicode EML export preserve text safely',
    () {
      expect(EmailBrief.fromJson(sample.json).json, sample.json);
      expect(
        const EmailBrief(mode: 'Reply', source: 'Incoming email').error,
        contains('reply'),
      );
      expect(
        () => EmailBrief.fromJson({...sample.json, 'tone': 'Bad'}),
        throwsFormatException,
      );
      expect(
        () => EnhancedEmail.fromJson({
          ...enhanced.json,
          'subjects': ['Only one'],
        }),
        throwsFormatException,
      );
      expect(
        () => EnhancedEmail.fromJson({
          ...enhanced.json,
          'subjects': ['A\nBcc: x', 'B', 'C'],
        }),
        throwsFormatException,
      );
      final eml = emailEml(
        'Café ☕\r\nBcc: nobody@example.test',
        'Hello, Zoë!\nSecond line.',
      );
      expect(eml, contains('X-Unsent: 1'));
      expect(eml, contains('Content-Transfer-Encoding: base64'));
      expect(eml, isNot(contains('\r\nBcc:')));
      expect(
        utf8.decode(
          base64.decode(eml.split('\r\n\r\n').last.replaceAll('\r\n', '')),
        ),
        'Hello, Zoë!\r\nSecond line.',
      );
    },
  );
  test(
    'request uses dedicated endpoint, explicit consent, no chat history and retry key',
    () async {
      final f = Studio();
      addTearDown(f.close);
      f.status = 429;
      await expectLater(
        f.client.enhance(sample),
        throwsA(isA<EmailEnhancerException>()),
      );
      final key = f.requests.single['requestKey'];
      f.status = 200;
      expect((await f.client.enhance(sample)).body, enhanced.body);
      expect(f.requests.last['requestKey'], key);
      expect(f.requests.last['consent'], true);
      expect(f.requests.last.containsKey('history'), false);
      await f.client.enhance(sample);
      expect(f.requests.last['requestKey'], isNot(key));
    },
  );
  test(
    'account changes discard late AI output and clear private drafts',
    () async {
      final f = Studio();
      addTearDown(f.close);
      await f.client.load();
      await f.client.save(draft('one'));
      f.pending = Completer();
      final pending = f.client.enhance(sample);
      final assertion = expectLater(
        pending,
        throwsA(isA<EmailEnhancerException>()),
      );
      f.authorization = token('other');
      f.changes.value++;
      expect(f.client.drafts, isEmpty);
      expect(f.client.available, false);
      f.pending!.complete(
        http.Response(jsonEncode({'result': enhanced.json}), 200),
      );
      await assertion;
    },
  );
  test(
    'drafts are isolated, survive token refresh, and reject conflicting writes',
    () async {
      final store = MemoryDrafts(), a = Studio();
      addTearDown(a.close);
      await a.client.load();
      await a.client.save(draft('one'));
      final other = Studio(store: a.store)..authorization = token('other');
      addTearDown(other.close);
      await other.client.load();
      expect(other.client.drafts, isEmpty);
      final same = Studio(store: a.store);
      addTearDown(same.close);
      await same.client.load();
      expect(same.client.drafts.single.id, 'one');
      await a.client.save(draft('two'));
      await expectLater(
        same.client.save(draft('three')),
        throwsA(isA<EmailEnhancerException>()),
      );
      final corrupt = Studio(store: store);
      addTearDown(corrupt.close);
      await corrupt.client.load();
      await corrupt.client.save(draft('one'));
      store.data[store.data.keys.single] = 'not json';
      await expectLater(
        corrupt.client.load(),
        throwsA(isA<EmailEnhancerException>()),
      );
      await expectLater(
        corrupt.client.save(draft('two')),
        throwsA(isA<EmailEnhancerException>()),
      );
      expect(store.data.values.single, 'not json');
    },
  );
  test(
    'duplicate enhancements are blocked and denied sessions cannot save',
    () async {
      final f = Studio();
      addTearDown(f.close);
      f.pending = Completer();
      final request = f.client.enhance(sample);
      await expectLater(
        f.client.enhance(sample),
        throwsA(isA<EmailEnhancerException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(f.requests.length, 1);
      f.pending!.complete(http.Response(jsonEncode({'error': 'Sign in'}), 401));
      await expectLater(request, throwsA(isA<EmailEnhancerException>()));
      expect(f.client.available, false);
      await expectLater(
        f.client.save(draft('x')),
        throwsA(isA<EmailEnhancerException>()),
      );
    },
  );
  testWidgets(
    'mobile polish, subject choice, edits, copy, compare, export and save',
    (t) async {
      final f = Studio();
      addTearDown(f.close);
      await social.mount(t, f.screen());
      await fixtures.capture(t, 'email-mobile-write');
      await generate(t, f);
      expect(f.requests.length, 1);
      expect(f.requests.single['mode'], 'Polish');
      await fixtures.capture(t, 'email-mobile-enhanced');
      await actions.tap(t, find.byKey(const Key('email-subject-1')));
      await actions.reveal(t, find.byKey(const Key('email-body')));
      await t.enterText(
        find.byKey(const Key('email-body')),
        'My reviewed email.',
      );
      await actions.tap(t, find.byKey(const Key('email-copy')));
      expect(
        f.io.copies.single,
        'Subject: ${enhanced.subjects[1]}\n\nMy reviewed email.',
      );
      await actions.tap(t, find.text('Export .eml'));
      expect(f.io.exports.single.$2, 'eml');
      expect(f.io.exports.single.$1, contains('X-Unsent: 1'));
      await actions.tap(t, find.byKey(const Key('email-compare')));
      expect(find.text(sample.source), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('email-enhance')));
      await t.pumpAndSettle();
      expect(f.client.drafts.length, 1);
      expect(f.client.drafts.single.body, 'My reviewed email.');
      await actions.tap(t, find.byKey(const Key('email-tab-2')));
      expect(find.text('Open draft'), findsOneWidget);
      await fixtures.capture(t, 'email-mobile-drafts');
    },
  );
  testWidgets(
    'reply requires direction and declined consent makes no request',
    (t) async {
      final f = Studio();
      addTearDown(f.close);
      f.consent = false;
      await social.mount(t, f.screen());
      await actions.tap(t, find.text('Reply'));
      await generate(t, f);
      expect(f.requests, isEmpty);
      await actions.reveal(t, find.byKey(const Key('email-reply-notes')));
      await t.enterText(
        find.byKey(const Key('email-reply-notes')),
        'Say I can attend.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('email-enhance')));
      await t.pumpAndSettle();
      expect(f.requests, isEmpty);
      f.consent = true;
      await t.tap(find.byKey(const Key('email-enhance')));
      await t.pumpAndSettle();
      expect(f.requests.single['mode'], 'Reply');
      expect(f.requests.single['context'], 'Say I can attend.');
    },
  );
  testWidgets('import and draft recovery do not require AI', (t) async {
    final f = Studio();
    addTearDown(f.close);
    f.io.imported = sample.source;
    await social.mount(t, f.screen());
    await actions.tap(t, find.text('Import text'));
    expect(f.requests, isEmpty);
    await t.tap(find.byKey(const Key('email-save')));
    await t.pumpAndSettle();
    expect(f.client.drafts.single.brief.source, sample.source);
    await actions.tap(t, find.byKey(const Key('email-tab-2')));
    await actions.tap(t, find.text('Open draft'));
    await actions.reveal(t, find.byKey(const Key('email-source')));
    expect(
      t
          .widget<TextField>(find.byKey(const Key('email-source')))
          .controller!
          .text,
      sample.source,
    );
  });
  testWidgets(
    'regeneration preserves manual edits until replacement is confirmed',
    (t) async {
      final f = Studio();
      addTearDown(f.close);
      await social.mount(t, f.screen());
      await generate(t, f);
      await actions.reveal(t, find.byKey(const Key('email-body')));
      await t.enterText(
        find.byKey(const Key('email-body')),
        'My manual changes.',
      );
      await actions.tap(t, find.byKey(const Key('email-tab-0')));
      await t.tap(find.byKey(const Key('email-enhance')));
      await t.pumpAndSettle();
      expect(find.text('Replace your edited email?'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(f.requests.length, 1);
      await actions.tap(t, find.byKey(const Key('email-tab-1')));
      await actions.reveal(t, find.byKey(const Key('email-body')));
      expect(
        t
            .widget<TextField>(find.byKey(const Key('email-body')))
            .controller!
            .text,
        'My manual changes.',
      );
      await actions.tap(t, find.byKey(const Key('email-tab-0')));
      await t.tap(find.byKey(const Key('email-enhance')));
      await t.pumpAndSettle();
      await t.tap(find.text('Enhance again'));
      await t.pumpAndSettle();
      expect(f.requests.length, 2);
    },
  );
  for (final layout in [
    (360.0, 1.0, 'pure_black'),
    (390.0, 2.0, 'pure_black'),
    (1280.0, 1.0, 'classic'),
  ]) {
    testWidgets('responsive layout ${layout.$1} ${layout.$2}', (t) async {
      final f = Studio();
      addTearDown(f.close);
      await social.mount(
        t,
        f.screen(),
        width: layout.$1,
        height: 1000,
        scale: layout.$2,
        theme: layout.$3,
      );
      await fixtures.capture(t, 'email-${layout.$1}-${layout.$2}');
      expect(t.takeException(), isNull);
      await generate(t, f);
      await actions.reveal(t, find.byKey(const Key('email-body')));
      expect(t.takeException(), isNull);
    });
  }
}
