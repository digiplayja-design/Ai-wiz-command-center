import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/contract_radar/radar_client.dart';
import 'package:ai_wiz_command_center/contract_radar/radar_monitor_screen.dart';
import 'package:ai_wiz_command_center/contract_radar/radar_pdf.dart';
import 'package:ai_wiz_command_center/contract_radar/radar_results.dart';
import 'package:ai_wiz_command_center/contract_radar/radar_screen.dart';
import 'contract_radar_test.dart' as fixtures;

class UpgradeRadar extends fixtures.FakeRadar {
  bool ready = true;
  bool failSettings = false, failSearch = false;
  final searchRequests = <Map<String, dynamic>>[];
  Map<String, dynamic> settings = {
    'version': 0,
    'enabled': false,
    'timezone': 'America/New_York',
    'digest_time': '09:00',
    'deadline_days': [7, 3, 1],
  };
  final searches = <Map<String, dynamic>>[];
  final alerts = <Map<String, dynamic>>[];
  final directRequests = <Map<String, dynamic>>[];
  final settingsRequests = <Map<String, dynamic>>[];
  final savedNotices = <String>[];
  int pdfCalls = 0;
  @override
  Future<Map<String, dynamic>> load() async => {
    ...await super.load(),
    'capabilities': {
      'directSamReady': ready,
      'monitoringReady': ready,
      'pdfImport': true,
    },
  };
  @override
  Future<Map<String, dynamic>> monitor() async => {
    'settings': settings,
    'searches': searches,
    'alerts': alerts,
    'capabilities': {
      'monitor_ready': true,
      'direct_sam_ready': ready,
      'automatic_cost': 0,
    },
  };
  @override
  Future<Map<String, dynamic>> saveMonitorSettings(
    Map<String, dynamic> data,
  ) async {
    settingsRequests.add(Map.of(data));
    if (failSettings) {
      throw const RadarException(
        'Connection interrupted. Your schedule is still here.',
      );
    }
    settings = {...data, 'version': (data['version'] as int) + 1};
    return {'settings': settings};
  }

  @override
  Future<Map<String, dynamic>> saveSearch(Map<String, dynamic> data) async {
    searchRequests.add(Map.of(data));
    if (failSearch) {
      throw const RadarException(
        'Saved search request interrupted. Retry the same filters.',
      );
    }
    searches.add({'id': 'search1', ...data});
    return {'search': searches.last};
  }

