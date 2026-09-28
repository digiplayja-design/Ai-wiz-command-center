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
import 'package:ai_wiz_command_center/live_convo/agent_studio_client.dart';
import 'package:ai_wiz_command_center/live_convo/agent_studio_design.dart';
import 'package:ai_wiz_command_center/live_convo/agent_studio_hub.dart';
import 'package:ai_wiz_command_center/live_convo/agent_studio_workflows.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_client.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_sheet.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

final agents = KorlixLiveConvoAgent.builtInFallbacks
    .map(
      (a) => a.copyWith(
        persistenceConfigured: true,
        memoryCount: 12,
        version: 3,
        trainingInstructions: 'Use clear, practical language.',
      ),
    )
    .toList();

class FakeAgents extends KorlixLiveConvoAgentClient {
  FakeAgents()
    : super(backendBaseUrl: 'https://fixture.test', headersBuilder: () => {});
  List<KorlixLiveConvoAgentMemory> memories = [
    const KorlixLiveConvoAgentMemory(
      id: 'm1',
      agentId: 'general',
      kind: 'preference',
      content: 'Use concise language.',
      label: 'Writing style',
      tags: ['writing'],
      importance: 5,
    ),
    const KorlixLiveConvoAgentMemory(
      id: 'm2',
      agentId: 'general',
      kind: 'fact',
      content: 'Internal project code Mercury.',
      label: 'Project',
      tags: ['project'],
      sensitive: true,
    ),
  ];
  Completer<KorlixLiveConvoAgentMemory>? saving;
  @override
  Future<KorlixLiveConvoAgentCatalog> loadCatalog() async =>
      KorlixLiveConvoAgentCatalog(agents: agents, persistenceConfigured: true);
  @override
  Future<KorlixLiveConvoAgentModelProof> loadModelProof() async =>
      const KorlixLiveConvoAgentModelProof(
        liveConvoModel: 'voice',
        liveDocsDocumentModel: 'gpt-6-astra',
        liveDocsReasoningEffort: 'xhigh',
        deterministicAuditEngine: true,
      );
  @override
  Future<List<KorlixLiveConvoAgentMemory>> loadMemories({
    required String agentId,
  }) async => memories;
  @override
  Future<KorlixLiveConvoAgentMemory> saveMemory({
    required String agentId,
    required KorlixLiveConvoMemoryDraft draft,
  }) async {
    if (!draft.confirmed) throw StateError('Unconfirmed');
    return saving!.future;
  }
}

Map<String, dynamic> workflow() => {
  'id': 'workflow-1',
  'revision': 1,
  'title': 'Product launch',
  'objective': 'Prepare a concise launch brief.',
  'priority': 'normal',
  'use_memory': false,
  'state': 'ready',
  'cursor': 0,
  'created_at': '2026-09-28T13:00:00Z',
  'events': [
    {'type': 'created', 'at': '2026-09-28T13:00:00Z'},
  ],
  'steps': [
    {
      'agent_id': 'general',
      'title': 'Plan',
      'instruction': 'Create the launch outline.',
      'status': 'pending',
    },
    {
      'agent_id': 'doc_wizard',
      'title': 'Draft',
      'instruction': 'Write the approved brief.',
      'status': 'pending',
    },
  ],
};

class FakeWorkflows extends AgentStudioClient {
  FakeWorkflows()
    : super(baseUrl: 'https://fixture.test', headersBuilder: () => {});
  Map<String, dynamic> w = workflow();
  List<String> actions = [];
  bool empty = false;
  @override
  Future<List<Map<String, dynamic>>> list() async => empty
      ? []
      : [
          {...w, 'step_count': 2},
        ];
  @override
  Future<Map<String, dynamic>> get(String id) async =>
      Map<String, dynamic>.from(w);
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> p) async {
    actions.add('create');
    w = {...workflow(), ...p};
    empty = false;
    return Map.from(w);
  }

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> value,
    String key,
  ) async {
    actions.add('run');
    w = {
      ...w,
      'revision': 2,
      'state': 'review',
      'steps': [
        {
          ...w['steps'][0],
          'status': 'review',
          'output': 'The actual launch plan.',
          'agent_version': 3,
        },
        w['steps'][1],
      ],
    };
    return Map.from(w);
  }

  @override
  Future<Map<String, dynamic>> act(
    Map<String, dynamic> value,
    String action, {
    String? feedback,
  }) async {
    actions.add(action);
    if (action == 'approve')
      w = {
        ...w,
        'revision': 3,
        'cursor': 1,
        'state': 'ready',
        'steps': [
          {...w['steps'][0], 'status': 'approved'},
          w['steps'][1],
        ],
      };
    return Map.from(w);
  }
}

