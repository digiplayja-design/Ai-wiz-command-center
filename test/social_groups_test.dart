import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_groups.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'social_test.dart' as social;
import 'social_replies_test.dart' as replies;
import 'agent_studio_test.dart' as fixtures;

final casey = <String, dynamic>{
  ...social.peer,
  'id': 'casey',
  'name': 'Casey Lee',
  'handle': 'casey',
  'color': 'mint',
};

class Groups {
  final calls = <SocialMap>[];
  final revision = ValueNotifier(0);
  String token = 'Bearer first';
  bool failCreate = false, denied = false, invited = false;
  List<String> hidden = [];
  SocialMap group = {
    'id': 'group',
    'name': 'Weekend circle',
    'owner': 'me',
    'is_owner': true,
    'state': 'accepted',
    'member_count': 3,
    'invited_count': 0,
    'unread': 1,
  };
  final messages = <SocialMap>[
    {
      ...replies.message('first', 1, 'Saturday or Sunday?'),
      'author': social.peer,
    },
    {
      ...replies.message('second', 2, 'Sunday works for me!', sender: 'casey'),
      'author': casey,
    },
  ];
  SocialMap card(SocialMap m) {
    if (m['reply_to'] == null) return m;
    return {
      ...m,
      'reply': messages.firstWhere((x) => x['id'] == m['reply_to']),
    };
  }

  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.path.split('/').last,
          data = r.method == 'POST'
              ? socialMap(jsonDecode(r.body))
              : r.url.queryParameters;
      calls.add({'action': action, ...data});
      SocialMap result = {};
      var status = 200;
      if (action == 'bootstrap') {
        result = {
          'profile': social.me,
          'categories': social.categories,
          'moderator': false,
        };
      }
      if (action == 'connections') {
        final q = '${data['q'] ?? ''}'.toLowerCase();
        result = {
          'items': [
            for (final p in [social.peer, casey])
              if ('${p['name']}'.toLowerCase().contains(q))
                {...p, 'connection': 'accepted'},
          ],
        };
      }
      if (action == 'groups') {
        result = {
          'items': [
            {...group, if (invited) 'state': 'invited'},
          ],
        };
      }
      if (action == 'group_create') {
        if (failCreate) {
          status = 503;
          result = {'error': 'Please retry. Your selections are saved.'};
        } else {
          group = {...group, 'id': data['group'], 'name': data['name']};
          result = {'group': group};
        }
      }
      if (action == 'group_accept') {
        invited = false;
        result = {'group': group};
      }
      if (action == 'group_rename') group = {...group, 'name': data['name']};
      if (action == 'group_details') {
        result = {
          'group': group,
          'members': [
            {'profile': social.me, 'is_owner': true, 'state': 'accepted'},
            {'profile': social.peer, 'is_owner': false, 'state': 'accepted'},
            {'profile': casey, 'is_owner': false, 'state': 'invited'},
          ],
        };
      }
      if (action == 'group_messages') {
        if (denied) {
          status = 403;
          result = {'error': 'This group is unavailable.'};
        } else {
          result = {
            'peer': group,
            'items': messages.map(card).toList(),
            'hidden_senders': hidden,
          };
        }
      }
      if (action == 'group_send') {
        messages.add({
          ...replies.message(
            '${data['id']}',
            messages.length + 1,
            '${data['body']}',
            sender: 'me',
          ),
          'author': social.me,
          'reply_to': data['reply_to'],
        });
        result = {'id': data['id']};
      }
      if (action == 'group_message') {
        result = {'message': messages.firstWhere((m) => m['id'] == data['id'])};
      }
      return http.Response(
        jsonEncode(result),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  void changeAccount() {
    token = 'Bearer another';
    revision.value++;
  }
}

Future<void> openPicker(
  WidgetTester t,
  Groups g, {
  double width = 390,
  double scale = 1,
}) async {
  await social.mount(
    t,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SocialGroupInvite(client: g.client),
              ),
            ),
            child: const Text('Start'),
          ),
        ),
      ),
    ),
    width: width,
    scale: scale,
  );
  await replies.tap(t, find.text('Start'));
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
  testWidgets(
    'multiple selections survive search and submit one group invitation batch',
    (t) async {
      final g = Groups();
      await openPicker(t, g);
      await t.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'Friends & family',
      );
      await replies.tap(t, find.byKey(const ValueKey('invite-peer')));
      await t.enterText(
        find.widgetWithText(TextField, 'Search your connections'),
        'Casey',
      );
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await replies.tap(t, find.byKey(const ValueKey('invite-casey')));
      expect(g.calls.where((c) => c['action'] == 'group_create'), isEmpty);
      await replies.tap(t, find.text('Create & invite (2)'));
      final sent = g.calls.singleWhere((c) => c['action'] == 'group_create');
      expect(sent['members'], ['casey', 'peer']);
      expect(sent['name'], 'Friends & family');
      expect(find.text('Start'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('failed creation keeps selections and retries with the same ID', (
    t,
  ) async {
    final g = Groups()..failCreate = true;
    await openPicker(t, g);
    await t.enterText(
      find.widgetWithText(TextField, 'Group name'),
      'Our group',
    );
    await replies.tap(t, find.byKey(const ValueKey('invite-peer')));
    await replies.tap(t, find.byKey(const ValueKey('invite-casey')));
    await replies.tap(t, find.text('Create & invite (2)'));
    expect(find.text('Create & invite (2)'), findsOneWidget);
    await replies.tap(t, find.text('Create & invite (2)'));
    final sent = g.calls.where((c) => c['action'] == 'group_create').toList();
    expect(sent[0]['group'], sent[1]['group']);
    g.changeAccount();
    await t.pumpAndSettle();
    expect(find.text('Our group'), findsNothing);
    expect(find.text('Casey Lee'), findsNothing);
    expect(find.text('Create & invite (2)'), findsNothing);
  });
  testWidgets(
    'Groups navigation accepts an invitation and opens the shared conversation',
    (t) async {
      final g = Groups()..invited = true;
      await social.mount(t, SocialScreen(client: g.client));
      await t.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is NavigationDestination && widget.label == 'Groups',
        ),
      );
      await t.pumpAndSettle();
      expect(g.calls.any((call) => call['action'] == 'groups'), true);
      await fixtures.reveal(t, find.text('GROUP INVITATION'));
      expect(find.text('GROUP INVITATION'), findsOneWidget);
      await replies.tap(t, find.text('Accept invitation'));
      expect(find.byType(SocialChatScreen), findsOneWidget);
      expect(g.calls.where((c) => c['action'] == 'group_accept').length, 1);
      expect(find.text('Weekend circle'), findsOneWidget);
      expect(find.byTooltip('Start a call'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'group replies identify each sender and use group-only endpoints',
    (t) async {
      final g = Groups();
      await social.mount(
        t,
        SocialChatScreen(
          client: g.client,
          me: social.me,
          peer: g.group,
          groupChat: true,
        ),
      );
      expect(find.text('Casey Lee'), findsOneWidget);
      expect(find.text('Jordan Rivera'), findsOneWidget);
      await replies.tap(t, find.byKey(const ValueKey('reply-second')));
      expect(find.text('Replying to Casey Lee'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Count me in 👍');
      await replies.tap(t, find.byTooltip('Send message'));
      final sent = g.calls.singleWhere((c) => c['action'] == 'group_send');
      expect(sent['group'], 'group');
      expect(sent['reply_to'], 'second');
      expect(sent.containsKey('peer'), false);
      await replies.tap(t, find.byKey(ValueKey('quote-${sent['id']}')));
      expect(
        g.calls.lastWhere((c) => c['action'] == 'group_message')['group'],
        'group',
      );
      expect(find.text('Original message'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'membership revocation clears loaded messages and reply drafts on refresh',
    (t) async {
      final g = Groups();
      await social.mount(
        t,
        SocialChatScreen(
          client: g.client,
          me: social.me,
          peer: g.group,
          groupChat: true,
        ),
      );
      await replies.tap(t, find.byKey(const ValueKey('reply-first')));
      await t.enterText(find.byType(TextField), 'Private draft');
      g.denied = true;
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('Saturday or Sunday?'), findsNothing);
      expect(find.text('Private draft'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets(
    'blocked sender refresh redacts loaded messages and selected reply',
    (t) async {
      final g = Groups();
      await social.mount(
        t,
        SocialChatScreen(
          client: g.client,
          me: social.me,
          peer: g.group,
          groupChat: true,
        ),
      );
      await replies.tap(t, find.byKey(const ValueKey('reply-first')));
      g.hidden = ['peer'];
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('Saturday or Sunday?'), findsNothing);
      expect(find.text('Replying to Jordan Rivera'), findsNothing);
      expect(find.text('Sunday works for me!'), findsOneWidget);
    },
  );
  testWidgets(
    'owner sees membership controls, nonowners see leave, and sessions clear roster',
    (t) async {
      final g = Groups();
      await social.mount(
        t,
        SocialGroupDetails(client: g.client, group: g.group),
      );
      expect(find.text('Invite people'), findsOneWidget);
      expect(find.byTooltip('Remove member'), findsOneWidget);
      expect(find.byTooltip('Cancel invitation'), findsOneWidget);
      await replies.tap(t, find.text('Rename group'));
      await t.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'Sunday crew',
      );
      await replies.tap(t, find.text('Save name'));
      expect(
        g.calls.singleWhere((c) => c['action'] == 'group_rename')['name'],
        'Sunday crew',
      );
      g.group = {...g.group, 'is_owner': false};
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Invite people'), findsNothing);
      expect(find.text('Leave group'), findsOneWidget);
      g.changeAccount();
      await t.pumpAndSettle();
      expect(find.text('Sunday crew'), findsNothing);
      expect(find.text('Casey Lee'), findsNothing);
    },
  );
  for (final size in [(320.0, 1.35), (390.0, 1.0), (1280.0, 1.0)]) {
    testWidgets('group invitation layout ${size.$1} text scale ${size.$2}', (
      t,
    ) async {
      final g = Groups();
      await openPicker(t, g, width: size.$1, scale: size.$2);
      await t.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'The creative circle',
      );
      await replies.tap(t, find.byKey(const ValueKey('invite-peer')));
      await replies.tap(t, find.byKey(const ValueKey('invite-casey')));
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-group-picker-${size.$1.toInt()}');
    });
  }
  testWidgets('group list and details fit narrow screens with larger text', (
    t,
  ) async {
    final g = Groups();
    await social.mount(
      t,
      SocialScreen(client: g.client),
      width: 320,
      scale: 1.35,
    );
    await replies.tap(t, find.text('Groups'));
    expect(t.takeException(), isNull);
    await fixtures.capture(t, 'social-groups-320');
    await replies.tap(t, find.text('Open group'));
    await replies.tap(t, find.byTooltip('Group details'));
    expect(find.byType(SocialGroupDetails), findsOneWidget);
    expect(t.takeException(), isNull);
    await fixtures.capture(t, 'social-group-details-320');
  });
}
