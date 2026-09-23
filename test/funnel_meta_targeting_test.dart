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
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_targeting.dart';
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
Map<String, dynamic> creativeFixture({bool saved = true}) {
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

Map<String, dynamic> fixture({bool saved = true, bool reviewed = false}) {
  final creative = creativeFixture();
  final d = <String, dynamic>{
    'source': 'meta_targeting_draft',
    'funnel_id': fid,
    'campaign_id': cid,
    'version': saved ? 1 : 0,
    'draft_revision': saved ? 1 : 0,
    'fingerprint': 'c' * 64,
    'creative': creative,
    'assets': saved
        ? {
            'countries': ['US', 'JM'],
            'age_min': 25,
            'age_max': 65,
            'placements': 'facebook_feed',
            'categories': ['NONE'],
          }
        : emptyMetaTargeting(),
    'saved_context': saved
        ? clone(creative['setup']['current_snapshot'])
        : null,
    'saved_labels': saved ? {'US': 'United States', 'JM': 'Jamaica'} : null,
    'updated_at': saved ? '2026-09-23T14:00:00Z' : null,
    'draft_current': saved,
    'draft_complete': saved,
    'editable': true,
    'catalog': {
      'version': 'korlix-meta-preparation-2026-09-23',
      'scope': 'country_planning',
      'countries': [
        {'code': 'US', 'name': 'United States'},
        {'code': 'JM', 'name': 'Jamaica'},
        {'code': 'CA', 'name': 'Canada'},
      ],
    },
    'ad_publishing_ready': false,
    'review_fingerprint': 'd' * 64,
    'review_checks': {
      'saved_draft': saved,
      'complete_choices': saved,
      'current_context': saved,
      'page_published': true,
      'plan_reviewed': true,
      'creative_saved': true,
      'creative_complete': true,
      'creative_current': true,
    },
    'review_ready': saved,
    'review_current': false,
    'reviewed_at': null,
    'reviewed_snapshot': null,
  };
  return reviewed ? reviewedFixture(d) : d;
}

Map<String, dynamic> reviewedFixture(Map<String, dynamic> data) {
  final d = clone(data), c = d['creative'];
  d['version']++;
  d['review_current'] = true;
  d['reviewed_at'] = '2026-09-23T14:10:00Z';
  d['reviewed_snapshot'] = {
    'assets': clone(d['assets']),
    'context': clone(d['saved_context']),
    'labels': clone(d['saved_labels']),
    'catalog_version': d['catalog']['version'],
    'draft_revision': d['draft_revision'],
    'saved_at': d['updated_at'],
    'creative': {
      'version': c['version'],
      'assets': clone(c['assets']),
      'image': clone(c['image']),
      'context': clone(c['saved_context']),
      'saved_at': c['updated_at'],
    },
  };
  return d;
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
    body: FunnelMetaTargeting(
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
    t.widget(find.widgetWithText(FilledButton, 'Save Meta targeting'));
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
    'Targeting and combined review validate exact creative, context and revision bindings',
    () {
      for (final d in [
        fixture(),
        fixture(saved: false),
        fixture(reviewed: true),
      ]) {
        expect(validateMetaTargeting(d, fid, cid), same(d));
      }
      final good = fixture(reviewed: true);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['ad_publishing_ready'] = true,
        (r) => r['campaign_id'] = 'other',
        (r) => r['draft_complete'] = false,
        (r) => r['review_ready'] = false,
        (r) => r['review_checks']['creative_current'] = false,
        (r) => r['assets']['countries'] = ['ZZ'],
        (r) => r['assets']['countries'] = ['US', 'US'],
        (r) => r['assets']['age_min'] = 17,
        (r) => r['assets']['categories'] = ['HOUSING'],
        (r) => r['assets']['categories'] = ['NONE', 'HOUSING'],
        (r) => r['assets']['placements'] = 'publish',
        (r) => r['saved_context']['landing_page']['destination'] =
            'javascript:bad',
        (r) => r['reviewed_snapshot']['creative']['version'] = 100,
        (r) => r['reviewed_snapshot']['creative']['assets']['headline'] =
            'Other reviewed text',
        (r) => r['reviewed_snapshot']['labels'] = {},
        (r) => r['reviewed_snapshot']['draft_revision'] = 0,
        (r) => r['reviewed_snapshot']['creative']['image']['id'] = 'bad',
        (r) =>
            r['reviewed_snapshot']['creative']['context']['campaign']['name'] =
                'Changed',
      ]) {
        final d = clone(good);
        mutate(d);
        expect(
          () => validateMetaTargeting(d, fid, cid),
          throwsA(isA<FunnelException>()),
        );
      }
      final stale = clone(good);
      stale['review_current'] = false;
      stale['creative']['version'] = 2;
      stale['creative']['assets']['headline'] = 'New creative';
      expect(validateMetaTargeting(stale, fid, cid)['review_current'], false);
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('Save, review, export and clear fit $width', (t) async {
      await t.binding.setSurfaceSize(Size(width, width == 1400 ? 1100 : 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var d = fixture();
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
          if (r.url.path.endsWith('/save')) {
            expect(b.keys.toSet(), {'version', 'fingerprint', 'assets'});
            d = {
              ...d,
              'version': d['version'] + 1,
              'draft_revision': d['draft_revision'] + 1,
              'assets': b['assets'],
            };
          } else if (r.url.path.endsWith('/review')) {
            expect(b['confirmed'], true);
            expect(b['review_fingerprint'], d['review_fingerprint']);
            d = reviewedFixture(d);
          } else {
            d = {
              ...d,
              'version': d['version'] + 1,
              'review_current': false,
              'reviewed_at': null,
              'reviewed_snapshot': null,
            };
          }
        }
        return reply(d);
      });
      addTearDown(c.dispose);
      final key = GlobalKey();
      await t.pumpWidget(
        app(c, captureKey: key, scale: width == 320 ? 1.3 : 1),
      );
      await t.pumpAndSettle();
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await capture(t, key, 'editor', width);
      }
      expect(t.takeException(), isNull);
      await tap(t, 'Save Meta targeting');
      await tap(t, metaTargetingReviewConfirmation);
      await tap(t, 'Save Meta preparation review');
      expect(find.text('PREPARATION REVIEW CURRENT'), findsOneWidget);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await capture(t, key, 'review', width);
      }
      await tap(t, 'Copy review record');
      expect(copied, contains('OWNER META PREPARATION REVIEW'));
      expect(copied, contains('Countries: United States (US), Jamaica (JM)'));
      expect(copied, contains('Headline: Meet your next partner'));
      expect(copied, contains('private KORLIX asset'));
      await tap(t, 'Clear Meta preparation review');
      await tap(t, 'Clear review');
      expect(find.text('PREPARATION NOT REVIEWED'), findsOneWidget);
      expect(calls.where((r) => r.method == 'POST').length, 3);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Country picker and special categories update draft without saving automatically',
    (t) async {
      var posts = 0;
      final c = makeClient((r) async {
        if (r.url.path.contains('/images/')) return reply({'content': pixel});
        if (r.method == 'POST') posts++;
        return reply(fixture());
      });
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await tap(t, 'Add target country');
      await t.enterText(field('Search choices'), 'Canada');
      await t.pumpAndSettle();
      await tap(t, 'Canada');
      expect(find.text('Canada'), findsOneWidget);
      await tap(t, 'Housing');
      expect(
        t
            .widget<DropdownButtonFormField<int>>(
              find.byWidgetPredicate(
                (w) =>
                    w is DropdownButtonFormField<int> &&
                    w.decoration.labelText == 'Minimum age',
              ),
            )
            .onChanged,
        isNull,
      );
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);
      expect(posts, 0);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save Meta preparation review'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('Creative editor return refreshes combined preparation state', (
    t,
  ) async {
    var reads = 0;
    final c = makeClient((r) async {
      if (r.url.path.contains('/images/')) return reply({'content': pixel});
      if (r.url.path.endsWith('/meta-creative')) {
        return reply(creativeFixture());
      }
      reads++;
      return reply(fixture());
    });
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    await tap(t, 'Open creative draft');
    expect(find.byType(FunnelMetaCreative), findsOneWidget);
    await tap(t, 'Close');
    expect(find.byType(FunnelMetaCreative), findsNothing);
    expect(reads, 2);
    expect(t.takeException(), isNull);
  });
  testWidgets('Late review response is ignored after workspace invalidation', (
    t,
  ) async {
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
    await tap(t, metaTargetingReviewConfirmation);
    await t.ensureVisible(find.text('Save Meta preparation review'));
    await t.tap(find.text('Save Meta preparation review'));
    await t.pump();
    scope.value++;
    await t.pump();
    pending.complete(reply(fixture(reviewed: true)));
    await t.pumpAndSettle();
    expect(find.textContaining('workspace changed'), findsOneWidget);
    expect(find.text('Save Meta preparation review'), findsNothing);
    expect(find.byType(FunnelPrivateImage), findsNothing);
  });
  testWidgets(
    'Scope change while creative child is open clears both private surfaces',
    (t) async {
      final scope = ValueNotifier(0);
      addTearDown(scope.dispose);
      final c = makeClient(
        (r) async => r.url.path.contains('/images/')
            ? reply({'content': pixel})
            : reply(
                r.url.path.endsWith('/meta-creative')
                    ? creativeFixture()
                    : fixture(),
              ),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c, scope: scope));
      await t.pumpAndSettle();
      await tap(t, 'Open creative draft');
      scope.value++;
      await t.pumpAndSettle();
      expect(find.text('Save Meta draft'), findsNothing);
      expect(find.text('Save Meta targeting'), findsNothing);
      expect(find.byType(FunnelPrivateImage), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Conflicts block further writes and export until reload', (
    t,
  ) async {
    final c = makeClient(
      (r) async => r.url.path.contains('/images/')
          ? reply({'content': pixel})
          : r.method == 'POST'
          ? reply({'error': 'Creative changed. Reload.'}, 409)
          : reply(fixture()),
    );
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    await tap(t, metaTargetingReviewConfirmation);
    await tap(t, 'Save Meta preparation review');
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
    expect(saveButton(t).onPressed, isNotNull);
  });
  for (final status in [401, 403, 404]) {
    testWidgets(
      'Denied $status clears targeting, creative and historical reviews',
      (t) async {
        var denied = false;
        final c = makeClient(
          (r) async => r.url.path.contains('/images/')
              ? reply({'content': pixel})
              : denied
              ? reply({'error': 'Unavailable'}, status)
              : reply(fixture(reviewed: true)),
        );
        addTearDown(c.dispose);
        await t.pumpWidget(app(c));
        await t.pumpAndSettle();
        denied = true;
        await tap(t, 'Reload saved draft');
        expect(find.text('Copy review record'), findsNothing);
        expect(find.text('United States'), findsNothing);
        expect(find.byType(FunnelPrivateImage), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Stale review exports its original creative rather than the newly saved creative',
    (t) async {
      final d = fixture(reviewed: true);
      d['review_current'] = false;
      d['creative']['version'] = 2;
      d['creative']['assets']['headline'] = 'New live draft headline';
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
      final c = makeClient(
        (r) async => r.url.path.contains('/images/')
            ? reply({'content': pixel})
            : reply(d),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await tap(t, 'Copy review record');
      expect(copied, contains('OUT OF DATE'));
      expect(copied, contains('Headline: Meet your next partner'));
      expect(copied, isNot(contains('New live draft headline')));
    },
  );
  testWidgets(
    'Archived drafts remain exportable and clearable but cannot be edited or reviewed',
    (t) async {
      final d = fixture(reviewed: true);
      d['editable'] = false;
      d['creative']['editable'] = false;
      d['review_current'] = false;
      d['review_ready'] = false;
      d['review_checks']['plan_reviewed'] = false;
      d['creative']['setup']['checks']['plan_reviewed'] = false;
      d['creative']['setup']['ready_for_review'] = false;
      final c = makeClient(
        (r) async => r.url.path.contains('/images/')
            ? reply({'content': pixel})
            : reply(d),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(saveButton(t).onPressed, isNull);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save Meta preparation review'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Copy review record'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('Malformed response clears review and export controls', (
    t,
  ) async {
    final c = makeClient(
      (r) async => reply({...fixture(), 'ad_publishing_ready': true}),
    );
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    expect(find.text('Copy review record'), findsNothing);
    expect(find.textContaining('could not be verified'), findsOneWidget);
  });
  testWidgets(
    'Campaign card opens Meta targeting and invalidates on client change',
    (t) async {
      final c = makeClient((r) async {
            if (r.url.path.contains('/images/')) {
              return reply({'content': pixel});
            }
            if (r.url.path.endsWith('/meta-targeting')) return reply(fixture());
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
      await tap(t, 'Meta targeting and placement');
      expect(find.text('Save Meta targeting'), findsOneWidget);
      await t.pumpWidget(parent(next));
      await t.pumpAndSettle();
      expect(find.text('Save Meta targeting'), findsNothing);
      expect(find.textContaining('workspace changed'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
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
      '/tmp/k172-$label-${width.toInt()}.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
