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
import 'package:ai_wiz_command_center/workforce/workforce_client.dart';
import 'package:ai_wiz_command_center/workforce/workforce_screen.dart';
import 'package:ai_wiz_command_center/workforce/workforce_forms.dart';
import 'package:ai_wiz_command_center/workforce/workforce_workspace.dart';
import 'package:ai_wiz_command_center/workforce/workforce_style.dart';
import 'package:ai_wiz_command_center/workforce/workforce_voice.dart';
import 'workforce_test.dart' as fixture;

const org = fixture.org, owner = fixture.owner, worker = fixture.employee;
WfJson task(
  String title, {
  String status = 'todo',
  String priority = 'normal',
}) => {
  'id': wfId(),
  'title': title,
  'status': status,
  'priority': priority,
  'assignee_id': worker,
  'project': 'West Wing',
  'worksite': 'Client site',
  'due_at': '2026-10-06T16:00:00Z',
  'details': 'Confirm the materials and prepare the work area.',
  'progress_note': '',
  'version': 1,
};
WfJson sample() {
  final data = fixture.sample();
  data['organization']['name'] = 'Brightside Field Services';
  data['organization']['business_profile'] = {
    'industry': 'field_service',
    'work_mode': 'hybrid',
    'description':
        'Local specialists, independent contractors and remote coordinators.',
  };
  data['tasks'] = [
    task('Inspect the installation', priority: 'high'),
    task('Confirm parts delivery', status: 'blocked', priority: 'urgent'),
    task('Prepare client handoff', status: 'done'),
  ];
  return data;
}

String token(String sub) =>
    'Bearer x.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': sub, 'session_id': 'fixture-session'}))).replaceAll('=', '')}.sig';
