import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/contract_radar/radar_client.dart';
import 'package:ai_wiz_command_center/contract_radar/radar_screen.dart';

final profile = {
  'businessName': 'Fixture Services',
  'services': 'Office cleaning',
  'location': 'Ohio',
  'capacity': 'Five staff',
  'certifications': 'Insurance held',
  'naics': '561720',
};
const sourceUrl = 'https://sam.gov/opp/1234567890abcdef1234567890abcdef/view';
Map<String, dynamic> notice() => {
  'title': 'Office cleaning opportunity',
  'agency': 'Fixture agency',
  'location': 'Ohio',
  'sourceUrl': sourceUrl,
  'summary': 'Provide weekly cleaning. Insurance required.',
  'deadline': '2099-10-01',
  'noticeType': 'solicitation',
  'source': 'official_search',
  'noticeText': '',
  'matchReason': 'Matches your services.',
};
Map<String, dynamic> opportunity() => {
  'id': 'saved',
  'data': notice(),
  'stage': 'saved',
  'notes': '',
  'review': <String, dynamic>{},
};
Map<String, dynamic> jobData(String state, {String kind = 'discover'}) => {
  'id': 'job',
  'kind': kind,
  'state': state,
  'result': {
    'opportunities': [notice()],
    'message': 'Review the official source.',
    'searchedAt': '2026-09-27T16:00:00Z',
  },
  'charged': 1,
  'error': state == 'failed' ? 'No credit was charged.' : null,
};

class FakeRadar extends RadarClient {
  FakeRadar()
    : super(backendBaseUrl: 'https://example.test', headersBuilder: () => {});
  Map<String, dynamic>? profileRow = {
    'data': Map<String, dynamic>.from(profile),
    'updatedAt': '2026-09-27',
  };
  List<Map<String, dynamic>> saved = [], jobs = [];
  List<Map<String, dynamic>> starts = [];
  int saves = 0, removes = 0, polls = 0, clears = 0;
  bool failStart = false, failSave = false;
  @override
  Future<Map<String, dynamic>> load() async => {
    'profile': profileRow,
    'opportunities': saved,
    'jobs': jobs,
  };
  @override
  Future<void> saveProfile(Map<String, dynamic> data) async {
    profileRow = {
      'data': Map<String, dynamic>.from(data),
      'updatedAt': '2026-09-27',
    };
  }

  @override
  Future<Map<String, dynamic>> saveOpportunity(
    Map<String, dynamic> data,
  ) async {
    if (failSave) {
      throw const RadarException(
        'Connection interrupted. Reopen the editor to retry.',
      );
    }
    saves++;
    final o = opportunity();
    if (data['job_id'] == null) {
      o['data'] = {...data, 'source': 'import', 'summary': 'Imported by you.'};
    }
    saved = [o];
    return o;
  }

  @override
  Future<void> updateOpportunity(String id, Map<String, dynamic> data) async {
    final o = saved.firstWhere((o) => o['id'] == id);
    if (data.containsKey('stage')) o['stage'] = data['stage'];
    if (data.containsKey('notes')) o['notes'] = data['notes'];
    if (data.containsKey('noticeText')) {
      (o['data'] as Map)['noticeText'] = data['noticeText'];
    }
  }

  @override
  Future<void> remove(String id) async {
    removes++;
    saved.removeWhere((o) => o['id'] == id);
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = [];
    jobs = [];
    profileRow = null;
  }

  @override
  Future<Map<String, dynamic>> start(Map<String, dynamic> data) async {
    starts.add(Map.of(data));
    if (failStart) {
      throw const RadarException(
        'Request interrupted. Refresh before retrying.',
      );
    }
    jobs = [jobData('running', kind: data['kind'])];
    return jobs.first;
  }

  @override
  Future<Map<String, dynamic>> job(String id) async {
    polls++;
    return jobs.first;
  }
}

