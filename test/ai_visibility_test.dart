import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/ai_visibility/visibility_client.dart';
import 'package:ai_wiz_command_center/ai_visibility/visibility_screen.dart';

final business = <String, dynamic>{
  'businessName': 'Bright Pine',
  'website': 'https://brightpine.example.com/',
  'services': 'office cleaning',
  'market': 'Columbus',
  'facts': 'Evening cleaning',
};
Map<String, dynamic> profile() => {
  ...business,
  'questions': visibilitySuggestedQuestions(business),
};
Map<String, dynamic> report({
  String id = 'report',
  String state = 'completed',
  String fingerprint = 'same',
  String date = '2026-09-27T12:00:00Z',
}) => {
  'id': id,
  'state': state,
  'phase': 'Checking three discovery questions',
  'createdAt': date,
  'completedAt': date,
  'charged': state == 'completed' ? 3 : 0,
  'error': state == 'failed' ? 'No credits were charged.' : null,
  'progress': {
    'completedActions': <String>[],
    'inquiries': 0,
    'bookings': 0,
    'notes': '',
  },
  'result': {
    'fingerprint': fingerprint,
    'business': business,
    'provider': 'OpenAI API web search',
    'model': 'gpt-6-astra',
    'sampleCount': 3,
    'nameMatches': 1,
    'siteCitations': 1,
    'scannedAt': date,
    'websiteObserved': true,
    'summary': 'Search-based findings.',
    'limits': 'Three samples; not a ranking or a guarantee.',
    'samples': [
      {
        'question': 'Which cleaners should customers compare?',
        'answer': 'Bright Pine is one option. Verify services.',
        'nameMatched': true,
        'siteCited': true,
        'citations': [
          {
            'title': 'Cited company page',
            'url': 'https://brightpine.example.com/services',
          },
        ],
        'retrievedSources': [
          {
            'title': 'Company',
            'url': 'https://brightpine.example.com/services',
          },
        ],
      },
    ],
    'observations': [
      {
        'topic': 'Service information',
        'observation': 'Cleaning is described.',
        'sourceUrl': 'https://brightpine.example.com/services',
      },
    ],
    'actions': [
      {
        'id': 'action-0',
        'title': 'Clarify your service area',
        'why': 'Help customers compare.',
        'how': 'Add accurate places served.',
        'priority': 'high',
        'sourceUrl': '',
      },
    ],
    'drafts': [
      {
        'type': 'faq',
        'title': 'Questions & answers',
        'body':
            'DRAFT — REVIEW AND VERIFY BEFORE PUBLISHING\n[ADD VERIFIED DETAIL: service hours]',
        'sourceUrls': <String>[],
      },
    ],
  },
};

class FakeVisibility extends VisibilityClient {
  FakeVisibility()
    : super(backendBaseUrl: 'https://example.test', headersBuilder: () => {});
  Map<String, dynamic>? profileRow = {
    'data': profile(),
    'updatedAt': '2026-09-27',
  };
  List<Map<String, dynamic>> runs = [];
  List<String> starts = [];
  int profileSaves = 0, progressSaves = 0, removes = 0, clears = 0, polls = 0;
  bool failStart = false, failProfile = false, failProgress = false;
  @override
  Future<Map<String, dynamic>> load() async => {
    'profile': profileRow,
    'runs': runs,
  };
  @override
  Future<Map<String, dynamic>> saveProfile(Map<String, dynamic> data) async {
    profileSaves++;
    if (failProfile) {
      throw const VisibilityException('Connection failed. Retry.');
    }
    if ((data['questions'] as List).every((x) => x == '')) {
      data = {...data, 'questions': visibilitySuggestedQuestions(data)};
    }
    profileRow = {'data': data, 'updatedAt': '2026-09-27'};
    return profileRow!;
  }

  @override
  Future<Map<String, dynamic>> start(String key) async {
    starts.add(key);
    if (failStart) {
      throw const VisibilityException(
        'Connection interrupted. Refresh before retrying.',
      );
    }
    final r = report(state: 'running');
    runs = [r, ...runs];
    return r;
  }

  @override
  Future<Map<String, dynamic>> run(String id) async {
    polls++;
    return runs.firstWhere((r) => r['id'] == id);
  }

  @override
  Future<Map<String, dynamic>> progress(
    String id,
    Map<String, dynamic> data,
  ) async {
    progressSaves++;
    if (failProgress) throw const VisibilityException('Progress interrupted.');
    final r = runs.firstWhere((r) => r['id'] == id);
    r['progress'] = data;
    return r;
  }

