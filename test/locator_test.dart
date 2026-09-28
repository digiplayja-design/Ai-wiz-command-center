import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/locator/locator_screen.dart';
import 'package:ai_wiz_command_center/locator/locator_search.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

Future<void> mount(WidgetTester tester, KorlixLocatorScreen page) async {
  tester.view.physicalSize = const Size(390, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('korlix_blue'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => page),
            ),
            child: const Text('Open Locator'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Locator'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> area(WidgetTester tester, String value) async {
  await tester.ensureVisible(find.byKey(const Key('locator-area')));
  await tester.enterText(find.byKey(const Key('locator-area')), value);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Google search includes acquired coordinates; manual area overrides them',
    () {
      const point = LocatorPosition(40.1234567, -74.7654321);
      final gps = locatorSearchUri(
        query: 'Find me a hospital near me',
        provider: LocatorMapProvider.google,
        position: point,
      );
      expect(gps.scheme, 'https');
      expect(gps.host, 'www.google.com');
      expect(gps.queryParameters['api'], '1');
      expect(
        gps.queryParameters['query'],
        'hospital near 40.123457,-74.765432',
      );
      final manual = locatorSearchUri(
        query: 'hospitals',
        provider: LocatorMapProvider.google,
        position: point,
        area: 'Columbus, Ohio',
      );
      expect(manual.queryParameters['query'], 'hospitals in Columbus, Ohio');
      expect(manual.toString(), isNot(contains('40.123')));
    },
  );
  test('Apple search uses sll without converting search into a pin label', () {
    final uri = locatorSearchUri(
      query: 'urgent care',
      provider: LocatorMapProvider.apple,
      position: const LocatorPosition(51.5, -.12),
    );
    expect(uri.host, 'maps.apple.com');
    expect(uri.queryParameters['q'], 'urgent care');
    expect(uri.queryParameters['sll'], '51.500000,-0.120000');
    expect(uri.queryParameters.containsKey('ll'), isFalse);
    final manual = locatorSearchUri(
      query: 'pharmacies',
      provider: LocatorMapProvider.apple,
      area: 'SW1A 1AA',
    );
    expect(manual.queryParameters['q'], 'pharmacies in SW1A 1AA');
    expect(manual.queryParameters.containsKey('sll'), isFalse);
  });
  test(
    'names and international locations are encoded without adding parameters',
    () {
      final uri = locatorSearchUri(
        query: 'St. Mary’s & Children #2',
        provider: LocatorMapProvider.google,
        area: 'São Paulo, Brasil',
      );
      expect(uri.queryParameters.length, 2);
      expect(
        uri.queryParameters['query'],
        'St. Mary’s & Children #2 in São Paulo, Brasil',
      );
      expect(uri.fragment, isEmpty);
      expect(cleanLocatorQuery('Findlay hospital'), 'Findlay hospital');
    },
  );
  test('empty, invalid-coordinate and overlong searches are rejected', () {
    expect(
      () => locatorSearchUri(query: ' ', provider: LocatorMapProvider.google),
      throwsFormatException,
    );
    expect(
      () => locatorSearchUri(
        query: 'hospital',
        provider: LocatorMapProvider.google,
        position: const LocatorPosition(double.nan, 0),
      ),
      throwsFormatException,
    );
    expect(
      () => locatorSearchUri(
        query: 'hospital',
        provider: LocatorMapProvider.google,
        position: const LocatorPosition(91, 0),
      ),
      throwsFormatException,
    );
    expect(
      () => locatorSearchUri(
        query: '医' * 300,
        provider: LocatorMapProvider.google,
      ),
      throwsFormatException,
    );
  });
  test(
    'all original categories remain alongside new care and travel categories',
    () {
      final names = [
        ...locatorCare,
        ...locatorEveryday,
        ...locatorExplore,
      ].map((c) => c.name);
      expect(
        names,
        containsAll([
          'Hospitals',
          'Urgent care',
          'Pharmacies',
          'Police stations',
          'Restaurants',
          'Gas stations',
          'ATMs',
          'Churches',
          'Bars',
          'Grocery stores',
          'Car washes',
          'Tire shops',
        ]),
      );
      expect(names.toSet().length, names.length);
    },
  );

  testWidgets(
    'hospital shortcut opens without GPS and respects provider selection',
    (tester) async {
      var locationCalls = 0;
      final launches = <Uri>[];
      await mount(
        tester,
        KorlixLocatorScreen(
          locate: () async {
            locationCalls++;
            return const LocatorPosition(40, -74);
          },
          openMap: (uri) async {
            launches.add(uri);
            return true;
          },
        ),
      );
      expect(locationCalls, 0);
      await tap(tester, 'Find hospitals');
      expect(locationCalls, 0);
      expect(launches.single.queryParameters['query'], 'hospitals');
      await area(tester, '43235');
      await tap(tester, 'Apple Maps');
      await tap(tester, 'Hospitals');
      expect(launches.last.host, 'maps.apple.com');
      expect(launches.last.queryParameters['q'], 'hospitals in 43235');
      expect(find.byType(ActionChip), findsOneWidget);
    },
  );

  testWidgets('GPS is explicit, used in map link, and removable', (
    tester,
  ) async {
    final launches = <Uri>[];
    await mount(
      tester,
      KorlixLocatorScreen(
        locate: () async => const LocatorPosition(40, -74, accuracy: 25),
        openMap: (uri) async {
          launches.add(uri);
          return true;
        },
      ),
    );
    await tap(tester, 'Use my location');
    expect(find.textContaining('reported accuracy 25 m'), findsOneWidget);
    await tap(tester, 'Find hospitals');
    expect(
      launches.single.queryParameters['query'],
      contains('40.000000,-74.000000'),
    );
    await tap(tester, 'Let maps choose the area');
    await tap(tester, 'Find hospitals');
    expect(launches.last.queryParameters['query'], 'hospitals');
  });

  testWidgets(
    'permission failure preserves manual search and never opens maps automatically',
    (tester) async {
      final launches = <Uri>[];
      await mount(
        tester,
        KorlixLocatorScreen(
          locate: () async =>
              throw const FormatException('Location access was not granted.'),
          openMap: (uri) async {
            launches.add(uri);
            return true;
          },
        ),
      );
      await area(tester, 'Kingston, Jamaica');
      await tap(tester, 'Use my location');
      expect(find.text('Location access was not granted.'), findsOneWidget);
      expect(launches, isEmpty);
      await tap(tester, 'Find hospitals');
      expect(
        launches.single.queryParameters['query'],
        'hospitals in Kingston, Jamaica',
      );
    },
  );

  testWidgets('typing an area invalidates a pending device-location request', (
    tester,
  ) async {
    final pending = Completer<LocatorPosition>();
    Uri? launched;
    await mount(
      tester,
      KorlixLocatorScreen(
        locate: () => pending.future,
        openMap: (uri) async {
          launched = uri;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Use my location'));
    await tester.pump();
    await area(tester, 'London');
    pending.complete(const LocatorPosition(40, -74));
    await tester.pumpAndSettle();
    expect(find.textContaining('Device location ready'), findsNothing);
    await tap(tester, 'Find hospitals');
    expect(launched!.queryParameters['query'], 'hospitals in London');
  });

  testWidgets(
    'failed launch offers retry, adds no history, and keeps the search',
    (tester) async {
      var attempts = 0;
      await mount(
        tester,
        KorlixLocatorScreen(openMap: (_) async => ++attempts > 1),
      );
      await tap(tester, 'Find hospitals');
      expect(find.textContaining('Maps did not open'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('locator-query')))
            .controller!
            .text,
        'hospitals',
      );
      await tap(tester, 'Search in Google Maps');
      expect(find.byType(ActionChip), findsOneWidget);
      expect(attempts, 2);
    },
  );

  testWidgets('opening maps cannot be duplicated by repeated taps', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var attempts = 0;
    await mount(
      tester,
      KorlixLocatorScreen(
        openMap: (_) {
          attempts++;
          return pending.future;
        },
      ),
    );
    await tester.tap(find.text('Find hospitals'));
    await tester.pump();
    await tester.tap(find.text('Find hospitals'));
    await tester.pump();
    expect(attempts, 1);
    pending.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('account change discards searches and ignores late location', (
    tester,
  ) async {
    final revision = ValueNotifier(0), pending = Completer<LocatorPosition>();
    var valid = true, opened = false;
    await mount(
      tester,
      KorlixLocatorScreen(
        sessionChanges: revision,
        isSessionCurrent: () => valid,
        locate: () => pending.future,
        openMap: (_) async {
          opened = true;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Use my location'));
    await tester.pump();
    valid = false;
    revision.value++;
    await tester.pumpAndSettle();
    pending.complete(const LocatorPosition(40, -74));
    await tester.pumpAndSettle();
    expect(find.byType(KorlixLocatorScreen), findsNothing);
    expect(opened, isFalse);
    expect(tester.takeException(), isNull);
    revision.dispose();
  });

  testWidgets(
    'Locator fits light and dark phones, desktops and 200 percent text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final output = Platform.environment['KORLIX_LOCATOR_REVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
          for (final font in [
            (
              'MaterialIcons',
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ),
            ('Roboto', 'assets/fieldproof/Roboto-Regular.ttf'),
          ]) {
            await (FontLoader(font.$1)..addFont(
                  File(
                    font.$2,
                  ).readAsBytes().then((b) => ByteData.sublistView(b)),
                ))
                .load();
          }
        });
      }
      for (final theme in ['korlix_blue', 'pure_white', 'pure_black']) {
        for (final view in [(390.0, 1.0), (320.0, 2.0), (1100.0, 1.0)]) {
          tester.view.physicalSize = Size(view.$1, 1100);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: korlixBuildTheme(theme),
              home: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(view.$2),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: KorlixLocatorScreen(openMap: (_) async => true),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$theme $view');
          for (final section in ['top', 'Health & help', 'Out & about']) {
            if (section != 'top') {
              await tester.ensureVisible(find.text(section));
              await tester.pumpAndSettle();
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$section $theme $view',
            );
            if (output != null && view.$2 == 1) {
              await tester.runAsync(() async {
                final img =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage(pixelRatio: 1.5);
                final bytes = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  '$output/$theme-${view.$1.toInt()}-${section == 'top'
                      ? 'top'
                      : section == 'Health & help'
                      ? 'care'
                      : 'explore'}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
                img.dispose();
              });
            }
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
