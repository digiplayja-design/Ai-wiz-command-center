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
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_targeting.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const fid = '00000000-0000-4000-8000-000000000001',
    cid = '00000000-0000-4000-8000-000000000003';
Map<String, dynamic> clone(Map<String, dynamic> m) => jsonDecode(jsonEncode(m));
const catalog = {
  'version': 'google-reference-2026-09-23',
  'geo_date': '2026-08-12',
  'language_mode': 'content_planning',
  'location_scope': 'countries',
  'countries': [
    {'code': 'CA', 'id': '2124', 'name': 'Canada'},
    {'code': 'JM', 'id': '2388', 'name': 'Jamaica'},
    {
      'code': 'SH',
      'id': '2654',
      'name': 'Saint Helena, Ascension and Tristan da Cunha',
    },
    {'code': 'US', 'id': '2840', 'name': 'United States'},
  ],
  'languages': [
    {'code': 'en', 'id': '1000', 'name': 'English'},
    {'code': 'es', 'id': '1003', 'name': 'Spanish'},
  ],
};
Map<String, dynamic> labels(Map a) => {
  'countries': {
    for (final r in catalog['countries'] as List)
      if ([...a['countries'], ...a['excluded_countries']].contains(r['code']))
        r['code']: r['name'],
  },
  'content_languages': {
    for (final r in catalog['languages'] as List)
      if ((a['content_languages'] as List).contains(r['code']))
        r['code']: r['name'],
  },
};
Map<String, dynamic> fixture({bool saved = true}) {
  final c = {
    'campaign_name': 'Autumn growth',
    'headline': 'Explore our services',
    'body': 'Talk with our team about your next step.',
    'cta': 'Start here',
    'audience': 'Businesses seeking support.',
    'daily_cents': 2500,
    'days': 14,
    'campaign_state': 'reviewed',
    'page_state': 'published',
    'page_version': 2,
    'brand': 'Acme Studio',
    'destination':
        'https://example.com/f/growth?utm_source=google&utm_medium=paid&utm_campaign=k143_${cid.replaceAll('-', '')}',
  };
  final a = saved
      ? <String, dynamic>{
          'countries': ['US'],
          'excluded_countries': ['CA'],
          'content_languages': ['en'],
          'location_mode': 'presence',
          'bidding': 'maximize_clicks',
        }
      : emptyGoogleTargeting();
  return {
    'source': 'google_targeting_draft',
    'funnel_id': fid,
    'campaign_id': cid,
    'version': saved ? 1 : 0,
    'fingerprint': 'a' * 64,
    'context': c,
    'saved_context': saved ? clone(c) : null,
    'assets': a,
    'catalog': clone(catalog),
    'updated_at': saved ? '2026-09-23T08:00:00Z' : null,
    'draft_current': saved,
    'editable': true,
    'draft_complete': saved,
    'ad_publishing_ready': false,
    'saved_labels': saved ? labels(a) : null,
  };
}

http.Response reply(Map r, [int code = 200]) => http.Response(
  jsonEncode(r),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
FunnelClient makeClient(Future<http.Response> Function(http.Request) fn) =>
    FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient(fn),
    );
