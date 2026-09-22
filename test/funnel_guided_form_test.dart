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
import 'package:ai_wiz_command_center/funnel_studio/funnel_library.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_form_preview.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

http.Response reply(Map data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root == null) return;
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
  });
  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label).last);
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> selectMode(WidgetTester t, String label) async {
    final dropdown = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Inquiry form',
    );
    await t.ensureVisible(dropdown);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester t,
    Future<http.Response> Function(http.Request) handler, {
    double width = 1440,
    double scale = 1,
  }) async {
    await t.binding.setSurfaceSize(Size(width, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: FunnelScreen(
          client: FunnelClient(
            backendBaseUrl: 'https://example.com',
            headersBuilder: () => {'Authorization': 'session'},
            client: MockClient(handler),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Open studio');
  }

  Map<String, dynamic> funnel({String? mode}) => {
    'id': 'funnel-one',
    'name': 'Our next conversation',
    'slug': 'conversation',
    'state': 'draft',
    'version': 1,
    'page_requests': 0,
    'lead_count': 0,
    'url': 'https://example.com/f/conversation',
    'draft': {
      ...funnelTemplate('consultation'),
      'brand': 'KORLIX AI',
      'form_mode': ?mode,
    }..removeWhere((k, v) => k == 'form_mode' && mode == null),
  };
  test(
    'New templates remain single page; generation and duplication preserve the chosen form mode',
    () {
      expect(funnelTemplate('event')['form_mode'], 'single');
      final current = {...funnelTemplate('product'), 'form_mode': 'guided'};
      expect(
        generatedCopy(current, funnelTemplate('event'))['form_mode'],
        'guided',
      );
      expect(
        generatedCopy({'brand': 'Legacy'}, current)['form_mode'],
        'single',
      );
      final copied = funnelCreatePayload('Copy', 'copy-page', current);
      expect(copied['document']['form_mode'], 'guided');
    },
  );
  testWidgets(
    'Legacy page defaults to single page; selecting guided saves a draft without publishing',
    (t) async {
      var f = funnel();
      final calls = <http.Request>[];
      await mount(t, (r) async {
        calls.add(r);
        if (r.method == 'PUT') {
          final b = jsonDecode(r.body);
          expect(b['document']['form_mode'], 'guided');
          expect(b['version'], 1);
          f = {...f, 'draft': b['document'], 'version': 2};
          return reply({'funnel': f});
        }
        return reply({
          'funnels': [f],
          'ai_ready': true,
        });
      });
      expect(find.text('Single page'), findsOneWidget);
      await selectMode(t, 'Guided · three steps');
      expect(find.byKey(const ValueKey('form-preview-step-0')), findsOneWidget);
      await tap(t, 'Save draft');
      expect(calls.where((r) => r.method == 'PUT'), hasLength(1));
      expect(calls.where((r) => r.url.path.endsWith('/publish')), isEmpty);
      expect(find.text('Guided · three steps'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save draft'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'Exploring preview steps makes no network requests or unsaved edits; switching form style resets the preview',
    (t) async {
      final calls = <http.Request>[];
      final f = funnel(mode: 'guided');
      await mount(t, (r) async {
        calls.add(r);
        return reply({
          'funnels': [f],
          'ai_ready': true,
        });
      });
      final before = calls.length;
      await t.ensureVisible(find.byKey(const ValueKey('form-preview-step-2')));
      await t.tap(find.byKey(const ValueKey('form-preview-step-2')));
      await t.pumpAndSettle();
      expect(find.text('Taylor Morgan'), findsOneWidget);
      expect(find.text('Sample details for preview'), findsOneWidget);
      expect(calls.length, before);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save draft'),
            )
            .onPressed,
        isNull,
      );
      await selectMode(t, 'Single page');
      expect(find.text('Taylor Morgan'), findsNothing);
      expect(find.byKey(const ValueKey('form-preview-step-0')), findsNothing);
      await selectMode(t, 'Guided · three steps');
      expect(
        t
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('form-preview-step-0')),
            )
            .selected,
        isTrue,
      );
      expect(find.text('Taylor Morgan'), findsNothing);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('Guided editor controls and all preview steps fit $width', (
      t,
    ) async {
      final f = funnel(mode: 'guided');
      await mount(
        t,
        (r) async => reply({
          'funnels': [f],
          'ai_ready': true,
        }),
        width: width,
        scale: width == 320 ? 1.3 : 1,
      );
      await selectMode(t, 'Single page');
      await selectMode(t, 'Guided · three steps');
      expect(t.takeException(), isNull);
      if (width < 900) await tap(t, 'Preview');
      for (var i = 0; i < 3; i++) {
        final chip = find.byKey(ValueKey('form-preview-step-$i'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    });
    testWidgets('Guided review preview remains readable at $width', (t) async {
      await t.binding.setSurfaceSize(Size(width > 600 ? 760 : width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: WfStyle.theme,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
              child: child!,
            ),
            home: const Scaffold(
              backgroundColor: Color(0xFFF5F7F7),
              body: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: FunnelFormPreview(
                  mode: 'guided',
                  brand: 'KORLIX AI',
                  cta: 'Let’s talk',
                  accent: WfStyle.cyan,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('form-preview-step-2')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
        await t.runAsync(() async {
          final image = await t
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              )
              .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/k150-guided-preview-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
