import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_native_actions.dart';
import 'package:ai_wiz_command_center/social/social_push_native.dart';
import 'package:ai_wiz_command_center/social/social_push_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _token({String user = 'member-one', String session = 'session-one'}) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({
      'iss': 'https://auth.test', 'sub': user, 'session_id': session,
    }))).replaceAll('=', '')}.s';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const requestId = '21cbd1c7-e136-4ada-a990-5b7ab3caea28';
  const channel = MethodChannel('korlix/social_native');
  late String token, owner;

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

  SocialMap action({String type = 'reply', String kind = 'peer'}) => {
    'type': type, 'owner': owner, 'kind': kind, 'id': 'target-one',
    'requestId': requestId, if (type == 'reply') 'text': '  Hello from my notification  ',
  };

  test('native actions reject other owners, invalid routes and malformed replies', () {
    expect(SocialNativeAction.parse(action(), owner)?.reply,
      'Hello from my notification');
    expect(SocialNativeAction.parse(action(type: 'open'), owner)?.reply, isNull);
    for (final change in [
      {'owner': 'another-owner'}, {'kind': 'url'}, {'type': 'execute'},
      {'id': '../../admin'}, {'id': ''}, {'requestId': ''},
      {'requestId': 'not-an-idempotency-uuid'}, {'text': '   '},
      {'text': List.filled(2001, 'x').join()},
    ]) {
      expect(SocialNativeAction.parse({...action(), ...change}, owner), isNull);
    }
    expect(SocialNativeAction.parse(action(), ''), isNull);
  });

  test('normal notification open action never sends a reply', () async {
    var sends = 0;
    final transport = MockClient((_) async { sends++; return http.Response('{}', 200); });
    final client = SocialClient(baseUrl: 'https://api.test',
      headersBuilder: () => {'Authorization': 'Bearer $token'}, client: transport);
    final open = SocialNativeAction.parse(action(type: 'open'), owner)!;
    await expectLater(open.send(client), throwsA(isA<SocialException>()));
    expect(sends, 0);
    client.dispose();
    transport.close();
  });

  test('reply retries preserve backend idempotency ID and target', () async {
    final bodies = <SocialMap>[];
    final paths = <String>[];
    final transport = MockClient((request) async {
      paths.add(request.url.path);
      bodies.add(socialMap(jsonDecode(request.body)));
      return http.Response(bodies.length == 1 ? '{"error":"retry"}' : '{}',
        bodies.length == 1 ? 503 : 200);
    });
    final client = SocialClient(baseUrl: 'https://api.test',
      headersBuilder: () => {'Authorization': 'Bearer $token'}, client: transport);
    final reply = SocialNativeAction.parse(action(kind: 'group'), owner)!;
    await expectLater(reply.send(client), throwsA(isA<SocialException>()));
    await reply.send(client);
    expect(paths, ['/api/social/group_send', '/api/social/group_send']);
    expect(bodies, [
      {'id': requestId, 'group': 'target-one', 'body': 'Hello from my notification'},
      {'id': requestId, 'group': 'target-one', 'body': 'Hello from my notification'},
    ]);
    client.dispose();
    transport.close();
  });

  test('reply rejects owner mismatch before issuing a request', () async {
    var sent = 0;
    final reply = SocialNativeAction.parse(action(), owner)!;
    token = _token(user: 'another-member');
    final transport = MockClient((_) async { sent++; return http.Response('{}', 200); });
    final client = SocialClient(baseUrl: 'https://api.test',
      headersBuilder: () => {'Authorization': 'Bearer $token'}, client: transport);
    await expectLater(reply.send(client), throwsA(isA<SocialException>()));
    expect(sent, 0);
    client.dispose();
    transport.close();
  });

  test('same-owner new login invalidates the already-created reply client', () async {
    var sent = 0;
    final transport = MockClient((_) async { sent++; return http.Response('{}', 200); });
    final client = SocialClient(baseUrl: 'https://api.test',
      headersBuilder: () => {'Authorization': 'Bearer $token'}, client: transport);
    final reply = SocialNativeAction.parse(action(), owner)!;
    token = _token(session: 'new-login');
    await expectLater(reply.send(client), throwsA(isA<SocialException>()));
    expect(sent, 0);
    client.dispose();
    transport.close();
  });

  test('reply result cannot survive logout while sending', () async {
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final transport = MockClient((_) {
      requested.complete();
      return response.future;
    });
    final client = SocialClient(baseUrl: 'https://api.test',
      headersBuilder: () => {'Authorization': 'Bearer $token'}, client: transport);
    final reply = SocialNativeAction.parse(action(), owner)!;
    final checked = expectLater(reply.send(client), throwsA(isA<SocialException>()));
    await requested.future;
    token = '';
    response.complete(http.Response('{}', 200));
    await checked;
    expect(client.available, isFalse);
    client.dispose();
    transport.close();
  });

  test('queued native owner transitions never skip a rapid logout', () async {
    final activations = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'activate') {
        activations.add('${call.arguments['owner']}');
        return true;
      }
      return {'push': true, 'provider': 'fcm', 'permission': 'granted'};
    });
    final platform = NativeSocialPushPlatform();
    await platform.syncOwner(owner);
    activations.clear();
    final logout = platform.syncOwner('');
    final login = platform.syncOwner(owner);
    await Future.wait([logout, login]);
    expect(activations, ['', owner]);
    platform.onOpen(null);
  });

  test('a native action arriving after an owner switch is discarded', () async {
    final pending = Completer<SocialMap>();
    final requested = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'activate') return true;
      if (call.method == 'takeEvent') {
        requested.complete();
        return pending.future;
      }
      return {'push': true};
    });
    final platform = NativeSocialPushPlatform();
    await platform.syncOwner(owner);
    final taking = platform.takeAction();
    await requested.future;
    await platform.syncOwner('different-owner');
    pending.complete(action());
    expect(await taking, isNull);
    platform.onOpen(null);
  });
}
