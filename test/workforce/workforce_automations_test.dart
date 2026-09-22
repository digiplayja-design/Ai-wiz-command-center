import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/workforce/workforce_client.dart';
import 'package:ai_wiz_command_center/workforce/workforce_automations.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const org = '00000000-0000-4000-8000-000000000001',
    recipient = '00000000-0000-4000-8000-000000000002';
WfJson rule({String channel = 'email', bool enabled = false}) => {
  'id': '00000000-0000-4000-8000-000000000003',
  'name': 'Work update reminders',
  'kind': 'missed_update',
  'channel': channel,
  'enabled': enabled,
  'version': 1,
  'recipient_id': recipient,
  'member_id': null,
  'local_time': '08:00:00',
  'delay_minutes': 10,
  'days': [1, 2, 3, 4, 5],
  'daily_limit': 5,
};

Future<void> mount(
  WidgetTester tester, {
  required List<WfJson> rules,
  List<WfJson> jobs = const [],
  List<WfJson>? calls,
  double width = 1200,
  bool ready = true,
  GlobalKey? capture,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = WorkforceClient(
    backendBaseUrl: 'https://example.invalid',
    headersBuilder: () => {},
    client: MockClient((request) async {
      if (request.method == 'POST') {
        final body = Map<String, dynamic>.from(jsonDecode(request.body));
        calls?.add({'path': request.url.path, ...body});
        if (request.url.path.endsWith('/toggle')) {
          rules.first['enabled'] = body['enabled'];
          rules.first['version'] = 2;
        } else if (request.url.path.endsWith('/automations')) {
          rules.add({...body, 'enabled': false, 'version': 1});
        } else if (request.url.path.endsWith('/review')) {
          jobs.first['status'] = 'reviewed';
        }
        return http.Response('{}', 200);
      }
      if (request.url.path.endsWith('/email-recipients')) {
        return http.Response(
          jsonEncode({
            'recipients': [
              {
                'id': recipient,
                'email': 'employer@example.com',
                'displayName': 'Employer',
                'active': true,
                'consentStatus': 'transactional_only',
              },
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'rules': rules,
          'jobs': jobs,
          'active_plan': true,
          'email_ready': ready,
          'outbound_calling_enabled': false,
        }),
        200,
      );
    }),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: WfStyle.theme,
      home: Scaffold(
        body: RepaintBoundary(
          key: capture,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: WorkforceAutomations(
              client: client,
              orgId: org,
              members: const [],
              timezone: 'America/New_York',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root == null) return;
    for (final entry in {
      'MaterialIcons': 'MaterialIcons-Regular.otf',
      'Roboto': 'Roboto-Regular.ttf',
    }.entries) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/${entry.value}',
      );
      if (file.existsSync()) {
        await (FontLoader(
              entry.key,
            )..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b))))
            .load();
      }
    }
  });
  testWidgets(
    'Enable is explicit and shows recipient, timing, weekdays and scope',
    (tester) async {
      final calls = <WfJson>[];
      await mount(tester, rules: [rule()], calls: calls);
      await click(tester, find.text('Review & enable'));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('To: Employer <employer@example.com>'),
        ),
        findsOneWidget,
      );
      expect(find.text('Days: Mon · Tue · Wed · Thu · Fri'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Enable automation');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(calls, isEmpty);
      await click(tester, find.byType(CheckboxListTile));
      await click(tester, button);
      expect(calls.single['confirmed'], true);
      expect(calls.single['enabled'], true);
      expect(calls.single['rule_id'], rule()['id']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Unavailable email cannot enable a rule; pausing remains available',
    (tester) async {
      final calls = <WfJson>[];
      await mount(tester, rules: [rule()], calls: calls, ready: false);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Review & enable'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        rules: [rule(enabled: true)],
        calls: calls,
        ready: false,
      );
      await click(tester, find.widgetWithText(OutlinedButton, 'Pause'));
      expect(calls.single['enabled'], false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Phone layout and call reviews remain honest and do not invoke outbound calling',
    (tester) async {
      final calls = <WfJson>[];
      final jobs = <WfJson>[
        {
          'id': 'job-one',
          'subject': 'Scheduled shift check-in',
          'body': 'No clock-in recorded for a scheduled shift.',
          'status': 'review',
          'created_at': '2026-09-22T08:15:00Z',
          'result_code': 'review_required_no_call_placed',
        },
      ];
      await mount(
        tester,
        rules: [rule(channel: 'call_review', enabled: true)],
        jobs: jobs,
        calls: calls,
        width: 390,
      );
      expect(tester.takeException(), isNull);
      await click(tester, find.text('Mark reviewed'));
      expect(calls.single['path'], '/api/workforce/$org/automations/review');
      expect(calls.single['job_id'], 'job-one');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'New email recipe is saved paused, never enabled or sent by the form',
    (tester) async {
      final calls = <WfJson>[];
      await mount(tester, rules: [], calls: calls);
      await click(tester, find.widgetWithText(OutlinedButton, 'Set up').first);
      final recipientField = find.byType(DropdownButtonFormField<String>).at(1);
      await click(tester, recipientField);
      await click(tester, find.text('employer@example.com').last);
      await click(tester, find.text('Save paused'));
      expect(calls.length, 1);
      expect(calls.single['recipient_id'], recipient);
      expect(calls.single.containsKey('enabled'), false);
      expect(find.text('Review & enable'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Desktop automation overview renders for release review', (
    tester,
  ) async {
    final capture = GlobalKey();
    await mount(tester, rules: [], width: 1600, capture: capture);
    expect(tester.takeException(), isNull);
    if (Platform.environment['WORKFORCE_CAPTURE_DIR'] case final String path) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(path).createSync(recursive: true);
        File(
          '$path/workforce_automations.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
