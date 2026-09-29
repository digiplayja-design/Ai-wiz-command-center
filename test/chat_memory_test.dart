import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/chat/chat_memory_client.dart';
import 'package:ai_wiz_command_center/chat/chat_memory_screen.dart';
import 'social_test.dart' show mount;
import 'agent_studio_test.dart' as fixtures;

class MemoryStore {
  bool enabled = true, fail = false;
  List<MemoryNote> notes = [
    {
      'id': 'one',
      'body': 'I prefer concise answers with practical examples.',
      'category': 'preferences',
      'version': 1,
    },
    {
      'id': 'two',
      'body': 'I run a design studio and am learning Spanish.',
      'category': 'work',
      'version': 1,
    },
  ];
  final List<String> actions = [];
  late final client = ChatMemoryClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': 'Bearer first'},
    client: MockClient((req) async {
      final action = req.url.pathSegments.last;
      actions.add(action);
      if (fail) {
        return http.Response(
          '{"error":"Connection unavailable. Refresh and retry."}',
          503,
        );
      }
      final data = req.method == 'POST' ? jsonDecode(req.body) as Map : {};
      if (action == 'settings') enabled = data['enabled'] == true;
      if (action == 'save') {
        notes.removeWhere((e) => e['id'] == data['id']);
        notes.add({
          ...data.map((k, v) => MapEntry('$k', v)),
          'version': (data['version'] as int? ?? 0) + 1,
        });
      }
      if (action == 'delete') notes.removeWhere((e) => e['id'] == data['id']);
      if (action == 'clear') notes.clear();
      return http.Response(
        jsonEncode({'enabled': enabled, 'items': notes}),
        200,
      );
    }),
  );
}

Future<void> tap(WidgetTester t, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    final scroll = find.byType(Scrollable).first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(finder, 280, scrollable: scroll);
  }
  await Scrollable.ensureVisible(t.element(finder), alignment: .5);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  test(
    'late responses cannot restore notes after switching accounts',
    () async {
      var token = 'Bearer first';
      final change = ValueNotifier(0), done = Completer<http.Response>();
      final c = ChatMemoryClient(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': token},
        sessionChanges: change,
        client: MockClient((_) => done.future),
      );
      final load = c.load();
      token = 'Bearer second';
      change.value++;
      done.complete(
        http.Response('{"enabled":true,"items":[{"body":"Private"}]}', 200),
      );
      expect(await load, false);
      expect(c.available, false);
      expect(c.items, isEmpty);
      c.dispose();
      change.dispose();
    },
  );
  test('401 clears previously loaded notes', () async {
    var status = 200;
    final c = ChatMemoryClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': 'Bearer first'},
      client: MockClient(
        (_) async => http.Response(
          status == 200
              ? '{"enabled":true,"items":[{"body":"Private"}]}'
              : '{}',
          status,
        ),
      ),
    );
    expect(await c.load(), true);
    status = 401;
    expect(await c.load(), false);
    expect(c.items, isEmpty);
    expect(c.available, false);
    c.dispose();
  });
  test(
    'local chat cache uses account identity, survives token refresh, and never embeds credentials',
    () {
      Map<String, String> token(String sub, String session) => {
        'Authorization':
            'Bearer prefix.${base64Url.encode(utf8.encode(jsonEncode({'sub': sub, 'iss': 'fixture', 'session_id': session})))}.secret-signature',
      };
      final one = chatAccountStorageKey(token('one', 'session1'));
      expect(one, chatAccountStorageKey(token('one', 'session2')));
      expect(one, isNot(chatAccountStorageKey(token('two', 'session1'))));
      expect(one, isNot(contains('secret-signature')));
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('memory screen at $width is readable and has no overflow', (
      t,
    ) async {
      final store = MemoryStore();
      addTearDown(store.client.dispose);
      await mount(
        t,
        ChatMemoryScreen(client: store.client),
        width: width,
        scale: width == 320 ? 1.2 : 1,
      );
      expect(find.text('Your context,\nremembered.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'main-chat-memory-${width.toInt()}');
      await tap(t, find.text('Add memory'));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'main-chat-memory-editor-${width.toInt()}');
      await tap(t, find.text('Cancel'));
    });
  }
  testWidgets(
    'add, edit, search, pause, and forget require deliberate actions',
    (t) async {
      final store = MemoryStore();
      addTearDown(store.client.dispose);
      await mount(t, ChatMemoryScreen(client: store.client));
      await tap(t, find.text('Add memory'));
      await t.enterText(
        find.byKey(const Key('memory-note-input')),
        'My name is Alex',
      );
      await tap(t, find.text('Save memory'));
      expect(store.notes.any((e) => e['body'] == 'My name is Alex'), true);
      await tap(t, find.byKey(const ValueKey('edit-one')));
      await t.enterText(
        find.byKey(const Key('memory-note-input')),
        'I prefer detailed answers',
      );
      await tap(t, find.text('Save memory'));
      expect(store.notes.firstWhere((e) => e['id'] == 'one')['version'], 2);
      final search = find.byType(TextField).first;
      await t.enterText(search, 'detailed');
      await t.pumpAndSettle();
      expect(find.text('I prefer detailed answers'), findsOneWidget);
      expect(
        find.text('I run a design studio and am learning Spanish.'),
        findsNothing,
      );
      await t.enterText(search, '');
      await t.pumpAndSettle();
      await tap(t, find.byType(Switch));
      expect(store.enabled, false);
      await tap(t, find.byKey(const ValueKey('forget-one')));
      await tap(t, find.text('Cancel'));
      expect(store.notes.any((e) => e['id'] == 'one'), true);
      await tap(t, find.byKey(const ValueKey('forget-one')));
      await tap(t, find.widgetWithText(FilledButton, 'Forget'));
      expect(store.notes.any((e) => e['id'] == 'one'), false);
      await tap(t, find.text('Forget all memories'));
      await tap(t, find.widgetWithText(FilledButton, 'Forget all'));
      expect(store.notes, isEmpty);
      expect(find.text('Start with something useful.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('failed save preserves the draft and never shows success', (
    t,
  ) async {
    final store = MemoryStore();
    addTearDown(store.client.dispose);
    await mount(t, ChatMemoryScreen(client: store.client));
    await tap(t, find.text('Add memory'));
    await t.enterText(
      find.byKey(const Key('memory-note-input')),
      'Keep my draft',
    );
    store.fail = true;
    await tap(t, find.text('Save memory'));
    expect(find.text('Keep my draft'), findsOneWidget);
    expect(find.byType(MemoryEditor), findsOneWidget);
    expect(store.notes.length, 2);
    expect(t.takeException(), isNull);
  });
  testWidgets('memory button displays confirmed state and opens controls', (
    t,
  ) async {
    final store = MemoryStore();
    addTearDown(store.client.dispose);
    await store.client.load();
    var opened = false;
    await mount(
      t,
      Scaffold(
        body: ChatMemoryButton(
          client: store.client,
          onPressed: () => opened = true,
        ),
      ),
    );
    expect(find.text('Memory on'), findsOneWidget);
    await t.tap(find.text('Memory on'));
    expect(opened, true);
    await store.client.setEnabled(false);
    await t.pumpAndSettle();
    expect(find.text('Memory paused'), findsOneWidget);
  });
}
