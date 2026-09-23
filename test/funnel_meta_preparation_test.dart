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
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_preparation.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const fid = '00000000-0000-4000-8000-000000000001';
const cid = '00000000-0000-4000-8000-000000000003';
const confirm =
    'I reviewed this plan, destination, planned USD budget, ad account and Facebook Page.';
Map<String, dynamic> clone(Map<String, dynamic> m) => jsonDecode(jsonEncode(m));
Map<String, dynamic> fixture({bool saved = false}) {
  final snapshot = {
    'campaign': {
      'id': cid,
      'name': 'Autumn growth',
      'headline': 'More clarity. Better conversations.',
      'body': 'Discover how our team can support your next business decision.',
      'cta': 'Book a conversation',
      'audience': 'Local businesses looking for support.',
      'daily_cents': 2500,
      'days': 14,
      'currency': 'USD',
      'planned_total_cents': 35000,
    },
    'landing_page': {
      'slug': 'growth',
      'version': 2,
      'brand': 'Acme Studio',
      'headline': 'Your next step starts here',
      'subheadline': 'Talk with our team',
      'cta': 'Get started',
      'destination':
          'https://example.com/f/growth?utm_source=facebook&utm_medium=paid&utm_campaign=k143_${cid.replaceAll('-', '')}',
    },
    'meta': {
      'connection_version': 4,
      'account': {
        'id': 'act_123',
        'name': 'Acme Advertising',
        'currency': 'USD',
        'timezone': 'America/New_York',
        'status': 1,
      },
      'page': {
        'id': '456',
        'name': 'Acme Studio',
        'category': 'Business service',
      },
      'accounts_refreshed_at': '2026-09-23T00:00:00Z',
      'pages_refreshed_at': '2026-09-23T00:00:00Z',
    },
  };
  return {
    'source': 'meta_setup',
    'funnel_id': fid,
    'campaign_id': cid,
    'version': saved ? 1 : 0,
    'fingerprint': 'a' * 64,
    'checks': {for (final key in metaSetupChecks.keys) key: true},
    'ready_for_review': true,
    'review_current': saved,
    'reviewed_at': saved ? '2026-09-23T00:30:00Z' : null,
    'reviewed_snapshot': saved ? clone(snapshot) : null,
    'current_snapshot': snapshot,
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
Future<void> tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).last);
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

FilledButton saveButton(WidgetTester t) =>
    t.widget(find.widgetWithText(FilledButton, 'Save Meta setup review'));