final captureKey = GlobalKey();
Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 390,
  double height = 844,
  double scale = 1.0,
  String theme = 'pure_black',
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme(theme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(key: captureKey, child: child),
      ),
    ),
  );
  await t.pumpAndSettle();
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    final scroll = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(f, 300, scrollable: scroll, maxScrolls: 50);
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await reveal(t, f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Widget hub({
  void Function(String, KorlixLiveConvoAgent)? action,
  ValueChanged<String>? select,
}) => AgentStudioHub(
  agents: agents,
  selectedId: 'general',
  activeId: 'general',
  loading: false,
  busy: false,
  connected: true,
  onSelect: select ?? (_) {},
  onAction: action ?? (_, _) {},
  onCreate: () {},
  onClose: () {},
  onRefresh: () {},
  workflows: const Text('Workflow area'),
  meetingCard: const Text('Meeting Copilot'),
  modelProof: const Text('Model proof'),
);
Future<void> capture(WidgetTester t, String name) async {
  final dir = Platform.environment['AGENT_STUDIO_SCREENSHOTS'];
  if (dir == null) return;
  await t.runAsync(() async {
    final image =
        await (captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final b = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(b!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null)
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
  });
  for (final theme in ['pure_white', 'pure_black']) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets(
        'Agent Studio $theme at $width supports large text and navigation',
        (t) async {
          await mount(t, hub(), width: width, scale: 1.25, theme: theme);
          expect(t.takeException(), isNull);
          await tap(
            t,
            find.byKey(const ValueKey('studio-tab-Brain Management')),
          );
          expect(
            find.text('Knowledge, with a little dimension.'),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await tap(t, find.text('Workflows'));
          expect(find.text('Workflow area'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'Agent search filters by partial name and capability; use targets selected card',
    (t) async {
      String? used;
      await mount(
        t,
        hub(
          action: (action, a) {
            if (action == 'use') used = a.id;
          },
        ),
        width: 1280,
      );
      final search = find.byType(TextField);
      await t.ensureVisible(search);
      await t.enterText(search, 'language');
      await t.pumpAndSettle();
      expect(find.text('Language Teacher'), findsOneWidget);
      expect(find.text('Graphic Designer'), findsNothing);
      await tap(t, find.text('Use agent'));
      expect(used, 'language_teacher');
      await t.enterText(search, 'no-match-at-all');
      await t.pumpAndSettle();
      expect(find.textContaining('No agents match'), findsOneWidget);
    },
  );
  testWidgets(
    'Brain animation respects reduced motion and exposes accessible activity',
    (t) async {
      await mount(t, const KorlixNeuralBrain(activity: 'training'));
      expect(t.hasRunningAnimations, isFalse);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains('Publishing training'),
        ),
        findsOneWidget,
      );
      await t.drag(find.byType(CustomPaint).last, const Offset(40, 0));
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Memory library searches content and filters sensitive records', (
    t,
  ) async {
    final c = FakeAgents();
    await mount(
      t,
      KorlixLiveConvoAgentHubSheet(
        client: c,
        activeAgent: agents.first,
        characterName: 'K-Nova',
        language: 'English',
      ),
    );
    await tap(t, find.byKey(const ValueKey('studio-tab-Brain Management')));
    await tap(t, find.text('Memory library'));
    final search = find.widgetWithText(
      TextField,
      'Search content, labels, or tags',
    );
    await t.ensureVisible(search);
    await t.enterText(search, 'Mercury');
    await t.pumpAndSettle();
    expect(find.text('1 of 2 memories'), findsOneWidget);
    await t.ensureVisible(find.text('Internal project code Mercury.'));
    expect(t.takeException(), isNull);
    await t.enterText(search, '');
    await tap(t, find.text('Sensitive only'));
    expect(find.text('1 of 2 memories'), findsOneWidget);
  });
  testWidgets(
    'Training studio starts unconfirmed and uses real editing state',
    (t) async {
      final c = FakeAgents();
      await mount(
        t,
        KorlixLiveConvoAgentHubSheet(
          client: c,
          activeAgent: agents.first,
          characterName: 'K-Nova',
          language: 'English',
        ),
        width: 390,
      );
      await tap(t, find.byKey(const ValueKey('studio-tab-Brain Management')));
      await tap(t, find.text('Training studio'));
      final field = find.widgetWithText(TextField, 'Instructions to learn');
      await reveal(t, field);
      await t.enterText(field, 'Write clear action lists.');
      await t.pumpAndSettle();
      await tap(t, find.text('Publish Training'));
      expect(
        find.textContaining('Confirm that these instructions'),
        findsOneWidget,
      );
      expect(find.text('Publish as long-term agent training'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Workflow executes one step, shows actual result, and only hands off on approval',
    (t) async {
      final c = FakeWorkflows();
      await mount(
        t,
        AgentStudioWorkflows(client: c, agents: agents),
        width: 390,
        scale: 1.25,
      );
      await tap(t, find.text('Product launch'));
      await tap(t, find.text('Run next step · 1 credit'));
      expect(c.actions, ['run']);
      await reveal(t, find.text('The actual launch plan.'));
      expect(find.text('The actual launch plan.'), findsOneWidget);
      await tap(t, find.text('Approve & hand off'));
      expect(c.actions, ['run', 'approve']);
      expect(find.text('1 of 2 steps approved'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Workflow builder validates inputs, saves assignments and creates no automatic run',
    (t) async {
      final c = FakeWorkflows()..empty = true;
      await mount(
        t,
        AgentStudioWorkflows(client: c, agents: agents),
        width: 390,
      );
      await tap(t, find.text('New workflow'));
      await tap(t, find.text('Create workflow'));
      expect(find.textContaining('Add a workflow name'), findsOneWidget);
      await reveal(t, find.widgetWithText(TextFormField, 'Workflow name'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Workflow name'),
        'Launch',
      );
      await reveal(
        t,
        find.widgetWithText(TextFormField, 'What should the team achieve?'),
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'What should the team achieve?'),
        'A useful product brief.',
      );
      await tap(t, find.text('Create workflow'));
      expect(c.actions, ['create']);
      expect(c.w['steps'].length, 3);
      expect(c.w['use_memory'], false);
      expect(t.takeException(), isNull);
    },
  );
  test('Workflow client rejects results after an account change', () async {
    var account = 'a';
    final wait = Completer<http.Response>();
    final c = AgentStudioClient(
      baseUrl: 'https://test.example',
      headersBuilder: () => {'Authorization': account},
      client: MockClient((r) => wait.future),
    );
    final result = c.list();
    account = 'b';
    wait.complete(http.Response('{"workflows":[]}', 200));
    await expectLater(result, throwsA(isA<AgentStudioException>()));
    await expectLater(c.list(), throwsA(isA<AgentStudioException>()));
    c.dispose();
  });
  test(
    'Agent memory client binds writes and discards late responses after account switch',
    () async {
      var account = 'a';
      var calls = 0;
      final wait = Completer<http.Response>();
      final c = KorlixLiveConvoAgentClient(
        backendBaseUrl: 'https://test.example',
        headersBuilder: () => {'Authorization': account},
        client: MockClient((r) {
          calls++;
          return wait.future;
        }),
      );
      final result = c.loadMemories(agentId: 'general');
      account = 'b';
      wait.complete(http.Response('{"memories":[]}', 200));
      await expectLater(
        result,
        throwsA(isA<KorlixLiveConvoAgentClientException>()),
      );
      await expectLater(
        c.saveMemory(
          agentId: 'general',
          draft: const KorlixLiveConvoMemoryDraft(
            content: 'old private context',
            confirmed: true,
          ),
        ),
        throwsA(isA<KorlixLiveConvoAgentClientException>()),
      );
      expect(calls, 1);
      c.close();
    },
  );
  test('Token refresh in the same session retains the workspace scope', () {
    String token(String sig) =>
        'Bearer h.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': 'owner', 'session_id': 'session'}))).replaceAll('=', '')}.$sig';
    expect(
      agentAccountScope({'Authorization': token('first')}),
      agentAccountScope({'Authorization': token('second')}),
    );
  });
  testWidgets(
    'Memory brain shows pending work and confirms only a saved result',
    (t) async {
      final c = FakeAgents()..saving = Completer<KorlixLiveConvoAgentMemory>();
      await mount(
        t,
        KorlixLiveConvoAgentHubSheet(
          client: c,
          activeAgent: agents.first,
          characterName: 'K-Nova',
          language: 'English',
        ),
        width: 320,
        scale: 1.25,
      );
      await tap(t, find.byKey(const ValueKey('studio-tab-Brain Management')));
      await tap(t, find.text('Memory library'));
      await tap(t, find.text('Add memory'));
      final field = find.widgetWithText(
        TextField,
        'What should this agent remember?',
      );
      await reveal(t, field);
      await t.enterText(field, 'Prefer short weekly summaries.');
      await tap(t, find.text('Save Confirmed Memory'));
      expect(find.textContaining('Confirm that this record'), findsOneWidget);
      await tap(t, find.text('Save in this agent’s long-term memory'));
      await reveal(t, find.text('Save Confirmed Memory'));
      await t.tap(find.text('Save Confirmed Memory'));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Saving memory'), findsOneWidget);
      expect(find.text('Update saved'), findsNothing);
      c.saving!.complete(
        const KorlixLiveConvoAgentMemory(
          id: 'm3',
          agentId: 'general',
          kind: 'preference',
          content: 'Prefer short weekly summaries.',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Update saved'), findsOneWidget);
      expect(find.text('Memory library'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Agent Studio visual captures', (t) async {
    await mount(t, hub(), width: 1440, height: 1100);
    await capture(t, 'agents-desktop');
    await tap(t, find.byKey(const ValueKey('studio-tab-Brain Management')));
    await capture(t, 'brain-desktop');
    t.view.physicalSize = const Size(390, 844);
    await t.pumpAndSettle();
    await capture(t, 'brain-mobile');
    await tap(t, find.text('Agents'));
    await capture(t, 'agents-mobile');
    expect(t.takeException(), isNull);
  });
}
