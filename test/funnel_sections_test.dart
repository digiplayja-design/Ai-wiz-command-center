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
import 'package:ai_wiz_command_center/funnel_studio/funnel_sections.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_templates.dart';
import 'funnel_studio_test.dart' show fixture;

http.Response reply(Map data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Finder keyed(String key) => find.byKey(ValueKey(key));
Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String key, String value) async {
  await t.ensureVisible(keyed(key));
  await t.enterText(keyed(key), value);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final e in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(e.key)..addFont(
              File(
                '$root/bin/cache/artifacts/material_fonts/${e.value}',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  Future<void> mount(
    WidgetTester t,
    Future<http.Response> Function(http.Request) handler, {
    double width = 1440,
  }) async {
    await t.binding.setSurfaceSize(Size(width, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
            child: child!,
          ),
          home: FunnelScreen(
            client: FunnelClient(
              backendBaseUrl: 'https://example.com',
              headersBuilder: () => {},
              client: MockClient(handler),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, find.text('Open studio'));
  }

  Future<void> screenshot(WidgetTester t, String name) async {
    if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] != '1') return;
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(keyed('capture'))
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/k152-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  test(
    'Legacy defaults, duplication and generated copy preserve independent section data',
    () {
      final current = funnelTemplate('consultation');
      current.remove('sections');
      expect(funnelSections(current).map(funnelSectionKey), [
        'main_image',
        'benefits',
        'inquiry',
        'faq',
      ]);
      current['sections'] = [
        ...defaultFunnelSections().reversed,
        {
          'kind': 'text',
          'id': 'text-1',
          'visible': true,
          'heading': 'Our approach',
          'body': 'A considered first conversation.',
        },
      ];
      final generated = generatedCopy(current, funnelTemplate('event'));
      expect(generated['sections'], current['sections']);
      generated['sections'][0]['visible'] = false;
      expect(current['sections'][0]['visible'], true);
      final clone = copyFunnel(current);
      clone['sections'].last['heading'] = 'Changed';
      expect(current['sections'].last['heading'], 'Our approach');
    },
  );
  testWidgets(
    'Reorder and visibility update preview and save only a draft; reload discards later edits',
    (t) async {
      var f = fixture();
      final calls = <http.Request>[];
      await mount(t, (r) async {
        calls.add(r);
        if (r.method == 'PUT') {
          final b = jsonDecode(r.body);
          f = {...f, 'draft': b['document'], 'version': 2};
          return reply({'funnel': f});
        }
        return reply({
          'funnels': [f],
        });
      });
      final originalBenefits = List.from(f['draft']['benefits']);
      await tap(t, find.text('Page sections'));
      await tap(t, keyed('section-up-inquiry'));
      await tap(t, keyed('section-visible-benefits'));
      expect(keyed('page-preview-benefits'), findsNothing);
      expect(keyed('page-preview-inquiry'), findsOneWidget);
      expect(keyed('section-visible-inquiry'), findsNothing);
      expect(keyed('section-remove-inquiry'), findsNothing);
      await tap(t, find.text('Save draft'));
      expect(funnelSections(f['draft']).map(funnelSectionKey), [
        'main_image',
        'inquiry',
        'benefits',
        'faq',
      ]);
      expect(f['draft']['sections'][2]['visible'], false);
      expect(f['draft']['benefits'], originalBenefits);
      expect(calls.where((r) => r.method != 'GET').map((r) => r.method), [
        'PUT',
      ]);
      await tap(t, find.text('Page sections'));
      await tap(t, keyed('section-visible-benefits'));
      await tap(t, keyed('section-up-inquiry'));
      expect(keyed('page-preview-benefits'), findsOneWidget);
      await tap(t, find.text('Reload saved'));
      await tap(t, find.text('Discard edits'));
      expect(keyed('page-preview-benefits'), findsNothing);
      expect(calls.where((r) => r.method != 'GET'), hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Text identity survives reorder; maximum and removal preserve remaining sections',
    (t) async {
      var d = funnelTemplate('consultation');
      await t.binding.setSurfaceSize(const Size(600, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (c, set) => FunnelSectionEditor(
                  document: d,
                  onChanged: (s) => set(() => d = {...d, 'sections': s}),
                ),
              ),
            ),
          ),
        ),
      );
      await tap(t, find.text('Page sections'));
      for (var n = 1; n <= 4; n++) {
        await tap(t, find.text('Add text section (${n - 1}/4)'));
        await enter(t, 'section-heading-text-$n', 'Heading $n');
        await enter(t, 'section-copy-text-$n', 'Copy $n\nSecond line.');
      }
      final add = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Add text section (4/4)'),
      );
      expect(add.onPressed, isNull);
      await tap(t, keyed('section-up-text-4'));
      await enter(t, 'section-copy-text-4', 'Moved text');
      final sections = funnelSections(d);
      expect(sections.where((s) => s['kind'] == 'text').map(funnelSectionKey), [
        'text-1',
        'text-2',
        'text-4',
        'text-3',
      ]);
      expect(
        sections.firstWhere((s) => s['id'] == 'text-4')['body'],
        'Moved text',
      );
      expect(
        sections.firstWhere((s) => s['id'] == 'text-3')['body'],
        'Copy 3\nSecond line.',
      );
      final field = t.widget<TextFormField>(keyed('section-heading-text-4'));
      expect(field.initialValue, 'Heading 4');
      await tap(t, keyed('section-remove-text-2'));
      await tap(t, find.text('Add text section (3/4)'));
      expect(
        t.widget<TextFormField>(keyed('section-heading-text-2')).initialValue,
        '',
      );
      expect(
        funnelSections(d).firstWhere((s) => s['id'] == 'text-4')['body'],
        'Moved text',
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'Section editor and matching preview fit $width with text and guided form',
      (t) async {
        var f = fixture();
        f['draft']['form_mode'] = 'guided';
        f['draft']['sections'] = [
          {
            'kind': 'text',
            'id': 'text-1',
            'visible': true,
            'heading': 'A thoughtful first conversation',
            'body':
                'Tell us what matters to your team.\nTogether, we can explore a practical next step.',
          },
          ...defaultFunnelSections(),
        ];
        await mount(
          t,
          (r) async => reply({
            'funnels': [f],
          }),
          width: width,
        );
        await tap(t, find.text('Page sections'));
        await t.ensureVisible(keyed('section-heading-text-1'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await screenshot(t, 'editor-${width.toInt()}');
        await tap(t, find.text('Preview').first);
        await t.ensureVisible(keyed('page-preview-text-1'));
        await t.pumpAndSettle();
        expect(
          find.descendant(
            of: keyed('page-preview-text-1'),
            matching: find.text('A thoughtful first conversation'),
          ),
          findsOneWidget,
        );
        expect(keyed('page-preview-inquiry'), findsOneWidget);
        expect(
          t.getTopLeft(keyed('page-preview-text-1')).dy,
          lessThan(t.getTopLeft(keyed('page-preview-inquiry')).dy),
        );
        expect(t.takeException(), isNull);
        await screenshot(t, 'preview-${width.toInt()}');
      },
    );
  }
}
