import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_alert_scope.dart';
import 'package:ai_wiz_command_center/social/social_call_screen.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

const _me = <String, dynamic>{'id': 'me', 'name': 'Alex', 'handle': 'alex'};
const _peer = <String, dynamic>{
  'id': 'friend',
  'name': 'Jordan',
  'handle': 'jordan',
  'connection': 'accepted',
  'color': 'cyan',
};

class _RoutesFixture {
  String token = 'Bearer first-account';
  final revision = ValueNotifier(0);
  final requests = <String>[];
  final observer = RouteObserver<ModalRoute<dynamic>>();
  final navigator = GlobalKey<NavigatorState>();
  late final notifications = SocialNotifications(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    shouldPoll: () => false,
    clientBuilder: makeClient,
  );

  SocialClient makeClient() => SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((request) async {
      final action = request.url.path.split('/').last;
      requests.add(action);
      return http.Response(
        jsonEncode(
          action == 'bootstrap'
              ? {'profile': _me, 'categories': []}
              : {'items': [], 'peer': _peer, 'group': _peer},
        ),
        200,
      );
    }),
  );

  Widget app(Widget home, {bool global = true}) => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [observer],
    theme: korlixBuildTheme('pure_black'),
    builder: (context, child) => global
        ? SocialAlertScope(
            notifications: notifications,
            routeObserver: observer,
            child: child!,
          )
        : child!,
    home: home,
  );

  void dispose() {
    notifications.dispose();
    revision.dispose();
  }
}

void main() {
  for (final group in [false, true]) {
    testWidgets(
      '${group ? 'group' : 'private'} chat suppresses only while its route is visible',
      (tester) async {
        final f = _RoutesFixture();
        final client = f.makeClient();
        final key = '${group ? 'group' : 'peer'}:friend';
        await tester.pumpWidget(
          f.app(
            SocialChatScreen(
              client: client,
              me: _me,
              peer: _peer,
              groupChat: group,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(f.notifications.activeConversationKey, key);

        unawaited(
          f.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Another app screen')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(f.notifications.activeConversationKey, isNull);

        f.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(f.notifications.activeConversationKey, key);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(f.notifications.activeConversationKey, isNull);
        client.dispose();
        f.dispose();
      },
    );
  }

  for (final other in ['other-friend', 'friend']) {
    testWidgets(
      'returning from stacked $other chat restores the visible conversation',
      (tester) async {
        final f = _RoutesFixture();
        final client = f.makeClient();
        await tester.pumpWidget(
          f.app(SocialChatScreen(client: client, me: _me, peer: _peer)),
        );
        await tester.pumpAndSettle();
        unawaited(
          f.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => SocialChatScreen(
                client: client,
                me: _me,
                peer: {..._peer, 'id': other},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(f.notifications.activeConversationKey, 'peer:$other');
        f.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(f.notifications.activeConversationKey, 'peer:friend');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        client.dispose();
        f.dispose();
      },
    );
  }

  testWidgets('old route cleanup cannot clear a new account conversation', (
    tester,
  ) async {
    final f = _RoutesFixture();
    final client = f.makeClient();
    await tester.pumpWidget(
      f.app(SocialChatScreen(client: client, me: _me, peer: _peer)),
    );
    await tester.pumpAndSettle();
    expect(f.notifications.activeConversationKey, 'peer:friend');
    f.token = 'Bearer second-account';
    f.revision.value++;
    f.notifications.setActiveConversation('peer:friend');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(f.notifications.activeConversationKey, 'peer:friend');
    expect(tester.takeException(), isNull);
    client.dispose();
    f.dispose();
  });

  for (final global in [false, true]) {
    testWidgets(
      'Social ${global ? 'uses the app receiver' : 'retains its standalone call poll'}',
      (tester) async {
        final f = _RoutesFixture();
        await tester.pumpWidget(
          f.app(SocialScreen(client: f.makeClient()), global: global),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(f.requests.contains('call_inbox'), !global);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        f.dispose();
      },
    );
  }

  testWidgets('an app-wide call prevents a second call from Social chat', (
    tester,
  ) async {
    final f = _RoutesFixture();
    expect(f.notifications.beginCall(), true);
    await tester.pumpWidget(
      f.app(SocialScreen(client: f.makeClient(), initialConversation: _peer)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SocialChatScreen), findsOneWidget);
    await tester.tap(find.text('Audio call'));
    await tester.pumpAndSettle();
    expect(find.byType(SocialCallScreen), findsNothing);
    expect(f.requests, isNot(contains('call_create')));
    expect(f.notifications.callOpen, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    f.dispose();
  });
}
