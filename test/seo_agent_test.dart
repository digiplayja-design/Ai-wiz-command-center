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
import 'package:ai_wiz_command_center/seo_agent/seo_client.dart';
import 'package:ai_wiz_command_center/seo_agent/seo_screen.dart';

const business = {
  'businessName': 'Bright Pine',
  'website': 'https://brightpine.example.com',
  'services': 'Office cleaning',
  'market': 'Columbus',
  'facts': 'Evening appointments',
};
Map<String, dynamic> report({String state = 'completed'}) => {
  'id': 'audit-one',
  'state': state,
  'phase': 'Reviewing public pages',
  'source': 'manual',
  'charged': 3,
  'createdAt': '2026-09-30T12:00:00Z',
  'progress': {'completedActions': <String>[], 'notes': ''},
  'result': {
    'siteUrl': business['website'],
    'score': 74,
    'scannedAt': '2026-09-30T12:00:00Z',
    'coverage': {'pagesScanned': 2, 'pageLimit': 5},
    'findings': [
      {
        'id': 'f1',
        'priority': 'high',
        'title': 'Clarify the page title',
        'detail': 'Describe the office cleaning service.',
        'evidence': 'Current title: Home',
        'url': business['website'],
      },
    ],
    'limitations': ['Only public pages were sampled.'],
    'ai': {
      'summary': 'Your service details need clearer headings.',
      'opportunities': [
        {
          'topic': 'Office cleaning options',
          'intent': 'Commercial',
          'rationale': 'Explain the available services.',
        },
      ],
      'actions': [
        {
          'id': 'a1',
          'title': 'Review the service title',
          'priority': 'high',
          'why': 'Help visitors understand the page.',
          'how': 'Use an accurate descriptive title.',
          'url': business['website'],
        },
      ],
      'drafts': [
        {
          'type': 'metadata',
          'title': 'Suggested page metadata',
          'body': 'Office Cleaning in Columbus | Bright Pine',
          'url': business['website'],
        },
      ],
    },
  },
};

class FakeSeo extends SeoClient {
  FakeSeo()
    : super(backendBaseUrl: 'https://example.test', headersBuilder: () => {});
  Map<String, dynamic>? profileRow = {
    'data': business,
    'monitoringEnabled': false,
  };
  List<Map<String, dynamic>> runs = [];
  final starts = <String>[], monitoring = <bool>[];
  int saves = 0, details = 0, progressSaves = 0;
  bool failSave = false, failStart = false, failProgress = false;
  Completer<Map<String, dynamic>>? loading;
  @override
  Future<Map<String, dynamic>> load() async => loading != null
      ? loading!.future
      : {'profile': profileRow, 'runs': runs, 'creditCost': 3};
  @override
  Future<Map<String, dynamic>> saveProfile(Map<String, dynamic> data) async {
    saves++;
    if (failSave) {
      throw const SeoException('Could not save. Your entries are still here.');
    }
    return profileRow = {'data': data, 'monitoringEnabled': false};
  }

