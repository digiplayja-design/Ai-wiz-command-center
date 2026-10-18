import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/social/social_app_alerts.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:ai_wiz_command_center/social/social_push_platform.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _token(String session) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({
      'iss': 'https://auth.test', 'sub': 'me', 'session_id': session,
    }))).replaceAll('=', '')}.s';

class _NativePush extends SocialPushPlatform {
  final queue = <SocialMap>[];
  final owners = <String>[];
  void Function()? callback;
  Completer<SocialMap?>? waiting;
  Completer<void>? requested;
  @override bool get isNative => true;
  @override bool get supported => false;
  @override String get permission => 'default';
  @override bool get launchRequested => false;
  @override void onOpen(void Function()? value) => callback = value;
  @override Future<void> syncOwner(String owner) async => owners.add(owner);
  @override Future<SocialMap?> takeAction() async {
    if (waiting != null) {
      final next = waiting!;
      waiting = null;
      requested?.complete();
      return next.future;
    }
    return queue.isEmpty ? null : queue.removeAt(0);
  }
  @override Future<SocialMap?> current(String owner) async => null;
  @override Future<SocialMap> subscribe(String owner, String publicKey) async => {};
  @override Future<void> unsubscribe(String owner) async {}
}

class _Host {
  final push = _NativePush();
  final revision = ValueNotifier(0);
  final navigator = GlobalKey<NavigatorState>();
  final observer = RouteObserver<ModalRoute<dynamic>>();
  final sent = <SocialMap>[];
  final transports = <http.Client>[];
  String token = '';
  bool ready = false;
  late final notifications = SocialNotifications(
    baseUrl: 'https://api.test', headersBuilder: headers,
    sessionChanges: revision, shouldPoll: () => true,
    clientBuilder: client, interval: const Duration(days: 1),
  );

  Map<String, String> headers() => token.isEmpty ? {} : {'Authorization': 'Bearer $token'};

  SocialClient client() {
    final transport = MockClient((request) async {
      final name = request.url.pathSegments.last;
      SocialMap result = {};
      if (name == 'bootstrap') {
        result = {'profile': {'id': 'me', 'name': 'Alex', 'handle': 'alex'}, 'categories': []};
      } else if (name == 'messages') {
        final id = request.url.queryParameters['peer'];
        result = {'peer': {'id': id, 'name': id == 'peer-two' ? 'Taylor' : 'Jordan'}, 'items': []};
      } else if (name == 'member') {
        result = {'profile': {'id': 'me', 'name': 'Alex'}};
      } else if (name == 'send' || name == 'group_send') {
        sent.add(socialMap(jsonDecode(request.body)));
      }
      return http.Response(jsonEncode(result), 200);
    });
    transports.add(transport);
    return SocialClient(baseUrl: 'https://api.test', headersBuilder: headers,
      sessionChanges: revision, client: transport);
  }

  SocialMap action(String id, String requestId, {bool reply = false}) => {
    'type': reply ? 'reply' : 'open', 'kind': 'peer', 'id': id,
    'owner': socialPushOwner({'Authorization': 'Bearer ${_token('one')}'}),
    'requestId': requestId, if (reply) 'text': 'Reply from the old login',
  };

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator, navigatorObservers: [observer],
      theme: korlixBuildTheme('korlix_blue'),
      builder: (_, child) => SocialAppAlerts(
        baseUrl: 'https://api.test', headersBuilder: headers,
        sessionChanges: revision, sessionReady: () => ready,
        navigatorKey: navigator, routeObserver: observer,
        notifications: notifications, clientBuilder: client,
        pushPlatform: push, child: child!,
      ),
      home: const Scaffold(body: Text('Home')),
    ));
    await tester.pumpAndSettle();
  }

  void signIn(String session) {
    ready = true;
    token = _token(session);
    revision.value++;
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    notifications.dispose();
    revision.dispose();
    for (final transport in transports) { transport.close(); }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  testWidgets('cold-launch action waits until authentication is restored', (tester) async {
    final host = _Host();
    host.push.queue.add(host.action('peer-one', 'cold-open'));
    await host.mount(tester);
    expect(host.push.owners, isEmpty);
    expect(find.byType(SocialChatScreen), findsNothing);
    host.signIn('one');
    await tester.pumpAndSettle();
    expect(host.push.owners, isNotEmpty);
    expect(host.push.owners, isNot(contains('')));
    expect(find.byType(SocialChatScreen), findsOneWidget);
    expect(host.sent, isEmpty);
    await host.dispose(tester);
  });

  testWidgets('native event during an open route is drained after closing it', (tester) async {
    final host = _Host();
    host.signIn('one');
    host.push.queue.add(host.action('peer-one', 'first-open'));
    await host.mount(tester);
    expect(find.byType(SocialChatScreen), findsOneWidget);
    host.push.queue.add(host.action('peer-two', 'second-open'));
    host.push.callback!();
    await tester.pump();
    host.navigator.currentState!.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(find.byType(SocialChatScreen), findsOneWidget);
    final screen = tester.widget<SocialChatScreen>(find.byType(SocialChatScreen));
    expect(screen.peer['id'], 'peer-two');
    await host.dispose(tester);
  });

  testWidgets('same-owner login change while draining cannot send stale reply', (tester) async {
    final host = _Host();
    host.signIn('one');
    final waiting = Completer<SocialMap?>();
    host.push.waiting = waiting;
    host.push.requested = Completer<void>();
    await host.mount(tester);
    await host.push.requested!.future;
    host.token = '';
    host.revision.value++;
    host.signIn('two');
    waiting.complete(host.action('peer-one',
      '85734e4c-c260-4acc-a88d-b12acd985166', reply: true));
    await tester.pumpAndSettle();
    expect(host.sent, isEmpty);
    expect(find.byType(SocialChatScreen), findsNothing);
    await host.dispose(tester);
  });
}
