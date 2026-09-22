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
import 'package:ai_wiz_command_center/workforce/workforce_screen.dart';
import 'package:ai_wiz_command_center/workforce/workforce_forms.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';

const owner = '00000000-0000-4000-8000-000000000001',
    employee = '00000000-0000-4000-8000-000000000002',
    org = '00000000-0000-4000-8000-000000000003';
const pol = {
  'require_selfie': true,
  'require_location': true,
  'hourly_updates': true,
  'interval_minutes': 60,
  'grace_minutes': 10,
  'retention_days': 30,
  'worksite': 'Brooklyn Studio',
  'latitude': null,
  'longitude': null,
  'radius_m': 200,
  'daily_goal': 10,
  'output_unit': 'tasks',
};
WfJson sample({bool worker = false}) {
  final members = [
    {
      'user_id': owner,
      'display_name': 'Ricardo Bailey',
      'role': 'owner',
      'email': 'owner@example.com',
      'team': 'Leadership',
      'active': true,
      'version': 1,
    },
    {
      'user_id': employee,
      'display_name': 'Amara Johnson',
      'role': 'employee',
      'email': 'amara@example.com',
      'team': 'Customer Success',
      'active': true,
      'version': 1,
    },
    {
      'user_id': 'third',
      'display_name': 'Daniel Kim',
      'role': 'employee',
      'email': 'daniel@example.com',
      'team': 'Operations',
      'active': true,
      'version': 1,
    },
    {
      'user_id': 'fourth',
      'display_name': 'Sofia Martinez',
      'role': 'manager',
      'email': 'sofia@example.com',
      'team': 'Digital Campaigns',
      'active': true,
      'version': 1,
    },
  ];
  final shifts = [
    {
      'id': 's1',
      'user_id': employee,
      'clock_in': '2026-09-21T13:00:00Z',
      'state': 'working',
      'worked_seconds': 16380,
      'break_seconds': 1200,
      'version': 3,
      'policy_snapshot': pol,
      'review_status': 'pending',
      'update_due': true,
    },
    {
      'id': 's2',
      'user_id': 'third',
      'clock_in': '2026-09-21T14:00:00Z',
      'state': 'break',
      'worked_seconds': 12600,
      'break_seconds': 600,
      'version': 2,
      'policy_snapshot': pol,
      'review_status': 'pending',
      'update_due': false,
    },
    {
      'id': 's3',
      'user_id': 'fourth',
      'clock_in': '2026-09-21T13:15:00Z',
      'state': 'working',
      'worked_seconds': 15300,
      'break_seconds': 1800,
      'version': 3,
      'policy_snapshot': pol,
      'review_status': 'pending',
      'update_due': false,
    },
  ];
  final updates = [
    {
      'id': 'u1',
      'user_id': employee,
      'shift_id': 's1',
      'summary':
          'Resolved five customer requests and completed the onboarding guide for our new enterprise client.',
      'quantity': 5,
      'output_unit': 'tasks',
      'project': 'Enterprise onboarding',
      'blockers': 'Waiting for the final campaign assets.',
      'created_at': '2026-09-21T16:00:00Z',
      'worked_seconds_at_submit': 10500,
    },
    {
      'id': 'u2',
      'user_id': 'fourth',
      'shift_id': 's3',
      'summary':
          'Published the September campaign and reviewed the weekly performance report.',
      'quantity': 3,
      'output_unit': 'tasks',
      'project': 'September campaign',
      'blockers': '',
      'created_at': '2026-09-21T17:00:00Z',
      'worked_seconds_at_submit': 14500,
    },
  ];
  final uid = worker ? employee : owner;
  return {
    'organization': {
      'id': org,
      'name': 'KORLIX Studio',
      'timezone': 'America/New_York',
      'policy': pol,
      'version': 1,
    },
    'member': members.firstWhere((m) => m['user_id'] == uid),
    'policy': pol,
    'active_plan': true,
    'from': '2026-09-21',
    'to': '2026-09-21',
    'server_now': '2026-09-21T18:00:00Z',
    'members': worker
        ? members.where((m) => m['user_id'] == uid).toList()
        : members,
    'shifts': worker
        ? shifts.where((s) => s['user_id'] == uid).toList()
        : shifts,
    'report_shifts': worker
        ? shifts.where((s) => s['user_id'] == uid).toList()
        : shifts,
    'updates': worker
        ? updates.where((u) => u['user_id'] == uid).toList()
        : updates,
    'period_updates': worker
        ? updates.where((u) => u['user_id'] == uid).toList()
        : updates,
    'corrections': [],
    'schedule': [
      {
        'id': 'schedule',
        'user_id': employee,
        'starts_at': '2026-09-22T13:00:00Z',
        'ends_at': '2026-09-22T21:00:00Z',
        'worksite': 'Brooklyn Studio',
        'notes': 'Enterprise client onboarding',
        'version': 1,
      },
    ],
    'events': [
      {
        'id': 'e1',
        'user_id': employee,
        'shift_id': 's1',
        'action': 'clock_in',
        'recorded_at': '2026-09-21T13:00:00Z',
        'flags': [],
        'has_photo': false,
        'location': {'latitude': 40.69, 'longitude': -73.99, 'accuracy': 12},
      },
    ],
    'invites': [],
    'metrics': {
      'working': 2,
      'on_break': 1,
      'updates_due': 1,
      'output': {'tasks': 8},
      'worked_seconds': 44280,
    },
    'email_agent_id': null,
  };
}