  @override
  Future<Map<String, dynamic>> directSearch(Map<String, dynamic> data) async {
    directRequests.add(data);
    return {
      'opportunities': [
        {...fixtures.notice(), 'noticeId': 'abc123', 'source': 'sam_api'},
      ],
      'searchedAt': '2026-10-04T10:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> saveDirectNotice(String noticeId) async {
    savedNotices.add(noticeId);
    saved.add(fixtures.opportunity());
    return {'opportunity': saved.last};
  }

  @override
  Future<Map<String, dynamic>> extractPdf(String name, Uint8List bytes) async {
    pdfCalls++;
    return {
      'filename': name,
      'text':
          'Inspection and cleaning. Submit by 2026-12-01. Insurance required.',
      'pageCount': 2,
      'truncated': true,
      'warnings': ['Check table reading order.'],
    };
  }

  @override
  Future<void> markAllAlertsRead() async {
    for (final alert in alerts) {
      alert['read_at'] = '2026-10-04';
    }
  }

  @override
  Future<void> clearAlerts() async {
    alerts.clear();
  }
}

Future<void> pumpRadar(
  WidgetTester t,
  UpgradeRadar client, {
  bool monitor = false,
  double width = 1100,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(scale),
        ),
        child: monitor
            ? RadarMonitorScreen(client: client, openLink: (_) async {})
            : ContractRadarScreen(
                client: client,
                ensureConsent: () async => true,
                pickPdf: () async => RadarPdf(
                  'Cleaning RFP.pdf',
                  Uint8List.fromList([37, 80, 68, 70]),
                ),
                disposeClient: false,
              ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  test(
    'direct filters take one valid NAICS code without changing the profile',
    () {
      expect(radarFirstNaics('561720, 561730'), '561720');
      expect(radarFirstNaics('NAICS 23'), '23');
      expect(radarFirstNaics('1234567'), '');
    },
  );

  test(
    'PDF multipart extraction is bounded and does not invoke an AI job',
    () async {
      final seen = <http.Request>[];
      final client = RadarClient(
        backendBaseUrl: 'https://fixture.invalid',
        headersBuilder: () => {'Authorization': 'Bearer fixture'},
        client: MockClient((request) async {
          seen.add(request);
          expect(request.url.path, '/api/contract-radar/documents');
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          expect(request.bodyBytes.length, greaterThan(4));
          return http.Response(
            jsonEncode({'text': 'Required insurance', 'pageCount': 1}),
            200,
          );
        }),
      );
      expect(
        (await client.extractPdf(
          'RFP.pdf',
          Uint8List.fromList([37, 80, 68, 70]),
        ))['text'],
        'Required insurance',
      );
      await expectLater(
        client.extractPdf('large.pdf', Uint8List(5 * 1024 * 1024 + 1)),
        throwsA(isA<RadarException>()),
      );
      expect(seen, hasLength(1));
      client.dispose();
    },
  );

  testWidgets(
    'direct SAM missing setup has a usable web fallback and cannot start a call',
    (t) async {
      final client = UpgradeRadar()..ready = false;
      await pumpRadar(t, client);
      await tap(t, find.byKey(const Key('radar-source-sam')));
      expect(find.textContaining('connect a SAM.gov API key'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('radar-discover')))
            .onPressed,
        isNull,
      );
      await tap(t, find.byKey(const Key('radar-source-web')));
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('radar-discover')))
            .onPressed,
        isNotNull,
      );
      expect(client.starts, isEmpty);
      expect(client.directRequests, isEmpty);
    },
  );

  testWidgets(
    'direct results use official notice identity and never start paid discovery',
    (t) async {
      final client = UpgradeRadar();
      await pumpRadar(t, client);
      await tap(t, find.byKey(const Key('radar-source-sam')));
      await t.enterText(
        find.byKey(const Key('radar-search-focus')),
        'cleaning',
      );
      await t.enterText(find.byKey(const Key('radar-sam-state')), 'ny');
      await tap(t, find.byKey(const Key('radar-discover')));
      expect(client.directRequests.single, {
        'query': 'cleaning',
        'naics': '561720',
        'state': 'NY',
      });
      expect(client.starts, isEmpty);
      await tap(t, find.byKey(const Key('radar-save-result-0')));
      expect(client.savedNotices, ['abc123']);
      expect(client.saveRequests, isEmpty);
    },
  );

  testWidgets(
    'one action saves the current source filters without enabling global monitoring',
    (t) async {
      final client = UpgradeRadar();
      await pumpRadar(t, client);
      await tap(t, find.byKey(const Key('radar-source-sam')));
      await t.enterText(
        find.byKey(const Key('radar-search-focus')),
        'school cleaning',
      );
      await t.enterText(find.byKey(const Key('radar-sam-state')), 'oh');
      await tap(t, find.byKey(const Key('radar-save-search')));
      expect(client.searches.single['query'], 'school cleaning');
      expect(client.searches.single['naics'], '561720');
      expect(client.searches.single['state'], 'OH');
      expect(client.settings['enabled'], isFalse);
      expect(client.starts, isEmpty);
    },
  );

  testWidgets(
    'PDF preview requires applying text before saving and never auto-reviews',
    (t) async {
      final client = UpgradeRadar();
      await pumpRadar(t, client);
      await tap(t, find.text('Paste an RFP'));
      await tap(t, find.byKey(const Key('radar-upload-pdf')));
      expect(client.pdfCalls, 1);
      expect(find.byKey(const Key('radar-pdf-preview-text')), findsOneWidget);
      expect(find.textContaining('Text is incomplete:'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('radar-notice-text')))
            .controller!
            .text,
        isEmpty,
      );
      expect(client.saves, 0);
      await tap(t, find.byKey(const Key('radar-pdf-use-text')));
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('radar-notice-text')))
            .controller!
            .text,
        contains('Insurance required'),
      );
      expect(client.saves, 0);
      await tap(t, find.byKey(const Key('radar-save-rfp')));
      expect(client.saveRequests.single['title'], 'Cleaning RFP');
      expect(
        client.saveRequests.single['noticeText'],
        contains('Insurance required'),
      );
      expect(client.starts, isEmpty);
    },
  );

  testWidgets(
    'monitoring requires explicit confirmation and preserves failed edits',
    (t) async {
      final client = UpgradeRadar();
      await pumpRadar(t, client, monitor: true);
      await tap(t, find.byKey(const Key('radar-monitor-enabled')));
      await tap(t, find.byKey(const Key('radar-monitor-save')));
      expect(find.text('Turn on daily monitoring?'), findsOneWidget);
      expect(client.settingsRequests, isEmpty);
      await tap(t, find.text('Cancel'));
      expect(client.settingsRequests, isEmpty);
      await t.enterText(find.byKey(const Key('radar-monitor-time')), '18:45');
      client.failSettings = true;
      await tap(t, find.byKey(const Key('radar-monitor-save')));
      await tap(t, find.text('Turn on'));
      expect(client.settingsRequests.single['version'], 0);
      expect(client.settingsRequests.single['digest_time'], '18:45');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('radar-monitor-time')))
            .controller!
            .text,
        '18:45',
      );
      expect(find.textContaining('Connection interrupted.'), findsOneWidget);
    },
  );

  testWidgets('alert read and clear keep destructive clearing explicit', (
    t,
  ) async {
    final client = UpgradeRadar()
      ..alerts.add({
        'id': 'alert1',
        'title': 'Deadline approaching',
        'message': 'Cleaning closes in 3 days',
        'created_at': '2026-10-04',
        'read_at': null,
      });
    await pumpRadar(t, client, monitor: true);
    await tap(t, find.text('Mark all read'));
    expect(client.alerts.single['read_at'], isNotNull);
    await tap(t, find.text('Clear history'));
    expect(client.alerts, hasLength(1));
    await tap(t, find.text('Clear'));
    expect(client.alerts, isEmpty);
  });

  testWidgets(
    'deadline monitoring remains available when the SAM key is missing',
    (t) async {
      final client = UpgradeRadar()..ready = false;
      await pumpRadar(t, client, monitor: true);
      expect(
        find.textContaining('Saved deadline reminders still work'),
        findsOneWidget,
      );
      expect(
        t
            .widget<SwitchListTile>(
              find.byKey(const Key('radar-monitor-enabled')),
            )
            .onChanged,
        isNotNull,
      );
      await tap(t, find.byKey(const Key('radar-monitor-enabled')));
      await tap(t, find.byKey(const Key('radar-monitor-save')));
      await tap(t, find.text('Turn on'));
      expect(client.settings['enabled'], isTrue);
    },
  );

  testWidgets(
    'latest saved-search matches save a notice and preserve unsaved schedule changes',
    (t) async {
      final client = UpgradeRadar()
        ..searches.add({
          'id': 'search1',
          'name': 'School cleaning',
          'query': 'cleaning',
          'enabled': true,
          'result': {
            'opportunities': [
              {...fixtures.notice(), 'noticeId': 'sam-match'},
            ],
          },
        });
      await pumpRadar(t, client, monitor: true);
      await t.enterText(find.byKey(const Key('radar-monitor-time')), '16:30');
      await tap(t, find.text('Latest notices · 1'));
      await tap(t, find.text('Save notice'));
      expect(client.savedNotices, ['sam-match']);
      await t.ensureVisible(find.byKey(const Key('radar-monitor-time')));
      expect(
        t
            .widget<TextField>(find.byKey(const Key('radar-monitor-time')))
            .controller!
            .text,
        '16:30',
      );
    },
  );

  testWidgets('account switching dismisses private monitor content', (t) async {
    final client = UpgradeRadar();
    await pumpRadar(t, client);
    await tap(t, find.byKey(const Key('radar-monitor-open')));
    expect(
      find.text('Daily checks, fewer missed opportunities'),
      findsOneWidget,
    );
    client.onAccessDenied!();
    await t.pumpAndSettle();
    expect(find.text('Daily checks, fewer missed opportunities'), findsNothing);
    expect(find.textContaining('Your session changed.'), findsOneWidget);
  });

  testWidgets('unchanged saved-search retry keeps the request identity', (
    t,
  ) async {
    final client = UpgradeRadar()..failSearch = true;
    await pumpRadar(t, client);
    await tap(t, find.byKey(const Key('radar-save-search')));
    client.failSearch = false;
    await tap(t, find.byKey(const Key('radar-save-search')));
    expect(client.searchRequests, hasLength(2));
    expect(
      client.searchRequests[0]['request_key'],
      client.searchRequests[1]['request_key'],
    );
    expect(client.starts, isEmpty);
  });

  testWidgets('official region choice is saved in the business profile', (
    t,
  ) async {
    final client = UpgradeRadar();
    await pumpRadar(t, client);
    await tap(t, find.text('Change business or service area'));
    await tap(t, find.byKey(const ValueKey('radar-geography-us')));
    await tap(t, find.text('Jamaica').last);
    await tap(t, find.byKey(const Key('radar-save-profile')));
    expect(client.profileRow!['data']['geography'], 'jm');
    expect(find.byKey(const Key('radar-source-sam')), findsNothing);
    expect(
      find.textContaining('official Jamaican procurement sources'),
      findsOneWidget,
    );
    expect(client.starts, isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'monitor and PDF controls fit 320px at 200% in ${brightness.name}',
      (t) async {
        final client = UpgradeRadar();
        await pumpRadar(
          t,
          client,
          monitor: true,
          width: 320,
          scale: 2,
          brightness: brightness,
        );
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byKey(const Key('radar-monitor-save')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await pumpRadar(
          t,
          client,
          width: 320,
          scale: 2,
          brightness: brightness,
        );
        await tap(t, find.text('Paste an RFP'));
        await tap(t, find.byKey(const Key('radar-upload-pdf')));
        expect(t.takeException(), isNull);
        await tap(t, find.byKey(const Key('radar-pdf-use-text')));
        expect(t.takeException(), isNull);
      },
    );
  }
}
