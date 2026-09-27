import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/study_studio/study_client.dart';
import 'package:ai_wiz_command_center/study_studio/study_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> cp(Map<String, dynamic> x) =>
    studyMap(jsonDecode(jsonEncode(x)));
Map<String, dynamic> pack({String key = id, String state = 'ready'}) => {
  'id': key,
  'state': state,
  'source': 'starter',
  'revision': 0,
  'details': {
    'topic': 'Everyday percentages',
    'minutes': 5,
    'level': 'beginner',
    'goal': 'understand',
  },
  'progress': {'read': {}, 'cards': {}, 'answers': {}},
  'lesson': state == 'ready'
      ? {
          'title': 'Percentages you can actually use',
          'summary':
              'Find a percentage, work out a discount and compare a change using everyday examples.',
          'objectives': [
            'Convert percentages to decimals.',
            'Calculate a discount.',
          ],
          'sections': [
            {
              'heading': 'Percent means out of 100',
              'body':
                  'A percentage describes a quantity relative to a whole. Divide a percentage by 100 to write it as a decimal.',
              'example': '25% = 25 ÷ 100 = 0.25.',
              'takeaway': '25% and 0.25 represent the same proportion.',
            },
            {
              'heading': 'Find a discount',
              'body':
                  'Multiply the original price by the percentage as a decimal, then subtract the discount.',
              'example': '20% of 60 is 12. The final price is 48.',
              'takeaway': 'Discount and final price are different.',
            },
            {
              'heading': 'Compare a change',
              'body':
                  'Divide the change by the original value and multiply by 100.',
              'example': 'From 40 to 50 is a 25% increase.',
              'takeaway': 'Use the original value.',
            },
          ],
          'cards': List.generate(
            4,
            (n) => {
              'front': n == 0 ? 'What does 15% mean?' : 'Practice prompt $n',
              'back': n == 0
                  ? '15 out of every 100, or 0.15.'
                  : 'Answer for card $n',
            },
          ),
          'quiz': List.generate(
            4,
            (n) => {
              'question': n == 0
                  ? 'What is 25% as a decimal?'
                  : 'Practice question $n',
              'options': ['2.5', '0.25', '25', '0.025'],
              'answer': 1,
              'hint': 'Divide by 100.',
              'explanation': '25 divided by 100 is 0.25.',
            },
          ),
          'recap': [
            'Percent means out of 100.',
            'Multiply to find the part.',
            'Use the starting value for change.',
          ],
          'limitations': [],
        }
      : {},
  'error': state == 'failed'
      ? 'Preparation failed. Your credit was returned.'
      : null,
};