  @override
  Future<Map<String, dynamic>> setMonitoring(bool enabled) async {
    monitoring.add(enabled);
    return profileRow = {
      ...profileRow!,
      'monitoringEnabled': enabled,
      'nextRunAt': '2026-10-07T12:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> start(String key) async {
    starts.add(key);
    if (failStart) {
      throw const SeoException(
        'Connection interrupted. Refresh before retrying.',
      );
    }
    final r = report(state: 'queued');
    runs = [r];
    return r;
  }

  @override
  Future<Map<String, dynamic>> run(String id) async {
    details++;
    return report();
  }

  @override
  Future<Map<String, dynamic>> progress(
    String id,
    Map<String, dynamic> data,
  ) async {
    progressSaves++;
    if (failProgress) {
      throw const SeoException('Review progress could not be saved.');
    }
    return {...report(), 'progress': data};
  }
}

Future<void> show(
  WidgetTester t,
  FakeSeo c, {
  double width = 1200,
  Future<bool> Function()? consent,
  Future<void> Function(String)? copy,
}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    RepaintBoundary(
      key: const Key('seo-capture'),
      child: MaterialApp(
        home: SeoAgentScreen(
          client: c,
          ensureConsent: consent ?? () async => true,
          copyText: copy,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> capture(WidgetTester t, String name) async {
  final directory = Platform.environment['SEO_SCREENSHOT_DIR'];
  if (directory == null) return;
  await t.pumpAndSettle();
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('seo-capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['SEO_SCREENSHOT_DIR'] == null) return;
    final font = FontLoader('Roboto');
    font.addFont(
      Future.value(
        ByteData.sublistView(
          await File('assets/fieldproof/Roboto-Regular.ttf').readAsBytes(),
        ),
      ),
    );
    await font.load();
  });
  test(
    'account changes reject late responses and prevent new requests',
    () async {
      String token(String sub) =>
          'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': sub, 'session_id': sub})))}.sig';
      var auth = token('one'), denied = 0, requests = 0;
      final changes = ValueNotifier(0), pending = Completer<http.Response>();
      final client = SeoClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {'Authorization': 'Bearer $auth'},
        sessionChanges: changes,
        client: MockClient((_) {
          requests++;
          return pending.future;
        }),
      )..onAccessDenied = () => denied++;
      final loading = client.load();
      auth = token('two');
      changes.value++;
      final check = expectLater(loading, throwsA(isA<SeoException>()));
      pending.complete(http.Response('{"profile":null,"runs":[]}', 200));
      await check;
      await expectLater(
        client.setMonitoring(true),
        throwsA(isA<SeoException>()),
      );
      expect(denied, 1);
      expect(requests, 1);
      client.dispose();
      changes.dispose();
    },
  );
  test(
    'monitoring consent is explicit and malformed profile saves fail',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final client = SeoClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            r.url.path.endsWith('/monitoring')
                ? jsonEncode({
                    'profile': {'data': business},
                  })
                : '{}',
            200,
          );
        }),
      );
      await client.setMonitoring(true);
      await client.setMonitoring(false);
      expect(bodies[0], {'enabled': true, 'consent': true});
      expect(bodies[1], {'enabled': false});
      await expectLater(
        client.saveProfile(business),
        throwsA(isA<SeoException>()),
      );
      client.dispose();
    },
  );
  testWidgets(
    'loading enables nothing and cancelled weekly consent enables nothing',
    (t) async {
      final c = FakeSeo();
      await show(t, c, consent: () async => false);
      expect(c.starts, isEmpty);
      expect(c.monitoring, isEmpty);
      expect(
        find.text('3 credits + 1 generation per audit\nUp to 5 public pages'),
        findsOneWidget,
      );
      await tap(t, find.byKey(const Key('seo-monitoring')));
      expect(find.text('Enable weekly monitoring?'), findsOneWidget);
      expect(
        find.textContaining('Each audit uses 3 credits and 1 generation'),
        findsOneWidget,
      );
      await tap(t, find.text('Cancel'));
      expect(c.monitoring, isEmpty);
      await tap(t, find.byKey(const Key('seo-monitoring')));
      await tap(t, find.text('Enable weekly'));
      expect(c.monitoring, isEmpty);
      expect(c.starts, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'audit consent locks duplicate dispatch and retries retain request identity',
    (t) async {
      final consent = Completer<bool>(), c = FakeSeo()..failStart = true;
      await show(t, c, consent: () => consent.future);
      await tap(t, find.byKey(const Key('seo-audit')));
      expect(
        t.widget<FilledButton>(find.byKey(const Key('seo-audit'))).onPressed,
        isNull,
      );
      expect(c.starts, isEmpty);
      consent.complete(true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await tap(t, find.byKey(const Key('seo-audit')));
      expect(c.starts.length, 2);
      expect(c.starts[0], c.starts[1]);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed setup preserves entries and blocks an audit of unsaved changes',
    (t) async {
      final c = FakeSeo()..failSave = true;
      await show(t, c, width: 390);
      await tap(t, find.byKey(const Key('seo-tab-2')));
      await t.enterText(
        find.byKey(const Key('seo-businessName')),
        'Bright Pine Updated',
      );
      await tap(t, find.byKey(const Key('seo-save-profile')));
      expect(c.saves, 1);
      expect(find.byKey(const Key('seo-setup-error')), findsOneWidget);
      final input = t.widget<TextFormField>(
        find.byKey(const Key('seo-businessName')),
      );
      expect(input.controller!.text, 'Bright Pine Updated');
      await tap(t, find.byKey(const Key('seo-audit')));
      expect(c.starts, isEmpty);
      expect(c.monitoring, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'full report is fetched before rendering and failed notes save preserves edits',
    (t) async {
      for (final width in [390.0, 1200.0]) {
        final c = FakeSeo()
          ..runs = [
            {
              'id': 'audit-one',
              'state': 'completed',
              'createdAt': '2026-09-30T12:00:00Z',
              'result': {'score': 74},
            },
          ];
        String? copied;
        await show(t, c, width: width, copy: (text) async => copied = text);
        await capture(t, 'seo-overview-${width.toInt()}');
        await tap(t, find.text('Open latest report'));
        expect(c.details, 1);
        await capture(t, 'seo-report-${width.toInt()}');
        await tap(t, find.text('Clarify the page title'));
        expect(find.text('Evidence: Current title: Home'), findsOneWidget);
        await tap(t, find.text('Suggested page metadata'));
        await tap(t, find.text('Copy draft'));
        expect(copied, contains('Office Cleaning in Columbus'));
        await t.ensureVisible(find.byKey(const Key('seo-notes')));
        await t.enterText(
          find.byKey(const Key('seo-notes')),
          'Verify details with the owner.',
        );
        c.failProgress = true;
        await tap(t, find.byKey(const Key('seo-save-progress')));
        expect(c.progressSaves, 1);
        expect(
          t
              .widget<TextField>(find.byKey(const Key('seo-notes')))
              .controller!
              .text,
          'Verify details with the owner.',
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('account lock clears profile and ignores a late load', (t) async {
    final c = FakeSeo()..loading = Completer<Map<String, dynamic>>();
    await show(t, c);
    c.onAccessDenied!();
    await t.pump();
    c.loading!.complete({
      'profile': {'data': business},
      'runs': [report()],
    });
    await t.pump();
    expect(
      find.text('Your sign-in changed. Reopen SEO Agent to continue.'),
      findsOneWidget,
    );
    expect(find.text('Bright Pine'), findsNothing);
    expect(find.byKey(const Key('seo-audit')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