Widget app(
  FunnelClient client, {
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
    body: FunnelMetaPreparation(
      client: client,
      funnelId: funnel,
      campaignId: cid,
      scope: scope,
    ),
  ),
);

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
  for (final size in [
    const Size(1400, 1100),
    const Size(390, 844),
    const Size(320, 844),
  ]) {
    testWidgets(
      'Review, copy and clear use exact snapshots and fit ${size.width}',
      (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        var data = fixture();
        final calls = <http.Request>[];
        String? clipboard;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = call.arguments['text'];
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
        final client = makeClient((r) async {
          calls.add(r);
          if (r.url.path.endsWith('/review')) data = fixture(saved: true);
          if (r.url.path.endsWith('/clear')) data = fixture()..['version'] = 2;
          return reply(data);
        });
        addTearDown(client.dispose);
        final key = GlobalKey();
        await t.pumpWidget(
          app(client, captureKey: key, scale: size.width == 320 ? 1.3 : 1),
        );
        await t.pumpAndSettle();
        expect(saveButton(t).onPressed, isNull);
        expect(calls.single.method, 'GET');
        expect(
          calls.single.url.path,
          '/api/funnels/$fid/campaigns/$cid/meta-setup',
        );
        await tap(t, confirm);
        expect(saveButton(t).onPressed, isNotNull);
        await tap(t, 'Save Meta setup review');
        expect(jsonDecode(calls.last.body), {
          'version': 0,
          'confirmed': true,
          'fingerprint': 'a' * 64,
        });
        expect(find.text('SETUP REVIEWED'), findsOneWidget);
        await tap(t, 'Copy saved review');
        expect(clipboard, contains('\$25.00 USD/day × 14 days = \$350.00 USD'));
        expect(clipboard, contains('Acme Studio (456)'));
        expect(
          clipboard,
          contains('No ad was created and no spending was authorized.'),
        );
        expect(clipboard, isNot(contains('OUT OF DATE')));
        expect(t.takeException(), isNull);
        if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
          await t.ensureVisible(find.text('SETUP REVIEWED'));
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
              '/tmp/k162-review-${size.width.toInt()}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tap(t, 'Clear saved review');
        expect(jsonDecode(calls.last.body), {'version': 1, 'confirmed': true});
        expect(find.text('SETUP REVIEW NEEDED'), findsOneWidget);
        expect(find.text('Copy saved review'), findsNothing);
        expect(calls.where((r) => r.method == 'POST'), hasLength(2));
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Currency mismatch blocks review and refresh is local setup only',
    (t) async {
      final data = fixture();
      data['checks']['currency_supported'] = false;
      data['current_snapshot']['meta']['account']['currency'] = 'JMD';
      data['ready_for_review'] = false;
      final calls = <http.Request>[];
      final client = makeClient((r) async {
        calls.add(r);
        return reply(data);
      });
      addTearDown(client.dispose);
      await t.pumpWidget(app(client));
      await t.pumpAndSettle();
      expect(find.textContaining('no currency conversion'), findsOneWidget);
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
        isNull,
      );
      expect(saveButton(t).onPressed, isNull);
      await tap(t, 'Refresh setup');
      expect(calls, hasLength(2));
      expect(
        calls.every(
          (r) => r.method == 'GET' && r.url.path.endsWith('/meta-setup'),
        ),
        isTrue,
      );
    },
  );
  for (final status in [400, 409]) {
    testWidgets(
      'Changed setup $status refreshes fingerprint and requires another review',
      (t) async {
        var data = fixture(saved: true);
        data['current_snapshot']['campaign']['headline'] =
            'Updated conversation';
        data['review_current'] = false;
        final calls = <http.Request>[];
        String? clipboard;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = call.arguments['text'];
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
        final client = makeClient((r) async {
          calls.add(r);
          if (r.method == 'POST') {
            data = clone(data)..['fingerprint'] = 'b' * 64;
            data['current_snapshot']['campaign']['headline'] =
                'Changed while reviewing';
            return reply({
              'error': 'The setup changed. Refresh this review.',
            }, status);
          }
          return reply(data);
        });
        addTearDown(client.dispose);
        await t.pumpWidget(app(client));
        await t.pumpAndSettle();
        expect(find.text('SETUP CHANGED · REVIEW AGAIN'), findsOneWidget);
        await tap(t, 'Copy saved review');
        expect(clipboard, contains('OUT OF DATE'));
        expect(clipboard, contains('More clarity. Better conversations.'));
        await tap(t, confirm);
        await tap(t, 'Save Meta setup review');
        expect(calls.map((r) => r.method), ['GET', 'POST', 'GET']);
        expect(find.text('Changed while reviewing'), findsOneWidget);
        expect(find.textContaining('The setup changed.'), findsOneWidget);
        expect(saveButton(t).onPressed, isNull);
        expect(
          t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final pendingSave in [false, true]) {
    testWidgets(
      'Access denial hides setup and rejects late ${pendingSave ? 'save' : 'read'}',
      (t) async {
        final pending = Completer<http.Response>();
        final client = makeClient((r) async {
          if (r.url.path.endsWith('/denied')) {
            return reply({'error': 'Sign in'}, 403);
          }
          if (!pendingSave || r.method == 'POST') return pending.future;
          return reply(fixture());
        });
        addTearDown(client.dispose);
        await t.pumpWidget(app(client));
        await t.pump();
        if (pendingSave) {
          await t.pumpAndSettle();
          await tap(t, confirm);
          await t.tap(find.text('Save Meta setup review'));
          await t.pump();
        }
        final denied = client.request('GET', '/denied');
        await expectLater(denied, throwsA(isA<FunnelException>()));
        await t.pumpAndSettle();
        expect(
          find.textContaining('Sign in with Enterprise access'),
          findsOneWidget,
        );
        pending.complete(reply(fixture(saved: true)));
        await t.pumpAndSettle();
        expect(find.text('Autumn growth'), findsNothing);
        expect(find.text('Save Meta setup review'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('Replacing client and funnel suppresses pending owner data', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    final old = makeClient((r) async => pending.future);
    final next = makeClient((r) async {
      final d = fixture();
      d['funnel_id'] = 'new-funnel';
      d['current_snapshot']['campaign']['name'] = 'New owner campaign';
      return reply(d);
    });
    addTearDown(old.dispose);
    addTearDown(next.dispose);
    await t.pumpWidget(app(old));
    await t.pump();
    await t.pumpWidget(app(next, funnel: 'new-funnel'));
    await t.pumpAndSettle();
    pending.complete(reply(fixture(saved: true)));
    await t.pumpAndSettle();
    expect(find.text('New owner campaign'), findsOneWidget);
    expect(find.text('Autumn growth'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Parent workspace change invalidates an open navigator dialog safely',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1400, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final change = ValueNotifier<bool>(false);
      addTearDown(change.dispose);
      final old = makeClient((r) async {
        if (r.url.path.endsWith('/meta-setup')) return reply(fixture());
        if (r.url.path.endsWith('/connection')) {
          return reply({'configured': false, 'connection': null});
        }
        return reply({
          'campaigns': [
            {
              ...fixture()['current_snapshot']['campaign'],
              'platform': 'meta',
              'state': 'reviewed',
              'version': 1,
              'review_current': true,
              'tracking_url': 'https://example.com',
              'reports': [],
            },
          ],
          'ai_ready': false,
        });
      });
      final next = makeClient(
        (r) async => reply(
          r.url.path.endsWith('/connection')
              ? {'configured': false, 'connection': null}
              : {'campaigns': [], 'ai_ready': false},
        ),
      );
      addTearDown(old.dispose);
      addTearDown(next.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: change,
              builder: (context, value, _) => SingleChildScrollView(
                child: FunnelCampaigns(
                  client: value ? next : old,
                  funnelId: value ? 'new-funnel' : fid,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Meta setup review');
      expect(find.text('Save Meta setup review'), findsOneWidget);
      change.value = true;
      await t.pumpAndSettle();
      expect(find.textContaining('campaign workspace changed'), findsOneWidget);
      expect(find.text('Save Meta setup review'), findsNothing);
      expect(t.takeException(), isNull);
      await tap(t, 'Close setup review');
      expect(find.text('Autumn growth'), findsNothing);
    },
  );
  testWidgets('Unreadable refresh hides the previous saved review', (t) async {
    var data = fixture(saved: true);
    final client = makeClient((r) async => reply(data));
    addTearDown(client.dispose);
    await t.pumpWidget(app(client));
    await t.pumpAndSettle();
    data = clone(data);
    data['reviewed_snapshot']['meta']['page'] = null;
    await tap(t, 'Refresh setup');
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.text('Autumn growth'), findsNothing);
    expect(find.text('Copy saved review'), findsNothing);
  });
  test(
    'Untrusted setup replies reject mismatched identities and inconsistent snapshots',
    () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (r) => r['source'] = 'other',
        (r) => r['funnel_id'] = 'other',
        (r) => r['campaign_id'] = 'other',
        (r) => r['version'] = -1,
        (r) => r['fingerprint'] = 'bad',
        (r) => r['ad_publishing_ready'] = true,
        (r) => r['checks']['extra'] = true,
        (r) => r['checks']['page_published'] = 'true',
        (r) => r['ready_for_review'] = false,
        (r) => r['reviewed_at'] = null,
        (r) => r['current_snapshot']['campaign']['planned_total_cents'] = 1,
        (r) => r['current_snapshot']['landing_page']['destination'] =
            'http://example.com',
        (r) => r['current_snapshot']['landing_page']['destination'] +=
            '&utm_source=evil',
        (r) => r['current_snapshot']['meta']['page'] = null,
        (r) => r['reviewed_snapshot']['meta']['account'] = null,
        (r) => r['reviewed_snapshot']['meta']['page'] = null,
        (r) => r['reviewed_snapshot']['meta']['account']['currency'] = 'JMD',
        (r) => r['reviewed_snapshot']['campaign']['headline'] =
            'Different reviewed content',
      ];
      expect(
        validateMetaPreparation(
          fixture(saved: true),
          fid,
          cid,
        )['review_current'],
        isTrue,
      );
      for (final mutate in mutations) {
        final data = clone(fixture(saved: true));
        mutate(data);
        expect(
          () => validateMetaPreparation(data, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
    },
  );
}