Future<void> show(
  WidgetTester t,
  FakeRadar c, {
  double width = 1500,
  double scale = 1,
  Future<bool> Function()? consent,
  Future<bool> Function(Uri)? open,
  Future<void> Function(String)? copy,
}) async {
  t.view.physicalSize = Size(width, 1100);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1100),
          textScaler: TextScaler.linear(scale),
        ),
        child: ContractRadarScreen(
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
    'client keeps authentication, endpoint and error handling scoped to Radar',
    () async {
      final c = RadarClient(
        backendBaseUrl: 'https://example.test/',
        headersBuilder: () => {'Authorization': 'Bearer test'},
        client: MockClient((r) async {
          expect(r.url.path, '/api/contract-radar');
          expect(r.headers['Authorization'], 'Bearer test');
          return http.Response(
            '{"profile":null,"opportunities":[],"jobs":[]}',
            200,
          );
        }),
      );
      expect((await c.load())['profile'], isNull);
      c.dispose();
    },
  );
  test(
    'session rotation keeps access while account change rejects stale responses',
    () async {
      String token(String user, String sig) =>
          'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': user, 'session_id': user})))}.$sig';
      String auth = token('one', 'a');
      final changes = ValueNotifier(0), pending = Completer<http.Response>();
      var locked = 0;
      final c = RadarClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'Bearer $auth'},
        sessionChanges: changes,
        client: MockClient((_) => pending.future),
      )..onAccessDenied = () => locked++;
      final work = c.load();
      auth = token('one', 'b');
      changes.value++;
      expect(locked, 0);
      auth = token('two', 'c');
      changes.value++;
      expect(locked, 1);
      final check = expectLater(work, throwsA(isA<RadarException>()));
      pending.complete(
        http.Response('{"profile":null,"opportunities":[],"jobs":[]}', 200),
      );
      await check;
      c.dispose();
      changes.dispose();
    },
  );
  testWidgets(
    'first use saves a business profile and reaches discovery on phone and desktop',
    (t) async {
      for (final width in [390.0, 1500.0]) {
        final c = FakeRadar()..profileRow = null;
        await show(t, c, width: width, scale: 1.4);
        expect(find.text('Your business profile'), findsOneWidget);
        for (final e in {
          'businessName': 'New business',
          'services': 'Meter installation',
          'location': 'Ohio',
        }.entries) {
          await t.enterText(find.byKey(Key('radar-profile-${e.key}')), e.value);
        }
        await tap(t, find.byKey(const Key('radar-save-profile')));
        expect(c.profileRow!['data']['services'], 'Meter installation');
        expect(find.byKey(const Key('radar-discover')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('consent denial never sends a discovery request', (t) async {
    final c = FakeRadar();
    await show(t, c, consent: () async => false);
    await tap(t, find.byKey(const Key('radar-discover')));
    expect(c.starts, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'discovery starts once and reopened jobs poll without redispatch',
    (t) async {
      final c = FakeRadar();
      await show(t, c);
      await t.tap(find.byKey(const Key('radar-discover')));
      await t.pump();
      await t.pump();
      expect(c.starts.length, 1);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('radar-discover')))
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
      final reopened = FakeRadar()..jobs = c.jobs;
      await show(t, reopened, width: 390);
      expect(
        find.textContaining('Nova is searching official notices'),
        findsOneWidget,
      );
      reopened.jobs = [jobData('completed')];
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.text('Office cleaning opportunity'), findsOneWidget);
      expect(reopened.starts, isEmpty);
      expect(reopened.polls, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'source links open the actual notice and saved results enter the pipeline',
    (t) async {
      Uri? opened;
      final c = FakeRadar()..jobs = [jobData('completed')];
      await show(
        t,
        c,
        open: (u) async {
          opened = u;
          return true;
        },
      );
      await tap(t, find.text('Open source'));
      expect(opened.toString(), sourceUrl);
      await tap(t, find.text('Save opportunity'));
      expect(c.saves, 1);
      expect(find.text('Saved'), findsOneWidget);
      await tap(t, find.text('Pipeline').first);
      expect(find.byKey(const Key('radar-review')), findsOneWidget);
      expect(find.textContaining('does not submit bids'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'network retry preserves the request key and avoids a second identity',
    (t) async {
      final c = FakeRadar()..failStart = true;
      await show(t, c);
      await tap(t, find.byKey(const Key('radar-discover')));
      await tap(t, find.byKey(const Key('radar-discover')));
      expect(c.starts.length, 2);
      expect(c.starts[0]['request_key'], c.starts[1]['request_key']);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pasted RFP survives a failed save and never auto-submits', (
    t,
  ) async {
    final c = FakeRadar()..failSave = true;
    await show(t, c);
    await tap(t, find.text('Paste an RFP'));
    await t.enterText(
      find.byKey(const Key('radar-import-title')),
      'Private opportunity',
    );
    await t.enterText(
      find.byKey(const Key('radar-notice-text')),
      'Private RFP text with insurance requirements.',
    );
    await tap(t, find.byKey(const Key('radar-save-rfp')));
    expect(find.textContaining('Connection interrupted'), findsOneWidget);
    c.failSave = false;
    await tap(t, find.text('Paste an RFP'));
    expect(
      find.text('Private RFP text with insurance requirements.'),
      findsOneWidget,
    );
    await tap(t, find.byKey(const Key('radar-save-rfp')));
    expect(c.saves, 1);
    expect(c.starts, isEmpty);
    expect(find.byKey(const Key('radar-review')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'account switch clears the workspace and closes a private RFP editor',
    (t) async {
      final c = FakeRadar();
      await show(t, c);
      await tap(t, find.text('Paste an RFP'));
      await t.enterText(
        find.byKey(const Key('radar-notice-text')),
        'Confidential buyer requirements',
      );
      c.onAccessDenied!();
      await t.pumpAndSettle();
      expect(find.text('Confidential buyer requirements'), findsNothing);
      expect(find.textContaining('Your session changed'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'review workspace shows evidence and copies a draft at enlarged phone size',
    (t) async {
      String? copied;
      final o = opportunity()
        ..['review'] = {
          'summary': 'Verify your documents.',
          'fit': 'needs_review',
          'limitedToSummary': true,
          'profileUpdatedAt': '2026-09-27',
          'reasons': ['Services align'],
          'requirements': [
            {
              'requirement': 'Insurance',
              'evidence': 'Insurance required.',
              'profileEvidence': 'Insurance held',
              'status': 'provided',
            },
          ],
          'questions': ['What is the square footage?'],
          'nextSteps': ['Check amendments'],
          'draft':
              'DRAFT — VERIFY BEFORE SUBMISSION\n[NEEDS YOUR INPUT: pricing]',
        };
      final c = FakeRadar()..saved = [o];
      await show(
        t,
        c,
        width: 390,
        scale: 1.6,
        copy: (s) async {
          copied = s;
        },
      );
      await tap(t, find.text('Pipeline').last);
      await tap(t, find.text('Open workspace'));
      expect(find.textContaining('Summary-only review'), findsOneWidget);
      await tap(t, find.byKey(const Key('radar-copy-draft')));
      expect(copied, contains('Insurance required.'));
      expect(copied, contains('[NEEDS YOUR INPUT: pricing]'));
      expect(c.starts, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('removal and clearing need explicit confirmation', (t) async {
    final c = FakeRadar()..saved = [opportunity()];
    await show(t, c);
    await tap(t, find.text('Pipeline').first);
    await tap(t, find.text('Open workspace'));
    await tap(t, find.byTooltip('Remove opportunity'));
    await tap(t, find.text('Keep'));
    expect(c.removes, 0);
    await tap(t, find.byTooltip('Remove opportunity'));
    await tap(t, find.text('Remove'));
    expect(c.removes, 1);
    await tap(t, find.text('Business').first);
    await tap(t, find.text('Clear my Contract Radar data'));
    await tap(t, find.text('Keep'));
    expect(c.clears, 0);
    await t.pumpWidget(const SizedBox());
  });
}
