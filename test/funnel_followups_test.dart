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
import 'package:ai_wiz_command_center/funnel_studio/funnel_followups.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

Map<String, dynamic> fixture() => {
  'settings': {
    'version': 1,
    'enabled': true,
    'email_enabled': true,
    'call_enabled': true,
    'delay_minutes': 0,
    'subject': 'Your inquiry at {{brand}}',
    'body': 'Hi {{name}},\n\nThank you for contacting {{brand}}.',
  },
  'page_state': 'published',
  'email_ready': true,
  'scheduling_ready': true,
  'outbound_calling_enabled': false,
  'total': 2,
  'offset': 0,
  'counts': {'open': 2, 'sent': 3, 'completed': 1},
  'tasks': [
    {
      'id': 'email-task',
      'version': 1,
      'channel': 'email',
      'state': 'review',
      'due_at': '2026-01-01T12:00:00Z',
      'lead_name': 'Taylor Morgan',
      'to_email': 'taylor@example.com',
      'email_allowed': true,
      'subject': 'Your inquiry at KORLIX AI',
      'body':
          'Hi Taylor,\n\nThank you for your interest. What would be a good next step for your team?\n\nKORLIX AI',
      'inquiry': 'We would like to discuss AI for our team.',
    },
    {
      'id': 'call-task',
      'version': 1,
      'channel': 'call_review',
      'state': 'review',
      'due_at': '2026-01-01T12:00:00Z',
      'lead_name': 'Jordan Lee',
      'phone': '+1 202 555 0134',
      'call_allowed': false,
      'inquiry': 'Please share more information.',
      'body': '',
      'subject': '',
    },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      for (final font in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(font.key)..addFont(
              File(
                '$root/bin/cache/artifacts/material_fonts/${font.value}',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  Future<void> render(
    WidgetTester t,
    Map<String, dynamic> data,
    List<http.Request> calls, {
    Size size = const Size(1440, 1100),
    GlobalKey? capture,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final client = FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {'Authorization': 'fresh-token'},
      client: MockClient((r) async {
        calls.add(r);
        expect(r.headers['Authorization'], 'fresh-token');
        if (r.method == 'POST' && r.url.path.endsWith('/send')) {
          data['tasks'][0]['state'] = 'sent';
          data['tasks'][0]['version'] = 2;
        }
        if (r.method == 'POST' && r.url.path.endsWith('/schedule')) {
          data['tasks'][0]['state'] = 'scheduled';
          data['tasks'][0]['version'] = 2;
          data['tasks'][0]['scheduled_for'] = jsonDecode(
            r.body,
          )['scheduled_for'];
        }
        if (r.method == 'POST' && r.url.path.endsWith('/cancelSchedule')) {
          data['tasks'][0]['state'] = 'review';
          data['tasks'][0]['version'] = 3;
        }
        if (r.method == 'POST' && r.url.path.endsWith('/settings')) {
          data['settings'] = jsonDecode(r.body);
        }
        return http.Response(
          jsonEncode(r.method == 'GET' ? data : {}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: WfStyle.theme,
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: FunnelFollowups(client: client, funnelId: 'funnel-id'),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final size in [const Size(1440, 1100), const Size(390, 844)]) {
    testWidgets(
      'Follow-up queue and exact-message approval fit ${size.width}',
      (t) async {
        final data = fixture(), calls = <http.Request>[], capture = GlobalKey();
        await render(t, data, calls, size: size, capture: capture);
        expect(t.takeException(), isNull);
        expect(find.text('Turn interest into a conversation.'), findsOneWidget);
        if (Platform.environment['KORLIX_FUNNEL_SCREENSHOTS'] == '1') {
          await t.runAsync(() async {
            final b =
                capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await b.toImage(pixelRatio: 1.5);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '/tmp/korlix-followups-${size.width.toInt()}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        final review = find.text('Review & send');
        await t.ensureVisible(review);
        await t.tap(review);
        await t.pumpAndSettle();
        expect(find.text('To: taylor@example.com'), findsOneWidget);
        final send = find.widgetWithText(FilledButton, 'Send email now');
        expect(t.widget<FilledButton>(send).onPressed, isNull);
        expect(calls.where((r) => r.method == 'POST'), isEmpty);
        await t.ensureVisible(find.byType(CheckboxListTile));
        await t.tap(find.byType(CheckboxListTile));
        await t.pumpAndSettle();
        await t.tap(send);
        await t.pumpAndSettle();
        final posts = calls.where((r) => r.url.path.endsWith('/send')).toList();
        expect(posts.length, 1);
        expect(jsonDecode(posts[0].body), {
          'task_id': 'email-task',
          'version': 1,
          'confirmed': true,
        });
        expect(t.takeException(), isNull);
        expect(find.text('PROVIDER ACCEPTED'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'Paused and suppressed tasks cannot send and pause requires explicit confirmation',
    (t) async {
      final d = fixture(), calls = <http.Request>[];
      d['tasks'][0]['email_allowed'] = false;
      await render(t, d, calls);
      final review = find.widgetWithText(FilledButton, 'Review & send');
      expect(t.widget<FilledButton>(review).onPressed, isNull);
      final pause = find.text('Pause workflow');
      await t.ensureVisible(pause);
      await t.tap(pause);
      await t.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      await t.tap(find.widgetWithText(FilledButton, 'Pause workflow').last);
      await t.pumpAndSettle();
      final post = calls.singleWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body)['enabled'], false);
      expect(jsonDecode(post.body)['confirmed'], true);
      expect(find.text('WORKFLOW PAUSED'), findsOneWidget);
    },
  );
  testWidgets(
    'Call completion says reviewed and makes no email or call request',
    (t) async {
      final d = fixture(), calls = <http.Request>[];
      await render(t, d, calls);
      final complete = find.text('Mark reviewed');
      await t.ensureVisible(complete);
      await t.tap(complete);
      await t.pumpAndSettle();
      expect(find.textContaining('does not place a call'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Mark reviewed'));
      await t.pumpAndSettle();
      final p = calls.singleWhere((r) => r.method == 'POST');
      expect(p.url.path, endsWith('/resolve'));
      expect(jsonDecode(p.body)['state'], 'done');
    },
  );
  for (final size in [const Size(1440, 1100), const Size(390, 844)]) {
    testWidgets(
      'Scheduled replies require approval and can be cancelled at ${size.width}',
      (t) async {
        final data = fixture(), calls = <http.Request>[];
        await render(t, data, calls, size: size);
        await t.ensureVisible(find.text('Schedule reply'));
        await t.tap(find.text('Schedule reply'));
        await t.pumpAndSettle();
        expect(find.text('Schedule with NOVA'), findsOneWidget);
        final approve = find.widgetWithText(FilledButton, 'Approve & schedule');
        expect(t.widget<FilledButton>(approve).onPressed, isNull);
        expect(calls.where((r) => r.method == 'POST'), isEmpty);
        await t.ensureVisible(find.byType(CheckboxListTile));
        await t.tap(find.byType(CheckboxListTile));
        await t.pumpAndSettle();
        await t.tap(approve);
        await t.pumpAndSettle();
        final post = calls.singleWhere((r) => r.method == 'POST');
        final body = jsonDecode(post.body);
        expect(post.url.path, endsWith('/schedule'));
        expect(body['confirmed'], true);
        expect(body['task_id'], 'email-task');
        expect(body['version'], 1);
        expect(DateTime.parse(body['scheduled_for']).isUtc, true);
        expect(
          DateTime.parse(body['scheduled_for']).isAfter(DateTime.now()),
          true,
        );
        expect(find.text('APPROVED · SCHEDULED'), findsOneWidget);
        await t.ensureVisible(find.text('Cancel scheduled reply'));
        await t.tap(find.text('Cancel scheduled reply'));
        await t.pumpAndSettle();
        expect(calls.where((r) => r.method == 'POST').length, 1);
        await t.tap(
          find.widgetWithText(FilledButton, 'Cancel scheduled reply'),
        );
        await t.pumpAndSettle();
        final cancel = calls.lastWhere((r) => r.method == 'POST');
        expect(cancel.url.path, endsWith('/cancelSchedule'));
        expect(jsonDecode(cancel.body)['version'], 2);
        expect(find.text('READY FOR REVIEW'), findsWidgets);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('NOVA Autopilot permission is required to schedule', (t) async {
    final data = fixture(), calls = <http.Request>[];
    data['scheduling_ready'] = false;
    await render(t, data, calls);
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Schedule reply'),
          )
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review & send'),
          )
          .onPressed,
      isNotNull,
    );
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
  });
}
