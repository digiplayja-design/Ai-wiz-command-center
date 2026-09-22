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
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_templates.dart';

Map<String, dynamic> fixture() => {
  'id': '00000000-0000-4000-8000-000000000003',
  'name': 'Your next growth conversation',
  'slug': 'korlix-growth',
  'state': 'draft',
  'version': 1,
  'url': 'https://example.com/f/korlix-growth',
  'lead_count': 0,
  'page_requests': 0,
  'draft': {
    ...funnelTemplate('consultation'),
    'brand': 'KORLIX AI',
    'headline': 'More clarity. Better conversations.',
    'subheadline':
        'Explore how AI can support your team. Tell us what you’re working toward and let’s find your next step.',
    'privacy_url': 'https://example.com/privacy',
    'contact_email': 'team@example.com',
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      final font = File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      if (font.existsSync())
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
    }
  });
  test(
    'Campaign links encode values and generated copy preserves business contact links',
    () {
      final link = Uri.parse(
        campaignLink('https://example.com/f/a', {
          'source': 'Facebook',
          'campaign': 'September & October',
          'term': '',
        }),
      );
      expect(link.queryParameters, {
        'utm_source': 'Facebook',
        'utm_campaign': 'September & October',
      });
      final current = {
        ...funnelTemplate('consultation'),
        'privacy_url': 'https://example.com/privacy',
      };
      final next = generatedCopy(current, {
        ...funnelTemplate('event'),
        'headline': 'New event',
      });
      expect(next['privacy_url'], current['privacy_url']);
      expect(next['headline'], 'New event');
    },
  );
  test(
    'Client uses fresh auth, surfaces conflicts and handles unreadable responses',
    () async {
      var token = 'one';
      var calls = 0;
      final client = FunnelClient(
        backendBaseUrl: 'https://example.com/',
        headersBuilder: () => {'Authorization': token},
        client: MockClient((r) async {
          expect(r.url.path, '/api/funnels');
          expect(r.headers['Authorization'], token);
          calls++;
          if (calls == 1)
            return http.Response(
              '{"funnels":[]}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          if (calls == 2)
            return http.Response('{"error":"Refresh this funnel."}', 409);
          return http.Response('<html>Bad gateway</html>', 502);
        }),
      );
      await client.request('GET', '');
      token = 'two';
      await expectLater(
        client.request('GET', ''),
        throwsA(isA<FunnelException>().having((e) => e.status, 'status', 409)),
      );
      await expectLater(
        client.request('GET', ''),
        throwsA(isA<FunnelException>()),
      );
    },
  );
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('Editor, campaign links and lead inbox fit ${size.width}', (
      t,
    ) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final f = fixture();
      final calls = <http.Request>[];
      final client = FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {'Authorization': 'session'},
        client: MockClient((r) async {
          calls.add(r);
          if (r.url.path.endsWith('/leads'))
            return http.Response(
              jsonEncode({'total': 0, 'leads': [], 'campaigns': []}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          return http.Response(
            jsonEncode({
              'funnels': [f],
              'ai_ready': true,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final boundary = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: FunnelScreen(client: client),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.runAsync(
        () => precacheImage(
          const AssetImage('assets/meeting_copilot/korlix_logo.jpeg'),
          boundary.currentContext!,
        ),
      );
      await t.pump();
      expect(find.text('NOVA Funnel Studio'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Open studio'));
      await t.tap(find.text('Open studio'));
      await t.pumpAndSettle();
      expect(find.text('Review & publish'), findsOneWidget);
      expect(t.takeException(), isNull);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/korlix-funnel-${size.width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.ensureVisible(find.text('Campaign links'));
      await t.tap(find.text('Campaign links'));
      await t.pumpAndSettle();
      expect(find.text('Know where interest comes from'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Leads'));
      await t.tap(find.text('Leads'));
      await t.pumpAndSettle();
      expect(calls.where((r) => r.url.path.endsWith('/leads')), hasLength(1));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Editing requires saving; publish requires explicit review; access denial clears data',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var f = fixture();
      var published = false, deny = false;
      final client = FunnelClient(
        backendBaseUrl: 'https://example.com',
        headersBuilder: () => {},
        client: MockClient((r) async {
          if (deny)
            return http.Response('{"error":"Enterprise required"}', 403);
          if (r.method == 'PUT') {
            final b = jsonDecode(r.body);
            expect(b['version'], 1);
            f = {...f, 'draft': b['document'], 'name': b['name'], 'version': 2};
            return http.Response(
              jsonEncode({'funnel': f}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.url.path.endsWith('/publish')) {
            final b = jsonDecode(r.body);
            expect(b['confirmed'], true);
            expect(b['version'], 2);
            published = true;
            f = {...f, 'state': 'published', 'version': 3};
            return http.Response(
              jsonEncode({'funnel': f}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'funnels': [f],
              'ai_ready': true,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await t.pumpWidget(MaterialApp(home: FunnelScreen(client: client)));
      await t.pumpAndSettle();
      await t.tap(find.text('Open studio'));
      await t.pumpAndSettle();
      final field = find.byKey(const ValueKey('1:brand'));
      await t.ensureVisible(field);
      await t.enterText(field, 'Updated brand');
      await t.pumpAndSettle();
      expect(find.text('UNSAVED EDITS'), findsOneWidget);
      final publishButton = find.widgetWithText(
        FilledButton,
        'Review & publish',
      );
      expect(t.widget<FilledButton>(publishButton).onPressed, isNull);
      await t.ensureVisible(find.text('Save draft'));
      await t.tap(find.text('Save draft'));
      await t.pumpAndSettle();
      await t.tap(find.text('Review & publish'));
      await t.pumpAndSettle();
      expect(published, false);
      await t.tap(find.text('Publish page'));
      await t.pumpAndSettle();
      expect(published, true);
      deny = true;
      await t.tap(find.text('Reload saved'));
      await t.pumpAndSettle();
      expect(find.text('Enterprise access required'), findsOneWidget);
      expect(find.text('Updated brand'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
