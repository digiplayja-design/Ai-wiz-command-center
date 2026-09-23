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
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

Map<String, dynamic> fixture() => {
  'id': '00000000-0000-4000-8000-000000000003',
  'name': 'Autumn growth',
  'platform': 'meta',
  'state': 'draft',
  'version': 2,
  'headline': 'More clarity. Better conversations.',
  'body': 'Discover how our team can support your next business decision.',
  'cta': 'Book a conversation',
  'audience': 'Local businesses looking for support.',
  'daily_cents': 2500,
  'days': 14,
  'planned_total_cents': 35000,
  'page_state': 'published',
  'review_current': false,
  'tagged_leads': 4,
  'covered_leads': 2,
  'tracking_url':
      'https://example.com/f/growth?utm_source=facebook&utm_campaign=k143_test',
  'reports': [
    {
      'day': '2026-09-21',
      'spend_cents': 5000,
      'clicks': 10,
      'impressions': 1000,
      'note': 'Manual dashboard entry',
    },
  ],
};
Future<void> tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).last);
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
  for (final size in [const Size(1400, 1100), const Size(390, 844)]) {
    testWidgets('Campaign workspace and review fit ${size.width}', (t) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final calls = <http.Request>[];
      final c = fixture();
      final client = FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {},
        client: MockClient((r) async {
          calls.add(r);
          if (r.url.path.endsWith('/meta/connection') ||
              r.url.path.endsWith('/google-ads/connection')) {
            return http.Response(
              jsonEncode({'configured': false, 'connection': null}),
              200,
            );
          }
          return http.Response(
            jsonEncode(
              r.method == 'GET'
                  ? {
                      'campaigns': [c],
                      'ai_ready': true,
                    }
                  : {'campaign': c},
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.dispose);
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: FunnelCampaigns(client: client, funnelId: 'f'),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Autumn growth'), findsOneWidget);
      expect(t.takeException(), isNull);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/k143-campaign-${size.width.toInt()}.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tap(t, 'Review plan');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Mark plan reviewed'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('does not publish an ad'), findsOneWidget);
      await tap(t, 'I reviewed the offer, copy, audience, and planned budget.');
      await tap(t, 'Mark plan reviewed');
      final review = calls.firstWhere((r) => r.url.path.endsWith('/review'));
      expect(jsonDecode(review.body), {
        'campaign_id': c['id'],
        'version': 2,
        'confirmed': true,
      });
      expect(t.takeException(), isNull);
      await tap(t, 'Results & reporting');
      expect(
        find.textContaining(
          'Cost per click: \$5.00 · Cost per tagged inquiry: \$25.00',
        ),
        findsOneWidget,
      );
      expect(find.text('MANUALLY RECORDED · USD'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tap(t, 'Close reporting');
      await tap(t, 'New campaign plan');
      expect(find.text('Build a campaign plan'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tap(t, 'Cancel');
    });
  }
  testWidgets(
    'Campaign create uses cents, validates budget and does not publish',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final calls = <http.Request>[];
      final client = FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {},
        client: MockClient((r) async {
          calls.add(r);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: CampaignEditor(
            client: client,
            path: '/f/campaigns',
            aiReady: false,
          ),
        ),
      );
      await t.pumpAndSettle();
      Finder field(String label) => find.widgetWithText(TextFormField, label);
      await t.enterText(field('Campaign name'), 'Fall launch');
      await t.enterText(field('Planned daily budget · USD'), 'NaN');
      await tap(t, 'Save campaign plan');
      expect(calls, isEmpty);
      await t.enterText(field('Planned daily budget · USD'), '12.34');
      await t.enterText(field('Duration · days'), '7');
      await tap(t, 'Save campaign plan');
      expect(calls, hasLength(1));
      final data = jsonDecode(calls.single.body);
      expect(data['daily_cents'], 1234);
      expect(data['days'], 7);
      expect(data['platform'], 'meta');
      expect(calls.single.url.path, '/api/funnels/f/campaigns/create');
    },
  );
  testWidgets('Failed saves retain input and show the conflict', (t) async {
    final client = FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient(
        (r) async => http.Response(
          '{"error":"This campaign changed. Refresh and review it again."}',
          409,
        ),
      ),
    );
    addTearDown(client.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: WfStyle.theme,
        home: CampaignEditor(
          client: client,
          path: '/f/campaigns',
          campaign: fixture(),
          aiReady: false,
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Save campaign plan');
    expect(find.textContaining('This campaign changed.'), findsOneWidget);
    expect(find.text('Autumn growth'), findsOneWidget);
  });
  testWidgets(
    'Manual reports send exact date and numbers; removal requires confirmation',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1000, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final calls = <http.Request>[];
      var c = fixture();
      final client = FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {},
        client: MockClient((r) async {
          calls.add(r);
          if (r.method == 'POST') c = {...c, 'version': 3};
          return http.Response(
            jsonEncode(
              r.method == 'GET'
                  ? {
                      'campaigns': [c],
                    }
                  : {'campaign': c},
            ),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: CampaignReports(
            client: client,
            path: '/f/campaigns',
            campaign: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, '2026-09-21 UTC · \$50.00');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Spend · USD'),
        '75.25',
      );
      await tap(t, 'Save daily results');
      final body = jsonDecode(calls.first.body);
      expect(body['day'], '2026-09-21');
      expect(body['spend_cents'], 7525);
      expect(body['version'], 2);
      await tap(t, 'Remove this day');
      expect(calls.where((r) => r.url.path.endsWith('/removeReport')), isEmpty);
      await tap(t, 'Remove day');
      expect(
        jsonDecode(
          calls.firstWhere((r) => r.url.path.endsWith('/removeReport')).body,
        )['confirmed'],
        true,
      );
    },
  );
}
