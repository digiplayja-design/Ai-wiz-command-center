import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/auth/korlix_token_store.dart';
import 'package:ai_wiz_command_center/social/social_bubble_app.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_floating_chat.dart';
import 'package:ai_wiz_command_center/social/social_push_platform.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _token({String user = 'me', String session = 'session-one', int exp = 2000}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
      'iss': 'https://auth.test', 'sub': user, 'session_id': session, 'exp': exp,
    }))).replaceAll('=', '')}.signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('korlix/social_native');
  late String token;
  late String owner;

  setUp(() {
    token = _token();
    owner = socialPushOwner({'Authorization': 'Bearer $token'});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  SocialBubbleSession session({Future<KorlixStoredTokens?> Function()? read}) =>
      SocialBubbleSession(
        owner: owner,
        now: () => DateTime.fromMillisecondsSinceEpoch(1000000),
        readTokens: read ?? () async => KorlixStoredTokens(accessToken: token),
      );

  test('only valid conversation routes can be opened', () {
    final valid = {'type': 'open', 'owner': owner, 'kind': 'peer', 'id': 'peer-one'};
    expect(SocialFloatingTarget.parse(valid)?.id, 'peer-one');
    expect(SocialFloatingTarget.parse({...valid, 'kind': 'group'})?.kind, 'group');
    for (final change in [
      {'type': 'reply'}, {'kind': 'url'}, {'id': '../admin'}, {'id': ''},
      {'owner': ''}, {'owner': '["issuer"]'}, {'owner': '["bad-url","me"]'},
      {'owner': '["https://auth.test",3]'},
    ]) {
      expect(SocialFloatingTarget.parse({...valid, ...change}), isNull);
    }
  });

  test('missing native channel degrades safely', () async {
    expect((await SocialFloatingChat.capabilities())['bubbles'], isFalse);
    expect(await SocialFloatingChat.launchTarget(), isNull);
    expect((await SocialFloatingChat.pin(
      SocialFloatingTarget(owner: owner, kind: 'peer', id: 'peer-one'), 'Peer',
    ))['status'], 'unsupported');
    await SocialFloatingChat.close();
    await SocialFloatingChat.openMain();
  });

  test('pin sends route identifiers but never credentials', () async {
    MethodCall? called;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      called = call;
      return {'status': 'shown'};
    });
    final target = SocialFloatingTarget(owner: owner, kind: 'group', id: 'group-one');
    expect((await SocialFloatingChat.pin(target, 'Weekend'))['status'], 'shown');
    expect(called!.method, 'pin');
    expect(called!.arguments, {
      'owner': owner, 'kind': 'group', 'id': 'group-one', 'title': 'Weekend',
    });
    expect(jsonEncode(called!.arguments), isNot(contains(token)));
  });

  test('iOS does not request an unsupported overlay', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async { calls++; return {}; });
    expect((await SocialFloatingChat.capabilities())['bubbles'], isFalse);
    expect((await SocialFloatingChat.pin(
      SocialFloatingTarget(owner: owner, kind: 'peer', id: 'peer-one'), 'Peer',
    ))['status'], 'unsupported');
    expect(calls, 0);
  });

  test('fresh token rotation in the same login is allowed', () async {
    final guard = session();
    expect(await guard.authorize(), token);
    token = _token(exp: 3000);
    expect(await guard.authorize(), token);
    expect(guard.headers['Authorization'], 'Bearer $token');
    guard.dispose();
  });

  test('account change invalidates the bubble before sending', () async {
    final guard = session();
    await guard.authorize();
    token = _token(user: 'another-member');
    await expectLater(guard.authorize(), throwsA(isA<SocialException>()));
    expect(guard.valid, isFalse);
    expect(guard.headers, isEmpty);
    guard.dispose();
  });

  test('same-account new login cannot reuse an open bubble', () async {
    final guard = session();
    await guard.authorize();
    token = _token(session: 'new-login');
    await expectLater(guard.authorize(), throwsA(isA<SocialException>()));
    expect(guard.valid, isFalse);
    guard.dispose();
  });

  test('expired tokens require main-app sign in without refresh', () async {
    token = _token(exp: 1000);
    final guard = session();
    await expectLater(guard.authorize(), throwsA(isA<SocialException>()));
    expect(guard.headers, isEmpty);
    guard.dispose();
  });

  test('missing session or secure-store failures do not leak token errors', () async {
    final guards = [
      session(read: () async => null),
      session(read: () async => throw StateError('secret-fixture')),
      session(read: () async => const KorlixStoredTokens(accessToken: 'invalid-private-token')),
    ];
    for (final guard in guards) {
      await expectLater(guard.authorize(), throwsA(
        isA<SocialException>().having((e) => e.message, 'message',
          'Open KORLIX to sign in, then reopen this floating chat.'),
      ));
      guard.dispose();
    }
  });

  test('transport reloads credentials instead of reusing stale request header', () async {
    final guard = session();
    await guard.authorize();
    token = _token(exp: 3000);
    final transport = SocialBubbleHttpClient(
      session: guard, baseUrl: 'https://api.test',
      inner: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer $token');
        return http.Response('{}', 200);
      }),
    );
    final request = http.Request('GET', Uri.parse('https://api.test/api/social/bootstrap'))
      ..headers['Authorization'] = 'Bearer stale';
    expect((await transport.send(request)).statusCode, 200);
    transport.close();
    guard.dispose();
  });

  test('late response after logout is discarded', () async {
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    KorlixStoredTokens? stored = KorlixStoredTokens(accessToken: token);
    final guard = session(read: () async => stored);
    final transport = SocialBubbleHttpClient(
      session: guard, baseUrl: 'https://api.test',
      inner: MockClient((_) {
        requested.complete();
        return response.future;
      }),
    );
    final request = transport.get(Uri.parse('https://api.test/api/social/messages'));
    final checked = expectLater(request, throwsA(isA<SocialException>()));
    await requested.future;
    stored = null;
    response.complete(http.Response('{"items":[{"body":"private"}]}', 200));
    await checked;
    expect(guard.valid, isFalse);
    transport.close();
    guard.dispose();
  });

  test('transport never attaches credentials to another origin or non-Social API', () async {
    var sent = 0;
    final guard = session();
    final transport = SocialBubbleHttpClient(
      session: guard, baseUrl: 'https://api.test',
      inner: MockClient((_) async { sent++; return http.Response('{}', 200); }),
    );
    for (final url in ['https://other.test/api/social/messages', 'https://api.test/admin']) {
      await expectLater(transport.get(Uri.parse(url)), throwsA(isA<SocialException>()));
    }
    expect(sent, 0);
    transport.close();
    guard.dispose();
  });

  testWidgets('bubble chat exposes no call, microphone or second pin action', (tester) async {
    final transport = MockClient((request) async => http.Response(jsonEncode(
      request.url.path.endsWith('/messages')
          ? {'peer': {'id': 'peer-one', 'name': 'Jordan'}, 'items': []}
          : {},
    ), 200));
    final client = SocialClient(
      baseUrl: 'https://api.test',
      headersBuilder: () => {'Authorization': 'Bearer $token'},
      client: transport,
    );
    await tester.pumpWidget(MaterialApp(
      theme: korlixBuildTheme('korlix_blue'),
      home: SocialChatScreen(
        client: client,
        me: const {'id': 'me', 'name': 'Alex'},
        peer: const {'id': 'peer-one', 'name': 'Jordan'},
        bubbleMode: true,
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('keep-chat-floating')), findsNothing);
    expect(find.text('Voice note'), findsNothing);
    expect(find.byTooltip('Start a call'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
    transport.close();
  });
}
