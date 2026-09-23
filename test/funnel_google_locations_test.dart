import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_locations.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_targeting.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_google_preflight.dart';
import 'funnel_google_targeting_test.dart' as base;
import 'funnel_google_radius_test.dart' as radius;
import 'funnel_google_preflight_test.dart' as preflight;

const city = <String, dynamic>{
  'id': '1023640',
  'name': 'Columbus,Ohio,United States',
  'country': 'US',
  'type': 'City',
};
Map<String, dynamic> fixture() {
  final d = base.fixture();
  d['radius_supported'] = true;
  d['locations_supported'] = true;
  d['location_catalog_version'] = googleLocationCatalogVersion;
  d['assets']['countries'] = <String>[];
  d['assets']['geo_locations'] = [base.clone(city)];
  d['saved_labels'] = base.labels(d['assets']);
  return d;
}

Map<String, dynamic> results({
  String query = 'Columbus',
  String country = 'US',
}) => {
  'source': 'google_location_catalog',
  'catalog_version': googleLocationCatalogVersion,
  'country': country,
  'query': query,
  'kind': 'all',
  'more': false,
  'locations': [base.clone(city)],
};
Future<void> search(WidgetTester t, String value) async {
  await t.enterText(find.byKey(const ValueKey('google-location-query')), value);
  await base.tap(t, 'Search locations');
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
    'Named target validation, capability gates and saved/review exports preserve exact reference identity',
    () {
      expect(
        validateGoogleTargeting(
          fixture(),
          base.fid,
          base.cid,
        )['draft_complete'],
        true,
      );
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d.remove('locations_supported'),
        (d) => d['location_catalog_version'] = 'unknown',
        (d) => d['assets']['countries'] = ['US'],
        (d) => d['assets']['proximities'] = [],
        (d) => d['assets']['excluded_countries'] = ['US'],
        (d) => d['assets']['geo_locations'] = [city, city],
        (d) => d['assets']['geo_locations'][0]['name'] = '<Ohio>',
        (d) => d['assets']['geo_locations'][0]['id'] = 1023640,
        (d) => d['assets']['geo_locations'][0]['country'] = 'XX',
      ]) {
        final d = fixture();
        change(d);
        expect(
          () => validateGoogleTargeting(d, base.fid, base.cid),
          throwsException,
        );
      }
      expect(
        googleTargetingComplete({...fixture()['assets'], 'geo_locations': []}),
        false,
      );
      expect(
        googleLocationsSummary(fixture()['assets']),
        contains('Google ID 1023640'),
      );
      final p = preflight.fixture();
      p['targeting'] = fixture();
      expect(
        googlePreparationSummary(p),
        contains('Columbus,Ohio,United States'),
      );
      expect(googlePreparationSummary(p), contains('Google ID 1023640'));
    },
  );
  test(
    'Location search rejects wrong country, stale query, malformed types, duplicates and oversized results',
    () {
      expect(validateGoogleLocationSearch(results(), 'US', 'Columbus', 'all'), [
        city,
      ]);
      for (final change in <void Function(Map<String, dynamic>)>[
        (r) => r['country'] = 'JM',
        (r) => r['query'] = 'Ohio',
        (r) => r['kind'] = 'city',
        (r) => r['catalog_version'] = 'other',
        (r) => r['more'] = 'true',
        (r) => r['locations'] = [city, city],
        (r) => r['locations'] = List.filled(31, city),
        (r) => r['locations'][0]['country'] = 'JM',
        (r) => r['locations'][0]['type'] = 'Airport',
      ]) {
        final r = results();
        change(r);
        expect(
          () => validateGoogleLocationSearch(r, 'US', 'Columbus', 'all'),
          throwsException,
        );
      }
    },
  );
  for (final width in [1400.0, 390.0, 320.0]) {
    testWidgets('City search, save, historical review and export fit $width', (
      t,
    ) async {
      await t.binding.setSurfaceSize(Size(width, width == 1400 ? 1100 : 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var d = base.fixture()
        ..['radius_supported'] = true
        ..['locations_supported'] = true
        ..['location_catalog_version'] = googleLocationCatalogVersion;
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
        if (r.url.path.endsWith('/locations')) {
          expect(r.url.queryParameters, {
            'q': 'Columbus',
            'country': 'US',
            'kind': 'all',
          });
          return base.reply(results());
        }
        if (r.url.path.endsWith('/save')) {
          sent = jsonDecode(r.body);
          d['assets'] = base.clone(sent!['assets']);
          d['saved_labels'] = base.labels(d['assets']);
          d['version']++;
          d['draft_revision']++;
          d['draft_complete'] = googleTargetingComplete(d['assets']);
          d['review_checks']['complete_choices'] = d['draft_complete'];
          d['review_ready'] = d['draft_complete'];
          d['review_current'] = false;
          d['review_fingerprint'] = 'c' * 64;
        } else if (r.url.path.endsWith('/review')) {
          radius.markReview(d);
        }
        return base.reply(d);
      });
      addTearDown(client.dispose);
      final key = GlobalKey();
      await t.pumpWidget(
        base.app(client, captureKey: key, scale: width == 320 ? 1.3 : 1),
      );
      await t.pumpAndSettle();
      await radius.mode(t, 'Cities and regions');
      await base.tap(t, 'Keep current targets');
      expect(find.text('Add target country'), findsOneWidget);
      await radius.mode(t, 'Cities and regions');
      await base.tap(t, 'Change target type');
      await base.tap(t, 'Add city or region');
      await search(t, 'Columbus');
      expect(find.text('Columbus, Ohio, United States'), findsOneWidget);
      await t.ensureVisible(
        find.byKey(const ValueKey('google-location-1023640')),
      );
      await t.pumpAndSettle();
      if (Platform.environment['KORLIX_LOCATION_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final shot = await boundary.toImage();
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          shot.dispose();
          await File(
            '/tmp/k176-locations-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await t.tap(find.byKey(const ValueKey('google-location-1023640')));
      await t.pumpAndSettle();
      await base.tap(t, 'Save targeting draft');
      expect(sent!['assets']['geo_locations'], [city]);
      await base.tap(t, 'Copy saved targeting');
      expect(copied, contains('Google ID 1023640'));
      expect(copied, contains('Columbus,Ohio,United States'));
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await base.tap(t, 'Save targeting review');
      await radius.mode(t, 'Radius areas');
      await base.tap(t, 'Change target type');
      await base.tap(t, 'Save targeting draft');
      expect(d['review_current'], false);
      await base.tap(t, 'Copy review record');
      expect(copied, contains('Google ID 1023640'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Old search replies cannot replace newer input or survive workspace changes',
    (t) async {
      final pending = Completer<http.Response>(), scope = ValueNotifier(0);
      addTearDown(scope.dispose);
      var d = fixture();
      d['assets']['geo_locations'] = [];
      d['draft_complete'] = false;
      d['review_checks']['complete_choices'] = false;
      d['review_ready'] = false;
      final client = base.makeClient(
        (r) async =>
            r.url.path.endsWith('/locations') ? pending.future : base.reply(d),
      );
      addTearDown(client.dispose);
      await t.pumpWidget(base.app(client, scope: scope));
      await t.pumpAndSettle();
      await base.tap(t, 'Add city or region');
      await t.enterText(
        find.byKey(const ValueKey('google-location-query')),
        'Columbus',
      );
      await t.tap(find.text('Search locations'));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('google-location-query')),
        'Ohio',
      );
      pending.complete(base.reply(results()));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('google-location-1023640')),
        findsNothing,
      );
      scope.value++;
      await t.pumpAndSettle();
      expect(
        find.text('This workspace is no longer available. Close this search.'),
        findsOneWidget,
      );
      expect(find.text('Search locations'), findsNothing);
    },
  );
  testWidgets(
    'Search errors are retryable and duplicate targets cannot be selected',
    (t) async {
      var calls = 0;
      final client = base.makeClient((r) async {
        if (r.url.path.endsWith('/locations')) {
          calls++;
          return calls == 1
              ? base.reply({'error': 'Try again'}, 503)
              : base.reply(results());
        }
        return base.reply(fixture());
      });
      addTearDown(client.dispose);
      await t.pumpWidget(base.app(client));
      await t.pumpAndSettle();
      await base.tap(t, 'Add city or region');
      await search(t, 'Columbus');
      expect(find.text('Try again'), findsOneWidget);
      await base.tap(t, 'Search locations');
      final tile = t.widget<ListTile>(
        find.byKey(const ValueKey('google-location-1023640')),
      );
      expect(tile.enabled, false);
      expect(tile.onTap, isNull);
      expect(t.takeException(), isNull);
    },
  );
}
