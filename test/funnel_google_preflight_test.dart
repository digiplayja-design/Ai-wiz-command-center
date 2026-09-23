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
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_campaigns.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_preflight.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'funnel_google_preparation_test.dart' as setup_fixture show fixture;
import 'funnel_google_creative_test.dart' as copy_fixture show fixture;
import 'funnel_google_keywords_test.dart' as keyword_fixture show fixture;
import 'funnel_google_targeting_test.dart'
    as target_fixture
    show fixture, labels;

const fid = '00000000-0000-4000-8000-000000000001',
    cid = '00000000-0000-4000-8000-000000000003';
Map<String, dynamic> clone(Map m) => jsonDecode(jsonEncode(m));
Map<String, dynamic> fixture({bool reviewed = true, bool saved = true}) {
  final setup = setup_fixture.fixture(saved: reviewed),
      creative = copy_fixture.fixture(saved: saved),
      keywords = keyword_fixture.fixture(saved: saved),
      targeting = target_fixture.fixture(saved: saved);
  final c = creative['context'], p = setup['current_snapshot']['campaign'];
  for (final key in [
    'headline',
    'body',
    'cta',
    'audience',
    'daily_cents',
    'days',
  ]) {
    p[key] = c[key];
  }
  if (reviewed) setup['reviewed_snapshot'] = clone(setup['current_snapshot']);
  for (final entry in [
    ('creative', creative),
    ('keywords', keywords),
    ('targeting', targeting),
  ]) {
    final d = entry.$2;
    if (reviewed && saved) {
      d['version'] = 2;
      d['review_current'] = true;
      d['reviewed_at'] = '2026-09-23T12:00:00Z';
      d['reviewed_snapshot'] = {
        'assets': clone(d['assets']),
        'context': clone(d['saved_context']),
        'draft_revision': 1,
        if (entry.$1 != 'creative') 'saved_at': d['updated_at'],
      };
      if (entry.$1 == 'targeting') {
        d['reviewed_snapshot']['labels'] = clone(d['saved_labels']);
        d['reviewed_snapshot']['catalog_version'] = d['catalog']['version'];
      }
    }
  }
  return {
    'source': 'google_preflight',
    'funnel_id': fid,
    'campaign_id': cid,
    'checked_at': '2026-09-23T12:30:00Z',
    'checks': {
      'page_published': true,
      'plan_reviewed': true,
      'setup_reviewed': reviewed,
      'copy_reviewed': reviewed && saved,
      'keywords_reviewed': reviewed && saved,
      'targeting_reviewed': reviewed && saved,
    },
    'preparation_complete': reviewed && saved,
    'ad_publishing_ready': false,
    'setup': setup,
    'creative': creative,
    'keywords': keywords,
    'targeting': targeting,
  };
}

http.Response reply(Map m, [int status = 200]) => http.Response(
  jsonEncode(m),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
FunnelClient client(Future<http.Response> Function(http.Request) fn) =>
    FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient(fn),
    );
