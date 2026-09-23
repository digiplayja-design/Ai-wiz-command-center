import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_radius.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_targeting.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_preflight.dart';
import 'funnel_google_targeting_test.dart' as base;
import 'funnel_google_preflight_test.dart' as preflight;

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
  d['assets']['proximities'] = [base.clone(radius)];
  d['saved_labels'] = base.labels(d['assets']);
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

void markReview(Map<String, dynamic> d) {
  d['version']++;
  d['review_current'] = true;
  d['reviewed_at'] = '2026-09-23T15:00:00Z';
  d['reviewed_snapshot'] = {
    'assets': base.clone(d['assets']),
    'context': base.clone(d['saved_context']),
    'labels': base.clone(d['saved_labels']),
    'catalog_version': d['catalog']['version'],
    'draft_revision': d['draft_revision'],
    'saved_at': d['updated_at'],
  };
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
      expect(googleRadiusNumber('39.961176', 6, -90000000, 90000000), 39961176);
      expect(
        googleRadiusNumber('-82.998794', 6, -180000000, 180000000),
        -82998794,
      );
      expect(googleRadiusNumber('15.125', 3, 1000, 200000), 15125);
      for (final s in [
        'NaN',
        'Infinity',
        '1e2',
        '90.000001',
        '1.1234567',
        '',
      ]) {
        expect(googleRadiusNumber(s, 6, -90000000, 90000000), isNull);
      }
      for (final s in ['0.999', '200.001', '15.1234', '-10']) {
        expect(googleRadiusNumber(s, 3, 1000, 200000), isNull);
      }
      expect(googleRadiusNumber('-90', 6, -90000000, 90000000), -90000000);
      expect(googleRadiusNumber('180', 6, -180000000, 180000000), 180000000);
      expect(googleRadiusValid(radius), true);
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
        expect(googleRadiusValid({...radius, ...change}), false);
      }
      expect(
        googleRadiiValid([
          radius,
          {...radius, 'label': 'Duplicate'},
        ]),
        false,
      );
      final d = radiusFixture();
      expect(validateGoogleTargeting(d, base.fid, base.cid), d);
      d['assets']['countries'] = ['US'];
      expect(
        () => validateGoogleTargeting(d, base.fid, base.cid),
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
        (d) => d['assets']['proximities'][0]['radius_meters'] = 0,
        (d) => d['draft_complete'] = false,
        (d) {
          markReview(d);
          d['reviewed_snapshot']['assets']['proximities'][0]['longitude_micro'] =
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
          () => validateGoogleTargeting(d, base.fid, base.cid),
          throwsException,
        );
      }
      expect(
        googleTargetingComplete({
          ...radiusFixture()['assets'],
          'proximities': [],
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
      final client = base.makeClient((r) async {
        if (r.url.path.endsWith('/save')) {
          sent = jsonDecode(r.body);
          d['assets'] = base.clone(sent!['assets']);
          d['version']++;
          d['draft_revision']++;
          d['saved_labels'] = base.labels(d['assets']);
          d['draft_complete'] = googleTargetingComplete(d['assets']);
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
      if (Platform.environment['KORLIX_RADIUS_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final shot = await boundary.toImage();
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          shot.dispose();
          await File(
            '/tmp/k174-radius-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await base.tap(t, 'Save targeting draft');
      expect(sent!['assets']['proximities'], [radius]);
      expect(sent!['assets']['countries'], isEmpty);
      await base.tap(t, 'Copy saved targeting');
      expect(copied, contains('15.125 km around 39.961176, -82.998794'));
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await base.tap(t, 'Save targeting review');
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
      await base.tap(t, 'Save targeting draft');
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
      final client = base.makeClient((r) async => base.reply(radiusFixture()));
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
      d['assets']['proximities'].add({
        ...radius,
        'label': 'Second',
        'latitude_micro': 1000000,
      });
      final client = base.makeClient((r) async => base.reply(d));
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
      final client = base.makeClient(
        (r) async =>
            r.method == 'POST' ? pending.future : base.reply(radiusFixture()),
      );
      addTearDown(client.dispose);
      addTearDown(scope.dispose);
      await t.pumpWidget(base.app(client, scope: scope));
      await t.pumpAndSettle();
      await enter(t, 'radius_meters', '20');
      await t.ensureVisible(find.text('Save targeting draft'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save targeting draft'));
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
    'Combined preparation summary includes exact radius values and country-only summaries remain valid',
    () {
      final d = preflight.fixture();
      final target = d['targeting'];
      target['radius_supported'] = true;
      target['assets']['countries'] = <String>[];
      target['assets']['proximities'] = [base.clone(radius)];
      target['saved_labels'] = base.labels(target['assets']);
      target['reviewed_snapshot']['assets'] = base.clone(target['assets']);
      target['reviewed_snapshot']['labels'] = base.clone(
        target['saved_labels'],
      );
      validateGooglePreflight(d, base.fid, base.cid);
      expect(
        googlePreparationSummary(d),
        contains('15.125 km around 39.961176, -82.998794'),
      );
      expect(
        googlePreparationSummary(preflight.fixture()),
        contains('Target area type: whole countries'),
      );
    },
  );
}