Widget app(
  FunnelClient c, {
  ValueNotifier<int>? scope,
  String funnel = fid,
  GlobalKey? captureKey,
  double scale = 1,
}) => MaterialApp(
  theme: WfStyle.theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: captureKey, child: child!),
  ),
  home: Scaffold(
    body: FunnelGoogleTargeting(
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

Finder field(String label) => find.widgetWithText(TextField, label);
FilledButton saveButton(WidgetTester t) =>
    t.widget(find.widgetWithText(FilledButton, 'Save targeting draft'));
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
    'Malformed targeting responses fail closed, including forged readiness, labels and conflicting selections',
    () {
      expect(
        validateGoogleTargeting(fixture(), fid, cid)['draft_complete'],
        true,
      );
      expect(
        validateGoogleTargeting(fixture(saved: false), fid, cid)['version'],
        0,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d['ad_publishing_ready'] = true,
        (d) => d['source'] = 'other',
        (d) => d['campaign_id'] = 'other',
        (d) => d['version'] = -1,
        (d) => d['fingerprint'] = 'x',
        (d) => d['assets']['countries'] = ['XX'],
        (d) => d['assets']['excluded_countries'] = ['US'],
        (d) => d['assets']['countries'] = ['US', 'US'],
        (d) => d['assets']['bidding'] = 'manual',
        (d) => d['assets']['content_languages'] = null,
        (d) => d['draft_complete'] = false,
        (d) => d['catalog']['version'] = 'unknown',
        (d) => d['catalog']['countries'][1]['code'] = 'CA',
        (d) => d['saved_labels']['countries'].remove('US'),
        (d) => d['context']['destination'] = 'http://example.com/f/growth',
        (d) => d['saved_context']['audience'] = 'different',
        (d) => d['editable'] = false,
      ]) {
        final d = fixture();
        mutate(d);
        expect(
          () => validateGoogleTargeting(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets(
      'Targeting selection save export and responsive layout at $width',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, width == 1400 ? 1100 : 950));
        addTearDown(() => t.binding.setSurfaceSize(null));
        var d = fixture();
        Map? sent;
        String copied = '';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = call.arguments['text'];
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final c = makeClient((r) async {
          if (r.method == 'POST') {
            expect(r.url.path, endsWith('/google-targeting/save'));
            sent = jsonDecode(r.body);
            d['assets'] = sent!['assets'];
            d['version'] = 2;
            d['saved_labels'] = labels(d['assets']);
            d['draft_complete'] = googleTargetingComplete(d['assets']);
          }
          return reply(d);
        });
        addTearDown(c.dispose);
        final key = GlobalKey();
        await t.pumpWidget(
          app(c, captureKey: key, scale: width == 320 ? 1.3 : 1),
        );
        await t.pumpAndSettle();
        await tap(t, 'Add target country');
        await t.enterText(field('Search choices'), 'jama');
        await t.pumpAndSettle();
        await tap(t, 'Jamaica');
        expect(find.text('UNSAVED CHANGES'), findsOneWidget);
        await tap(t, 'Add excluded country');
        expect(find.widgetWithText(ListTile, 'Jamaica'), findsNothing);
        expect(find.widgetWithText(ListTile, 'United States'), findsNothing);
        await tap(t, 'Cancel');
        await tap(t, 'Add content language');
        await tap(t, 'Spanish');
        await tap(t, 'Save targeting draft');
        expect(sent!.keys.toSet(), {'version', 'fingerprint', 'assets'});
        expect(sent!['version'], 1);
        expect(sent!['assets']['countries'], ['US', 'JM']);
        expect(sent!['assets']['content_languages'], ['en', 'es']);
        expect(find.text('Targeting draft saved.'), findsOneWidget);
        await tap(t, 'Copy saved targeting');
        expect(copied, contains('United States, Jamaica'));
        expect(copied, contains('English, Spanish'));
        expect(copied, contains('Saved version: 2'));
        expect(copied, contains('No ad or spending'));
        if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
          for (final part in ['top', 'bottom']) {
            await t.ensureVisible(
              find.text(
                part == 'top'
                    ? 'Google targeting draft'
                    : 'Save targeting draft',
              ),
            );
            await t.pumpAndSettle();
            await t.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '/tmp/k168-$part-${width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Choose reach and bidding without defaults; incomplete choices remain saveable',
    (t) async {
      Map? sent;
      var d = fixture(saved: false);
      final c = makeClient((r) async {
        if (r.method == 'POST') {
          sent = jsonDecode(r.body);
          d['assets'] = sent!['assets'];
          d['version'] = 1;
          d['saved_context'] = clone(d['context']);
          d['saved_labels'] = labels(d['assets']);
          d['updated_at'] = '2026-09-23T08:00:00Z';
          d['draft_current'] = true;
          d['draft_complete'] = googleTargetingComplete(d['assets']);
        }
        return reply(d);
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.text('NEW DRAFT'), findsOneWidget);
      expect(saveButton(t).onPressed, isNotNull);
      var drop = find.byType(DropdownButtonFormField<String>).first;
      await t.ensureVisible(drop);
      await t.pumpAndSettle();
      await t.tap(drop);
      await t.pumpAndSettle();
      await tap(t, 'People in or interested in these countries');
      drop = find.byType(DropdownButtonFormField<String>).last;
      await t.ensureVisible(drop);
      await t.pumpAndSettle();
      await t.tap(drop);
      await t.pumpAndSettle();
      await tap(t, 'Maximize conversions');
      await tap(t, 'Save targeting draft');
      expect(sent!['assets']['location_mode'], 'presence_or_interest');
      expect(sent!['assets']['bidding'], 'maximize_conversions');
      expect(sent!['assets']['countries'], isEmpty);
      expect(find.textContaining('incomplete draft'), findsOneWidget);
    },
  );
  testWidgets(
    'Conflict preserves choices until confirmed reload; cancel preserves edits',
    (t) async {
      final c = makeClient(
        (r) async => r.method == 'POST'
            ? reply({'error': 'Changed; reload.'}, 409)
            : reply(fixture()),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await tap(t, 'Add target country');
      await tap(t, 'Jamaica');
      await tap(t, 'Save targeting draft');
      expect(find.text('Jamaica'), findsOneWidget);
      expect(saveButton(t).onPressed, isNull);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Copy saved targeting'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, 'Reload saved draft');
      await tap(t, 'Keep editing');
      expect(find.text('Jamaica'), findsOneWidget);
      await tap(t, 'Reload saved draft');
      await tap(t, 'Discard changes');
      expect(find.text('Jamaica'), findsNothing);
      expect(saveButton(t).onPressed, isNotNull);
    },
  );
  testWidgets(
    'Stale archived draft exports the saved labels and context; malformed reload hides draft',
    (t) async {
      var d = fixture();
      d['context']['campaign_name'] = 'Changed campaign';
      d['context']['campaign_state'] = 'archived';
      d['draft_current'] = false;
      d['editable'] = false;
      d['saved_labels']['countries']['US'] = 'Saved country label';
      String copied = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = call.arguments['text'];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final c = makeClient((r) async => reply(d));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(saveButton(t).onPressed, isNull);
      await tap(t, 'Copy saved targeting');
      expect(copied, contains('OUT OF DATE'));
      expect(copied, contains('Autumn growth'));
      expect(copied, contains('Saved country label'));
      expect(copied, isNot(contains('Changed campaign')));
      d = fixture();
      d['ad_publishing_ready'] = true;
      await tap(t, 'Reload saved draft');
      expect(find.text('Target countries'), findsNothing);
      expect(find.textContaining('could not be verified'), findsOneWidget);
    },
  );
  testWidgets(
    'Access loss during save removes choices and rejects late completion',
    (t) async {
      final pending = Completer<http.Response>();
      final c = makeClient((r) async {
        if (r.url.path.endsWith('/denied')) {
          return reply({'error': 'Denied'}, 403);
        }
        return r.method == 'POST' ? pending.future : reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save targeting draft'));
      await t.tap(find.text('Save targeting draft'));
      await t.pump();
      await expectLater(
        c.request('GET', '/denied'),
        throwsA(isA<FunnelException>()),
      );
      pending.complete(reply(fixture()));
      await t.pumpAndSettle();
      expect(find.text('United States'), findsNothing);
      expect(find.textContaining('Enterprise access'), findsOneWidget);
      expect(find.text('Targeting draft saved.'), findsNothing);
    },
  );
  testWidgets('Scope change with picker open discards its late selection', (
    t,
  ) async {
    final scope = ValueNotifier(0),
        c = makeClient((r) async => reply(fixture()));
    addTearDown(scope.dispose);
    addTearDown(c.dispose);
    await t.pumpWidget(app(c, scope: scope));
    await t.pumpAndSettle();
    await tap(t, 'Add target country');
    scope.value++;
    await t.pumpAndSettle();
    await tap(t, 'Jamaica');
    expect(find.textContaining('workspace changed'), findsOneWidget);
    expect(find.text('UNSAVED CHANGES'), findsNothing);
    expect(find.text('United States'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Client and funnel changes ignore previous reads', (t) async {
    final pending = Completer<http.Response>(),
        a = makeClient((r) => pending.future),
        b = makeClient((r) async {
          final d = fixture();
          d['funnel_id'] = 'next';
          return reply(d);
        });
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(app(a));
    await t.pump();
    await t.pumpWidget(app(b, funnel: 'next'));
    await t.pumpAndSettle();
    pending.complete(reply(fixture(saved: false)));
    await t.pumpAndSettle();
    expect(find.text('SAVED DRAFT'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Missing campaign clears data and leaves Close available', (
    t,
  ) async {
    final c = makeClient((r) async => reply({'error': 'Missing'}, 404));
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    expect(find.text('United States'), findsNothing);
    expect(find.textContaining('no longer available'), findsOneWidget);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Close')).onPressed,
      isNotNull,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('Open campaign dialog invalidates when parent owner changes', (
    t,
  ) async {
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
    final a = makeClient(
      (r) async => reply(
        r.url.path.endsWith('/google-targeting')
            ? fixture()
            : r.url.path.endsWith('/campaigns')
            ? {
                'campaigns': [campaign],
                'ai_ready': false,
              }
            : {'configured': false, 'connection': null},
      ),
    );
    final b = makeClient(
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
    await tap(t, 'Targeting draft');
    expect(find.text('Google targeting draft'), findsOneWidget);
    await t.pumpWidget(parent(b));
    await t.pumpAndSettle();
    expect(find.textContaining('workspace changed'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FunnelGoogleTargeting),
        matching: find.text('United States'),
      ),
      findsNothing,
    );
    expect(t.takeException(), isNull);
  });
}
