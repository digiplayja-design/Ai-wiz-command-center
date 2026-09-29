import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_forms.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'agent_studio_test.dart' as fixtures;

final me = <String, dynamic>{
  'id': 'me',
  'name': 'Alex Morgan',
  'handle': 'alex',
  'bio': 'Curious about what comes next.',
  'color': 'cyan',
  'discoverable': true,
  'show_online': false,
};
final peer = <String, dynamic>{
  'id': 'peer',
  'name': 'Jordan Rivera',
  'handle': 'jordan',
  'bio': 'Design, basketball and thoughtful conversations.',
  'color': 'violet',
  'online': true,
};
final categories = <SocialMap>[
  for (final c in [
    ('sports', 'Sports', 'mint'),
    ('entertainment', 'Entertainment', 'violet'),
    ('politics', 'Politics', 'coral'),
    ('religion', 'Religion & Beliefs', 'gold'),
    ('stock-market', 'Stock Market', 'cyan'),
    ('technology', 'Technology', 'blue'),
    ('business', 'Business', 'gold'),
    ('community', 'Community', 'mint'),
  ])
    {
      'id': c.$1,
      'name': c.$2,
      'color': c.$3,
      'description': 'A place for ideas and conversation.',
    },
];
final topic = <String, dynamic>{
  'id': 'topic',
  'category': 'sports',
  'title': 'What makes a great team?',
  'body':
      'Talent, trust, or the moments in between? Let’s talk about what brings a team together.',
  'author': peer,
  'created_at': '2026-09-28T16:00:00Z',
  'updated_at': '2026-09-28T16:00:00Z',
  'reply_count': 2,
  'locked': false,
};

