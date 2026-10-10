import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

SocialMap message(String id, int seq, String body, {String sender = 'peer'}) =>
    {
      'id': id,
      'seq': seq,
      'sender': sender,
      'body': body,
      'created_at': '2026-09-28T22:50:00Z',
      'deleted': false,
    };

class Replies {
  final messages = <SocialMap>[
    message('first', 1, 'Are we meeting on Friday?'),
    message('second', 2, 'And should I bring the designs? 🎨'),
  ];
  final sends = <SocialMap>[];
  final opens = <String>[];
  final revision = ValueNotifier(0);
  String token = 'Bearer account-one';
  bool failSend = false;
  SocialMap original = message(
    'older',
    0,
    'An earlier message with the full details, outside the currently loaded page.',
  );
  SocialMap card(SocialMap m) {
    if (m['reply_to'] == null) return m;
    final p = m['reply_to'] == original['id']
        ? original
        : messages.firstWhere((x) => x['id'] == m['reply_to']);
    return {
      ...m,
      'reply': {...p, if (p['deleted'] == true) 'body': ''},
    };
  }

  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.path.split('/').last;
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : r.url.queryParameters;
      SocialMap result = {};
      var status = 200;
      if (action == 'messages') {
        result = {'items': messages.map(card).toList(), 'peer': social.peer};
      }
      if (action == 'message') {
        opens.add('${data['id']}');
        result = {'message': original, 'peer': social.peer};
      }
      if (action == 'send') {
        sends.add({...data});
        if (failSend) {
          status = 503;
          result = {'error': 'Connection interrupted. Please retry.'};
        } else {
          messages.add({
            ...message(
              '${data['id']}',
              messages.length + 1,
              '${data['body']}',
              sender: 'me',
            ),
            'reply_to': data['reply_to'],
          });
          result = {'id': data['id']};
        }
      }
      return http.Response(
        jsonEncode(result),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  void switchAccount() {
    token = 'Bearer account-two';
    revision.value++;
  }
}

Future<void> tap(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  if (f.evaluate().isEmpty) {
    final scroll = find.byType(Scrollable).first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(f, 240, scrollable: scroll);
  }
  await Scrollable.ensureVisible(t.element(f), alignment: .5);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> mount(
  WidgetTester t,
  Replies r, {
  double width = 390,
  double scale = 1,
}) => social.mount(
  t,
  SocialChatScreen(client: r.client, me: social.me, peer: social.peer),
  width: width,
  scale: scale,
);
Finder get preview => find.byKey(const ValueKey('reply-composer-preview'));

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
  testWidgets(
    'choosing a reply keeps the composer mounted and opens its keyboard',
    (t) async {
      final r = Replies();
      await mount(t, r);
      final editor = find.descendant(
        of: find.byType(TextField),
        matching: find.byType(EditableText),
      );
      final composer = t.state<EditableTextState>(editor);
      await t.tap(find.byKey(const ValueKey('reply-first')));
      await t.pumpAndSettle();
      expect(t.state<EditableTextState>(editor), same(composer));
      expect(composer.widget.focusNode.hasFocus, isTrue);
      expect(t.testTextInput.isVisible, isTrue);
      expect(preview, findsOneWidget);
    },
  );
  testWidgets(
    'reply reopens a dismissed keyboard without clearing the current draft',
    (t) async {
      final r = Replies();
      await mount(t, r);
      await t.enterText(find.byType(TextField), 'Keep this draft');
      t.testTextInput.hide();
      await t.tap(find.byKey(const ValueKey('reply-first')));
      await t.pumpAndSettle();
      expect(t.testTextInput.isVisible, isTrue);
      expect(find.text('Keep this draft'), findsOneWidget);
      t.testTextInput.hide();
      await t.tap(find.byKey(const ValueKey('reply-second')));
      await t.pumpAndSettle();
      expect(t.testTextInput.isVisible, isTrue);
      expect(find.text('Keep this draft'), findsOneWidget);
    },
  );
  testWidgets(
    'Reply from the message menu opens the keyboard for the chosen message',
    (t) async {
      final r = Replies();
      await mount(t, r);
      await t.tap(find.byTooltip('Message options').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Reply').last);
      await t.pumpAndSettle();
      expect(t.testTextInput.isVisible, isTrue);
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Are we meeting on Friday?'),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'reply selects the specific message, cancels without losing draft, and sends a linked quote',
    (t) async {
      final r = Replies();
      await mount(t, r);
      await tap(t, find.byKey(const ValueKey('reply-first')));
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Are we meeting on Friday?'),
        ),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextField), 'Yes, Friday works 👍');
      await tap(t, find.byTooltip('Cancel reply'));
      expect(preview, findsNothing);
      expect(find.text('Yes, Friday works 👍'), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('reply-second')));
      expect(
        find.descendant(
          of: preview,
          matching: find.text('And should I bring the designs? 🎨'),
        ),
        findsOneWidget,
      );
      await tap(t, find.byTooltip('Send message'));
      expect(r.sends.single['reply_to'], 'second');
      expect(r.sends.single['body'], 'Yes, Friday works 👍');
      expect(preview, findsNothing);
      expect(
        find.byKey(ValueKey('quote-${r.sends.single['id']}')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'failed replies retain draft and target; retries keep identity until target changes',
    (t) async {
      final r = Replies()..failSend = true;
      await mount(t, r);
      await tap(t, find.byKey(const ValueKey('reply-first')));
      await t.enterText(find.byType(TextField), 'Yes');
      await tap(t, find.byTooltip('Send message'));
      expect(preview, findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      await tap(t, find.byTooltip('Send message'));
      expect(r.sends[0]['id'], r.sends[1]['id']);
      await tap(t, find.byKey(const ValueKey('reply-second')));
      r.failSend = false;
      await tap(t, find.byTooltip('Send message'));
      expect(r.sends[2]['id'], isNot(r.sends[1]['id']));
      expect(r.sends[2]['reply_to'], 'second');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'quoted originals outside the loaded page are fetched afresh, including removals',
    (t) async {
      final r = Replies();
      r.messages.add({
        ...message('response', 3, 'That makes sense.', sender: 'me'),
        'reply_to': 'older',
      });
      await mount(t, r);
      await tap(t, find.byKey(const ValueKey('quote-response')));
      expect(r.opens.single, 'older');
      expect(find.text('Original message'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, '${r.original['body']}'),
        findsOneWidget,
      );
      await tap(t, find.text('Reply to this message'));
      expect(preview, findsOneWidget);
      expect(t.testTextInput.isVisible, isTrue);
      expect(
        t.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      r.original = {...r.original, 'body': '', 'deleted': true};
      await tap(t, find.byTooltip('Cancel reply'));
      await tap(t, find.byKey(const ValueKey('quote-response')));
      expect(find.text('Message removed'), findsWidgets);
      expect(find.text('Reply to this message'), findsNothing);
      expect(find.textContaining('An earlier message'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('account changes clear reply drafts and open original content', (
    t,
  ) async {
    final r = Replies();
    r.messages.add({
      ...message('response', 3, 'That makes sense.', sender: 'me'),
      'reply_to': 'older',
    });
    await mount(t, r);
    await tap(t, find.byKey(const ValueKey('reply-first')));
    await t.enterText(find.byType(TextField), 'Private unsent reply');
    await tap(t, find.byKey(const ValueKey('quote-response')));
    r.switchAccount();
    await t.pumpAndSettle();
    expect(find.textContaining('An earlier message'), findsNothing);
    expect(find.text('Private unsent reply'), findsNothing);
    expect(preview, findsNothing);
    expect(find.text('This conversation is unavailable.'), findsOneWidget);
  });
  testWidgets(
    'polling a removed selected message clears its quote but preserves the draft',
    (t) async {
      final r = Replies();
      await mount(t, r);
      await tap(t, find.byKey(const ValueKey('reply-first')));
      await t.enterText(find.byType(TextField), 'Keep this draft');
      r.messages[0] = {...r.messages[0], 'body': '', 'deleted': true};
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(preview, findsNothing);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(find.text('Are we meeting on Friday?'), findsNothing);
    },
  );
  for (final size in [(390.0, 1.0), (320.0, 1.4), (1280.0, 1.0)]) {
    testWidgets('reply layout ${size.$1} at text scale ${size.$2}', (t) async {
      final r = Replies();
      r.messages.add({
        ...message(
          'response',
          3,
          'Absolutely — bring the designs! 👍',
          sender: 'me',
        ),
        'reply_to': 'second',
      });
      await mount(t, r, width: size.$1, scale: size.$2);
      await tap(t, find.byKey(const ValueKey('reply-response')));
      await t.enterText(find.byType(TextField), 'Looking forward to it');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(preview, findsOneWidget);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-replies-${size.$1.toInt()}');
    });
  }
}
