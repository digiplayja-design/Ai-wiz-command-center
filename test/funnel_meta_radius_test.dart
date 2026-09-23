import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_radius.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_targeting.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_radius_fields.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'funnel_meta_targeting_test.dart' as base;

const radius = <String, dynamic>{
  'label': 'Columbus service area',
  'latitude_micro': 39961176,
  'longitude_micro': -82998794,
  'radius_meters': 15125,
};
Map<String, dynamic> radiusFixture() {
  final d = base.fixture();
  d['radius_supported'] = true;
  d['assets']['countries'] = <String>[];
  d['assets']['custom_locations'] = [base.clone(radius)];
  d['saved_labels'] = <String, dynamic>{};
  return d;
}

Future<void> enter(WidgetTester t, String key, String value) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> mode(WidgetTester t, String name) async {
  final f = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        '${w.key}'.contains('area-mode-'),
  );
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
  await base.tap(t, name);
}

bool metaAreaValid(dynamic v) => radiusAreaValid(v, maxMeters: 80000);
FunnelClient makeClient(Future<http.Response> Function(http.Request) fn) =>
    base.makeClient(
      (r) async => r.url.path.contains('/images/')
          ? base.reply({'content': base.pixel})
          : await fn(r),
    );
void markReview(Map<String, dynamic> d) {
  final n = base.reviewedFixture(d);
  d.clear();
  d.addAll(n);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final name in ['MaterialIcons-Regular.otf', 'Roboto-Regular.ttf']) {
        final file = File('$root/bin/cache/artifacts/material_fonts/$name');
        if (file.existsSync()) {
          await (FontLoader(
                name.startsWith('Material') ? 'MaterialIcons' : 'Roboto',
              )..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  test(
    'Radius input preserves exact decimal precision and rejects invalid, oversized and mixed targets',
    () {
      expect(radiusNumber('39.961176', 6, -90000000, 90000000), 39961176);
      expect(radiusNumber('-82.998794', 6, -180000000, 180000000), -82998794);
      expect(radiusNumber('15.125', 3, 1000, 80000), 15125);
      for (final s in [
        'NaN',
        'Infinity',
        '1e2',
        '90.000001',
        '1.1234567',
        '',
      ]) {
        expect(radiusNumber(s, 6, -90000000, 90000000), isNull);
      }
      for (final s in ['0.999', '80.001', '15.1234', '-10']) {
        expect(radiusNumber(s, 3, 1000, 80000), isNull);
      }
      expect(radiusNumber('-90', 6, -90000000, 90000000), -90000000);
      expect(radiusNumber('180', 6, -180000000, 180000000), 180000000);
      expect(metaAreaValid(radius), true);
      for (final change in <Map<String, dynamic>>[
        {'label': ' name'},
        {'label': 'a\u0085b'},
        {'label': 'a\u2028b'},
        {'label': '<x>'},
        {'latitude_micro': 1.5},
        {'longitude_micro': 180000001},
        {'radius_meters': 999},
        {'extra': true},
      ]) {
        expect(metaAreaValid({...radius, ...change}), false);
      }
      expect(
        metaRadiiValid([
          radius,
          {...radius, 'label': 'Duplicate'},
        ]),
        false,
      );
      final d = radiusFixture();
      expect(validateMetaTargeting(d, base.fid, base.cid), d);
      d['assets']['countries'] = ['US'];
      expect(
        () => validateMetaTargeting(d, base.fid, base.cid),
        throwsException,
      );
    },
  );
  test(
    'Malformed radius capability, completeness and historical records fail closed',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d.remove('radius_supported'),
        (d) => d['radius_supported'] = 'true',
        (d) => d['assets']['custom_locations'][0]['radius_meters'] = 0,
        (d) => d['draft_complete'] = false,
        (d) {
          markReview(d);
          d['reviewed_snapshot']['assets']['custom_locations'][0]['longitude_micro'] =
              181000000;
        },
        (d) {
          d['version'] = 0;
          d['draft_revision'] = 0;
        },
      ]) {
        final d = radiusFixture();
        mutate(d);
        expect(
          () => validateMetaTargeting(d, base.fid, base.cid),
          throwsException,
        );
      }
      expect(
        metaTargetingComplete({
          ...radiusFixture()['assets'],
          'custom_locations': [],
        }),
        false,
      );
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('Radius editor save review and historical export fit $width', (
      t,
    ) async {
      await t.binding.setSurfaceSize(Size(width, width == 1400 ? 1100 : 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var d = base.fixture()..['radius_supported'] = true;
      String copied = '';
      Map? sent;
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
      final client = makeClient((r) async {
        if (r.url.path.endsWith('/save')) {
          sent = jsonDecode(r.body);
          d['assets'] = base.clone(sent!['assets']);
          d['version']++;
          d['draft_revision']++;
          d['saved_labels'] = <String, dynamic>{};
          d['draft_complete'] = metaTargetingComplete(d['assets']);
          d['review_checks']['complete_choices'] = d['draft_complete'];
          d['review_ready'] = d['draft_complete'];
          d['review_current'] = false;
          d['review_fingerprint'] = 'c' * 64;
        } else if (r.url.path.endsWith('/review')) {
          markReview(d);
        }
        return base.reply(d);
      });
      addTearDown(client.dispose);
      final key = GlobalKey();
      await t.pumpWidget(
        base.app(client, captureKey: key, scale: width == 320 ? 1.3 : 1),
      );
      await t.pumpAndSettle();
      await mode(t, 'Radius areas');
      await base.tap(t, 'Change target type');
      expect(find.text('Add target country'), findsNothing);
      await base.tap(t, 'Add radius area');
      expect(base.saveButton(t).onPressed, isNull);
      await enter(t, 'radius-label', 'Columbus service area');
      await enter(t, 'latitude_micro', '39.961176');
      await enter(t, 'longitude_micro', '-82.998794');
      await enter(t, 'radius_meters', '15.125');
      expect(base.saveButton(t).onPressed, isNotNull);
      await t.ensureVisible(find.text('Radius area'));
      await t.pumpAndSettle();
      if (Platform.environment['KORLIX_META_RADIUS_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final shot = await boundary.toImage();
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          shot.dispose();
          await File(
            '/tmp/k175-meta-radius-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await base.tap(t, 'Save Meta targeting');
      expect(sent!['assets']['custom_locations'], [radius]);
      expect(sent!['assets']['countries'], isEmpty);
      await base.tap(t, 'Copy saved targeting');
      expect(copied, contains('15.125 km around 39.961176, -82.998794'));
      await base.tap(t, metaTargetingReviewConfirmation);
      await base.tap(t, 'Save Meta preparation review');
      expect(d['review_current'], true);
      await enter(t, 'radius_meters', '20');
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Copy saved targeting'),
            )
            .onPressed,
        isNull,
      );
      await base.tap(t, 'Save Meta targeting');
      expect(d['review_current'], false);
      await base.tap(t, 'Copy review record');
      expect(copied, contains('15.125 km'));
      expect(copied, isNot(contains('20.000 km')));
      await base.tap(t, 'Copy saved targeting');
      expect(copied, contains('20.000 km'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Cancelled target-type change preserves selections; confirmed change drops radius data',
    (t) async {
      final client = makeClient((r) async => base.reply(radiusFixture()));
      addTearDown(client.dispose);
      await t.pumpWidget(base.app(client));
      await t.pumpAndSettle();
      await mode(t, 'Whole countries');
      await base.tap(t, 'Keep current targets');
      expect(find.text('Radius targets'), findsOneWidget);
      expect(find.text('Add target country'), findsNothing);
      await mode(t, 'Whole countries');
      await base.tap(t, 'Change target type');
      expect(find.text('Add target country'), findsOneWidget);
      expect(find.text('Radius targets'), findsNothing);
    },
  );
  testWidgets(
    'Removing an earlier area preserves unsaved text in the remaining area',
    (t) async {
      final d = radiusFixture();
      d['assets']['custom_locations'].add({
        ...radius,
        'label': 'Second',
        'latitude_micro': 1000000,
      });
      final client = makeClient((r) async => base.reply(d));
      addTearDown(client.dispose);
      await t.pumpWidget(base.app(client));
      await t.pumpAndSettle();
      final last = find.byKey(const ValueKey('radius-label')).last;
      await t.ensureVisible(last);
      await t.pumpAndSettle();
      await t.enterText(last, 'Second edited');
      await t.pumpAndSettle();
      final firstRemove = find.byTooltip('Remove radius area').first;
      await t.ensureVisible(firstRemove);
      await t.pumpAndSettle();
      await t.tap(firstRemove);
      await t.pumpAndSettle();
      expect(find.text('Second edited'), findsOneWidget);
      expect(find.text('Columbus service area'), findsNothing);
    },
  );
  testWidgets(
    'Scope loss clears unsaved radius coordinates and ignores pending save',
    (t) async {
      final pending = Completer<http.Response>(), scope = ValueNotifier(0);
      final client = makeClient(
        (r) async =>
            r.method == 'POST' ? pending.future : base.reply(radiusFixture()),
      );
      addTearDown(client.dispose);
      addTearDown(scope.dispose);
      await t.pumpWidget(base.app(client, scope: scope));
      await t.pumpAndSettle();
      await enter(t, 'radius_meters', '20');
      await t.ensureVisible(find.text('Save Meta targeting'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save Meta targeting'));
      await t.pump();
      scope.value++;
      await t.pumpAndSettle();
      expect(find.text('Columbus service area'), findsNothing);
      expect(find.byKey(const ValueKey('latitude_micro')), findsNothing);
      pending.complete(base.reply(radiusFixture()));
      await t.pumpAndSettle();
      expect(find.text('Columbus service area'), findsNothing);
    },
  );
  test(
    'Saved export includes exact local areas and special-category boundary',
    () {
      final d = radiusFixture();
      expect(
        metaTargetingExport(d),
        contains('15.125 km around 39.961176, -82.998794'),
      );
      d['assets']['categories'] = ['HOUSING'];
      d['assets']['age_min'] = 18;
      d['draft_complete'] = false;
      d['review_ready'] = false;
      d['review_checks']['complete_choices'] = false;
      expect(validateMetaTargeting(d, base.fid, base.cid), same(d));
      expect(metaTargetingExport(d), contains(metaRadiusCategoryNotice));
      expect(
        metaTargetingExport(base.fixture()),
        contains('Countries: United States (US), Jamaica (JM)'),
      );
    },
  );
  testWidgets(
    'Special-category local drafts save and retain areas but cannot be reviewed',
    (t) async {
      var d = radiusFixture();
      Map? sent;
      final client = makeClient((r) async {
        if (r.url.path.endsWith('/save')) {
          sent = jsonDecode(r.body);
          d['assets'] = base.clone(sent!['assets']);
          d['version']++;
          d['draft_revision']++;
          d['draft_complete'] = metaTargetingComplete(d['assets']);
          d['review_checks']['complete_choices'] = d['draft_complete'];
          d['review_ready'] = d['draft_complete'];
        }
        return base.reply(d);
      });
      addTearDown(client.dispose);
      await t.pumpWidget(base.app(client));
      await t.pumpAndSettle();
      await base.tap(t, 'Housing');
      expect(find.text(metaRadiusCategoryNotice), findsOneWidget);
      expect(base.saveButton(t).onPressed, isNotNull);
      await base.tap(t, 'Save Meta targeting');
      expect(sent!['assets']['custom_locations'], [radius]);
      expect(sent!['assets']['categories'], ['HOUSING']);
      expect(sent!['assets']['age_min'], 18);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save Meta preparation review'),
            )
            .onPressed,
        isNull,
      );
      await base.tap(t, 'No special category');
      expect(find.text(metaRadiusCategoryNotice), findsNothing);
      expect(find.byKey(const ValueKey('latitude_micro')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
