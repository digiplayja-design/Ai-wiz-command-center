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
import 'package:ai_wiz_command_center/funnel_studio/funnel_images.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_campaigns.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_preparation.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_creative.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const fid = '00000000-0000-4000-8000-000000000001';
const cid = '00000000-0000-4000-8000-000000000003';
const confirm =
    'I reviewed this plan, destination, planned USD budget, ad account and Facebook Page.';
Map<String, dynamic> clone(Map<String, dynamic> m) => jsonDecode(jsonEncode(m));
Map<String, dynamic> setupFixture({bool saved = false}) {
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

const iid = '00000000-0000-4000-8000-000000000007';
const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAYAAAAECAIAAAAiZtkUAAAAEUlEQVR4nGOQ75yChhjIFQIAW1AdoZS4RIkAAAAASUVORK5CYII=';
Map<String, dynamic> fixture({bool saved = true}) {
  final setup = setupFixture();
  return {
    'source': 'meta_ad_draft',
    'funnel_id': fid,
    'campaign_id': cid,
    'version': saved ? 1 : 0,
    'fingerprint': 'a' * 64,
    'setup': setup,
    'saved_context': saved ? clone(setup['current_snapshot']) : null,
    'assets': {
      'primary_text': saved
          ? 'Discover how our team can help your business.'
          : '',
      'headline': saved ? 'Meet your next partner' : '',
      'description': saved ? 'Start a conversation.' : '',
      'cta': 'LEARN_MORE',
      'image_id': saved ? iid : null,
      'image_alt': saved ? 'Our friendly team' : '',
    },
    'image': saved ? imageFixture() : null,
    'updated_at': saved ? '2026-09-23T13:00:00Z' : null,
    'draft_current': saved,
    'editable': true,
    'creative_complete': saved,
    'ad_publishing_ready': false,
  };
}

Map<String, dynamic> imageFixture() => {
  'id': iid,
  'label': 'Our team.png',
  'width': 600,
  'height': 400,
  'sha256': 'b' * 64,
  'page_count': 0,
  'creative_count': 1,
};
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
  Future<FunnelPickedImage?> Function()? picker,
}) => MaterialApp(
  theme: WfStyle.theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: captureKey, child: child!),
  ),
  home: Scaffold(
    body: FunnelMetaCreative(
      client: c,
      funnelId: funnel,
      campaignId: cid,
      scope: scope,
      picker: picker ?? pickFunnelImage,
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
    t.widget(find.widgetWithText(FilledButton, 'Save Meta draft'));
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
    'Validator and export bind identity, destination, image and completion',
    () {
      expect(validateMetaCreative(fixture(), fid, cid)['version'], 1);
      expect(
        validateMetaCreative(fixture(saved: false), fid, cid)['version'],
        0,
      );
      expect(metaCreativeTextError('😀' * 100, 100), isNull);
      expect(metaCreativeTextError('😀' * 101, 100), isNotNull);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['ad_publishing_ready'] = true,
        (r) => r['campaign_id'] = 'other',
        (r) => r['version'] = -1,
        (r) => r['creative_complete'] = false,
        (r) => r['fingerprint'] = 'c' * 64,
        (r) => r['image']['id'] = 'other',
        (r) => r['assets']['image_id'] = null,
        (r) => r['assets']['cta'] = 'PUBLISH',
        (r) => r['assets']['primary_text'] = 'bad\ntext',
        (r) => r['assets']['headline'] = 'x' * 101,
        (r) => r['saved_context']['landing_page']['destination'] =
            'javascript:bad',
        (r) => r['saved_context']['campaign']['name'] = 'Changed',
        (r) => r['updated_at'] = 'yesterday',
        (r) => r['image']['sha256'] = 'invalid',
      ]) {
        final r = fixture();
        mutate(r);
        expect(
          () => validateMetaCreative(r, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
      final d = fixture();
      d['draft_current'] = false;
      d['setup']['current_snapshot']['meta']['page']['name'] = 'New Page';
      final out = metaCreativeExport(validateMetaCreative(d, fid, cid));
      expect(out, contains('OUT OF DATE'));
      expect(out, contains('Facebook Page at save: Acme Studio'));
      expect(out, contains('private KORLIX asset'));
      expect(out, contains('No ad or spending'));
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('Editor saves, previews and exports at $width', (t) async {
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
      final c = makeClient((r) async {
        calls.add(r);
        if (r.url.path.contains('/images/')) return reply({'content': pixel});
        if (r.method == 'POST') {
          final b = jsonDecode(r.body);
          expect(b.keys.toSet(), {'version', 'fingerprint', 'assets'});
          data = {...data, 'version': 2, 'assets': b['assets']};
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
        await capture(t, key, 'editor', width);
      }
      await t.enterText(field('Headline'), 'Plan your next step');
      await t.pump();
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);
      await tap(t, 'Save Meta draft');
      expect(find.text('Meta ad draft saved.'), findsOneWidget);
      expect(calls.where((r) => r.method == 'POST').length, 1);
      await tap(t, 'Copy saved draft');
      expect(copied, contains('Headline: Plan your next step'));
      expect(copied, contains('facebook'));
      expect(copied, contains('Our team.png'));
      await t.ensureVisible(find.text('Preview'));
      await t.pumpAndSettle();
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await capture(t, key, 'preview', width);
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Image chooser selects a private image and saves only its reference',
    (t) async {
      var data = fixture(saved: false);
      Map? body;
      final c = makeClient((r) async {
        if (r.url.path.endsWith('/images')) {
          return reply({
            'images': [imageFixture()],
          });
        }
        if (r.url.path.contains('/images/')) return reply({'content': pixel});
        if (r.method == 'POST') {
          body = jsonDecode(r.body);
          data = {
            ...data,
            'version': 1,
            'assets': body!['assets'],
            'image': imageFixture(),
            'saved_context': clone(data['setup']['current_snapshot']),
            'updated_at': '2026-09-23T13:00:00Z',
            'draft_current': true,
          };
        }
        return reply(data);
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await tap(t, 'Choose image');
      await tap(t, 'Use image');
      expect(find.text('Our team.png · 600 × 400'), findsOneWidget);
      await tap(t, 'Save Meta draft');
      expect(body!['assets']['image_id'], iid);
      expect(body!['assets']['image_alt'], 'Our team');
      expect(body.toString(), isNot(contains(pixel)));
      await tap(t, 'Remove image');
      expect(find.text('Image description'), findsNothing);
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);
    },
  );
  testWidgets('Conflict blocks save and export until confirmed reload', (
    t,
  ) async {
    var calls = 0;
    final c = makeClient((r) async {
      if (r.url.path.contains('/images/')) return reply({'content': pixel});
      if (r.method == 'POST') {
        calls++;
        return reply({'error': 'Changed. Reload before saving.'}, 409);
      }
      return reply(fixture());
    });
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    await t.enterText(field('Headline'), 'Changed');
    await tap(t, 'Save Meta draft');
    expect(saveButton(t).onPressed, isNull);
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Copy saved draft'),
          )
          .onPressed,
      isNull,
    );
    await tap(t, 'Reload after conflict');
    await tap(t, 'Keep editing');
    expect(calls, 1);
    await tap(t, 'Reload after conflict');
    await tap(t, 'Discard changes');
    expect(saveButton(t).onPressed, isNotNull);
  });
  testWidgets(
    'Late save response cannot restore private data after owner scope changes',
    (t) async {
      final scope = ValueNotifier(0), pending = Completer<http.Response>();
      addTearDown(scope.dispose);
      final c = makeClient((r) async {
        if (r.url.path.contains('/images/')) return reply({'content': pixel});
        if (r.method == 'POST') return pending.future;
        return reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c, scope: scope));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save Meta draft'));
      await t.tap(find.text('Save Meta draft'));
      await t.pump();
      scope.value++;
      await t.pump();
      pending.complete(reply(fixture()));
      await t.pumpAndSettle();
      expect(find.text('Meet your next partner'), findsNothing);
      expect(find.text('Save Meta draft'), findsNothing);
      expect(find.textContaining('workspace changed'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Pending picker is cancelled when owner scope changes before upload',
    (t) async {
      final scope = ValueNotifier(0), pending = Completer<FunnelPickedImage?>();
      addTearDown(scope.dispose);
      var uploads = 0;
      final c = makeClient((r) async {
        if (r.url.path.contains('/images/')) return reply({'content': pixel});
        if (r.method == 'POST') uploads++;
        return reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c, scope: scope, picker: () => pending.future));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Upload image'));
      await t.tap(find.text('Upload image'));
      await t.pump();
      scope.value++;
      await t.pump();
      pending.complete(FunnelPickedImage('team.png', base64Decode(pixel)));
      await t.pumpAndSettle();
      expect(uploads, 0);
      expect(find.text('Save Meta draft'), findsNothing);
    },
  );
  for (final code in [401, 403, 404]) {
    testWidgets('Denied $code clears text, images and export', (t) async {
      var deny = false;
      final c = makeClient((r) async {
        if (r.url.path.contains('/images/')) return reply({'content': pixel});
        return deny ? reply({'error': 'Unavailable'}, code) : reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      deny = true;
      await tap(t, 'Reload saved draft');
      expect(find.text('Meet your next partner'), findsNothing);
      expect(find.byType(FunnelPrivateImage), findsNothing);
      expect(find.text('Copy saved draft'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Malformed save response clears unverified data', (t) async {
    final c = makeClient((r) async {
      if (r.url.path.contains('/images/')) return reply({'content': pixel});
      return reply(
        r.method == 'POST'
            ? {...fixture(), 'ad_publishing_ready': true}
            : fixture(),
      );
    });
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    await tap(t, 'Save Meta draft');
    expect(find.text('Copy saved draft'), findsNothing);
    expect(find.textContaining('could not be verified'), findsOneWidget);
  });
  testWidgets(
    'Archived draft allows export but disables editing and image upload',
    (t) async {
      final c = makeClient(
        (r) async => r.url.path.contains('/images/')
            ? reply({'content': pixel})
            : reply({...fixture(), 'editable': false}),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(saveButton(t).onPressed, isNull);
      expect(t.widget<TextField>(field('Headline')).enabled, false);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Upload image'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Copy saved draft'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'Upload uses private image API and returns a selectable draft asset',
    (t) async {
      var uploaded = false;
      final c = makeClient((r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/images')) {
          uploaded = true;
          expect(r.headers['content-type'], contains('multipart/form-data'));
          return reply({'image': imageFixture()});
        }
        if (r.url.path.contains('/images/')) return reply({'content': pixel});
        return reply(fixture(saved: false));
      });
      addTearDown(c.dispose);
      await t.pumpWidget(
        app(
          c,
          picker: () async =>
              FunnelPickedImage('Our team.png', base64Decode(pixel)),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Upload image');
      expect(uploaded, true);
      expect(find.text('Our team.png · 600 × 400'), findsOneWidget);
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);
      await t.ensureVisible(find.text('Preview'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    },
  );
  testWidgets(
    'Campaign entry opens Meta creative and invalidates it when client changes',
    (t) async {
      final c = makeClient((r) async {
            if (r.url.path.endsWith('/meta-creative')) return reply(fixture());
            if (r.url.path.contains('/images/')) {
              return reply({'content': pixel});
            }
            if (r.url.path.endsWith('/campaigns')) {
              return reply({
                'ai_ready': false,
                'campaigns': [
                  {
                    ...setupFixture()['current_snapshot']['campaign'],
                    'platform': 'meta',
                    'state': 'reviewed',
                    'version': 1,
                    'page_state': 'published',
                    'review_current': true,
                    'tracking_url': 'https://example.com',
                    'reports': [],
                  },
                ],
              });
            }
            return reply({'configured': false, 'connection': null});
          }),
          next = makeClient(
            (r) async => reply(
              r.url.path.endsWith('/campaigns')
                  ? {'campaigns': [], 'ai_ready': false}
                  : {'configured': false, 'connection': null},
            ),
          );
      addTearDown(c.dispose);
      addTearDown(next.dispose);
      Widget parent(FunnelClient client) => MaterialApp(
        theme: WfStyle.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FunnelCampaigns(client: client, funnelId: fid),
          ),
        ),
      );
      await t.pumpWidget(parent(c));
      await t.pumpAndSettle();
      await tap(t, 'Meta ad creative');
      expect(find.text('Save Meta draft'), findsOneWidget);
      await t.pumpWidget(parent(next));
      await t.pumpAndSettle();
      expect(find.text('Save Meta draft'), findsNothing);
      expect(find.textContaining('workspace changed'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Image library disables deletion for creative references', (
    t,
  ) async {
    final c = makeClient(
      (r) async => reply(
        r.url.path.endsWith('/images')
            ? {
                'images': [imageFixture()],
                'used_bytes': 1000,
              }
            : {'content': pixel},
      ),
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: WfStyle.theme,
        home: Scaffold(
          body: FunnelImageLibrary(
            client: c,
            slot: 'hero_image',
            protectedIds: {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.textContaining('In use'), findsOneWidget);
  });
}

Future<void> capture(
  WidgetTester t,
  GlobalKey key,
  String label,
  double width,
) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      '/tmp/k171-$label-${width.toInt()}.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
