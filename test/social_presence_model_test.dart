import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _PresenceFixture {
  _PresenceFixture({bool enablePresence = true}) {
    notifications = SocialNotifications(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': token},
      sessionChanges: revision,
      shouldPoll: () => visible,
      enableCalls: true,
      enablePresence: enablePresence,
      clientBuilder: () => SocialClient(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': token},
        sessionChanges: revision,
        client: MockClient((request) async {
          requests.add(request);
          final action = request.url.path.split('/').last;
          if (action == 'presence') {
            if (presenceResponse != null) return presenceResponse!(request);
            return http.Response(
              jsonEncode({'ok': true, 'show_online': true, 'online': true}),
              presenceStatus,
            );
          }
          return http.Response(
            jsonEncode(
              action == 'call_inbox'
                  ? {'call': call}
                  : {'items': action == 'connections' ? peers : []},
            ),
            200,
          );
        }),
      ),
    );
  }

  String token = 'Bearer first-account';
  bool visible = true;
  final revision = ValueNotifier(0);
  late final SocialNotifications notifications;
  final requests = <http.Request>[];
  List<SocialMap> peers = [];
  SocialMap? call;
  int presenceStatus = 200;
  Future<http.Response> Function(http.Request)? presenceResponse;

  List<http.Request> get presenceRequests => requests
      .where((request) => request.url.path.endsWith('/presence'))
      .toList();

  void dispose() {
    notifications.dispose();
    revision.dispose();
  }
}

SocialMap _peer(int unread) => {
  'id': 'friend',
  'name': 'Friend',
  'connection': 'accepted',
  'unread': unread,
};