void main() {
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
        final loader = FontLoader(entry.key)
          ..addFont(file.readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    }
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('Work board filters and actions render at $width', (t) async {
      t.view.physicalSize = Size(width, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      WfJson? progress;
      await t.pumpWidget(
        MaterialApp(
          theme: WfStyle.theme,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: WorkforceTaskBoard(
                  tasks: wfRows(sample()['tasks']),
                  members: wfRows(sample()['members']),
                  userId: owner,
                  canManage: true,
                  canWrite: true,
                  onCreate: () {},
                  onEdit: (_) {},
                  onProgress: (v) => progress = v,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Confirm parts delivery'), findsOneWidget);
      expect(find.text('Prepare client handoff'), findsNothing);
      await t.ensureVisible(find.text('Update progress').first);
      await t.tap(find.text('Update progress').first);
      expect(progress?['title'], 'Confirm parts delivery');
      await t.enterText(find.byType(TextField), 'installation');
      await t.pumpAndSettle();
      expect(find.text('Inspect the installation'), findsOneWidget);
      expect(find.text('Confirm parts delivery'), findsNothing);
      expect(t.takeException(), isNull);
      await t.enterText(find.byType(TextField), '');
      await t.pumpAndSettle();
      if (Platform.environment['KORLIX_WORKFORCE_SCREENSHOTS'] == '1' &&
          width != 768) {
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('/tmp/workforce-qa').create(recursive: true);
          await File(
            '/tmp/workforce-qa/board-${width.toInt()}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'Any business onboarding exposes industry and work mode presets',
    (t) async {
      final c = WorkforceClient(
        backendBaseUrl: 'https://test.invalid',
        headersBuilder: () => {},
        client: MockClient(
          (_) async =>
              http.Response('{"can_create":true,"workspaces":[]}', 200),
        ),
      );
      await t.pumpWidget(MaterialApp(home: WorkforceScreen(client: c)));
      await t.pumpAndSettle();
      expect(find.text('Your business.\nYour workforce.'), findsOneWidget);
      expect(find.text('Create business workspace'), findsOneWidget);
      await t.ensureVisible(find.text('Create business workspace'));
      await t.tap(find.text('Create business workspace'));
      await t.pumpAndSettle();
      final form = t.widget<WorkforceForm>(find.byType(WorkforceForm));
      expect(
        form.fields.firstWhere((f) => f.keyName == 'industry').choices!.length,
        12,
      );
      expect(
        form.fields.firstWhere((f) => f.keyName == 'work_mode').choices!.keys,
        containsAll(['field', 'remote', 'hybrid', 'onsite']),
      );
      expect(find.textContaining('any business'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'K-Nova task stays unsaved until editable review is saved with pinned member version',
    (t) async {
      t.view.physicalSize = const Size(1200, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final data = sample();
      final writes = <WfJson>[];
      final client = fixture.client(
        data,
        handler: (r) async {
          if (r.method == 'POST') {
            writes.add(wfMap(jsonDecode(r.body)));
            return http.Response('{"saved":true}', 200);
          }
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/workspaces')
                  ? {
                      'can_create': true,
                      'workspaces': [
                        {'id': org, 'name': 'Brightside Field Services'},
                      ],
                    }
                  : data,
            ),
            200,
          );
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: WorkforceScreen(
            client: client,
            openVoice: (snapshot) async => {
              'saved': false,
              'reviewRequired': true,
              'organization_id': org,
              'member_id': owner,
              'member_version': 1,
              'action': 'task_create',
              'draft': {
                'title': 'Check the equipment',
                'assignee_id': worker,
                'priority': 'high',
                'details': 'Inspect before use',
                'project': 'Client A',
                'worksite': 'East',
              },
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Talk to K-Nova'));
      await t.pumpAndSettle();
      expect(find.text('Review K-Nova task'), findsOneWidget);
      expect(writes, isEmpty);
      final title = find.byWidgetPredicate(
        (w) => w is TextFormField && w.initialValue == 'Check the equipment',
      );
      expect(title, findsOneWidget);
      await t.enterText(title, 'Check and label the equipment');
      await t.ensureVisible(find.text('Save task'));
      await t.tap(find.text('Save task'));
      await t.pumpAndSettle();
      expect(writes.single['action'], 'task_create');
      final p = wfMap(writes.single['payload']);
      expect(p['title'], 'Check and label the equipment');
      expect(p['assignee_id'], worker);
      expect(p['expected_member_version'], 1);
      expect(p['due_at'], isNull);
      expect(p['request_id'], isNotEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Membership change during voice discards a prepared assignment before review',
    (t) async {
      t.view.physicalSize = const Size(1200, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final data = sample();
      await t.pumpWidget(
        MaterialApp(
          home: WorkforceScreen(
            client: fixture.client(data),
            openVoice: (snapshot) async {
              data['member']['version'] = 2;
              return {
                'saved': false,
                'reviewRequired': true,
                'organization_id': org,
                'member_id': owner,
                'member_version': 1,
                'action': 'task_create',
                'draft': {'title': 'Stale assignment', 'assignee_id': worker},
              };
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Talk to K-Nova'));
      await t.pumpAndSettle();
      expect(find.byType(WorkforceForm), findsNothing);
      expect(find.textContaining('workspace changed'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  test('Client rejects a late response after an account change', () async {
    var principal = token(owner);
    final revision = ValueNotifier(0), gate = Completer<http.Response>();
    final client = WorkforceClient(
      backendBaseUrl: 'https://test.invalid',
      headersBuilder: () => {'Authorization': principal},
      sessionChanges: revision,
      client: MockClient((_) => gate.future),
    );
    final future = client.request('GET', '/$org');
    final assertion = expectLater(future, throwsA(isA<WorkforceException>()));
    principal = token(worker);
    revision.value++;
    gate.complete(http.Response(jsonEncode(sample()), 200));
    await assertion;
    expect(client.sessionChanged, isTrue);
    client.dispose();
    revision.dispose();
  });
  test(
    'Voice controller rejects unknown people, duplicate rewrites, and stale membership',
    () async {
      var reads = 0, prepares = 0, version = 1;
      final c = WorkforceClient(
        backendBaseUrl: 'https://test.invalid',
        headersBuilder: () => {},
        client: MockClient((r) async {
          if (r.method == 'POST') {
            prepares++;
            final b = wfMap(jsonDecode(r.body));
            return http.Response(
              jsonEncode({
                'success': true,
                'action': b['action'],
                'draft': b['payload'],
                'organization_id': org,
                'member_id': owner,
                'member_version': version,
                'saved': false,
                'reviewRequired': true,
              }),
              200,
            );
          }
          reads++;
          return http.Response(
            jsonEncode({
              'organization': {'id': org},
              'member': {'user_id': owner, 'version': version},
              'members': [
                {'user_id': owner, 'active': true},
              ],
              'own_shifts': [],
            }),
            200,
          );
        }),
      );
      final v = WorkforceVoiceController(
        client: c,
        organizationId: org,
        memberId: owner,
        memberVersion: 1,
      );
      await v.handleToolCall('get_workforce_context', {}, 'context');
      await v.handleToolCall('get_workforce_context', {}, 'context');
      expect(reads, 1);
      final args = {
        'title': 'Draft',
        'details': '',
        'assignee_id': worker,
        'priority': 'normal',
        'project': '',
        'worksite': '',
        'due_at': '',
      };
      expect(
        (await v.handleToolCall(
          'draft_workforce_task',
          args,
          'bad',
        ))['success'],
        false,
      );
      expect(prepares, 0);
      args['assignee_id'] = owner;
      expect(
        (await v.handleToolCall(
          'draft_workforce_task',
          args,
          'draft',
        ))['success'],
        true,
      );
      args['title'] = 'Changed';
      expect(
        (await v.handleToolCall(
          'draft_workforce_task',
          args,
          'draft',
        ))['success'],
        false,
      );
      expect(prepares, 1);
      version = 2;
      expect(
        await v.handleToolCall('get_workforce_context', {}, 'fresh'),
        containsPair('discarded', true),
      );
      expect(v.available, false);
      expect(v.pendingDraft, isNull);
      v.dispose();
      c.dispose();
    },
  );
}
