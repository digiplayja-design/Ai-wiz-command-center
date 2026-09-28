import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/resume_studio/resume_client.dart';
import 'package:ai_wiz_command_center/resume_studio/resume_model.dart';
import 'package:ai_wiz_command_center/resume_studio/resume_export.dart';
import 'package:ai_wiz_command_center/resume_studio/resume_screen.dart';
import 'social_test.dart' as screen;
import 'agent_studio_test.dart' as fixtures;

String token(
  String user, {
  String session = 'session-1',
  String signature = 'x',
}) =>
    'Bearer a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.test/auth/v1', 'sub': user, 'session_id': session})))}.$signature';
ResumeDraft sample() => ResumeDraft(
  title: 'Operations - Northstar',
  fields: {
    'name': 'Alex Rivera',
    'role': 'Operations Manager',
    'email': 'alex@example.test',
    'phone': '+1 555 010 0123',
    'location': 'Portland, OR',
    'link': 'portfolio.example.test',
    'summary':
        'Operations professional with experience coordinating service teams, improving daily workflows, and supporting reliable customer delivery.',
    'skills':
        'Project management, Excel, process improvement, team coordination',
    'projects': 'Organized a community repair workshop with local volunteers.',
    'certifications':
        'Project leadership certificate - Example Institute, 2024',
    'company': 'Northstar',
    'job': 'PRIVATE TARGET NOTES - never in an export',
    'keywords': 'Excel, project management, Java, SQL',
    'letter':
        'Dear Hiring Team,\n\nI am interested in the Operations Manager role. My experience coordinating service teams and improving daily workflows would help me contribute to your organization.\n\nThank you for considering my application.\n\nSincerely,\nAlex Rivera',
  },
  experience: [
    {
      'title': 'Operations Coordinator',
      'company': 'Example Services',
      'dates': 'Mar 2022 - Present',
      'location': 'Portland, OR',
      'bullets':
          'Coordinated weekly schedules for a 12-person service team.\nReduced handoff delays by introducing a shared tracking checklist.\nPrepared monthly Excel reports for the operations manager.',
    },
  ],
  education: [
    {
      'degree': 'BA, Business Administration',
      'school': 'Example University',
      'dates': '2021',
      'details': '',
    },
  ],
);