WorkforceClient client(
  WfJson data, {
  Future<http.Response> Function(http.Request)? handler,
}) => WorkforceClient(
  backendBaseUrl: 'https://example.test',
  headersBuilder: () => {'Authorization': 'Bearer verified'},
  client: MockClient(
    handler ??
        (r) async => http.Response(
          jsonEncode(
            r.url.path.endsWith('/workspaces')
                ? {
                    'can_create': data['member']['role'] == 'owner',
                    'workspaces': [
                      {'id': org, 'name': 'KORLIX Studio'},
                    ],
                  }
                : data,
          ),
          200,
        ),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final flutterRoot = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (flutterRoot == null) return;
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
    final font =
        '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';
    if (File(font).existsSync()) {
      final loader = FontLoader(
        'Roboto',
      )..addFont(File(font).readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  test(
    'Client refuses invalid upstream data, reports 401 and keeps role errors scoped',
    () async {
      var signedOut = false;
      final c = WorkforceClient(
        backendBaseUrl: 'https://example.test/',
        headersBuilder: () => {'Authorization': 'Bearer x'},
        client: MockClient((r) async {
          expect(r.url.path, '/api/workforce/workspaces');
          expect(r.headers['Authorization'], 'Bearer x');
          return http.Response('{"error":"Sign in"}', 401);
        }),
      );
      c.onSignedOut = () => signedOut = true;
      await expectLater(
        c.request('GET', '/workspaces'),
        throwsA(isA<WorkforceException>()),
      );
      expect(signedOut, true);
      final bad = WorkforceClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient((_) async => http.Response('bad', 200)),
      );
      await expectLater(
        bad.request('GET', '/workspaces'),
        throwsA(isA<WorkforceException>()),
      );
      expect(wfDuration(3671), '01:01:11');
      expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(wfId()), true);
    },
  );
  for (final size in [
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 1100),
  ]) {
    for (final worker in [false, true]) {
      testWidgets(
        '${worker ? 'employee' : 'employer'} responsive ${size.width}',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          await t.pumpWidget(
            MaterialApp(
              home: RepaintBoundary(
                key: boundary,
                child: WorkforceScreen(client: client(sample(worker: worker))),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.runAsync(() async {
            await precacheImage(
              const AssetImage('assets/meeting_copilot/korlix_logo.jpeg'),
              boundary.currentContext!,
            );
          });
          await t.pump();
          expect(
            find.text(worker ? 'Make today count.' : 'Your team, in rhythm.'),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          if (worker) {
            expect(find.text('Clock out'), findsOneWidget);
            expect(find.text('Invite employee'), findsNothing);
          } else {
            expect(find.text('Invite employee'), findsOneWidget);
          }
          if (Platform.environment['KORLIX_WORKFORCE_SCREENSHOTS'] == '1' &&
              (size.width == 1440 && !worker || size.width == 390 && worker)) {
            await t.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory(
                Platform.environment['KORLIX_SCREENSHOT_DIR'] ??
                    'build/workforce-previews',
              )..createSync(recursive: true);
              File(
                '${dir.path}/KORLIX_Workforce_${worker ? 'Employee' : 'Employer'}_Preview.png',
              ).writeAsBytesSync(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets('Every employer view renders and forms retain server errors', (
    t,
  ) async {
    t.view.physicalSize = const Size(1440, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(home: WorkforceScreen(client: client(sample()))),
    );
    await t.pumpAndSettle();
    for (final label in [
      'My day',
      'Work log',
      'Timesheets',
      'Schedule',
      'Policies',
    ]) {
      await t.tap(find.text(label).first);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpWidget(
      MaterialApp(
        theme: WfStyle.theme,
        home: Scaffold(
          body: WorkforceForm(
            title: 'Update',
            description: 'Test',
            fields: const [WfField('summary', 'Summary')],
            submit: (_) async =>
                throw const WorkforceException('Network unavailable'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Completed work');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Network unavailable'), findsOneWidget);
    expect(find.text('Completed work'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Clock-out allows a missing-evidence exception and does not invent a photo',
    (t) async {
      t.view.physicalSize = const Size(768, 1024);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      WfJson? saved;
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: Scaffold(
            body: WorkforcePunchDialog(
              clockOut: true,
              policy: pol,
              submit: (p) async {
                saved = p;
              },
            ),
          ),
        ),
      );
      await t.tap(find.text('Confirm clock-out'));
      await t.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['selfie'], isNull);
      expect(saved!['location'], isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Session expiry clears attendance and employee names', (t) async {
    var expired = false;
    final data = sample();
    final c = client(
      data,
      handler: (r) async => expired
          ? http.Response('{"error":"Session expired"}', 401)
          : http.Response(
              jsonEncode(
                r.url.path.endsWith('/workspaces')
                    ? {
                        'can_create': true,
                        'workspaces': [
                          {'id': org, 'name': 'KORLIX Studio'},
                        ],
                      }
                    : data,
              ),
              200,
            ),
    );
    await t.pumpWidget(MaterialApp(home: WorkforceScreen(client: c)));
    await t.pumpAndSettle();
    expect(find.text('Amara Johnson'), findsOneWidget);
    expired = true;
    await t.pump(const Duration(seconds: 31));
    await t.pumpAndSettle();
    expect(find.text('Amara Johnson'), findsNothing);
    expect(find.textContaining('session expired'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