Widget app(
  FunnelClient c, {
  ValueNotifier<int>? scope,
  GlobalKey? captureKey,
  double scale = 1,
  String funnel = fid,
}) => MaterialApp(
  theme: WfStyle.theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: captureKey, child: child!),
  ),
  home: Scaffold(
    body: FunnelGooglePreflight(
      client: c,
      funnelId: funnel,
      campaignId: cid,
      scope: scope,
    ),
  ),
);
Future<void> tap(WidgetTester t, String label) async {
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(label).last);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final f in ['MaterialIcons-Regular.otf', 'Roboto-Regular.ttf']) {
        final file = File('$root/bin/cache/artifacts/material_fonts/$f');
        if (file.existsSync()) {
          await (FontLoader(
                f.startsWith('Material') ? 'MaterialIcons' : 'Roboto',
              )..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  test(
    'Aggregate validation rejects mismatched campaigns, readiness, context and component metadata',
    () {
      expect(
        validateGooglePreflight(fixture(), fid, cid)['preparation_complete'],
        true,
      );
      expect(
        validateGooglePreflight(
          fixture(reviewed: false, saved: false),
          fid,
          cid,
        )['preparation_complete'],
        false,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d['ad_publishing_ready'] = true,
        (d) => d['source'] = 'other',
        (d) => d['checked_at'] = 'bad',
        (d) => d['preparation_complete'] = false,
        (d) => d['checks']['setup_reviewed'] = false,
        (d) => d['checks']['extra'] = true,
        (d) => d['targeting']['campaign_id'] = 'other',
        (d) => d['keywords'] = null,
        (d) => d['creative']['review_current'] = false,
        (d) => d['targeting']['catalog']['version'] = 'bad',
        (d) => d['setup']['current_snapshot']['campaign']['name'] =
            'Different campaign',
        (d) => d['keywords']['context']['page_version'] = 3,
      ]) {
        final d = fixture();
        mutate(d);
        expect(
          () => validateGooglePreflight(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('Combined checklist and faithful summary fit $width', (
      t,
    ) async {
      await t.binding.setSurfaceSize(Size(width, width == 1400 ? 1100 : 950));
      addTearDown(() => t.binding.setSurfaceSize(null));
      String? copied;
      final requests = <http.Request>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final c = client((r) async {
        requests.add(r);
        return reply(fixture());
      });
      addTearDown(c.dispose);
      final key = GlobalKey();
      await t.pumpWidget(
        app(c, captureKey: key, scale: width == 320 ? 1.3 : 1),
      );
      await t.pumpAndSettle();
      expect(find.text('6 of 6 preparation checks current'), findsOneWidget);
      expect(find.text('PREPARATION REVIEWS CURRENT'), findsOneWidget);
      await tap(t, 'Copy preparation summary');
      expect(copied, contains('ALL PREPARATION REVIEWS CURRENT AT CHECK TIME'));
      expect(copied, contains('Meet our team'));
      expect(copied, contains('Exact match:\nbusiness support'));
      expect(copied, contains('Negative broad match:\njobs'));
      expect(copied, contains('Target countries: United States'));
      expect(copied, contains('Excluded countries: Canada'));
      expect(copied, contains('Account cache refreshed: 2026-09-23T00:00:00Z'));
      expect(copied, contains('authorize spending'));
      expect(copied, contains('Checked: 2026-09-23T12:30:00Z'));
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        for (final part in ['top', 'bottom']) {
          await t.ensureVisible(
            find.text(
              part == 'top'
                  ? 'Google preparation checklist'
                  : 'Copy preparation summary',
            ),
          );
          await t.pumpAndSettle();
          await t.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              '/tmp/k170-$part-${width.toInt()}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      expect(requests.length, 1);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, endsWith('/google-preflight'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Missing drafts and provider setup show actionable incomplete checks',
    (t) async {
      final d = fixture(reviewed: false, saved: false);
      d['setup']['checks']['google_configured'] = false;
      d['setup']['ready_for_review'] = false;
      final c = client((r) async => reply(d));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.text('2 of 6 preparation checks current'), findsOneWidget);
      expect(find.text('NOT REVIEWED'), findsNWidgets(4));
      expect(
        find.text('KORLIX Google Ads activation is still needed.'),
        findsOneWidget,
      );
      expect(find.text('No saved draft yet.'), findsNWidgets(3));
      expect(t.takeException(), isNull);
    },
  );
  test(
    'Stale summary labels latest saved draft separately from previous reviewed choices',
    () {
      final d = fixture();
      final t = d['targeting'];
      t['version'] = 3;
      t['draft_revision'] = 2;
      t['review_current'] = false;
      t['updated_at'] = '2026-09-23T12:20:00Z';
      t['assets']['countries'] = ['JM'];
      t['saved_labels'] = target_fixture.labels(t['assets']);
      d['checks']['targeting_reviewed'] = false;
      d['preparation_complete'] = false;
      validateGooglePreflight(d, fid, cid);
      final export = googlePreparationSummary(d);
      expect(export, contains('Targeting: OUT OF DATE'));
      expect(export, contains('Target countries: Jamaica'));
      expect(export, isNot(contains('Target countries: United States')));
      expect(export, contains('prior review may cover an earlier revision'));
      expect(t['reviewed_snapshot']['assets']['countries'], ['US']);
    },
  );
  for (final pair in [
    ('Open setup review', 'google-setup'),
    ('Open copy review', 'google-creative'),
    ('Open keyword review', 'google-keywords'),
    ('Open targeting review', 'google-targeting'),
  ]) {
    testWidgets(
      '${pair.$1} opens its existing editor and refreshes the aggregate on return',
      (t) async {
        var reads = 0;
        final requests = <String>[];
        final d = fixture();
        final key = {
          'google-setup': 'setup',
          'google-creative': 'creative',
          'google-keywords': 'keywords',
          'google-targeting': 'targeting',
        }[pair.$2]!;
        final c = client((r) async {
          requests.add(r.url.path);
          expect(r.method, 'GET');
          if (r.url.path.endsWith('/google-preflight')) {
            reads++;
            return reply(d);
          }
          expect(r.url.path, endsWith('/${pair.$2}'));
          return reply(d[key]);
        });
        addTearDown(c.dispose);
        await t.pumpWidget(app(c));
        await t.pumpAndSettle();
        await tap(t, pair.$1);
        await tap(
          t,
          pair.$2 == 'google-setup' ? 'Close setup review' : 'Close',
        );
        expect(reads, 2);
        expect(requests.length, 3);
        expect(find.text('6 of 6 preparation checks current'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Read failure and malformed refresh remove the previous private summary',
    (t) async {
      var mode = 0;
      final c = client(
        (r) async => mode == 1
            ? reply({'error': 'Temporarily unavailable'}, 503)
            : reply(mode == 2 ? {'source': 'broken'} : fixture()),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      mode = 1;
      await tap(t, 'Refresh checklist');
      expect(find.text('Autumn growth'), findsNothing);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Copy preparation summary'),
            )
            .onPressed,
        isNull,
      );
      mode = 2;
      await tap(t, 'Refresh checklist');
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.text('Autumn growth'), findsNothing);
    },
  );
  testWidgets('Access loss during refresh discards late private data', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    var reads = 0;
    final c = client((r) async {
      if (r.url.path.endsWith('/denied')) {
        return reply({'error': 'Denied'}, 403);
      }
      return ++reads == 1 ? reply(fixture()) : pending.future;
    });
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Refresh checklist'));
    await t.tap(find.text('Refresh checklist'));
    await t.pump();
    await expectLater(
      c.request('GET', '/denied'),
      throwsA(isA<FunnelException>()),
    );
    pending.complete(reply(fixture()));
    await t.pumpAndSettle();
    expect(find.text('Autumn growth'), findsNothing);
    expect(find.textContaining('Enterprise access'), findsOneWidget);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Close')).onPressed,
      isNotNull,
    );
  });
  testWidgets('Owner scope invalidation also clears an open child review', (
    t,
  ) async {
    final scope = ValueNotifier(0), d = fixture();
    final c = client(
      (r) async =>
          reply(r.url.path.endsWith('/google-preflight') ? d : d['creative']),
    );
    addTearDown(c.dispose);
    addTearDown(scope.dispose);
    await t.pumpWidget(app(c, scope: scope));
    await t.pumpAndSettle();
    await tap(t, 'Open copy review');
    scope.value++;
    await t.pumpAndSettle();
    expect(find.textContaining('workspace changed'), findsNWidgets(2));
    await tap(t, 'Close');
    expect(find.textContaining('workspace changed'), findsOneWidget);
    expect(find.text('Autumn growth'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('New client rejects old pending response', (t) async {
    final pending = Completer<http.Response>(),
        a = client((r) => pending.future),
        b = client((r) async => reply(fixture(reviewed: false)));
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(app(a));
    await t.pump();
    await t.pumpWidget(app(b));
    await t.pumpAndSettle();
    pending.complete(reply(fixture()));
    await t.pumpAndSettle();
    expect(find.text('2 of 6 preparation checks current'), findsOneWidget);
    expect(find.text('PREPARATION REVIEWS CURRENT'), findsNothing);
  });
  testWidgets('Missing campaign keeps Close available without private data', (
    t,
  ) async {
    final c = client((r) async => reply({'error': 'Missing'}, 404));
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    expect(find.textContaining('no longer available'), findsOneWidget);
    expect(find.text('Copy preparation summary'), findsNothing);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Close')).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'Campaign card opens the checklist and parent owner change invalidates it',
    (t) async {
      final campaign = {
        'id': cid,
        'name': 'Autumn growth',
        'platform': 'google',
        'state': 'reviewed',
        'version': 2,
        'headline': 'Plan',
        'body': 'Body',
        'cta': 'Talk',
        'audience': 'Businesses',
        'daily_cents': 2500,
        'days': 14,
        'planned_total_cents': 35000,
        'page_state': 'published',
        'review_current': true,
        'tracking_url': 'https://example.com/f/growth',
        'reports': [],
      };
      final a = client(
        (r) async => reply(
          r.url.path.endsWith('/google-preflight')
              ? fixture()
              : r.url.path.endsWith('/campaigns')
              ? {
                  'campaigns': [campaign],
                  'ai_ready': false,
                }
              : {'configured': false, 'connection': null},
        ),
      );
      final b = client(
        (r) async => reply(
          r.url.path.endsWith('/campaigns')
              ? {'campaigns': [], 'ai_ready': false}
              : {'configured': false, 'connection': null},
        ),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      Widget parent(FunnelClient c) => MaterialApp(
        theme: WfStyle.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FunnelCampaigns(client: c, funnelId: fid),
          ),
        ),
      );
      await t.pumpWidget(parent(a));
      await t.pumpAndSettle();
      await tap(t, 'Preparation checklist');
      expect(find.text('Google preparation checklist'), findsOneWidget);
      await t.pumpWidget(parent(b));
      await t.pumpAndSettle();
      expect(find.textContaining('workspace changed'), findsOneWidget);
      expect(find.text('Copy preparation summary'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
