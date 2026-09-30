import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:ai_wiz_command_center/social/social_notification_banner.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';

class InboxFixture {
  String token = 'Bearer first-account';
  bool visible = true;
  final revision = ValueNotifier(0);
  final requests = <http.Request>[];
  List<SocialMap> peers = [], groups = [];
  int status = 200;
  Future<http.Response> Function(http.Request)? respond;
  late final notifications = SocialNotifications(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    shouldPoll: () => visible,
    clientBuilder: () => SocialClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': token},
      sessionChanges: revision,
      client: MockClient((request) async {
        requests.add(request);
        if (respond != null) return respond!(request);
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        final rows = request.url.path.endsWith('/groups') ? groups : peers;
        return http.Response(
          jsonEncode({'items': rows.skip(offset).take(41).toList()}),
          status,
        );
      }),
    ),
  );
  void dispose() {
    notifications.dispose();
    revision.dispose();
  }
}

SocialMap peer(String id, int unread) => {
  'id': id,
  'name': 'Person $id',
  'connection': 'accepted',
  'unread': unread,
};
SocialMap group(String id, int unread) => {
  'id': id,
  'name': 'Group $id',
  'state': 'accepted',
  'unread': unread,
};

void main() {
  for (final groupChat in [false, true]) {
    testWidgets(
      'notification routes into ${groupChat ? 'group' : 'private'} chat',
      (tester) async {
        final calls = <String>[];
        final destination = groupChat ? group('family', 2) : peer('friend', 2);
        final client = SocialClient(
          baseUrl: 'https://fixture.test',
          headersBuilder: () => {'Authorization': 'Bearer route-account'},
          client: MockClient((r) async {
            final action = r.url.path.split('/').last;
            calls.add(action);
            return http.Response(
              jsonEncode(
                action == 'bootstrap'
                    ? {
                        'profile': {'id': 'me', 'name': 'Me'},
                        'categories': [],
                      }
                    : {'items': [], 'peer': destination, 'group': destination},
              ),
              200,
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SocialScreen(
              client: client,
              initialConversation: destination,
              initialGroupChat: groupChat,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SocialChatScreen), findsOneWidget);
        expect(
          tester
              .widget<SocialChatScreen>(find.byType(SocialChatScreen))
              .groupChat,
          groupChat,
        );
        expect(calls, contains(groupChat ? 'group_messages' : 'messages'));
        expect(calls, isNot(contains('send')));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  test(
    'counts all private/group pages without counting look-ahead twice',
    () async {
      final f = InboxFixture();
      addTearDown(f.dispose);
      f.peers = [for (var i = 0; i < 43; i++) peer('$i', i == 42 ? 3 : 1)];
      f.groups = [
        group('family', 4),
        {...group('invite', 9), 'state': 'invited'},
      ];
      await f.notifications.refresh();
      expect(f.notifications.totalUnread, 49);
      expect(f.notifications.conversations.length, 44);
      expect(f.requests.map((r) => r.method), everyElement('GET'));
      expect(
        f.requests
            .where((r) => r.url.path.endsWith('/connections'))
            .map((r) => r.url.queryParameters['offset']),
        ['0', '40'],
      );
      f.peers = [];
      f.groups = [];
      await f.notifications.refresh();
      expect(f.notifications.totalUnread, 0);
    },
  );

  test('does not poll while hidden, resumes, and coalesces requests', () async {
    final f = InboxFixture();
    addTearDown(f.dispose);
    f.visible = false;
    await f.notifications.refresh();
    expect(f.requests, isEmpty);
    f.visible = true;
    f.notifications.setForeground(false);
    await f.notifications.refresh();
    expect(f.requests, isEmpty);
    f.peers = [peer('a', 2)];
    f.notifications.setForeground(true);
    await Future.wait([f.notifications.refresh(), f.notifications.refresh()]);
    expect(f.requests.length, 2);
    expect(f.notifications.totalUnread, 2);
  });

  test('temporary error retains counts; revoked access clears them', () async {
    final f = InboxFixture();
    addTearDown(f.dispose);
    f.peers = [peer('a', 2)];
    await f.notifications.refresh();
    f.status = 503;
    await f.notifications.refresh();
    expect(f.notifications.totalUnread, 2);
    f.status = 403;
    await f.notifications.refresh();
    expect(f.notifications.totalUnread, 0);
  });

  test('sign-out clears state and ignores an old in-flight response', () async {
    final f = InboxFixture();
    addTearDown(f.dispose);
    f.peers = [peer('a', 2)];
    await f.notifications.refresh();
    final delayed = Completer<http.Response>();
    f.respond = (_) => delayed.future;
    final oldRequest = f.notifications.refresh();
    f.token = '';
    f.revision.value++;
    expect(f.notifications.totalUnread, 0);
    delayed.complete(
      http.Response(
        jsonEncode({
          'items': [peer('old', 50)],
        }),
        200,
      ),
    );
    await oldRequest;
    expect(f.notifications.totalUnread, 0);
    f.respond = null;
    f.peers = [peer('new', 1)];
    f.token = 'Bearer second-account';
    f.revision.value++;
    await f.notifications.refresh();
    expect(f.notifications.totalUnread, 1);
    expect(f.notifications.conversations.single.card['id'], 'new');
  });

  testWidgets('home banner opens the unread conversation and hides when read', (
    tester,
  ) async {
    final f = InboxFixture();
    f.peers = [peer('a', 2)];
    await f.notifications.refresh();
    SocialUnreadConversation? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SocialNotificationBanner(
            notifications: f.notifications,
            onOpen: (item) async => opened = item,
          ),
        ),
      ),
    );
    expect(find.text('2 unread messages'), findsOneWidget);
    await tester.tap(find.text('KORLIX Social'));
    await tester.pump();
    expect(opened?.card['id'], 'a');
    expect(f.requests.map((r) => r.method), everyElement('GET'));
    f.peers = [];
    await f.notifications.refresh();
    await tester.pump();
    expect(find.text('KORLIX Social'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    f.dispose();
  });

  testWidgets('multiple chats open an inbox and route the selected group', (
    tester,
  ) async {
    final f = InboxFixture();
    f.peers = [peer('a', 2)];
    f.groups = [group('family', 3)];
    await f.notifications.refresh();
    SocialUnreadConversation? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SocialNotificationBanner(
            notifications: f.notifications,
            onOpen: (item) async => opened = item,
          ),
        ),
      ),
    );
    await tester.tap(find.text('KORLIX Social'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group family'));
    await tester.pumpAndSettle();
    expect(opened?.group, isTrue);
    expect(opened?.card['id'], 'family');
    await tester.pumpWidget(const SizedBox.shrink());
    f.dispose();
  });
}