class FakeStudy extends StudyClient {
  FakeStudy()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  List<Map<String, dynamic>> rows = [], creates = [], events = [];
  Map<String, dynamic>? current;
  bool failCreate = false, failEvent = false, preparing = false, failed = false;
  int exports = 0, deletes = 0, opens = 0;
  Completer<Map<String, dynamic>>? createWait;
  Completer<List<int>>? exportWait;
  @override
  Future<List<Map<String, dynamic>>> list() async => rows.map(cp).toList();
  void sync() {
    if (current == null) return;
    rows = [
      {
        ...cp(current!),
        'title': studyMap(current!['lesson'])['title'],
        'cardCount': 4,
        'sectionCount': 3,
        'questionCount': 4,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> b) async {
    creates.add(cp(b));
    if (failCreate) {
      failCreate = false;
      throw const StudyException('Connection interrupted');
    }
    if (createWait != null) return createWait!.future;
    current = pack(
      key: b['request_key'],
      state: preparing
          ? 'preparing'
          : failed
          ? 'failed'
          : 'ready',
    );
    sync();
    return cp(current!);
  }

  @override
  Future<Map<String, dynamic>> open(String value) async {
    opens++;
    current ??= pack(key: value);
    return cp(current!);
  }

  @override
  Future<Map<String, dynamic>> progress(
    String value,
    Map<String, dynamic> b,
  ) async {
    events.add(cp(b));
    if (failEvent) {
      failEvent = false;
      throw const StudyException('Save acknowledgement interrupted');
    }
    final s = current!, p = studyMap(s['progress']), key = '${b['index']}';
    switch (b['event']) {
      case 'read':
        p['read'][key] = true;
      case 'card':
        p['cards'][key] = {
          'rating': b['rating'],
          'days': b['rating'] == 'again' ? 0 : 1,
          'due': DateTime.now()
              .add(Duration(minutes: b['rating'] == 'again' ? 10 : 1440))
              .toIso8601String(),
        };
      case 'answer':
        final a = studyMap(p['answers'][key]);
        p['answers'][key] = {
          'choice': b['choice'],
          'firstChoice': a['firstChoice'] ?? b['choice'],
          'attempts': (a['attempts'] as int? ?? 0) + 1,
        };
      case 'resetQuiz':
        p['answers'] = {};
    }
    s['progress'] = p;
    s['revision']++;
    sync();
    return cp(s);
  }

  @override
  Future<void> remove(String value) async {
    deletes++;
    rows = [];
    current = null;
  }

  @override
  Future<List<int>> export(String value) async {
    exports++;
    return exportWait?.future ?? utf8.encode('Study guide and answer key');
  }
}

final boundary = GlobalKey();
Future<void> show(
  WidgetTester t,
  FakeStudy c, {
  double width = 1100,
  double scale = 1,
  String theme = 'pure_white',
  bool consent = true,
  StudyFileSaver? save,
}) async {
  t.view.physicalSize = Size(width, 1050);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme(theme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundary,
        child: StudyScreen(
          client: c,
          ensureConsent: (_) async => consent,
          saveFile: save ?? (a, b, c, d) async {},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> start(
  WidgetTester t,
  FakeStudy c, {
  double width = 1100,
  double scale = 1,
}) async {
  await show(t, c, width: width, scale: scale);
  await tap(t, find.text('Start lesson').first);
}

Future<void> tab(WidgetTester t, String label) =>
    tap(t, find.widgetWithText(ChoiceChip, label));
String jwt(String actor, String session) =>
    'x.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://auth.test', 'sub': actor, 'session_id': session}))).replaceAll('=', '')}.x';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null)
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
  });
  testWidgets('empty topic explains next step without creating a request', (
    t,
  ) async {
    final c = FakeStudy();
    await show(t, c);
    await tap(t, find.text('Create my study pack'));
    expect(find.textContaining('Add a topic'), findsOneWidget);
    expect(c.creates, isEmpty);
  });
  testWidgets(
    'instant starter bypasses AI consent and opens real lesson controls',
    (t) async {
      final c = FakeStudy();
      await show(t, c, consent: false);
      await tap(t, find.text('Start lesson').first);
      expect(c.creates.single['starter'], 'percentages');
      expect(c.creates.single['consent'], isNull);
      expect(find.text('Percent means out of 100'), findsOneWidget);
      expect(find.text('Mark read & continue'), findsOneWidget);
    },
  );
  testWidgets('AI consent denied does not submit pasted text', (t) async {
    final c = FakeStudy();
    await show(t, c, consent: false);
    await t.enterText(find.widgetWithText(TextField, 'Your topic'), 'Algebra');
    await tap(t, find.text('Create my study pack'));
    expect(c.creates, isEmpty);
    expect(find.text('Algebra'), findsOneWidget);
  });
  testWidgets(
    'custom topic settings and notes are submitted only after consent',
    (t) async {
      final c = FakeStudy();
      await show(t, c);
      await t.enterText(
        find.widgetWithText(TextField, 'Your topic'),
        'Learn fractions',
      );
      await tap(t, find.text('Use my notes (optional)'));
      await t.enterText(
        find.widgetWithText(TextField, 'Reference notes'),
        'My own notes about fractions.',
      );
      await tap(t, find.text('Personalize my session'));
      await tap(t, find.text('Know the basics'));
      await tap(t, find.text('Prepare for a test'));
      await tap(t, find.text('20 minutes'));
      await tap(t, find.text('Create my study pack'));
      final b = c.creates.single;
      expect(b['topic'], 'Learn fractions');
      expect(b['notes'], 'My own notes about fractions.');
      expect(b['level'], 'intermediate');
      expect(b['goal'], 'exam');
      expect(b['minutes'], 20);
      expect(b['consent'], true);
    },
  );
  testWidgets(
    'lost create acknowledgement keeps exactly the same request for retry',
    (t) async {
      final c = FakeStudy()..failCreate = true;
      await show(t, c);
      await t.enterText(
        find.widgetWithText(TextField, 'Your topic'),
        'Fractions',
      );
      await tap(t, find.text('Create my study pack'));
      expect(find.text('Retry same request'), findsOneWidget);
      await tap(t, find.text('Retry same request'));
      expect(c.creates.length, 2);
      expect(c.creates[0], c.creates[1]);
      expect(find.text('Percent means out of 100'), findsOneWidget);
    },
  );
  testWidgets(
    'preparing pack can be revisited and polling opens completed result',
    (t) async {
      final c = FakeStudy()..preparing = true;
      await show(t, c);
      await t.enterText(
        find.widgetWithText(TextField, 'Your topic'),
        'Fractions',
      );
      await t.ensureVisible(find.text('Create my study pack'));
      await t.tap(find.text('Create my study pack'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('KORLIX is preparing your study pack'), findsOneWidget);
      c.current = pack(key: c.current!['id']);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Percent means out of 100'), findsOneWidget);
      expect(c.creates.length, 1);
    },
  );
  testWidgets(
    'failed generation returns to editable topic and asks to re-paste notes',
    (t) async {
      final c = FakeStudy()..failed = true;
      await show(t, c);
      await t.enterText(
        find.widgetWithText(TextField, 'Your topic'),
        'Fractions',
      );
      await tap(t, find.text('Create my study pack'));
      await tap(t, find.text('Try this topic again'));
      expect(find.text('Create my study pack'), findsOneWidget);
      expect(
        find.textContaining('Paste any reference notes again'),
        findsOneWidget,
      );
    },
  );
  testWidgets('reading progress advances through sections into flashcards', (
    t,
  ) async {
    final c = FakeStudy();
    await start(t, c);
    await tap(t, find.text('Mark read & continue'));
    expect(find.text('Find a discount').hitTestable(), findsOneWidget);
    await tap(t, find.text('Mark read & continue'));
    await tap(t, find.text('Mark read & try flashcards'));
    expect(find.text('What does 15% mean?'), findsOneWidget);
    expect(studyMap(studyMap(c.current!['progress'])['read']).length, 3);
  });
  testWidgets('cards conceal answer until reveal and save recall rating', (
    t,
  ) async {
    final c = FakeStudy();
    await start(t, c);
    await tab(t, 'Flashcards');
    expect(find.text('15 out of every 100, or 0.15.'), findsNothing);
    await tap(t, find.text('Reveal answer'));
    expect(find.text('15 out of every 100, or 0.15.'), findsOneWidget);
    await tap(t, find.text('I knew this'));
    expect(c.events.last['rating'], 'known');
    expect(find.text('Practice prompt 1'), findsOneWidget);
    expect(find.text('Answer for card 1'), findsNothing);
  });
  testWidgets('due-only review removes rated cards and shows caught-up state', (
    t,
  ) async {
    final c = FakeStudy();
    await start(t, c);
    await tab(t, 'Flashcards');
    await tap(t, find.text('Ready to review (4)'));
    for (var i = 0; i < 4; i++) {
      await tap(t, find.text('Reveal answer'));
      await tap(t, find.text('Review again'));
    }
    expect(find.text('You’re caught up for now'), findsOneWidget);
    await tap(t, find.text('Practice all cards'));
    expect(find.text('What does 15% mean?'), findsOneWidget);
  });
  testWidgets(
    'quiz gives hints and explanation, correction retains first-try result',
    (t) async {
      final c = FakeStudy();
      await start(t, c);
      await tab(t, 'Practice quiz');
      expect(find.text('Divide by 100.'), findsNothing);
      await tap(t, find.text('Give me a hint'));
      expect(find.text('Divide by 100.'), findsOneWidget);
      await tap(t, find.text('2.5'));
      await tap(t, find.text('Check answer'));
      expect(find.textContaining('Let’s work through it.'), findsOneWidget);
      await tap(t, find.text('Try this question again'));
      await tap(t, find.text('0.25'));
      await tap(t, find.text('Check answer'));
      expect(find.textContaining('That’s right.'), findsOneWidget);
      expect(find.textContaining('First-try correct: 0 of 4'), findsOneWidget);
      expect(c.current!['progress']['answers']['0']['firstChoice'], 0);
      expect(c.current!['progress']['answers']['0']['choice'], 1);
    },
  );
  testWidgets(
    'quiz restart needs confirmation and does not remove reading progress',
    (t) async {
      final c = FakeStudy();
      await start(t, c);
      await tap(t, find.text('Mark read & continue'));
      await tab(t, 'Practice quiz');
      await tap(t, find.text('0.25'));
      await tap(t, find.text('Check answer'));
      await tap(t, find.text('Restart quiz'));
      await tap(t, find.text('Cancel'));
      expect(c.current!['progress']['answers'], isNotEmpty);
      await tap(t, find.text('Restart quiz'));
      await tap(t, find.widgetWithText(FilledButton, 'Restart quiz'));
      expect(c.current!['progress']['answers'], isEmpty);
      expect(c.current!['progress']['read']['0'], true);
    },
  );
  testWidgets('uncertain progress save is retried with stable event key', (
    t,
  ) async {
    final c = FakeStudy()..failEvent = true;
    await start(t, c);
    await tap(t, find.text('Mark read & continue'));
    expect(find.text('Retry saving progress'), findsOneWidget);
    await tap(t, find.text('Retry saving progress'));
    expect(c.events.length, 2);
    expect(c.events[0], c.events[1]);
    expect(find.text('1/3 sections read'), findsOneWidget);
  });
  testWidgets('refresh recovers saved progress and unlocks uncertain save', (
    t,
  ) async {
    final c = FakeStudy()..failEvent = true;
    await start(t, c);
    await tap(t, find.text('Mark read & continue'));
    await tap(t, find.text('Refresh saved progress'));
    expect(find.text('Retry saving progress'), findsNothing);
    expect(find.textContaining('Progress refreshed'), findsOneWidget);
  });
  testWidgets(
    'library search, resume and confirmed removal operate on owned pack',
    (t) async {
      final c = FakeStudy();
      await start(t, c);
      await tab(t, 'My learning');
      await t.enterText(
        find.widgetWithText(TextField, 'Search your study packs'),
        'missing topic',
      );
      await t.pump();
      expect(find.text('No matching study packs'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'Search your study packs'),
        'percent',
      );
      await t.pump();
      await tap(t, find.text('Continue learning'));
      expect(c.opens, 1);
      await tab(t, 'My learning');
      await tap(t, find.text('Delete'));
      await tap(t, find.text('Cancel'));
      expect(c.deletes, 0);
      await tap(t, find.text('Delete'));
      await tap(t, find.text('Delete pack'));
      expect(c.deletes, 1);
      expect(find.text('Start your first study pack'), findsOneWidget);
    },
  );
  testWidgets(
    'export sends plain-text guide to file saver and reports completion',
    (t) async {
      final c = FakeStudy();
      String? name, type;
      await show(
        t,
        c,
        save: (bytes, n, m, rect) async {
          name = n;
          type = m;
          expect(utf8.decode(bytes), contains('answer key'));
        },
      );
      await tap(t, find.text('Start lesson').first);
      await tap(t, find.text('Export study guide'));
      expect(name, endsWith('.txt'));
      expect(type, 'text/plain');
      expect(find.textContaining('Study guide export started'), findsOneWidget);
    },
  );
  testWidgets('sign-in change clears private content and rejects late export', (
    t,
  ) async {
    final c = FakeStudy()..exportWait = Completer();
    var saves = 0;
    await show(
      t,
      c,
      save: (a, b, c, d) async {
        saves++;
      },
    );
    await tap(t, find.text('Start lesson').first);
    await t.ensureVisible(find.text('Export study guide'));
    await t.tap(find.text('Export study guide'));
    await t.pump();
    c.onAccessDenied!();
    await t.pump();
    c.exportWait!.complete(utf8.encode('Private lesson'));
    await t.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Percentages you can actually use'), findsNothing);
    expect(find.textContaining('Your sign-in changed'), findsOneWidget);
  });
  testWidgets('sign-in change closes private deletion confirmation', (t) async {
    final c = FakeStudy();
    await start(t, c);
    await tab(t, 'My learning');
    await tap(t, find.text('Delete'));
    expect(find.text('Delete this study pack?'), findsOneWidget);
    c.onAccessDenied!();
    await t.pumpAndSettle();
    expect(find.text('Delete this study pack?'), findsNothing);
    expect(c.deletes, 0);
  });
  testWidgets('focus timer can start and pause without AI requests', (t) async {
    final c = FakeStudy();
    await start(t, c);
    await tap(t, find.text('Focus 5:00'));
    expect(find.text('Pause 5:00'), findsOneWidget);
    await tap(t, find.text('Pause 5:00'));
    expect(find.text('Focus 5:00'), findsOneWidget);
    expect(c.creates.length, 1);
    expect(c.events, isEmpty);
  });
  test(
    'review count includes unrated and due cards but excludes future ratings',
    () {
      final s = pack();
      s['progress']['cards'] = {
        '0': {'due': '2026-10-01T00:00:00Z'},
        '1': {'due': '2026-09-01T00:00:00Z'},
      };
      expect(studyDue(s, DateTime.utc(2026, 9, 27)), 3);
    },
  );
  test(
    'client binds session and rejects late responses after sign-in changes',
    () async {
      final changes = ValueNotifier(0), response = Completer<http.Response>();
      var actor = 'user-a';
      final client = StudyClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {
          'Authorization': 'Bearer ${jwt(actor, 'session')}',
        },
        sessionChanges: changes,
        client: MockClient((r) => response.future),
      );
      final pending = client.open(id);
      actor = 'user-b';
      changes.value++;
      response.complete(http.Response(jsonEncode({'set': pack()}), 200));
      await expectLater(pending, throwsA(isA<StudyException>()));
      await expectLater(client.list(), throwsA(isA<StudyException>()));
      client.dispose();
      changes.dispose();
    },
  );
  test(
    'client rejects mismatched pack identity and wrong download content type',
    () async {
      final client = StudyClient(
        backendBaseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        client: MockClient(
          (r) async => r.url.path.endsWith('/export')
              ? http.Response(
                  '<html>Login</html>',
                  200,
                  headers: {'content-type': 'text/html'},
                )
              : http.Response(jsonEncode({'set': pack(key: 'different')}), 200),
        ),
      );
      await expectLater(client.open(id), throwsA(isA<StudyException>()));
      await expectLater(client.export(id), throwsA(isA<StudyException>()));
      client.dispose();
    },
  );
  testWidgets(
    'phone and desktop layouts fit with larger text on all study tabs',
    (t) async {
      for (final width in [320.0, 390.0, 1440.0]) {
        final c = FakeStudy();
        await start(t, c, width: width, scale: 1.25);
        expect(t.takeException(), isNull);
        for (final label in ['Flashcards', 'Practice quiz', 'Recap']) {
          await tab(t, label);
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox());
        await t.pump();
      }
    },
  );
  testWidgets(
    'optional screenshots use actual Flutter lesson and quiz screens',
    (t) async {
      final dir = Platform.environment['STUDY_CAPTURE_DIR'];
      if (dir == null) return;
      Directory(dir).createSync(recursive: true);
      for (final width in [390.0, 1440.0]) {
        final c = FakeStudy();
        await show(
          t,
          c,
          width: width,
          theme: width == 390 ? 'pure_white' : 'midnight',
        );
        Future<void> capture(String label) async {
          await t.pumpAndSettle();
          await t.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$dir/study-$label-${width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('start');
        await tap(t, find.text('Start lesson').first);
        await capture('lesson');
        await tab(t, 'Practice quiz');
        await t.ensureVisible(find.text('What is 25% as a decimal?'));
        await capture('quiz');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump();
      }
    },
  );
}