class Store {
  String auth = token('one');
  String language = 'en';
  final revision = ValueNotifier(0);
  final calls = <http.Request>[];
  String response =
      'Operations professional coordinating service teams and improving reliable delivery.';
  int status = 200;
  Completer<http.Response>? pending;
  late final client = ResumeClient(
    baseUrl: 'https://fixture.test',
    language: language,
    headersBuilder: () => {
      'Authorization': auth,
      'Content-Type': 'application/json',
    },
    sessionChanges: revision,
    client: MockClient((r) async {
      calls.add(r);
      if (pending != null) return pending!.future;
      return http.Response(
        jsonEncode(
          status == 200
              ? {'content': response}
              : {'error': 'Plan allowance reached'},
        ),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  ResumeScreen page() => ResumeScreen(
    client: client,
    ensureConsent: (_) async => true,
    saveFile: (bytes, name, mime, rect) async {
      saved.add((bytes, name, mime));
    },
  );
  final saved = <(Uint8List, String, String)>[];
}

Future<void> tap(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await Scrollable.ensureVisible(t.element(f), alignment: .5);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

// TextFormField stores its decoration in the descendant TextField.
Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
    'content excludes targeting notes and preserves ordering; copies are independent',
    () {
      final d = sample();
      expect(d.text, contains('12-person'));
      expect(d.text, isNot(contains('PRIVATE TARGET')));
      expect(d.text, isNot(contains('Dear Hiring')));
      d.order.remove('skills');
      d.order.insert(0, 'skills');
      expect(d.text.indexOf('Skills'), lessThan(d.text.indexOf('Experience')));
      final copy = d.clone(newIdentity: true);
      expect(copy.id, isNot(d.id));
      copy.experience.first['company'] = 'Changed';
      expect(d.experience.first['company'], 'Example Services');
    },
  );
  test(
    'keyword comparison respects word boundaries, punctuation, and phrases',
    () {
      final d = sample()
        ..fields['skills'] = 'JavaScript, C++, project    management';
      d.fields['keywords'] =
          'Java, JavaScript, C++, project management, Python';
      expect(resumeKeywordMatches(d), {
        'Java': false,
        'JavaScript': true,
        'C++': true,
        'project management': true,
        'Python': false,
      });
    },
  );
  test(
    'import validates structured output and never imports AI-supplied IDs or template markup',
    () {
      final d = sample();
      final imported = resumeFromAiImport(
        '```json\n${jsonEncode({'id': 'untrusted', 'fields': d.fields, 'experience': d.experience, 'education': d.education})}\n```',
      );
      expect(imported.id, isNot('untrusted'));
      expect(imported.get('job'), '');
      expect(imported.get('name'), 'Alex Rivera');
      expect(
        () => resumeFromAiImport(
          '{"fields":{},"experience":"bad","education":[]}',
        ),
        throwsFormatException,
      );
      expect(() => resumeFromAiImport('Not JSON'), throwsFormatException);
    },
  );
  test(
    'drafts stay separate per account and survive token refresh and a new sign-in',
    () async {
      final a = Store();
      await a.client.saveAll([sample()]);
      a.auth = token('one', signature: 'refreshed');
      a.revision.value++;
      expect((await a.client.drafts()).length, 1);
      final b = Store()..auth = token('two');
      expect(await b.client.drafts(), isEmpty);
      a.auth = token('two');
      a.revision.value++;
      await expectLater(a.client.drafts(), throwsA(isA<ResumeException>()));
      final fresh = Store()..auth = token('one', session: 'new');
      expect((await fresh.client.drafts()).single.get('name'), 'Alex Rivera');
      a.client.dispose();
      b.client.dispose();
      fresh.client.dispose();
    },
  );
  test(
    'AI requests are isolated and stale responses are rejected after account change',
    () async {
      final a = Store()
        ..language = 'fr'
        ..pending = Completer<http.Response>();
      final result = a.client.suggest('Refine profile', sample().aiFacts);
      final assertion = expectLater(result, throwsA(isA<ResumeException>()));
      await Future<void>.delayed(Duration.zero);
      final body = jsonDecode(a.calls.single.body);
      expect(body['purpose'], 'resume_studio');
      expect(body['language'], 'fr');
      expect(body['history'], isEmpty);
      expect(body['command'], isNot(contains('alex@example.test')));
      a.auth = token('two');
      a.revision.value++;
      a.pending!.complete(http.Response('{"content":"Private result"}', 200));
      await assertion;
      a.client.dispose();
    },
  );
  test('stale draft saves fail without overwriting another editor', () async {
    final a = Store(), b = Store();
    await a.client.saveAll([sample()]);
    final one = await a.client.drafts(), two = await b.client.drafts();
    one.single.title = 'Saved elsewhere';
    await a.client.saveAll(one);
    two.single.title = 'Stale update';
    await expectLater(b.client.saveAll(two), throwsA(isA<ResumeException>()));
    expect((await a.client.drafts()).single.title, 'Saved elsewhere');
    a.client.dispose();
    b.client.dispose();
  });
  test('file import preserves upload endpoint, MIME, and bounds', () async {
    final a = Store();
    await a.client.importFile(
      Uint8List.fromList(utf8.encode('My resume')),
      'resume.txt',
    );
    expect(a.calls.single.url.path, '/api/analyze-document');
    expect(
      a.calls.single.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    expect(a.calls.single.body, contains('My resume'));
    expect(
      () => a.client.importFile(Uint8List(5 * 1024 * 1024 + 1), 'huge.pdf'),
      throwsA(isA<ResumeException>()),
    );
    expect(a.calls.length, 1);
    a.client.dispose();
  });
  test(
    'real Word package escapes markup and excludes private targeting notes',
    () {
      final d = sample()..fields['name'] = 'Alex & Morgan <Team>';
      final archive = ZipDecoder().decodeBytes(resumeDocx(d));
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      expect(xml, contains('Alex &amp; Morgan &lt;Team&gt;'));
      expect(xml, isNot(contains('PRIVATE TARGET')));
      expect(archive.findFile('[Content_Types].xml'), isNotNull);
      expect(xml, contains('Coordinated weekly schedules'));
    },
  );
  test(
    'PDF and Word QA fixtures cover all styles, a cover letter, and long multipage content',
    () async {
      final dir = Platform.environment['RESUME_EXPORT_QA'];
      for (final style in ['modern', 'executive', 'minimal']) {
        final d = sample()..template = style;
        final bytes = await resumePdf(d);
        expect(utf8.decode(bytes.take(4).toList()), '%PDF');
        if (dir != null) {
          await Directory(dir).create(recursive: true);
          await File('$dir/$style.pdf').writeAsBytes(bytes);
          await File('$dir/$style.docx').writeAsBytes(resumeDocx(d));
        }
      }
      final d = sample();
      final letter = await resumePdf(d, letter: true);
      d.fields['projects'] = List.generate(
        45,
        (i) =>
            'Project ${i + 1}: Coordinated community activities, maintained schedules, and prepared clear progress updates.',
      ).join('\n');
      final long = await resumePdf(d);
      if (dir != null) {
        await File('$dir/cover-letter.pdf').writeAsBytes(letter);
        await File('$dir/long.pdf').writeAsBytes(long);
      }
    },
  );
  for (final config in [
    (320.0, 1.0, 'pure_black'),
    (390.0, 1.3, 'korlix_blue'),
    (1280.0, 1.0, 'pure_white'),
  ]) {
    testWidgets('responsive hub and editor ${config.$1}', (t) async {
      final a = Store();
      await a.client.saveAll([sample()]);
      await screen.mount(
        t,
        a.page(),
        width: config.$1,
        scale: config.$2,
        theme: config.$3,
      );
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'resume-hub-${config.$1.toInt()}');
      await tap(t, find.text('Open resume'));
      expect(t.takeException(), isNull);
      await tap(t, find.text('02  Style'));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'resume-style-${config.$1.toInt()}');
      await tap(t, find.text('03  Review & export'));
      expect(t.takeException(), isNull);
      await tap(t, find.text('Export Word'));
      expect(a.saved.single.$2, endsWith('.docx'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('edit, save, reopen, and duplicate preserve the original', (
    t,
  ) async {
    final a = Store();
    await screen.mount(t, a.page());
    await tap(t, find.text('Create a resume'));
    await t.enterText(input('Full name'), 'Sam Taylor');
    await t.enterText(input('Professional email'), 'sam@example.test');
    await tap(t, find.text('Save draft'));
    await tap(t, find.byTooltip('My resumes'));
    await tap(t, find.text('Open resume'));
    expect(
      t.widget<TextField>(input('Full name')).controller!.text,
      'Sam Taylor',
    );
    await tap(t, find.byTooltip('My resumes'));
    await tap(t, find.byTooltip('Draft options'));
    await tap(t, find.text('Duplicate for another job'));
    await t.enterText(input('Full name'), 'Sam for another role');
    await tap(t, find.text('Save draft'));
    expect((await a.client.drafts()).length, 2);
    expect((await a.client.drafts()).last.get('name'), 'Sam Taylor');
  });
  testWidgets(
    'AI suggestion requires review, supports apply and undo, and failures preserve content',
    (t) async {
      final a = Store();
      await a.client.saveAll([sample()]);
      await screen.mount(t, a.page());
      await tap(t, find.text('Open resume'));
      await tap(t, find.text('Profile').first);
      final old = t
          .widget<TextField>(input('Professional profile'))
          .controller!
          .text;
      await tap(t, find.text('Refine with K-Nova'));
      expect(find.text('Review your profile'), findsOneWidget);
      await tap(t, find.text('Keep original'));
      expect(
        t.widget<TextField>(input('Professional profile')).controller!.text,
        old,
      );
      await tap(t, find.text('Refine with K-Nova'));
      await tap(t, find.text('Apply to draft'));
      expect(
        t.widget<TextField>(input('Professional profile')).controller!.text,
        a.response,
      );
      await tap(t, find.byTooltip('Undo last AI or structural change'));
      expect(
        t.widget<TextField>(input('Professional profile')).controller!.text,
        old,
      );
      a.status = 429;
      await tap(t, find.text('Refine with K-Nova'));
      expect(find.text('Plan allowance reached'), findsOneWidget);
      expect(
        t.widget<TextField>(input('Professional profile')).controller!.text,
        old,
      );
    },
  );
  testWidgets(
    'import creates a reviewable new draft and logout clears private screen content',
    (t) async {
      final a = Store();
      final d = sample();
      a.response = jsonEncode({
        'fields': d.fields,
        'experience': d.experience,
        'education': d.education,
      });
      await screen.mount(t, a.page());
      await tap(t, find.text('Import a resume'));
      await t.enterText(
        input('Paste resume text'),
        'Alex Rivera - Operations Coordinator',
      );
      await tap(t, find.text('Organize text'));
      expect(find.text('Review imported facts'), findsOneWidget);
      await tap(t, find.text('Use this draft'));
      expect(
        t.widget<TextField>(input('Full name')).controller!.text,
        'Alex Rivera',
      );
      await tap(t, find.text('Preview'));
      a.auth = token('two');
      a.revision.value++;
      await t.pumpAndSettle();
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.text('Alex Rivera'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
