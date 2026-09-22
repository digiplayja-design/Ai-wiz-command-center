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
import 'package:ai_wiz_command_center/funnel_studio/funnel_rehearsal.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_templates.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

Map<String, dynamic> funnel() => {
  'id': 'test-funnel',
  'name': 'Our next conversation',
  'slug': 'conversation',
  'state': 'draft',
  'version': 4,
  'draft': {...funnelTemplate('consultation'), 'brand': 'KORLIX AI'},
};
Map<String, dynamic> report() => {
  'kind': 'simulation',
  'saved_version': 4,
  'workflow_version': 2,
  'sample': {'name': 'Taylor Morgan'},
  'accepted_in_scenario': true,
  'checks': [
    {
      'id': 'availability',
      'title': 'Draft publication scenario',
      'status': 'scenario',
      'detail':
          'Shows what would happen if you published the current editor draft.',
    },
    {
      'id': 'page',
      'title': 'Page content and required details',
      'status': 'pass',
    },
    {'id': 'inquiry', 'title': 'Sample inquiry validation', 'status': 'pass'},
  ],
  'receipt': {
    'message': 'Thank you. Our team will review your inquiry.',
    'booking_url': 'https://example.com/book',
  },
  'workflow_note':
      '2 review tasks would become due after 60 minutes. This is task timing, not a send time.',
  'tasks': [
    {
      'channel': 'email',
      'subject': 'Your inquiry at KORLIX AI',
      'body':
          'Hi Taylor Morgan,\n\nThank you for contacting KORLIX AI. What would be a good next step for you?',
    },
    {'channel': 'call_review'},
  ],
  'performed_actions': [],
  'delivery_tested': false,
  'limits':
      'Simulation only. No inquiry, contact, task, email, call or ad is created. Live form cookies, rate limits, existing contact permissions, provider readiness and delivery still need separate verification. New inquiries are not automatically enrolled in a sequence.',
};
http.Response response(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root == null) return;
    for (final e in {
      'MaterialIcons': 'MaterialIcons-Regular.otf',
      'Roboto': 'Roboto-Regular.ttf',
    }.entries) {
      await (FontLoader(e.key)..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/${e.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<void> mount(
    WidgetTester t,
    Future<http.Response> Function(http.Request) handler, {
    double width = 1440,
    double scale = 1,
    bool studio = false,
  }) async {
    await t.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final client = FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {'Authorization': 'session'},
      client: MockClient(handler),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: WfStyle.theme,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: studio
              ? FunnelScreen(client: client)
              : Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: FunnelRehearsal(
                      client: client,
                      funnel: funnel(),
                      document: {
                        ...funnel()['draft'] as Map<String, dynamic>,
                        'brand': 'Unsaved brand',
                      },
                      name: 'Unsaved name',
                      dirty: true,
                    ),
                  ),
                ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> run(WidgetTester t) async {
    await t.ensureVisible(find.byKey(const ValueKey('rehearsal-run')));
    await t.tap(find.byKey(const ValueKey('rehearsal-run')));
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, String key, String choice) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
    await t.tap(find.text(choice).last);
    await t.pumpAndSettle();
  }

  testWidgets(
    'Draft rehearses unsaved content, published excludes it, changes clear old results; access loss hides results',
    (t) async {
      final calls = <http.Request>[];
      var status = 200;
      await mount(t, (r) async {
        calls.add(r);
        return status == 200
            ? response(report())
            : response({'error': 'Access changed'}, status);
      });
      expect(calls, isEmpty);
      await run(t);
      expect(calls.single.url.path, '/api/funnels/test-funnel/rehearsal');
      expect(calls.single.method, 'POST');
      expect(calls.single.headers['Authorization'], 'session');
      final body = jsonDecode(calls.single.body);
      expect(body['document']['brand'], 'Unsaved brand');
      expect(body['name'], 'Unsaved name');
      expect(body['version'], 4);
      expect(find.text('Inquiry path preview'), findsOneWidget);
      await choose(t, 'rehearsal-source', 'Published page');
      expect(find.text('Inquiry path preview'), findsNothing);
      await run(t);
      final published = jsonDecode(calls.last.body);
      expect(published.containsKey('document'), false);
      expect(published.containsKey('name'), false);
      expect(published['source'], 'published');
      await choose(t, 'rehearsal-scenario', 'Response consent missing');
      expect(find.text('Inquiry path preview'), findsNothing);
      await run(t);
      expect(jsonDecode(calls.last.body)['scenario'], 'missing_consent');
      status = 409;
      await run(t);
      expect(find.text('Inquiry path preview'), findsNothing);
      expect(find.text('Access changed'), findsOneWidget);
      status = 403;
      await run(t);
      expect(
        find.text('Sign in with an Enterprise account to run rehearsal.'),
        findsOneWidget,
      );
      expect(find.text('Your inquiry at KORLIX AI'), findsNothing);
    },
  );
  testWidgets('Missing backend contract cannot show a successful simulation', (
    t,
  ) async {
    await mount(t, (_) async => response({'ok': true}));
    await run(t);
    expect(find.textContaining('could not load the result'), findsOneWidget);
    expect(find.text('Inquiry path preview'), findsNothing);
  });
  testWidgets(
    'Leaving while a rehearsal is pending cannot restore its result',
    (t) async {
      final pending = Completer<http.Response>();
      await mount(t, (_) => pending.future);
      await t.tap(find.byKey(const ValueKey('rehearsal-run')));
      await t.pump();
      await t.pumpWidget(const MaterialApp(home: Text('Another screen')));
      pending.complete(response(report()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Inquiry path preview'), findsNothing);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('Rehearsal controls and report fit $width', (t) async {
      await mount(
        t,
        (_) async => response(report()),
        width: width,
        scale: width == 320 ? 1.3 : 1,
      );
      expect(t.takeException(), isNull);
      await run(t);
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
            '/tmp/k147-rehearsal-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.ensureVisible(find.text('Call review task'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await choose(t, 'rehearsal-scenario', 'Response consent missing');
      expect(t.takeException(), isNull);
    });
  }
  for (final width in [1440.0, 390.0]) {
    testWidgets(
      'Checklist links reveal and focus the actual field at $width without saving or publishing',
      (t) async {
        final calls = <http.Request>[];
        await mount(
          t,
          (r) async {
            calls.add(r);
            return response({
              'funnels': [funnel()],
              'ai_ready': false,
            });
          },
          width: width,
          studio: true,
        );
        await t.ensureVisible(find.text('Open studio'));
        await t.tap(find.text('Open studio'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Edit privacy URL'));
        await t.tap(find.text('Edit privacy URL'));
        await t.pumpAndSettle();
        final privacy = find.byKey(const ValueKey('1:privacy_url'));
        expect(
          t
              .widget<EditableText>(
                find.descendant(
                  of: privacy,
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          true,
        );
        expect(t.getRect(privacy).top, greaterThanOrEqualTo(0));
        expect(t.getRect(privacy).bottom, lessThanOrEqualTo(1000));
        await t.ensureVisible(find.text('Leads'));
        await t.tap(find.text('Leads'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Edit contact email'));
        await t.tap(find.text('Edit contact email'));
        await t.pumpAndSettle();
        expect(
          t
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const ValueKey('1:contact_email')),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          true,
        );
        expect(calls.every((r) => r.method == 'GET'), true);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Run rehearsal'));
        await t.tap(find.text('Run rehearsal'));
        await t.pumpAndSettle();
        expect(find.text('Rehearse the next conversation'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
