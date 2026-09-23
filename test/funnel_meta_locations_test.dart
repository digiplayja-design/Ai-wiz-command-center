import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_locations.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_meta_targeting.dart';
import 'funnel_meta_targeting_test.dart' as base;
import 'funnel_meta_radius_test.dart' as radius;

const city = <String, dynamic>{
  'key': '424242',
  'name': 'Columbus',
  'country': 'US',
  'type': 'city',
  'region': 'Ohio',
};
String get proof => '1999999999999.${'a' * 64}';
Map<String, dynamic> fixture({bool country = false}) {
  final d = base.fixture();
  d['radius_supported'] = true;
  d['locations_supported'] = true;
  d['location_lookup_ready'] = true;
  if (!country) {
    d['assets']['countries'] = <String>[];
    d['assets']['geo_locations'] = [base.clone(city)];
    d['saved_labels'] = <String, dynamic>{};
  }
  return d;
}

Map<String, dynamic> found([String query = 'Columbus']) => {
  'source': 'meta_location_search',
  'query': query,
  'country': 'US',
  'kind': 'all',
  'fingerprint': 'c' * 64,
  'more': false,
  'locations': [
    {...city, 'proof': proof},
  ],
};
void main() {
  test(
    'Meta named shape, separate ID namespaces, exclusive modes and special-category review',
    () {
      final d = fixture();
      expect(validateMetaTargeting(d, base.fid, base.cid), same(d));
      expect(metaTargetingComplete(d['assets']), isTrue);
      for (final patch in [
        {'key': 42},
        {'country': 'ZZ'},
        {'name': '<city>'},
        {'region': ' Ohio'},
        {'type': 'zip'},
        {'proof': proof},
      ]) {
        final a = base.clone(d['assets']);
        a['geo_locations'] = [
          {...city, ...patch},
        ];
        expect(metaTargetingValid(a, d['catalog']), isFalse);
      }
      for (final patch in [
        {
          'countries': ['US'],
        },
        {'custom_locations': []},
        {
          'geo_locations': [city, city],
        },
      ]) {
        expect(
          metaTargetingValid({...d['assets'], ...patch}, d['catalog']),
          isFalse,
        );
      }
      expect(
        metaTargetingValid({
          ...d['assets'],
          'geo_locations': [
            city,
            {...city, 'type': 'region'},
          ],
        }, d['catalog']),
        isTrue,
      );
      expect(
        metaTargetingComplete({
          ...d['assets'],
          'age_min': 18,
          'categories': ['HOUSING'],
        }),
        isFalse,
      );
      expect(
        () => validateMetaTargeting(
          {...d, 'location_lookup_ready': false},
          base.fid,
          base.cid,
        ),
        throwsException,
      );
    },
  );
  test(
    'Search responses bind query, country, type, fingerprint, proof shape and duplicate choices',
    () {
      expect(
        validateMetaLocationSearch(found(), 'US', 'Columbus', 'all', 'c' * 64),
        hasLength(1),
      );
      for (final patch in [
        {'country': 'CA'},
        {'query': 'other'},
        {'kind': 'city'},
        {'fingerprint': 'a' * 64},
        {'source': 'google_location_catalog'},
        {'more': 1},
        {
          'locations': [city],
        },
        {
          'locations': [
            {...city, 'proof': 'bad'},
          ],
        },
        {
          'locations': [
            {...city, 'proof': proof},
            {...city, 'proof': proof},
          ],
        },
      ]) {
        expect(
          () => validateMetaLocationSearch(
            {...found(), ...patch},
            'US',
            'Columbus',
            'all',
            'c' * 64,
          ),
          throwsException,
        );
      }
    },
  );
  test(
    'Saved and historical exports preserve exact Meta names, region, type and key without proof',
    () {
      final d = base.reviewedFixture(fixture());
      final text = metaTargetingExport(d);
      expect(text, contains('Columbus, Ohio (US)'));
      expect(text, contains('Meta key 424242'));
      expect(text, contains('city'));
      expect(text, isNot(contains(proof)));
      final old = base.clone(d['reviewed_snapshot']['assets']);
      d['assets']['geo_locations'][0]['name'] = 'New city';
      expect(metaLocationsSummary(old), contains('Columbus'));
      expect(metaLocationsSummary(old), isNot(contains('New city')));
    },
  );
  testWidgets(
    'Picker sends only explicit search and discards late results after query or scope changes',
    (t) async {
      final scope = ValueNotifier(0);
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      final c = base.makeClient((r) async {
        calls++;
        expect(r.url.queryParameters, {
          'q': 'Columbus',
          'country': 'US',
          'kind': 'all',
          'fingerprint': 'c' * 64,
        });
        return base.reply(await pending.future);
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetaLocationPicker(
              client: c,
              path: '/test',
              fingerprint: 'c' * 64,
              countries: fixture()['catalog']['countries'].cast<Map>(),
              blocked: {},
              scope: scope,
              active: () => true,
            ),
          ),
        ),
      );
      await t.enterText(
        find.byKey(const ValueKey('meta-location-query')),
        'Columbus',
      );
      await t.pump();
      expect(calls, 0);
      await base.tap(t, 'Search locations');
      expect(calls, 1);
      await t.enterText(
        find.byKey(const ValueKey('meta-location-query')),
        'Kingston',
      );
      pending.complete(found());
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('meta-location-city:424242')),
        findsNothing,
      );
      scope.value++;
      await t.pumpAndSettle();
      expect(
        find.textContaining('workspace is no longer available'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      scope.dispose();
      c.dispose();
    },
  );
  testWidgets(
    'Picker disables already selected results and rejects denied access',
    (t) async {
      var denied = false;
      final c = base.makeClient(
        (r) async => denied
            ? base.reply({'error': 'Access lost'}, 403)
            : base.reply(found()),
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetaLocationPicker(
              client: c,
              path: '/test',
              fingerprint: 'c' * 64,
              countries: fixture()['catalog']['countries'].cast<Map>(),
              blocked: {'city:424242'},
              active: () => true,
            ),
          ),
        ),
      );
      await t.enterText(
        find.byKey(const ValueKey('meta-location-query')),
        'Columbus',
      );
      await base.tap(t, 'Search locations');
      final tile = t.widget<ListTile>(
        find.byKey(const ValueKey('meta-location-city:424242')),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
      denied = true;
      await base.tap(t, 'Search locations');
      expect(
        find.textContaining('workspace is no longer available'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Location mode confirms replacement and save sends transient proofs separately',
    (t) async {
      var d = fixture(country: true);
      Map? sent;
      final c = radius.makeClient((r) async {
        if (r.url.path.endsWith('/locations')) return base.reply(found());
        if (r.method == 'POST' && r.url.path.endsWith('/save')) {
          sent = jsonDecode(r.body);
          d = fixture();
          d['assets'] = sent!['assets'];
          d['version']++;
          d['draft_revision']++;
          return base.reply(d);
        }
        return base.reply(d);
      });
      await t.pumpWidget(base.app(c));
      await t.pumpAndSettle();
      await radius.mode(t, 'Cities and regions');
      await base.tap(t, 'Keep current targets');
      expect(find.text('Meta city and region targets'), findsNothing);
      await radius.mode(t, 'Cities and regions');
      await base.tap(t, 'Change target type');
      await base.tap(t, 'Add Meta city or region');
      await t.enterText(
        find.byKey(const ValueKey('meta-location-query')),
        'Columbus',
      );
      await base.tap(t, 'Search locations');
      await t.tap(find.byKey(const ValueKey('meta-location-city:424242')));
      await t.pumpAndSettle();
      await base.tap(t, 'Save Meta targeting');
      expect(sent?['assets']['geo_locations'], [city]);
      expect(sent?['assets']['countries'], isEmpty);
      expect(sent?['assets'].containsKey('custom_locations'), isFalse);
      expect(sent?['location_proofs'], {'city:424242': proof});
      expect(find.text('Targeting draft saved.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Deferred Meta setup disables new search while preserving saved selections',
    (t) async {
      final d = fixture();
      d['location_lookup_ready'] = false;
      d['creative']['setup']['checks']['meta_configured'] = false;
      d['creative']['setup']['ready_for_review'] = false;
      var calls = 0;
      final c = radius.makeClient((r) async {
        calls++;
        return base.reply(d);
      });
      await t.pumpWidget(base.app(c));
      await t.pumpAndSettle();
      final button = find.widgetWithText(
        OutlinedButton,
        'Add Meta city or region',
      );
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      expect(t.widget<OutlinedButton>(button).onPressed, isNull);
      expect(
        find.textContaining('Location search will be available'),
        findsOneWidget,
      );
      expect(find.textContaining('Meta key 424242'), findsWidgets);
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Meta picker and editor fit desktop and narrow phones with large text',
    (t) async {
      final c = radius.makeClient((r) async => base.reply(fixture()));
      for (final size in [
        const Size(1400, 1200),
        const Size(390, 1000),
        const Size(320, 950),
      ]) {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(base.app(c, scale: size.width == 320 ? 1.3 : 1));
        await t.pumpAndSettle();
        await base.tap(t, 'Add Meta city or region');
        expect(find.text('Find a Meta city or region'), findsOneWidget);
        expect(t.takeException(), isNull);
        await base.tap(t, 'Close search');
        await t.pumpWidget(const SizedBox());
      }
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      c.dispose();
    },
  );
  testWidgets(
    'Changing clients clears an open private location picker and rejects its late response',
    (t) async {
      final pending = Completer<Map<String, dynamic>>();
      final first = radius.makeClient(
        (r) async => r.url.path.endsWith('/locations')
            ? base.reply(await pending.future)
            : base.reply(fixture()),
      );
      final second = radius.makeClient((r) async => base.reply(fixture()));
      await t.pumpWidget(base.app(first));
      await t.pumpAndSettle();
      await base.tap(t, 'Add Meta city or region');
      await t.enterText(
        find.byKey(const ValueKey('meta-location-query')),
        'Columbus',
      );
      await base.tap(t, 'Search locations');
      await t.pumpWidget(base.app(second));
      await t.pumpAndSettle();
      pending.complete(found());
      await t.pumpAndSettle();
      expect(
        find.textContaining('workspace is no longer available'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('meta-location-city:424242')),
        findsNothing,
      );
      await t.pumpWidget(const SizedBox());
      first.dispose();
      second.dispose();
    },
  );
}
