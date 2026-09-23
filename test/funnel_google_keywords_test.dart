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
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_keywords.dart';
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
    'source': 'google_keyword_draft',
    'funnel_id': fid,
    'campaign_id': cid,
    'version': saved ? 1 : 0,
    'fingerprint': 'a' * 64,
    'context': c,
    'saved_context': saved ? clone(c) : null,
    'assets': <String, dynamic>{
      for (final k in googleKeywordLabels.keys)
        k: saved && k == 'exact'
            ? ['business support']
            : saved && k == 'negative_broad'
            ? ['jobs']
            : [],
    },
    'updated_at': saved ? '2026-09-23T08:00:00Z' : null,
    'draft_current': saved,
    'editable': true,
    'keyword_count': saved ? 1 : 0,
    'negative_count': saved ? 1 : 0,
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
    body: FunnelGoogleKeywords(
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
    t.widget(find.widgetWithText(FilledButton, 'Save keyword draft'));
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
    'Malformed keyword state fails closed and draft validation follows text and aggregate limits',
    () {
      expect(validateGoogleKeywords(fixture(), fid, cid)['keyword_count'], 1);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d['ad_publishing_ready'] = true,
        (d) => d['source'] = 'other',
        (d) => d['campaign_id'] = 'other',
        (d) => d['keyword_count'] = 2,
        (d) => d['negative_count'] = 3,
        (d) => d['version'] = -1,
        (d) => d['assets']['exact'] = ['[term]'],
        (d) => d['assets']['exact'] = null,
        (d) => d['assets']['exact'] = ['same', 'SAME'],
        (d) => d['context']['destination'] = 'javascript:alert(1)',
        (d) => d['saved_context']['headline'] = 'unexpected',
        (d) => d['updated_at'] = 'broken',
        (d) => d['assets']['extra'] = [],
        (d) => d['editable'] = false,
      ]) {
        final d = fixture();
        mutate(d);
        expect(
          () => validateGoogleKeywords(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
      expect(googleKeywordError('中' * 80), isNull);
      expect(googleKeywordError('😀' * 80), isNull);
      for (final text in [
        'x' * 81,
        List.filled(11, 'word').join(' '),
        'two  spaces',
        'x\u200by',
        '"term"',
        '+term',
        'x\\y',
      ]) {
        expect(googleKeywordError(text), isNotNull);
      }
      final a = fixture()['assets'] as Map;
      a['exact'] = List.generate(50, (i) => 'term $i');
      expect(googleKeywordsValid(a), true);
      a['phrase'] = ['extra'];
      expect(googleKeywordsValid(a), false);
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets(
      'Six match lists save normalized keywords and copy only saved data at $width',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, width == 1400 ? 1100 : 950));
        addTearDown(() => t.binding.setSurfaceSize(null));
        var data = fixture(saved: false);
        Map? posted;
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
          if (r.method == 'POST') {
            posted = jsonDecode(r.body);
            data = fixture();
            data['assets'] = posted!['assets'];
            data['keyword_count'] = 2;
            data['negative_count'] = 1;
          }
          return reply(data);
        });
        addTearDown(c.dispose);
        final key = GlobalKey();
        await t.pumpWidget(
          app(c, captureKey: key, scale: width == 320 ? 1.3 : 1),
        );
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(6));
        await t.enterText(
          field('Exact match'),
          '  business   support  \nlocal services\n',
        );
        await t.ensureVisible(field('Negative broad match'));
        await t.enterText(field('Negative broad match'), 'jobs');
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Copy saved keywords'),
              )
              .onPressed,
          isNull,
        );
        await tap(t, 'Save keyword draft');
        expect(posted!.keys.toSet(), {'version', 'fingerprint', 'assets'});
        expect(posted!['version'], 0);
        expect(posted!['assets']['exact'], [
          'business support',
          'local services',
        ]);
        expect(posted!['assets']['negative_broad'], ['jobs']);
        expect(find.text('Keyword draft saved.'), findsOneWidget);
        await tap(t, 'Copy saved keywords');
        expect(
          copied,
          contains('Exact match:\nbusiness support\nlocal services'),
        );
        expect(copied, contains('Negative broad match:\njobs'));
        expect(copied, contains('Saved version: 1'));
        expect(copied, contains('https://example.com/f/growth'));
        if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
          await t.ensureVisible(find.text('Google keyword draft'));
          await t.pumpAndSettle();
          await t.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/k166-keywords-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Invalid terms block saves; overlap explains exclusions and empty draft can be saved',
    (t) async {
      var posts = 0;
      final c = makeClient((r) async {
        if (r.method == 'POST') {
          posts++;
          final d = fixture();
          d['assets'] = jsonDecode(r.body)['assets'];
          d['keyword_count'] = 0;
          d['negative_count'] = 0;
          return reply(d);
        }
        return reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      for (final text in [
        '[term]',
        'same\nSAME',
        'x' * 81,
        List.generate(51, (i) => 'term $i').join('\n'),
      ]) {
        await t.enterText(field('Exact match'), text);
        await t.pump();
        expect(saveButton(t).onPressed, isNull);
      }
      await t.enterText(field('Exact match'), 'jobs');
      await t.pump();
      expect(find.textContaining('Same text appears'), findsOneWidget);
      expect(saveButton(t).onPressed, isNotNull);
      await t.enterText(field('Exact match'), '');
      await t.enterText(field('Negative broad match'), '');
      await t.pump();
      expect(find.textContaining('No positive keywords yet'), findsOneWidget);
      await tap(t, 'Save keyword draft');
      expect(posts, 1);
    },
  );
  testWidgets('Conflict preserves text and forces explicit discard or reload', (
    t,
  ) async {
    var posts = 0;
    final c = makeClient((r) async {
      if (r.method == 'POST') {
        posts++;
        return reply({'error': 'Reload the saved keyword draft.'}, 409);
      }
      return reply(fixture());
    });
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    await t.enterText(field('Exact match'), 'unsaved keyword');
    await tap(t, 'Save keyword draft');
    expect(posts, 1);
    expect(saveButton(t).onPressed, isNull);
    expect(
      t.widget<TextField>(field('Exact match')).controller!.text,
      'unsaved keyword',
    );
    await tap(t, 'Reload saved draft');
    await tap(t, 'Keep editing');
    expect(saveButton(t).onPressed, isNull);
    await tap(t, 'Reload saved draft');
    await tap(t, 'Discard changes');
    expect(
      t.widget<TextField>(field('Exact match')).controller!.text,
      'business support',
    );
    expect(saveButton(t).onPressed, isNotNull);
  });
  testWidgets(
    'Stale export preserves saved context and archive permits copy only',
    (t) async {
      var d = fixture();
      d['context']['campaign_name'] = 'Changed campaign';
      d['context']['campaign_state'] = 'archived';
      d['draft_current'] = false;
      d['editable'] = false;
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
      final c = makeClient((r) async => reply(d));
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(saveButton(t).onPressed, isNull);
      await tap(t, 'Copy saved keywords');
      expect(copied, contains('OUT OF DATE'));
      expect(copied, contains('Autumn growth'));
      expect(copied, isNot(contains('Changed campaign')));
      d = fixture();
      d['ad_publishing_ready'] = true;
      await tap(t, 'Reload saved draft');
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('could not be verified'), findsOneWidget);
    },
  );
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
      await t.ensureVisible(find.text('Save keyword draft'));
      await t.tap(find.text('Save keyword draft'));
      await t.pump();
      await expectLater(
        c.request('GET', '/denied'),
        throwsA(isA<FunnelException>()),
      );
      pending.complete(reply(fixture()));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Enterprise access'), findsOneWidget);
      expect(find.text('Keyword draft saved.'), findsNothing);
    },
  );
  testWidgets('Missing campaign clears fields and keeps Close available', (
    t,
  ) async {
    final c = makeClient(
      (r) async => reply({'error': 'Campaign not found.'}, 404),
    );
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Close')).onPressed,
      isNotNull,
    );
    expect(find.textContaining('no longer available'), findsOneWidget);
  });
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
        r.url.path.endsWith('/google-keywords')
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
    await tap(t, 'Search keywords');
    expect(find.text('Google keyword draft'), findsOneWidget);
    await t.pumpWidget(parent(b));
    await t.pumpAndSettle();
    expect(find.textContaining('workspace changed'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FunnelGoogleKeywords),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(t.takeException(), isNull);
  });
}
