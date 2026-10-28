import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_social_core/social/social_client.dart';
import 'package:korlix_social_core/social/social_message_text.dart';
import 'package:korlix_social_core/social/social_threads.dart';

import 'social_test.dart' as fixtures;
import 'agent_studio_test.dart' as screenshots;

http.Response _response(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class InteractionsStore {
  final reactions = <SocialMap>[], sends = <SocialMap>[];
  List<SocialMap> saved = [];
  bool fail = false;
  Completer<http.Response>? pending;
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': 'Bearer fixture'},
    client: MockClient((request) async {
      final action = request.url.path.split('/').last;
      final data = request.method == 'POST'
          ? socialMap(jsonDecode(request.body))
          : <String, dynamic>{};
      if (action == 'react') {
        reactions.add(data);
        if (pending != null) return pending!.future;
        if (fail) return _response('{"error":"Try again"}', 503);
        saved = data['emoji'] == null
            ? []
            : [
                {'emoji': data['emoji'], 'count': 1, 'mine': true},
              ];
        return _response(
          jsonEncode({'id': 'message', 'reactions': saved}),
          200,
        );
      }
      if (action.endsWith('messages')) {
        return _response(
          jsonEncode({
            'peer': fixtures.peer,
            'items': [
              {
                'id': 'message',
                'seq': 1,
                'sender': 'peer',
                'body': 'Wonderful news',
                'created_at': '2026-10-28T12:00:00Z',
                'reactions': saved,
                'formatting': [
                  {'start': 0, 'end': 9, 'style': 'bold'},
                ],
              },
            ],
          }),
          200,
        );
      }
      if (action.endsWith('send')) {
        sends.add(data);
        if (fail) return _response('{"error":"Try again"}', 503);
      }
      return _response('{}', 200);
    }),
  );
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
    'style toggles preserve plain text, overlap and Unicode code-point offsets',
    () {
      final c = SocialTextController()..text = '  Hi 👋🏽 世界  ';
      addTearDown(c.dispose);
      final start = c.text.indexOf('👋');
      expect(
        c.toggle(
          'bold',
          TextSelection(baseOffset: start, extentOffset: start + 4),
        ),
        isTrue,
      );
      expect(
        c.toggle(
          'italic',
          TextSelection(baseOffset: start, extentOffset: start + 4),
        ),
        isTrue,
      );
      expect(
        c.formatting,
        containsAll([
          {'start': 3, 'end': 5, 'style': 'bold'},
          {'start': 3, 'end': 5, 'style': 'italic'},
        ]),
      );
      expect(c.text, '  Hi 👋🏽 世界  ');
      c.toggle(
        'bold',
        TextSelection(baseOffset: start, extentOffset: start + 4),
      );
      expect(c.formatting.single['style'], 'italic');
      c.clear();
      expect(c.formatting, isEmpty);
    },
  );

  test('typing, replacement and deletion shift existing styles', () {
    final c = SocialTextController()..text = 'Hello world';
    addTearDown(c.dispose);
    c.toggle('highlight', const TextSelection(baseOffset: 6, extentOffset: 11));
    c.value = const TextEditingValue(
      text: 'Hey Hello world',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(c.formatting.single, {'start': 10, 'end': 15, 'style': 'highlight'});
    c.value = const TextEditingValue(
      text: 'Hey Hello all',
      selection: TextSelection.collapsed(offset: 13),
    );
    expect(c.formatting.single, {'start': 10, 'end': 13, 'style': 'highlight'});
    c.value = const TextEditingValue(
      text: 'Hey Hello ',
      selection: TextSelection.collapsed(offset: 10),
    );
    expect(c.formatting, isEmpty);
  });

  test('dictionary accepts one word and rejects phrases, URLs and emoji', () {
    for (final word in ['hello', 'café', '世界', "don't", 'well-being']) {
      expect(socialDictionaryWord(word), word);
    }
    expect(socialDictionaryWord('“Wonderful!”'), 'Wonderful');
    for (final value in ['two words', 'https://example.com', '😂', '', '123']) {
      expect(socialDictionaryWord(value), isNull);
    }
  });

  test('malformed received ranges cannot crash text rendering', () {
    final span = socialMessageSpan('Hi 👋', [
      {'start': -1, 'end': 100, 'style': 'bold'},
      {'start': 0, 'end': '1', 'style': 'italic'},
      {'start': 3, 'end': 4, 'style': 'highlight'},
      {'start': 0, 'end': 1, 'style': 'unknown'},
    ], const TextStyle());
    expect(span.toPlainText(), 'Hi 👋');
    expect((span.children!.last as TextSpan).style!.backgroundColor, isNotNull);
  });

  for (final group in [false, true]) {
    testWidgets(
      'long press offers quick reactions and persists changes in ${group ? 'groups' : 'direct chats'}',
      (t) async {
        final store = InteractionsStore();
        addTearDown(store.client.dispose);
        await fixtures.mount(
          t,
          SocialChatScreen(
            client: store.client,
            me: fixtures.me,
            peer: fixtures.peer,
            groupChat: group,
          ),
          width: 320,
          scale: 1.3,
        );
        await t.longPress(find.text('Wonderful news'));
        await t.pumpAndSettle();
        expect(find.byTooltip('React Thumbs up'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        await screenshots.capture(
          t,
          group ? 'messenger-group-reactions' : 'messenger-direct-reactions',
        );
        await t.tap(find.byTooltip('React Thumbs up'));
        await t.pumpAndSettle();
        expect(store.reactions.single['emoji'], '👍');
        expect(
          store.reactions.single[group ? 'group' : 'peer'],
          fixtures.peer['id'],
        );
        expect(find.text('👍 1'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('reaction-count-👍')));
        await t.pumpAndSettle();
        expect(store.reactions.last['emoji'], isNull);
        expect(find.text('👍 1'), findsNothing);
        await t.tap(find.byKey(const ValueKey('react-message')));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).last, 'cry');
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Cry'));
        await t.pumpAndSettle();
        expect(find.text('😢 1'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('failed reaction does not fabricate a count and can be retried', (
    t,
  ) async {
    final store = InteractionsStore()..fail = true;
    addTearDown(store.client.dispose);
    await fixtures.mount(
      t,
      SocialChatScreen(
        client: store.client,
        me: fixtures.me,
        peer: fixtures.peer,
      ),
    );
    await t.longPress(find.text('Wonderful news'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('React Laugh'));
    await t.pumpAndSettle();
    expect(find.text('😂 1'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    store.fail = false;
    await t.longPress(find.text('Wonderful news'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('React Laugh'));
    await t.pumpAndSettle();
    expect(find.text('😂 1'), findsOneWidget);
  });

  testWidgets(
    'composer selection offers dictionary and all four formatting actions',
    (t) async {
      final store = InteractionsStore();
      addTearDown(store.client.dispose);
      await fixtures.mount(
        t,
        SocialChatScreen(
          client: store.client,
          me: fixtures.me,
          peer: fixtures.peer,
        ),
      );
      await t.enterText(find.byType(TextField), 'Wonderful');
      final field = t.widget<TextField>(find.byType(TextField));
      final editor = t.state<EditableTextState>(
        find.descendant(
          of: find.byType(TextField),
          matching: find.byType(EditableText),
        ),
      );
      // Simulate the OS selecting a word (iOS uses double-tap; a held cursor
      // can remain collapsed). The toolbar must follow the actual selection.
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Wonderful',
          selection: TextSelection(baseOffset: 0, extentOffset: 9),
        ),
      );
      await t.pump();
      editor.showToolbar();
      await t.pumpAndSettle();
      expect(find.text('Dictionary'), findsOneWidget);
      expect(editor.textEditingValue.selection.isCollapsed, isFalse);
      for (final label in ['Bold', 'Italic', 'Strikethrough', 'Highlight']) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text('Bold'));
      await t.pumpAndSettle();
      expect(
        (field.controller! as SocialTextController).formatting.single['style'],
        'bold',
      );
      await screenshots.capture(t, 'messenger-formatted-composer');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(store.sends.single['body'], 'Wonderful');
      expect(store.sends.single['formatting'], [
        {'style': 'bold', 'start': 0, 'end': 9},
      ]);
      expect(field.controller!.text, isEmpty);
    },
  );

  testWidgets(
    'formatting changes use a new send ID while unchanged retries reuse it',
    (t) async {
      final store = InteractionsStore()..fail = true;
      addTearDown(store.client.dispose);
      await fixtures.mount(
        t,
        SocialChatScreen(
          client: store.client,
          me: fixtures.me,
          peer: fixtures.peer,
        ),
      );
      await t.enterText(find.byType(TextField), 'Same words');
      final controller =
          t.widget<TextField>(find.byType(TextField)).controller!
              as SocialTextController;
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(store.sends[0]['id'], store.sends[1]['id']);
      controller.toggle(
        'strike',
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(store.sends.last['id'], isNot(store.sends.first['id']));
      expect(store.sends.last['formatting'], [
        {'style': 'strike', 'start': 0, 'end': 4},
      ]);
    },
  );

  testWidgets(
    'an account change closes reaction access and ignores a delayed result',
    (t) async {
      final store = InteractionsStore()..pending = Completer<http.Response>();
      addTearDown(store.client.dispose);
      await fixtures.mount(
        t,
        SocialChatScreen(
          client: store.client,
          me: fixtures.me,
          peer: fixtures.peer,
        ),
      );
      await t.longPress(find.text('Wonderful news'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('React Smile'));
      await t.pump();
      store.client.invalidateSession();
      await t.pumpAndSettle();
      store.pending!.complete(
        _response('{"reactions":[{"emoji":"🙂","count":1,"mine":true}]}', 200),
      );
      await t.pumpAndSettle();
      expect(find.text('🙂 1'), findsNothing);
    },
  );
}
