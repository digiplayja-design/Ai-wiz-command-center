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
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_creative.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const fid = '00000000-0000-4000-8000-000000000001',
    cid = '00000000-0000-4000-8000-000000000003';
Map<String, dynamic> clone(Map<String, dynamic> m) => jsonDecode(jsonEncode(m));
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
  return {
    'source': 'google_search_draft',
    'funnel_id': fid,
    'campaign_id': cid,
    'version': saved ? 1 : 0,
    'fingerprint': 'a' * 64,
    'context': c,
    'saved_context': saved ? clone(c) : null,
    'assets': {
      'headlines': saved
          ? ['Meet our team', 'Explore our services', 'Start a conversation']
          : [],
      'descriptions': saved
          ? [
              'Tell us what your business needs.',
              'Discover how our team can help.',
            ]
          : [],
      'path1': saved ? 'services' : '',
      'path2': '',
    },
    'updated_at': saved ? '2026-09-23T08:00:00Z' : null,
    'draft_current': saved,
    'editable': true,
    'text_complete': saved,
    'ad_publishing_ready': false,
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
    body: FunnelGoogleCreative(
      client: c,
      funnelId: funnel,
      campaignId: cid,
      scope: scope,
    ),
  ),
);
Future<void> tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).last);
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextField, label);
FilledButton saveButton(WidgetTester t) =>
    t.widget(find.widgetWithText(FilledButton, 'Save search-ad draft'));
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
    'Validation rejects malformed state, executable destination and incorrect completion',
    () {
      expect(googleDraftUnits('中aé'), 5);
      expect(googleDraftTextError('中' * 16, 30), isNotNull);
      expect(googleDraftTextError('x/y', 15, path: true), isNotNull);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['ad_publishing_ready'] = true,
        (r) => r['version'] = -1,
        (r) => r['campaign_id'] = 'other',
        (r) => r['text_complete'] = false,
        (r) => r['context']['destination'] = 'javascript:alert(1)',
        (r) => r['assets']['headlines'] = ['same', 'Same'],
        (r) => r['assets']['headlines'] = ['a' * 31],
        (r) => r['assets']['path2'] = 'x/y',
        (r) => r['saved_context'] = null,
        (r) => r['updated_at'] = 'yesterday',
      ]) {
        final r = fixture();
        mutate(r);
        expect(
          () => validateGoogleCreative(r, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
      expect(
        validateGoogleCreative(fixture(saved: false), fid, cid)['version'],
        0,
      );
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('Editor saves, previews and copies at $width', (t) async {
      await t.binding.setSurfaceSize(Size(width, width == 1400 ? 1100 : 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var data = fixture();
      final calls = <http.Request>[];
      String? copied;
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
      final c = makeClient((r) async {
        calls.add(r);
        if (r.method == 'POST') {
          final body = jsonDecode(r.body);
          expect(body.keys.toSet(), {'version', 'fingerprint', 'assets'});
          expect(body['version'], 1);
          expect(body['fingerprint'], 'a' * 64);
          data = {...data, 'assets': body['assets'], 'version': 2};
        }
        return reply(data);
      });
      addTearDown(c.dispose);
      final key = GlobalKey();
      await t.pumpWidget(
        app(c, captureKey: key, scale: width == 320 ? 1.3 : 1),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/k164-editor-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      await t.enterText(field('Headline 1'), 'Find your next step');
      await t.pump();
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);
      await tap(t, 'Save search-ad draft');
      expect(calls.where((r) => r.method == 'POST').length, 1);
      expect(find.text('Search-ad draft saved.'), findsOneWidget);
      await tap(t, 'Copy saved draft');
      expect(copied, contains('Find your next step'));
      expect(copied, contains('No ad or spending has been created.'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Incomplete text can be saved; invalid and duplicate text blocks saving',
    (t) async {
      final c = makeClient((r) async => reply(fixture(saved: false)));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await t.enterText(field('Headline 1'), 'One headline');
      await t.pump();
      expect(saveButton(t).onPressed, isNotNull);
      expect(find.text('TEXT INCOMPLETE'), findsOneWidget);
      await t.enterText(field('Headline 2'), 'one headline');
      await t.pump();
      expect(saveButton(t).onPressed, isNull);
      await t.enterText(field('Headline 2'), '中' * 16);
      await t.pump();
      expect(saveButton(t).onPressed, isNull);
      await t.enterText(field('Headline 2'), '');
      await t.enterText(field('Display path 2'), 'second');
      await t.pump();
      expect(saveButton(t).onPressed, isNull);
    },
  );
  testWidgets(
    'Stale draft copy retains old destination and explicit stale label',
    (t) async {
      final data = fixture();
      data['draft_current'] = false;
      data['context']['headline'] = 'New campaign offer';
      String? copied;
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
      final c = makeClient((r) async => reply(data));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await tap(t, 'Copy saved draft');
      expect(copied, contains('OUT OF DATE'));
      expect(copied, contains('Destination at save:'));
    },
  );
  testWidgets(
    'Conflict keeps typed text and requires explicit confirmed reload',
    (t) async {
      var posts = 0;
      final c = makeClient((r) async {
        if (r.method == 'POST') {
          posts++;
          return reply({'error': 'Draft changed. Reload.'}, 409);
        }
        return reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await t.enterText(field('Headline 1'), 'My unsaved copy');
      await tap(t, 'Save search-ad draft');
      expect(saveButton(t).onPressed, isNull);
      expect(
        t.widget<TextField>(field('Headline 1')).controller!.text,
        'My unsaved copy',
      );
      await tap(t, 'Reload saved draft');
      await tap(t, 'Keep editing');
      expect(posts, 1);
      await tap(t, 'Reload saved draft');
      await tap(t, 'Discard changes');
      expect(
        t.widget<TextField>(field('Headline 1')).controller!.text,
        'Meet our team',
      );
      expect(saveButton(t).onPressed, isNotNull);
    },
  );
  testWidgets('Archive is read-only and malformed responses fail closed', (
    t,
  ) async {
    var data = fixture();
    data['context']['campaign_state'] = 'archived';
    data['editable'] = false;
    data['draft_current'] = false;
    final c = makeClient((r) async => reply(data));
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    expect(saveButton(t).onPressed, isNull);
    data = fixture();
    data['ad_publishing_ready'] = true;
    await tap(t, 'Reload saved draft');
    expect(find.text('Save search-ad draft'), findsNothing);
    expect(find.textContaining('could not be verified'), findsOneWidget);
  });
  testWidgets(
    'Access denial during save removes private text and pending completion',
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
      await t.ensureVisible(find.text('Save search-ad draft'));
      await t.tap(find.text('Save search-ad draft'));
      await t.pump();
      await expectLater(
        c.request('GET', '/denied'),
        throwsA(isA<FunnelException>()),
      );
      pending.complete(reply(fixture()));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Enterprise access'), findsOneWidget);
      expect(find.text('Search-ad draft saved.'), findsNothing);
    },
  );
  testWidgets('Client and funnel changes ignore earlier reads', (t) async {
    final pending = Completer<http.Response>();
    final a = makeClient((r) => pending.future),
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
        r.url.path.endsWith('/google-creative')
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
    await tap(t, 'Search-ad draft');
    expect(find.text('Google search-ad draft'), findsOneWidget);
    await t.pumpWidget(parent(b));
    await t.pumpAndSettle();
    expect(find.textContaining('workspace changed'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FunnelGoogleCreative),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(t.takeException(), isNull);
  });
}
