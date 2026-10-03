import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Fixture {
  _Fixture({bool enableCalls = true}) {
    notifications = SocialNotifications(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': token},
      sessionChanges: revision,
      shouldPoll: () => visible,
      enableCalls: enableCalls,
      clientBuilder: () => SocialClient(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': token},
        sessionChanges: revision,
        client: MockClient((request) async {
          requests.add(request);
          if (respond != null) return respond!(request);
          final action = request.url.path.split('/').last;
          return http.Response(
            jsonEncode(
              action == 'call_inbox'
                  ? {'call': call}
                  : {'items': action == 'groups' ? groups : peers},
            ),
            status,
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
  List<SocialMap> peers = [], groups = [];
  SocialMap? call;
  int status = 200;
  Future<http.Response> Function(http.Request)? respond;
  void dispose() {
    notifications.dispose();
    revision.dispose();
  }
}

SocialMap _peer(String id, int unread) => {
  'id': id,
  'name': 'Person $id',
  'connection': 'accepted',
  'unread': unread,
};
SocialMap _group(String id, int unread) => {
  'id': id,
  'name': 'Group $id',
  'state': 'accepted',
  'unread': unread,
};
SocialMap _call(String id, {int age = 0, String state = 'ringing'}) => {
  'id': id,
  'state': state,
  'mode': 'audio',
  'incoming': true,
  'created_at': DateTime.now()
      .subtract(Duration(seconds: age))
      .toIso8601String(),
  'peer': {'id': 'friend', 'name': 'Friend'},
};

void main() {
  test(
    'initial unread is silent; only later increases produce a new alert',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.peers = [_peer('a', 4)];
      f.groups = [_group('family', 2)];
      await f.notifications.refresh();
      expect(f.notifications.totalUnread, 6);
      expect(f.notifications.messageAlert, isNull);
      expect(f.notifications.messageRevision, 0);

      f.peers = [_peer('a', 5)];
      await f.notifications.refresh();
      expect(f.notifications.messageAlert?.key, 'peer:a');
      expect(f.notifications.messageRevision, 1);
      await f.notifications.refresh();
      expect(f.notifications.messageRevision, 1);
      f.notifications.dismissMessage();
      await f.notifications.refresh();
      expect(f.notifications.messageAlert, isNull);

      f.groups = [_group('family', 3)];
      await f.notifications.refresh();
      expect(f.notifications.messageAlert?.key, 'group:family');
      expect(f.notifications.messageRevision, 2);
      f.groups = [];
      await f.notifications.refresh();
      expect(f.notifications.messageAlert, isNull);
    },
  );

  test(
    'individual conversation increase alerts even when total decreases',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.peers = [_peer('a', 10), _peer('b', 1)];
      await f.notifications.refresh();
      f.peers = [_peer('a', 0), _peer('b', 2)];
      await f.notifications.refresh();
      expect(f.notifications.totalUnread, 2);
      expect(f.notifications.messageAlert?.key, 'peer:b');
      f.peers = [_peer('b', 0)];
      await f.notifications.refresh();
      expect(f.notifications.messageAlert, isNull);
    },
  );

  test(
    'visible conversation suppresses alerts without deferring duplicates',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.notifications.refresh();
      f.notifications.setActiveConversation('peer:a');
      f.peers = [_peer('a', 1)];
      await f.notifications.refresh();
      expect(f.notifications.messageAlert, isNull);
      f.notifications.setActiveConversation(null);
      await f.notifications.refresh();
      expect(f.notifications.messageAlert, isNull);
      f.peers = [_peer('a', 2)];
      await f.notifications.refresh();
      expect(f.notifications.messageAlert?.key, 'peer:a');
      f.notifications.setActiveConversation('peer:a');
      expect(f.notifications.messageAlert, isNull);
      expect(f.notifications.activeConversationKey, 'peer:a');
    },
  );

  test(
    'background clears alerts and ignores pending message and call loads',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.notifications.refresh();
      f.peers = [_peer('a', 1)];
      f.call = _call('first');
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      expect(f.notifications.messageAlert, isNotNull);
      expect(f.notifications.incomingCall, isNotNull);
      final messages = Completer<http.Response>();
      final calls = Completer<http.Response>();
      f.respond = (r) =>
          r.url.path.endsWith('/call_inbox') ? calls.future : messages.future;
      final pending = Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      f.notifications.setForeground(false);
      expect(f.notifications.messageAlert, isNull);
      expect(f.notifications.incomingCall, isNull);
      calls.complete(http.Response(jsonEncode({'call': _call('late')}), 200));
      messages.complete(
        http.Response(
          jsonEncode({
            'items': [_peer('a', 9)],
          }),
          200,
        ),
      );
      await pending;
      expect(f.notifications.totalUnread, 1);
      expect(f.notifications.messageAlert, isNull);
      expect(f.notifications.incomingCall, isNull);
      final count = f.requests.length;
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      expect(f.requests.length, count);
      f.respond = null;
      f.peers = [_peer('a', 2)];
      f.call = null;
      f.notifications.setForeground(true);
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      expect(f.notifications.messageAlert?.unread, 2);
    },
  );

  test(
    'shouldPoll suppresses in-flight responses and further requests',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.notifications.refresh();
      final response = Completer<http.Response>();
      f.respond = (_) => response.future;
      final request = f.notifications.refresh();
      f.visible = false;
      response.complete(
        http.Response(
          jsonEncode({
            'items': [_peer('a', 5)],
          }),
          200,
        ),
      );
      await request;
      expect(f.notifications.totalUnread, 0);
      expect(f.notifications.messageAlert, isNull);
      final count = f.requests.length;
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      expect(f.requests.length, count);
    },
  );

  test(
    'calls use one session device and deduplicate repeated inbox results',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.call = _call('one');
      await f.notifications.refreshCalls();
      expect(f.notifications.incomingCall?['id'], 'one');
      expect(f.notifications.callRevision, 1);
      await f.notifications.refreshCalls();
      expect(f.notifications.callRevision, 1);
      f.call = null;
      await f.notifications.refreshCalls();
      expect(f.notifications.incomingCall, isNull);
      f.call = _call('two');
      await f.notifications.refreshCalls();
      expect(f.notifications.callRevision, 2);
      expect(
        f.requests.map((r) => r.url.queryParameters['device']),
        everyElement(f.notifications.client!.callDevice),
      );
      expect(f.requests.map((r) => r.method), everyElement('GET'));
    },
  );

  test('message and call refresh each coalesce concurrent requests', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final messages = Completer<http.Response>();
    final calls = Completer<http.Response>();
    f.respond = (r) => r.url.path.endsWith('/call_inbox')
        ? calls.future
        : r.url.path.endsWith('/groups')
        ? Future.value(http.Response('{"items":[]}', 200))
        : messages.future;
    final waiting = Future.wait([
      f.notifications.refresh(),
      f.notifications.refresh(),
      f.notifications.refreshCalls(),
      f.notifications.refreshCalls(),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(f.requests.length, 2);
    calls.complete(http.Response(jsonEncode({'call': _call('one')}), 200));
    messages.complete(http.Response('{"items":[]}', 200));
    await waiting;
    expect(f.requests.length, 3);
    expect(f.notifications.incomingCall?['id'], 'one');
  });

  test(
    'call route reservation blocks duplicate routes and stale inbox loads',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.call = _call('one');
      await f.notifications.refreshCalls();
      final response = Completer<http.Response>();
      f.respond = (_) => response.future;
      final pending = f.notifications.refreshCalls();
      expect(f.notifications.beginCall(), isTrue);
      expect(f.notifications.beginCall(), isFalse);
      expect(f.notifications.callOpen, isTrue);
      expect(f.notifications.incomingCall, isNull);
      response.complete(
        http.Response(jsonEncode({'call': _call('late')}), 200),
      );
      await pending;
      expect(f.notifications.incomingCall, isNull);
      f.notifications.setForeground(false);
      expect(f.notifications.callOpen, isTrue);
      f.respond = null;
      f.call = null;
      f.notifications.setForeground(true);
      await f.notifications.refreshCalls();
      f.notifications.endCall();
      await f.notifications.refreshCalls();
      expect(f.notifications.callOpen, isFalse);
      expect(f.notifications.incomingCall, isNull);
    },
  );

  for (final state in ['accepted', 'ended', 'declined', 'missed']) {
    test('a call $state elsewhere removes its incoming alert', () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.call = _call('one');
      await f.notifications.refreshCalls();
      f.call = _call('one', state: state);
      await f.notifications.refreshCalls();
      expect(f.notifications.incomingCall, isNull);
    });
  }

  testWidgets(
    'call expires locally during an outage and cannot revive from a repeated response',
    (tester) async {
      final f = _Fixture();
      f.call = _call('one', age: 44);
      await f.notifications.refreshCalls();
      expect(f.notifications.incomingCall, isNotNull);
      f.status = 503;
      await f.notifications.refreshCalls();
      expect(f.notifications.incomingCall, isNotNull);
      await tester.pump(const Duration(seconds: 46));
      expect(f.notifications.incomingCall, isNull);
      f.status = 200;
      await f.notifications.refreshCalls();
      expect(f.notifications.incomingCall, isNull);
      expect(f.notifications.callRevision, 1);
      f.dispose();
    },
  );

  for (final clockOffset in [-3600, 44, 3600]) {
    testWidgets(
      'server invitation survives clock offset $clockOffset but repeated polls cannot extend its deadline',
      (tester) async {
        final f = _Fixture();
        f.call = _call('skewed', age: clockOffset);
        await f.notifications.refreshCalls();
        expect(f.notifications.incomingCall?['id'], 'skewed');
        await tester.pump(const Duration(seconds: 40));
        await f.notifications.refreshCalls();
        expect(f.notifications.incomingCall?['id'], 'skewed');
        expect(f.notifications.callRevision, 1);
        f.status = 503;
        await tester.pump(const Duration(seconds: 6));
        expect(f.notifications.incomingCall, isNull);
        f.dispose();
      },
    );
  }

  test(
    'sign-out clears private state and old in-flight call response',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.notifications.refresh();
      f.peers = [_peer('old', 2)];
      f.call = _call('old');
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      f.notifications.setActiveConversation('peer:other');
      final oldClient = f.notifications.client;
      final response = Completer<http.Response>();
      f.respond = (_) => response.future;
      final oldRequest = f.notifications.refreshCalls();
      f.token = '';
      f.revision.value++;
      expect(f.notifications.client, isNull);
      expect(oldClient!.available, isFalse);
      expect(f.notifications.totalUnread, 0);
      expect(f.notifications.messageAlert, isNull);
      expect(f.notifications.incomingCall, isNull);
      expect(f.notifications.activeConversationKey, isNull);
      expect(f.notifications.beginCall(), isFalse);
      response.complete(
        http.Response(jsonEncode({'call': _call('late')}), 200),
      );
      await oldRequest;
      expect(f.notifications.incomingCall, isNull);
      f.respond = null;
      f.call = null;
      f.peers = [_peer('new', 7)];
      f.token = 'Bearer second-account';
      f.revision.value++;
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      expect(f.notifications.totalUnread, 7);
      expect(f.notifications.messageAlert, isNull);
      expect(f.notifications.client, isNot(same(oldClient)));
    },
  );

  test(
    'denied access clears alerts; temporary failures preserve confirmed state',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.notifications.refresh();
      f.peers = [_peer('a', 1)];
      f.call = _call('one');
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      f.status = 503;
      await Future.wait([
        f.notifications.refresh(),
        f.notifications.refreshCalls(),
      ]);
      expect(f.notifications.messageAlert, isNotNull);
      expect(f.notifications.incomingCall, isNotNull);
      f.status = 401;
      await f.notifications.refreshCalls();
      expect(f.notifications.available, isFalse);
      expect(f.notifications.totalUnread, 0);
      expect(f.notifications.messageAlert, isNull);
      expect(f.notifications.incomingCall, isNull);
    },
  );

  for (final teardown in [false, true]) {
    test(
      'shared client announces denial before ${teardown ? 'model disposal' : 'account replacement'}',
      () async {
        final f = _Fixture();
        final oldClient = f.notifications.client!;
        var observed = false;
        void checkStillUndisposed() {}
        oldClient.addListener(() {
          observed = true;
          expect(oldClient.available, isFalse);
          expect(f.notifications.client, isNull);
          // ChangeNotifier asserts if a listener is added after disposal.
          expect(
            () => oldClient.addListener(checkStillUndisposed),
            returnsNormally,
          );
          oldClient.removeListener(checkStillUndisposed);
        });
        if (teardown) {
          f.notifications.dispose();
          expect(observed, isTrue);
          f.revision.dispose();
        } else {
          f.token = 'Bearer replacement-account';
          f.revision.value++;
          expect(observed, isTrue);
          expect(f.notifications.client, isNot(same(oldClient)));
          await Future.wait([
            f.notifications.refresh(),
            f.notifications.refreshCalls(),
          ]);
          f.dispose();
        }
      },
    );
  }

  testWidgets('calls are opt-in and automatic polls run every three seconds', (
    tester,
  ) async {
    final enabled = _Fixture();
    final disabled = _Fixture(enableCalls: false);
    await disabled.notifications.refreshCalls();
    await tester.pump(const Duration(seconds: 3));
    expect(
      enabled.requests.where((r) => r.url.path.endsWith('/call_inbox')),
      hasLength(1),
    );
    expect(disabled.requests, isEmpty);
    enabled.dispose();
    disabled.dispose();
  });
}