void main() {
  test(
    'visibility is confirmed by server and failures do not invent offline',
    () async {
      final f = _PresenceFixture();
      addTearDown(f.dispose);
      await f.notifications.refreshPresence();
      expect(f.notifications.showOnline, true);
      expect(f.notifications.presenceOnline, true);
      f.presenceStatus = 503;
      await f.notifications.refreshPresence();
      expect(f.notifications.showOnline, true);
      expect(f.notifications.presenceOnline, isNull);
      expect(f.notifications.presenceFailed, true);
      await expectLater(
        f.notifications.setPresenceVisibility(false),
        throwsA(isA<SocialException>()),
      );
      expect(f.notifications.showOnline, true);
      expect(f.notifications.presenceChanging, false);
      f.presenceResponse = (request) async => http.Response(
        jsonEncode({'ok': true, 'show_online': false, 'online': false}),
        200,
      );
      await f.notifications.setPresenceVisibility(false);
      expect(f.notifications.showOnline, false);
      expect(f.notifications.presenceOnline, false);
      expect(f.notifications.presenceFailed, false);
      expect(jsonDecode(f.presenceRequests.last.body), {
        'active': true,
        'show_online': false,
      });
    },
  );

  test(
    'toggle waits for heartbeat and blocks overlap until server acknowledgement',
    () async {
      final f = _PresenceFixture();
      addTearDown(f.dispose);
      final heartbeat = Completer<http.Response>();
      final toggle = Completer<http.Response>();
      f.presenceResponse = (request) =>
          jsonDecode(request.body).containsKey('show_online')
          ? toggle.future
          : heartbeat.future;
      final pending = f.notifications.refreshPresence();
      final changing = f.notifications.setPresenceVisibility(false);
      await Future<void>.delayed(Duration.zero);
      expect(f.presenceRequests, hasLength(1));
      expect(f.notifications.presenceChanging, true);
      heartbeat.complete(
        http.Response('{"ok":true,"show_online":true,"online":true}', 200),
      );
      await pending;
      await Future<void>.delayed(Duration.zero);
      await f.notifications.refreshPresence();
      expect(f.presenceRequests, hasLength(2));
      toggle.complete(
        http.Response('{"ok":true,"show_online":false,"online":false}', 200),
      );
      await changing;
      expect(f.notifications.showOnline, false);
      expect(f.notifications.presenceChanging, false);
    },
  );

  test(
    'old-server success without status acknowledgement cannot confirm a toggle',
    () async {
      final f = _PresenceFixture();
      addTearDown(f.dispose);
      f.presenceResponse = (_) async => http.Response('{"ok":true}', 200);
      await expectLater(
        f.notifications.setPresenceVisibility(true),
        throwsStateError,
      );
      expect(f.notifications.showOnline, isNull);
      expect(f.notifications.presenceFailed, true);
    },
  );

  test(
    'late visibility response cannot change the replacement account',
    () async {
      final f = _PresenceFixture();
      addTearDown(f.dispose);
      final response = Completer<http.Response>();
      f.presenceResponse = (request) =>
          request.headers['authorization'] == 'Bearer first-account'
          ? response.future
          : Future.value(
              http.Response(
                '{"ok":true,"show_online":true,"online":true}',
                200,
              ),
            );
      final change = f.notifications.setPresenceVisibility(false);
      final rejected = expectLater(change, throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      f.token = 'Bearer replacement';
      f.revision.value++;
      await f.notifications.refreshPresence();
      response.complete(
        http.Response('{"ok":true,"show_online":false,"online":false}', 200),
      );
      await rejected;
      expect(f.notifications.showOnline, true);
      expect(f.notifications.presenceChanging, false);
    },
  );

  testWidgets('foreground presence refreshes every thirty seconds', (
    tester,
  ) async {
    final fixture = _PresenceFixture();
    await fixture.notifications.refreshPresence();
    expect(fixture.presenceRequests, hasLength(1));
    await tester.pump(const Duration(seconds: 29));
    expect(fixture.presenceRequests, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.presenceRequests, hasLength(2));
    await tester.pump(const Duration(seconds: 30));
    expect(fixture.presenceRequests, hasLength(3));
    for (final request in fixture.presenceRequests) {
      expect(request.method, 'POST');
      // Visibility remains a server-side profile privacy decision.
      expect(jsonDecode(request.body), {'active': true});
    }
    fixture.dispose();
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.presenceRequests, hasLength(3));
  });

  testWidgets('background stops presence and resume refreshes immediately', (
    tester,
  ) async {
    final fixture = _PresenceFixture();
    await fixture.notifications.refreshPresence();
    fixture.notifications.setForeground(false);
    await fixture.notifications.refreshPresence();
    await tester.pump(const Duration(seconds: 90));
    expect(fixture.presenceRequests, hasLength(1));

    fixture.notifications.setForeground(true);
    await fixture.notifications.refreshPresence();
    expect(fixture.presenceRequests, hasLength(2));
    expect(
      fixture.presenceRequests.map((request) => jsonDecode(request.body)),
      everyElement({'active': true}),
    );
    fixture.dispose();
  });

  testWidgets('application polling gate also suppresses presence', (
    tester,
  ) async {
    final fixture = _PresenceFixture()..visible = false;
    await fixture.notifications.refreshPresence();
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.presenceRequests, isEmpty);
    fixture.visible = true;
    await fixture.notifications.refreshPresence();
    expect(fixture.presenceRequests, hasLength(1));
    fixture.dispose();
  });

  testWidgets('presence opt-in is disabled for other model consumers', (
    tester,
  ) async {
    final fixture = _PresenceFixture(enablePresence: false);
    await fixture.notifications.refreshPresence();
    fixture.notifications.setForeground(true);
    fixture.token = 'Bearer second-account';
    fixture.revision.value++;
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.presenceRequests, isEmpty);
    fixture.dispose();
  });

  test(
    'simultaneous refreshes share one request and can retry after failure',
    () async {
      final fixture = _PresenceFixture();
      addTearDown(fixture.dispose);
      final pending = Completer<http.Response>();
      fixture.presenceResponse = (_) => pending.future;
      final first = fixture.notifications.refreshPresence();
      final second = fixture.notifications.refreshPresence();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.presenceRequests, hasLength(1));
      pending.complete(http.Response('{}', 503));
      await Future.wait([first, second]);
      fixture.presenceResponse = null;
      await fixture.notifications.refreshPresence();
      expect(fixture.presenceRequests, hasLength(2));
    },
  );

  test(
    'old session completion cannot release a new session heartbeat',
    () async {
      final fixture = _PresenceFixture();
      addTearDown(fixture.dispose);
      final oldResponse = Completer<http.Response>();
      final newResponse = Completer<http.Response>();
      fixture.presenceResponse = (request) =>
          request.headers['authorization'] == 'Bearer first-account'
          ? oldResponse.future
          : newResponse.future;
      final oldRequest = fixture.notifications.refreshPresence();
      fixture.token = 'Bearer second-account';
      fixture.revision.value++;
      final newRequest = fixture.notifications.refreshPresence();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.presenceRequests, hasLength(2));

      oldResponse.complete(http.Response('{}', 401));
      await oldRequest;
      final repeated = fixture.notifications.refreshPresence();
      expect(fixture.presenceRequests, hasLength(2));
      expect(fixture.notifications.available, isTrue);
      newResponse.complete(http.Response('{}', 200));
      await Future.wait([newRequest, repeated]);
      expect(
        fixture.presenceRequests.map(
          (request) => request.headers['authorization'],
        ),
        ['Bearer first-account', 'Bearer second-account'],
      );
    },
  );

  testWidgets('sign-out stops heartbeat without sending an offline override', (
    tester,
  ) async {
    final fixture = _PresenceFixture();
    await fixture.notifications.refreshPresence();
    fixture.token = '';
    fixture.revision.value++;
    await fixture.notifications.refreshPresence();
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.presenceRequests, hasLength(1));
    expect(jsonDecode(fixture.presenceRequests.single.body), {'active': true});
    expect(fixture.notifications.available, isFalse);
    fixture.dispose();
  });

  for (final status in [403, 503]) {
    test(
      'presence response $status preserves message and call alerts',
      () async {
        final fixture = _PresenceFixture();
        addTearDown(fixture.dispose);
        await fixture.notifications.refresh();
        fixture.peers = [_peer(2)];
        fixture.call = {
          'id': 'call',
          'state': 'ringing',
          'mode': 'audio',
          'created_at': DateTime.now().toIso8601String(),
          'peer': _peer(0),
        };
        await Future.wait([
          fixture.notifications.refresh(),
          fixture.notifications.refreshCalls(),
        ]);
        expect(fixture.notifications.messageAlert?.key, 'peer:friend');
        expect(fixture.notifications.incomingCall?['id'], 'call');
        fixture.presenceStatus = status;
        await fixture.notifications.refreshPresence();
        expect(fixture.notifications.totalUnread, 2);
        expect(fixture.notifications.messageAlert?.key, 'peer:friend');
        expect(fixture.notifications.incomingCall?['id'], 'call');
        expect(fixture.notifications.available, isTrue);
      },
    );
  }

  testWidgets('presence continues while a chat or call route is open', (
    tester,
  ) async {
    final fixture = _PresenceFixture();
    await fixture.notifications.refreshPresence();
    fixture.notifications.setActiveConversation('peer:friend');
    expect(fixture.notifications.beginCall(), isTrue);
    await tester.pump(const Duration(seconds: 30));
    expect(fixture.presenceRequests, hasLength(2));
    expect(fixture.notifications.callOpen, isTrue);
    expect(fixture.notifications.activeConversationKey, 'peer:friend');
    fixture.dispose();
  });
}
