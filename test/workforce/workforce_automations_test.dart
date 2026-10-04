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
  double textScale = 1,
  int? updateError,
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
        } else if (request.url.path.endsWith('/automations/update')) {
          if (updateError != null) {
            return http.Response(
              jsonEncode({
                'error':
                    'This reminder changed. Close and reopen it before saving.',
              }),
              updateError,
            );
          }
          final index = rules.indexWhere((r) => r['id'] == body['id']);
          rules[index] = {
            ...body,
            'enabled': false,
            'version': (body['version'] as int) + 1,
          };
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
                'name': 'Employer',
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
          'workspace_email': {'ready': ready, 'reply_to': 'owner@example.com'},
          'outbound_calling_enabled': false,
        }),
        200,
      );
    }),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MaterialApp(
        theme: WfStyle.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
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
      final recipientField = find.byKey(const ValueKey('reminder-recipient'));
      await click(tester, recipientField);
      await click(tester, find.text('employer@example.com').last);
      await click(tester, find.text('Save paused'));
      expect(calls.length, 1);
      expect(calls.single['recipient_id'], recipient);
      expect(calls.single['channel'], 'workspace_email');
      expect(calls.single['delivery_mode'], 'review');
      expect(calls.single['send_start'], '08:00');
      expect(calls.single.containsKey('enabled'), false);
      expect(find.text('Review & enable'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Reminder instructions save on the existing rule and survive reopen',
    (tester) async {
      final calls = <WfJson>[];
      final rules = <WfJson>[
        {
          ...rule(channel: 'workspace_email'),
          'instructions': 'Original instructions',
          'delivery_mode': 'review',
          'send_start': '09:30:00',
          'send_end': '17:30:00',
        },
      ];
      final capture = GlobalKey();
      await mount(
        tester,
        rules: rules,
        calls: calls,
        width: 1100,
        capture: capture,
      );
      await click(tester, find.text('Edit reminder'));
      final instructions = find.byKey(const ValueKey('reminder-instructions'));
      expect(
        tester.widget<TextFormField>(instructions).controller!.text,
        'Original instructions',
      );
      expect(find.text('More options'), findsOneWidget);
      await tester.enterText(
        instructions,
        'Include completed jobs, quantities and any blockers.',
      );
      await click(tester, find.text('Email preview'));
      expect(
        find
            .textContaining(
              'Include completed jobs, quantities and any blockers.',
            )
            .evaluate()
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(calls, isEmpty);
      if (Platform.environment['WORKFORCE_CAPTURE_DIR']
          case final String path) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(path).createSync(recursive: true);
          File(
            '$path/workforce_reminder_editor.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await click(tester, find.text('Save changes'));
      expect(calls.length, 1);
      expect(calls.single['path'], '/api/workforce/$org/automations/update');
      expect(calls.single['id'], rule()['id']);
      expect(calls.single['version'], 1);
      expect(
        calls.single['instructions'],
        'Include completed jobs, quantities and any blockers.',
      );
      expect(calls.single['send_start'], '09:30');
      expect(calls.single['send_end'], '17:30');
      expect(rules.length, 1);
      expect(rules.single['enabled'], false);
      await click(tester, find.text('Edit reminder'));
      expect(
        tester.widget<TextFormField>(instructions).controller!.text,
        'Include completed jobs, quantities and any blockers.',
      );
      await click(tester, find.text('Cancel'));
      await click(tester, find.text('Review & enable'));
      expect(
        find.textContaining(
          'Include completed jobs, quantities and any blockers.',
        ),
        findsWidgets,
      );
      expect(calls.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'A rejected save keeps instructions in the editor at 320 pixels and large text',
    (tester) async {
      final calls = <WfJson>[];
      await mount(
        tester,
        rules: [
          {
            ...rule(channel: 'workspace_email'),
            'send_start': '08:00:00',
            'send_end': '18:00:00',
            'instructions': 'Old',
          },
        ],
        calls: calls,
        width: 320,
        textScale: 2,
        updateError: 409,
      );
      await click(tester, find.text('Edit reminder'));
      final instructions = find.byKey(const ValueKey('reminder-instructions'));
      await tester.enterText(instructions, 'Keep these unsaved instructions');
      await click(tester, find.text('Save changes'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester.widget<TextFormField>(instructions).controller!.text,
        'Keep these unsaved instructions',
      );
      expect(
        find.text('This reminder changed. Close and reopen it before saving.'),
        findsOneWidget,
      );
      expect(calls.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Recipient approval saves permission without enabling rules or sending',
    (tester) async {
      final calls = <WfJson>[];
      await mount(tester, rules: [], calls: calls, width: 390);
      await click(tester, find.text('Add email recipient'));
      final button = find.widgetWithText(FilledButton, 'Approve recipient');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextFormField).at(0), 'Supervisor');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'supervisor@example.com',
      );
      await click(tester, find.byType(CheckboxListTile));
      await click(tester, button);
      expect(
        calls.single['path'],
        '/api/workforce/$org/automations/email-recipients',
      );
      expect(calls.single['confirmed'], true);
      expect(calls.single['email'], 'supervisor@example.com');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Workforce draft review shows the recipient and exact body before approval',
    (tester) async {
      final calls = <WfJson>[];
      final directRule = {
        ...rule(channel: 'workspace_email', enabled: true),
        'delivery_mode': 'review',
        'send_start': '08:00:00',
        'send_end': '18:00:00',
      };
      await mount(
        tester,
        rules: [directRule],
        calls: calls,
        width: 390,
        jobs: [
          {
            'id': 'draft-one',
            'version': 3,
            'subject': 'Daily summary',
            'body': 'Two completed updates and one blocker.',
            'recipient_email': 'supervisor@example.com',
            'status': 'draft',
            'created_at': '2026-10-04T08:00:00Z',
            'expires_at': '2026-10-04T10:00:00Z',
          },
        ],
      );
      await click(tester, find.text('Review draft'));
      expect(find.text('To: supervisor@example.com').last, findsOneWidget);
      expect(
        find.text('Two completed updates and one blocker.').last,
        findsOneWidget,
      );
      expect(calls, isEmpty);
      await click(tester, find.text('Approve this email'));
      expect(calls.single['action'], 'approve');
      expect(calls.single['version'], 3);
      expect(calls.single['confirmed'], true);
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