class Store {
  Store({this.joined = true, this.incoming = false});
  bool joined, incoming, accepted = false;
  final calls = <SocialMap>[];
  final messages = <SocialMap>[];
  String token = 'Bearer account-one';
  final revision = ValueNotifier(0);
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.path.split('/').last;
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : r.url.queryParameters;
      calls.add({'action': action, 'method': r.method, ...data});
      SocialMap result = {};
      if (action == 'bootstrap') {
        result = {
          'profile': joined ? me : null,
          'categories': categories,
          'moderator': false,
        };
      }
      if (action == 'members' || action == 'connections') {
        result = {
          'items': [
            {
              ...peer,
              if (incoming || accepted)
                'connection': accepted ? 'accepted' : 'pending',
              if (incoming) 'incoming': true,
              'unread': 0,
            },
          ],
        };
      }
      if (action == 'topics') {
        result = {
          'items': [topic],
        };
      }
      if (action == 'topic') {
        result = {
          'topic': topic,
          'items': [
            {
              'id': 'reply',
              'seq': 1,
              'body': 'Trust is the foundation.',
              'author': me,
              'created_at': '2026-09-28T16:10:00Z',
              'updated_at': '2026-09-28T16:10:00Z',
            },
          ],
        };
      }
      if (action == 'accept') accepted = true;
      if (action == 'messages') result = {'peer': peer, 'items': messages};
      if (action == 'send') {
        messages.add({
          'id': data['id'],
          'seq': messages.length + 1,
          'sender': 'me',
          'body': data['body'],
          'created_at': '2026-09-28T17:00:00Z',
          'deleted': false,
        });
        result = {'id': data['id']};
      }
      if (action == 'save_profile') {
        joined = true;
        result = {
          'profile': {...me, ...data},
        };
      }
      if (action == 'create_topic') result = {'id': data['id']};
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 390,
  double height = 844,
  double scale = 1,
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
        child: RepaintBoundary(key: fixtures.captureKey, child: child!),
      ),
      home: child,
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
  test('client rejects late responses after account switch', () async {
    var token = 'Bearer first';
    final change = ValueNotifier(0), done = Completer<http.Response>();
    final c = SocialClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': token},
      sessionChanges: change,
      client: MockClient((_) => done.future),
    );
    final response = c.get('messages', {'peer': 'peer'});
    final rejected = expectLater(
      response,
      throwsA(isA<SocialException>().having((e) => e.status, 'status', 401)),
    );
    token = 'Bearer second';
    change.value++;
    done.complete(http.Response('{"items":[{"body":"private"}]}', 200));
    await rejected;
    expect(c.available, false);
    c.dispose();
    change.dispose();
  });
  test('token refresh within the same session keeps Social open', () async {
    String jwt(String sig) =>
        'Bearer a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': 'account', 'session_id': 'session'})))}.$sig';
    var token = jwt('first');
    final change = ValueNotifier(0);
    final c = SocialClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': token},
      sessionChanges: change,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    token = jwt('second');
    change.value++;
    await c.get('bootstrap');
    expect(c.available, true);
    c.dispose();
    change.dispose();
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('people and forums fit $width with scaled text', (t) async {
      final s = Store();
      await mount(
        t,
        SocialScreen(client: s.client),
        width: width,
        scale: width == 320 ? 1.4 : 1,
        theme: width == 320 ? 'pure_white' : 'korlix_blue',
      );
      expect(t.takeException(), isNull);
      await fixtures.tap(t, find.text('Follow'));
      expect(s.calls.where((c) => c['action'] == 'request').length, 1);
      await t.tap(find.text('Forums').last);
      await t.pumpAndSettle();
      final scroll = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (var i = 0; i < 20 && find.text('Sports').evaluate().isEmpty; i++) {
        scroll.jumpTo((scroll.pixels + 160).clamp(0, scroll.maxScrollExtent));
        await t.pumpAndSettle();
      }
      expect(find.text('Sports'), findsWidgets);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-forums-${width.toInt()}');
      await fixtures.tap(t, find.text('Sports').first);
      for (
        var i = 0;
        i < 20 && find.text('All forums').evaluate().isEmpty;
        i++
      ) {
        scroll.jumpTo((scroll.pixels + 160).clamp(0, scroll.maxScrollExtent));
        await t.pumpAndSettle();
      }
      expect(find.text('All forums'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'joining requires agreement and keeps online status off by default',
    (t) async {
      final s = Store(joined: false);
      await mount(
        t,
        SocialScreen(client: s.client),
        width: 390,
        theme: 'korlix_blue',
      );
      await fixtures.capture(t, 'social-welcome');
      await fixtures.tap(t, find.text('Create my Social profile'));
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'Alex');
      await t.enterText(fields.at(1), 'alex');
      final switches = t
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches[1].value, false);
      expect(s.calls.where((c) => c['action'] == 'save_profile'), isEmpty);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.byType(CheckboxListTile)),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await fixtures.tap(t, find.text('Create my Social profile').last);
      final saved = s.calls.singleWhere((c) => c['action'] == 'save_profile');
      expect(saved['accepted_rules'], true);
      expect(saved['show_online'], false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'accepting a request unlocks a conversation without sending a message',
    (t) async {
      final s = Store(incoming: true);
      await mount(
        t,
        SocialScreen(client: s.client),
        width: 390,
        theme: 'korlix_blue',
      );
      await fixtures.tap(t, find.text('Accept follow'));
      expect(s.accepted, true);
      expect(s.calls.where((c) => c['action'] == 'send'), isEmpty);
      await fixtures.tap(t, find.text('Message'));
      expect(find.textContaining('Say hello to'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Hi Jordan!');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(s.messages.single['body'], 'Hi Jordan!');
      expect(find.text('Hi Jordan!'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account change immediately removes loaded profiles and private messages',
    (t) async {
      final s = Store();
      s.accepted = true;
      await mount(t, SocialScreen(client: s.client), width: 390);
      await fixtures.tap(t, find.text('Message'));
      s.token = 'Bearer other-account';
      s.revision.value++;
      await t.pumpAndSettle();
      expect(find.textContaining('session changed'), findsOneWidget);
      expect(find.byTooltip('Send message'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Sign in to join the conversation.'), findsOneWidget);
      expect(find.text('Jordan Rivera'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'forum topic composer does not publish until the user taps publish',
    (t) async {
      final s = Store();
      await mount(
        t,
        SocialComposeTopic(
          client: s.client,
          categories: categories,
          category: 'sports',
        ),
        width: 320,
        scale: 1.3,
      );
      expect(s.calls, isEmpty);
      await t.enterText(find.byType(TextFormField).at(0), 'A new topic');
      await t.enterText(
        find.byType(TextFormField).at(1),
        'A thoughtful discussion.',
      );
      expect(t.takeException(), isNull);
      await fixtures.tap(t, find.text('Publish topic'));
      expect(s.calls.single['action'], 'create_topic');
      expect(s.calls.single['category'], 'sports');
      await t.pumpWidget(const SizedBox());
      s.client.dispose();
    },
  );
  testWidgets('discussion displays replies and publishes only submitted text', (
    t,
  ) async {
    final s = Store();
    await mount(
      t,
      SocialTopicScreen(
        client: s.client,
        me: me,
        id: 'topic',
        categories: categories,
      ),
      width: 390,
      theme: 'korlix_blue',
    );
    await fixtures.reveal(t, find.text('What makes a great team?'));
    expect(find.text('What makes a great team?'), findsOneWidget);
    await fixtures.capture(t, 'social-discussion');
    await fixtures.reveal(t, find.byType(TextField));
    await t.enterText(find.byType(TextField), 'A shared purpose.');
    await fixtures.tap(t, find.text('Publish reply'));
    expect(
      s.calls.singleWhere((c) => c['action'] == 'reply')['body'],
      'A shared purpose.',
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    s.client.dispose();
  });
  testWidgets('conversation layout fits a narrow screen', (t) async {
    final s = Store();
    s.messages.addAll([
      {
        'id': 'one',
        'seq': 1,
        'sender': 'peer',
        'body': 'Hi Alex! What are you working on?',
        'created_at': '2026-09-28T17:00:00Z',
        'deleted': false,
      },
      {
        'id': 'two',
        'seq': 2,
        'sender': 'me',
        'body': 'A new idea. Great to connect with you here.',
        'created_at': '2026-09-28T17:01:00Z',
        'read_at': '2026-09-28T17:01:01Z',
        'deleted': false,
      },
    ]);
    await mount(
      t,
      SocialChatScreen(client: s.client, me: me, peer: peer),
      width: 390,
      theme: 'korlix_blue',
    );
    await t.pumpAndSettle();
    await fixtures.capture(t, 'social-conversation');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    s.client.dispose();
  });
  testWidgets('failed requests show a retry state without fabricated members', (
    t,
  ) async {
    final c = SocialClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': 'Bearer sample'},
      client: MockClient(
        (_) async => http.Response('{"error":"Social is unavailable."}', 503),
      ),
    );
    await mount(t, SocialScreen(client: c), width: 390);
    await fixtures.reveal(t, find.text('Social is unavailable.'));
    expect(find.text('Social is unavailable.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Jordan Rivera'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
