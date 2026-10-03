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
  final List<Map<String, dynamic>> saveRequests = [];
  int saves = 0, removes = 0, polls = 0, clears = 0;
  int profileSaves = 0, loads = 0;
  bool failProfile = false;
  Completer<void>? profileGate;
  bool failStart = false, failSave = false;
  @override
  Future<Map<String, dynamic>> load() async {
    loads++;
    return {'profile': profileRow, 'opportunities': saved, 'jobs': jobs};
  }

  @override
  Future<Map<String, dynamic>> saveProfile(Map<String, dynamic> data) async {
    profileSaves++;
    if (profileGate != null) await profileGate!.future;
    if (failProfile) {
      throw const RadarException('Connection interrupted. Please retry.');
    }
    profileRow = {
      'data': Map<String, dynamic>.from(data),
      'updatedAt': '2026-09-27',
    };
    return profileRow!;
  }

  @override
  Future<Map<String, dynamic>> saveOpportunity(
    Map<String, dynamic> data,
  ) async {
    saveRequests.add(Map<String, dynamic>.from(data));
    if (failSave) {
      throw const RadarException(
        'Connection interrupted. Reopen the editor to retry.',
      );
    }
    saves++;
    final o = opportunity();
    if (data['job_id'] == null) {
      o['data'] = {...data, 'source': 'import', 'summary': 'Imported by you.'};
    } else {
      final job = jobs.firstWhere((j) => j['id'] == data['job_id']);
      o['data'] = Map<String, dynamic>.from(
        (job['result']['opportunities'] as List)[data['index'] as int] as Map,
      );
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
  double height = 1100,
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

Future<void> fillBusiness(WidgetTester t) async {
  for (final e in {
    'businessName': 'New business',
    'services': 'Office cleaning',
    'location': 'Ohio',
  }.entries) {
    await t.enterText(find.byKey(Key('radar-profile-${e.key}')), e.value);
  }
}

Map<String, dynamic> resultsJob() => jobData('completed')
  ..['result'] = {
    'opportunities': [
      {...notice(), 'title': 'Office cleaning bid', 'deadline': '2099-12-01'},
      {
        ...notice(),
        'title': 'Roof repair market research',
        'noticeType': 'sources_sought',
        'deadline': '2099-11-01',
        'sourceUrl':
            'https://sam.gov/opp/abcdef1234567890abcdef1234567890/view',
      },
    ],
    'message': 'Review the official source.',
    'searchedAt': '2026-09-27T16:00:00Z',
  };

void main() {
  test('profile PUT requires a confirmed saved profile response', () async {
    bool confirmed = true;
    final c = RadarClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {'Authorization': 'Bearer test'},
      client: MockClient((r) async {
        expect(r.method, 'PUT');
        expect(r.url.path, '/api/contract-radar/profile');
        expect(r.headers['Authorization'], 'Bearer test');
        expect(jsonDecode(r.body), profile);
        return http.Response(
          jsonEncode(
            confirmed
                ? {
                    'profile': {'data': profile, 'updatedAt': '2026-09-27'},
                  }
                : {},
          ),
          200,
        );
      }),
    );
    expect((await c.saveProfile(profile))['data'], profile);
    confirmed = false;
    await expectLater(c.saveProfile(profile), throwsA(isA<RadarException>()));
    c.dispose();
  });
  testWidgets(
    'phone save reveals and focuses missing fields, then confirms required-only profile',
    (t) async {
      final c = FakeRadar()..profileRow = null;
      await show(t, c, width: 390, height: 780, scale: 1.25);
      await t.enterText(
        find.byKey(const Key('radar-profile-businessName')),
        'My business',
      );
      await tap(t, find.byKey(const Key('radar-save-profile')));
      expect(c.profileSaves, 0);
      expect(
        find.text('Describe the services or products you offer.').hitTestable(),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('radar-profile-services')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await t.enterText(
        find.byKey(const Key('radar-profile-services')),
        'Office cleaning',
      );
      await tap(t, find.byKey(const Key('radar-save-profile')));
      expect(c.profileSaves, 0);
      expect(
        find
            .text('Enter where you can work, such as a city or country.')
            .hitTestable(),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const Key('radar-profile-location')),
        'Jamaica',
      );
      await tap(t, find.byKey(const Key('radar-save-profile')));
      expect(c.profileSaves, 1);
      expect(c.profileRow!['data']['location'], 'Jamaica');
      expect(c.profileRow!['data']['certifications'], '');
      expect(
        c.loads,
        1,
        reason: 'A confirmed save does not depend on a second read',
      );
      expect(find.byKey(const Key('radar-discover')), findsOneWidget);
      expect(find.textContaining('Business profile saved.'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed phone save keeps entries with visible retry feedback and prevents duplicate saves',
    (t) async {
      final c = FakeRadar()
        ..profileRow = null
        ..failProfile = true;
      await show(t, c, width: 390, height: 780);
      for (final e in {
        'businessName': 'My business',
        'services': 'Cleaning',
        'location': 'Ohio',
      }.entries) {
        await t.enterText(find.byKey(Key('radar-profile-${e.key}')), e.value);
      }
      await tap(t, find.byKey(const Key('radar-save-profile')));
      expect(
        find.byKey(const Key('radar-profile-save-error')).hitTestable(),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextField>(
              find.byKey(const Key('radar-profile-businessName')),
            )
            .controller!
            .text,
        'My business',
      );
      expect(c.profileRow, isNull);
      c.failProfile = false;
      c.profileGate = Completer<void>();
      await t.ensureVisible(find.byKey(const Key('radar-save-profile')));
      await t.tap(find.byKey(const Key('radar-save-profile')));
      await t.pump();
      expect(find.text('Saving profile…'), findsWidgets);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('radar-save-profile')))
            .onPressed,
        isNull,
      );
      expect(c.profileSaves, 2);
      c.profileGate!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('radar-discover')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
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
        expect(find.byKey(const Key('radar-discover')), findsOneWidget);
        expect(find.text('Save & find contracts'), findsOneWidget);
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
    'first search saves the three required fields and asks consent once',
    (t) async {
      final c = FakeRadar()..profileRow = null;
      var consentCalls = 0;
      await show(
        t,
        c,
        width: 390,
        consent: () async {
          consentCalls++;
          return true;
        },
      );
      await fillBusiness(t);
      await t.enterText(
        find.byKey(const Key('radar-search-focus')),
        'Schools and offices',
      );
      await t.ensureVisible(find.byKey(const Key('radar-discover')));
      await t.tap(find.byKey(const Key('radar-discover')));
      await t.pump();
      await t.pump();
      expect(c.profileSaves, 1);
      expect(c.profileRow!['data']['businessName'], 'New business');
      expect(c.profileRow!['data']['certifications'], '');
      expect(consentCalls, 1);
      expect(c.starts, hasLength(1));
      expect(c.starts.single['query'], 'Schools and offices');
      expect(c.starts.single['consent'], isTrue);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('radar-discover')))
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed first search save keeps fields and never starts a paid search',
    (t) async {
      final c = FakeRadar()
        ..profileRow = null
        ..failProfile = true;
      var consentCalls = 0;
      await show(
        t,
        c,
        consent: () async {
          consentCalls++;
          return true;
        },
      );
      await fillBusiness(t);
      await tap(t, find.byKey(const Key('radar-discover')));
      expect(c.profileSaves, 1);
      expect(c.starts, isEmpty);
      expect(consentCalls, 0);
      expect(c.profileRow, isNull);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('radar-profile-services')))
            .controller!
            .text,
        'Office cleaning',
      );
      expect(find.byKey(const Key('radar-profile-save-error')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'declining consent after first profile save never starts discovery',
    (t) async {
      final c = FakeRadar()..profileRow = null;
      await show(t, c, consent: () async => false);
      await fillBusiness(t);
      await tap(t, find.byKey(const Key('radar-discover')));
      expect(c.profileSaves, 1);
      expect(c.profileRow, isNotNull);
      expect(c.starts, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
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
        find.textContaining('KORLIX is searching official notices'),
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
      await tap(t, find.text('View official notice'));
      expect(opened.toString(), sourceUrl);
      await tap(t, find.byKey(const Key('radar-save-result-0')));
      expect(c.saves, 1);
      expect(find.text('Saved'), findsWidgets);
      await tap(t, find.text('Saved').first);
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
  testWidgets('editing the saved service area creates a new search identity', (
    t,
  ) async {
    final c = FakeRadar()..failStart = true;
    await show(t, c);
    await tap(t, find.byKey(const Key('radar-discover')));
    await tap(t, find.byKey(const Key('radar-search-profile')));
    await t.enterText(
      find.byKey(const Key('radar-profile-location')),
      'New York',
    );
    await tap(t, find.byKey(const Key('radar-discover')));
    expect(c.profileSaves, 1);
    expect(c.profileRow!['data']['location'], 'New York');
    expect(c.starts, hasLength(2));
    expect(c.starts[0]['request_key'], isNot(c.starts[1]['request_key']));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'filtering results is local and saving keeps the server result index',
    (t) async {
      final c = FakeRadar()..jobs = [resultsJob()];
      await show(t, c);
      await tap(t, find.byKey(const Key('radar-result-controls')));
      await tap(t, find.byKey(const Key('radar-filter-earlyLeads')));
      await t.enterText(find.byKey(const Key('radar-result-filter')), 'Roof');
      await t.pumpAndSettle();
      expect(find.text('Office cleaning bid'), findsNothing);
      expect(find.text('Roof repair market research'), findsOneWidget);
      expect(c.starts, isEmpty);
      expect(c.profileSaves, 0);
      await tap(t, find.byKey(const Key('radar-save-result-1')));
      expect(c.saveRequests, hasLength(1));
      expect(c.saveRequests.single['job_id'], 'job');
      expect(c.saveRequests.single['index'], 1);
      expect(c.saved.single['data']['title'], 'Roof repair market research');
      expect(c.starts, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'deadline sorting changes order without changing saved result identity',
    (t) async {
      final c = FakeRadar()..jobs = [resultsJob()];
      await show(t, c);
      await tap(t, find.byKey(const Key('radar-result-controls')));
      await tap(t, find.byKey(const Key('radar-result-sort')));
      await tap(t, find.text('Deadline: soonest first').last);
      expect(
        t.getTopLeft(find.text('Roof repair market research')).dy,
        lessThan(t.getTopLeft(find.text('Office cleaning bid')).dy),
      );
      await tap(t, find.byKey(const Key('radar-save-result-1')));
      expect(c.saveRequests.single['index'], 1);
      expect(c.starts, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'clear filters restores all downloaded results without a new search',
    (t) async {
      final c = FakeRadar()..jobs = [resultsJob()];
      await show(t, c);
      await tap(t, find.byKey(const Key('radar-result-controls')));
      await tap(t, find.byKey(const Key('radar-result-sort')));
      await tap(t, find.text('Deadline: soonest first').last);
      await tap(t, find.byKey(const Key('radar-filter-solicitations')));
      await t.enterText(
        find.byKey(const Key('radar-result-filter')),
        'Not found',
      );
      await t.pumpAndSettle();
      expect(find.text('Office cleaning bid'), findsNothing);
      expect(find.text('Roof repair market research'), findsNothing);
      await tap(t, find.text('Clear filters'));
      expect(find.text('Office cleaning bid'), findsOneWidget);
      expect(find.text('Roof repair market research'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Office cleaning bid')).dy,
        lessThan(t.getTopLeft(find.text('Roof repair market research')).dy),
      );
      expect(
        find
            .descendant(
              of: find.byKey(const Key('radar-result-sort')),
              matching: find.text('Search order'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('radar-result-filter')))
            .controller!
            .text,
        isEmpty,
      );
      expect(c.starts, isEmpty);
      expect(c.loads, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'hiding past deadlines retains notices with an unknown deadline',
    (t) async {
      final results = resultsJob();
      results['result']['opportunities'][0]['deadline'] = '2000-01-01';
      results['result']['opportunities'][1]['deadline'] = null;
      final c = FakeRadar()..jobs = [results];
      await show(t, c);
      expect(find.text('Office cleaning bid'), findsOneWidget);
      await tap(t, find.byKey(const Key('radar-result-controls')));
      await tap(t, find.byKey(const Key('radar-hide-past')));
      expect(find.text('Office cleaning bid'), findsNothing);
      expect(find.text('Roof repair market research'), findsOneWidget);
      expect(c.starts, isEmpty);
      await tap(t, find.text('Clear filters'));
      expect(find.text('Office cleaning bid'), findsOneWidget);
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('radar-hide-past')))
            .value,
        isFalse,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'search and result controls fit a 320px phone at double text size',
    (t) async {
      final fresh = FakeRadar()..profileRow = null;
      await show(t, fresh, width: 320, height: 800, scale: 2);
      expect(t.takeException(), isNull);
      await tap(t, find.text('More business details (optional)'));
      expect(
        find.byKey(const Key('radar-profile-certifications')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final returning = FakeRadar()..jobs = [resultsJob()];
      await show(t, returning, width: 320, height: 800, scale: 2);
      expect(t.takeException(), isNull);
      await tap(t, find.byKey(const Key('radar-result-controls')));
      expect(t.takeException(), isNull);
      await tap(t, find.byKey(const Key('radar-filter-earlyLeads')));
      await t.ensureVisible(find.byKey(const Key('radar-save-result-1')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
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
      await tap(t, find.text('Saved').last);
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
    await t.enterText(
      find.byKey(const Key('radar-search-focus')),
      'School cleaning in Ohio',
    );
    await tap(t, find.text('Saved').first);
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
    await tap(t, find.text('Clear my Contract Radar data'));
    await tap(t, find.text('Remove'));
    expect(c.clears, 1);
    await tap(t, find.text('Find').first);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('radar-search-focus')))
          .controller!
          .text,
      isEmpty,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