  @override
  Future<void> remove(String id) async {
    removes++;
    runs.removeWhere((r) => r['id'] == id);
  }

  @override
  Future<void> clear() async {
    clears++;
    runs = [];
    profileRow = null;
  }
}

Future<void> show(
  WidgetTester t,
  FakeVisibility c, {
  double width = 1440,
  double height = 1000,
  double scale = 1,
  Future<bool> Function()? consent,
  Future<bool> Function(Uri)? open,
  Future<void> Function(String)? copy,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(scale),
        ),
        child: AiVisibilityScreen(
          client: c,
          ensureConsent: consent ?? () async => true,
          openLink: open,
          copyText: copy,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 80));
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  test(
    'authenticated profile PUT returns confirmed profile and rejects malformed acknowledgement',
    () async {
      bool valid = true;
      final c = VisibilityClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'Bearer token'},
        client: MockClient((r) async {
          expect(r.url.path, '/api/ai-visibility/profile');
          expect(r.method, 'PUT');
          expect(r.headers['Authorization'], 'Bearer token');
          return http.Response(
            jsonEncode(
              valid
                  ? {
                      'profile': {'data': profile()},
                    }
                  : {},
            ),
            200,
          );
        }),
      );
      expect((await c.saveProfile(profile()))['data'], profile());
      valid = false;
      await expectLater(
        c.saveProfile(profile()),
        throwsA(isA<VisibilityException>()),
      );
      c.dispose();
    },
  );
  test('session changes discard a stale visibility response', () async {
    String token(String u) =>
        'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': u, 'session_id': u})))}.signature';
    var auth = token('one'), locked = 0;
    final changes = ValueNotifier(0), pending = Completer<http.Response>();
    final c = VisibilityClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {'Authorization': 'Bearer $auth'},
      sessionChanges: changes,
      client: MockClient((_) => pending.future),
    )..onAccessDenied = () => locked++;
    final request = c.load();
    auth = token('two');
    changes.value++;
    expect(locked, 1);
    final check = expectLater(request, throwsA(isA<VisibilityException>()));
    pending.complete(http.Response('{"profile":null,"runs":[]}', 200));
    await check;
    c.dispose();
    changes.dispose();
  });
  testWidgets(
    'required setup errors are visible on phones and confirmed saving opens overview',
    (t) async {
      final c = FakeVisibility()..profileRow = null;
      await show(t, c, width: 390, height: 780, scale: 1.25);
      await t.enterText(
        find.byKey(const Key('visibility-businessName')),
        'Bright Pine',
      );
      await tap(t, find.byKey(const Key('visibility-save-profile')));
      expect(c.profileSaves, 0);
      expect(find.text('Enter your website.').hitTestable(), findsOneWidget);
      for (final e in {
        'website': 'brightpine.example.com',
        'services': 'office cleaning',
        'market': 'Columbus',
      }.entries) {
        await t.enterText(find.byKey(Key('visibility-${e.key}')), e.value);
      }
      c.failProfile = true;
      await tap(t, find.byKey(const Key('visibility-save-profile')));
      expect(
        find.byKey(const Key('visibility-setup-error')).hitTestable(),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('visibility-businessName')))
            .controller!
            .text,
        'Bright Pine',
      );
      c.failProfile = false;
      await tap(t, find.byKey(const Key('visibility-save-profile')));
      expect(c.profileRow!['data']['questions'].length, 3);
      expect(find.byKey(const Key('visibility-scan')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'consent denial starts no scan and failed starts retain one request identity',
    (t) async {
      final c = FakeVisibility();
      await show(t, c, consent: () async => false);
      await tap(t, find.byKey(const Key('visibility-scan')));
      expect(c.starts, isEmpty);
      await t.pumpWidget(const SizedBox());
      final next = FakeVisibility()..failStart = true;
      await show(t, next);
      await tap(t, find.byKey(const Key('visibility-scan')));
      await tap(t, find.byKey(const Key('visibility-scan')));
      expect(next.starts.length, 2);
      expect(next.starts[0], next.starts[1]);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('running scans reopen, poll and finish without redispatch', (
    t,
  ) async {
    final c = FakeVisibility()..runs = [report(state: 'running')];
    await show(t, c, width: 390);
    expect(find.textContaining('KORLIX is working:'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('visibility-scan')))
          .onPressed,
      isNull,
    );
    expect(c.starts, isEmpty);
    c.runs = [report()];
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    await t.pump();
    expect(c.polls, greaterThan(0));
    expect(c.starts, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'reports show evidence, open real sources and copy drafts at phone and desktop widths',
    (t) async {
      for (final width in [390.0, 1440.0]) {
        final c = FakeVisibility()..runs = [report()];
        Uri? opened;
        String? copied;
        await show(
          t,
          c,
          width: width,
          scale: 1.3,
          open: (u) async {
            opened = u;
            return true;
          },
          copy: (s) async {
            copied = s;
          },
        );
        await tap(t, find.text('Open report'));
        expect(find.text('Name appears'), findsOneWidget);
        expect(find.textContaining('New baseline:'), findsOneWidget);
        await tap(t, find.text('Which cleaners should customers compare?'));
        await tap(t, find.text('Cited company page'));
        expect(opened.toString(), 'https://brightpine.example.com/services');
        await tap(t, find.text('Questions & answers'));
        await tap(t, find.text('Copy draft'));
        expect(copied, contains('ADD VERIFIED DETAIL'));
        await tap(t, find.byKey(const Key('visibility-copy-report')));
        expect(copied, contains('OpenAI API web search'));
        expect(copied, contains('https://brightpine.example.com/services'));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    },
  );
  test(
    'comparison requires the same fingerprint and an earlier completed report',
    () {
      final current = report();
      expect(
        comparableVisibilityRun(current, [
          report(id: 'changed', fingerprint: 'different', date: '2026-09-26'),
        ]),
        isNull,
      );
      expect(
        comparableVisibilityRun(current, [
          report(id: 'future', date: '2026-09-28'),
        ]),
        isNull,
      );
      expect(
        comparableVisibilityRun(current, [
          report(id: 'old', date: '2026-09-26'),
        ])!['id'],
        'old',
      );
    },
  );
  testWidgets('progress is manual, bounded and retained after a failed save', (
    t,
  ) async {
    final c = FakeVisibility()..runs = [report()];
    await show(t, c, width: 390);
    await tap(t, find.text('Open report'));
    await t.ensureVisible(find.byKey(const Key('visibility-inquiries')));
    await t.enterText(find.byKey(const Key('visibility-inquiries')), '-1');
    await tap(t, find.byKey(const Key('visibility-save-progress')));
    expect(c.progressSaves, 0);
    await t.enterText(find.byKey(const Key('visibility-inquiries')), '7');
    await t.enterText(find.byKey(const Key('visibility-bookings')), '2');
    await t.enterText(
      find.byKey(const Key('visibility-progress-notes')),
      'Follow-up next week',
    );
    c.failProgress = true;
    await tap(t, find.byKey(const Key('visibility-save-progress')));
    expect(
      t
          .widget<TextField>(find.byKey(const Key('visibility-progress-notes')))
          .controller!
          .text,
      'Follow-up next week',
    );
    c.failProgress = false;
    await tap(t, find.byKey(const Key('visibility-save-progress')));
    expect(c.runs[0]['progress']['inquiries'], 7);
    expect(c.runs[0]['result']['nameMatches'], 1);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('account change clears private setup and report contents', (
    t,
  ) async {
    final c = FakeVisibility()..runs = [report()];
    await show(t, c);
    await tap(t, find.text('Open report'));
    c.onAccessDenied!();
    await t.pumpAndSettle();
    expect(find.textContaining('Your session changed.'), findsOneWidget);
    expect(find.text('Bright Pine'), findsNothing);
    expect(find.byKey(const Key('visibility-copy-report')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('remove and clear require confirmation', (t) async {
    final c = FakeVisibility()..runs = [report()];
    await show(t, c);
    await tap(t, find.text('Open report'));
    await tap(t, find.text('Remove this report'));
    expect(c.removes, 0);
    await tap(t, find.text('Keep'));
    expect(c.runs.length, 1);
    await tap(t, find.text('Remove this report'));
    await tap(t, find.text('Remove'));
    expect(c.removes, 1);
    await tap(t, find.text('Business'));
    await tap(t, find.text('Clear my AI Visibility data'));
    expect(c.clears, 0);
    await tap(t, find.text('Remove'));
    expect(c.clears, 1);
    expect(find.byKey(const Key('visibility-save-profile')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
