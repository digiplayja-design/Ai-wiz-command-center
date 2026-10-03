import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/social/social_app_alerts.dart';
import 'package:ai_wiz_command_center/social/social_call_controller.dart';
import 'package:ai_wiz_command_center/social/social_call_screen.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'social_calls_test.dart' as calls;

const _peer = <String, dynamic>{
  'id': 'peer-one',
  'name': 'Jordan Rivera',
  'handle': 'jordan',
  'color': 'violet',
  'connection': 'accepted',
};

class _Ring {
  _Ring(this.id, this.outgoing, this.expiresAt);
  final String? id;
  final bool outgoing;
  final DateTime? expiresAt;
}

class _Sounds extends KorlixSoundService {
  final plays = <(KorlixSound, String?)>[];
  final rings = <Object, _Ring>{};
  final quietOwners = <Object>{};
  int activations = 0, maximumSimultaneousRings = 0;

  @override
  Future<void> play(KorlixSound sound, {String? eventId}) async {
    plays.add((sound, eventId));
  }

  @override
  Future<bool> activate() async {
    activations++;
    return true;
  }

  @override
  void setRinging(
    Object owner,
    bool ringing, {
    String? callId,
    DateTime? expiresAt,
    bool outgoing = false,
  }) {
    if (ringing) {
      rings[owner] = _Ring(callId, outgoing, expiresAt);
    } else {
      rings.remove(owner);
    }
    if (rings.length > maximumSimultaneousRings) {
      maximumSimultaneousRings = rings.length;
    }
  }

  @override
  void setQuiet(Object owner, bool active) {
    if (active) {
      quietOwners.add(owner);
    } else {
      quietOwners.remove(owner);
    }
  }
}

class _Store {
  String token = 'Bearer sound-account';
  final session = ValueNotifier(0);
  int unread = 0;
  final requests = <String>[];
  SocialMap? incoming;
  Completer<http.Response>? declining;

  Map<String, String> headers() => {'Authorization': token};
  SocialClient client() => SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: headers,
    sessionChanges: session,
    client: MockClient((request) async {
      final action = request.url.pathSegments.last;
      requests.add(action);
      SocialMap result = {};
      if (action == 'connections') {
        result = {
          'items': [
            {..._peer, 'unread': unread},
          ],
        };
      } else if (action == 'groups') {
        result = {'items': []};
      } else if (action == 'call_inbox' || action == 'call_poll') {
        result = {'call': incoming, 'signals': []};
      } else if (action == 'member') {
        result = {'profile': _peer};
      } else if (action == 'call_end') {
        if (declining != null) return declining!.future;
        incoming = null;
      }
      return http.Response(jsonEncode(result), 200);
    }),
  );

  void ring() {
    incoming = {
      'id': 'incoming-one',
      'peer': _peer,
      'mode': 'audio',
      'state': 'ringing',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class _Harness {
  _Harness(this.store) {
    notifications = SocialNotifications(
      baseUrl: 'https://fixture.test',
      headersBuilder: store.headers,
      sessionChanges: store.session,
      shouldPoll: () => true,
      clientBuilder: store.client,
      enableCalls: true,
      interval: const Duration(days: 1),
    );
  }

  final _Store store;
  final sounds = _Sounds();
  late final SocialNotifications notifications;
  final navigator = GlobalKey<NavigatorState>();
  final observer = RouteObserver<ModalRoute<dynamic>>();
  bool disposed = false;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        builder: (_, child) => SocialAppAlerts(
          baseUrl: 'https://fixture.test',
          headersBuilder: store.headers,
          sessionChanges: store.session,
          navigatorKey: navigator,
          routeObserver: observer,
          notifications: notifications,
          sounds: sounds,
          child: child!,
        ),
        home: const Scaffold(body: Text('Another KORLIX tool')),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => dispose(tester));
  }

  Future<void> dispose(WidgetTester tester) async {
    if (disposed) return;
    disposed = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    notifications.dispose();
    store.session.dispose();
    sounds.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  testWidgets('only fresh message revisions sound above other tools', (
    tester,
  ) async {
    final store = _Store()..unread = 4;
    final h = _Harness(store);
    await h.mount(tester);
    expect(h.sounds.plays, isEmpty);
    store.unread = 5;
    await h.notifications.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Another KORLIX tool'), findsOneWidget);
    expect(h.sounds.plays.map((event) => event.$1), [KorlixSound.message]);
    final firstEvent = h.sounds.plays.single.$2;
    await h.notifications.refresh();
    h.notifications.dismissMessage();
    await tester.pumpAndSettle();
    expect(h.sounds.plays, hasLength(1));
    h.notifications.setActiveConversation('peer:peer-one');
    store.unread = 6;
    await h.notifications.refresh();
    expect(h.sounds.plays, hasLength(1));
    h.notifications.setActiveConversation(null);
    store.unread = 7;
    await h.notifications.refresh();
    expect(h.sounds.plays, hasLength(2));
    expect(h.sounds.plays.last.$2, isNot(firstEvent));
    store.token = 'Bearer another-account';
    store.unread = 40;
    store.session.value++;
    await tester.pumpAndSettle();
    expect(h.sounds.plays, hasLength(2));
    await h.dispose(tester);
  });

  testWidgets('mounting an existing message alert does not replay it', (
    tester,
  ) async {
    final store = _Store();
    final h = _Harness(store);
    await h.notifications.refresh();
    store.unread = 1;
    await h.notifications.refresh();
    expect(h.notifications.messageRevision, 1);
    await h.mount(tester);
    expect(h.sounds.plays, isEmpty);
    await h.dispose(tester);
  });

  testWidgets('incoming ring transfers to call route without answering', (
    tester,
  ) async {
    const channel = MethodChannel('FlutterWebRTC.Method');
    final deviceCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      deviceCalls.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final store = _Store();
    final h = _Harness(store);
    await h.mount(tester);
    store.ring();
    await h.notifications.refreshCalls();
    await tester.pumpAndSettle();
    expect(h.sounds.rings, hasLength(1));
    final deadline = h.sounds.rings.values.single.expiresAt;
    await h.notifications.refreshCalls();
    expect(h.sounds.rings.values.single.expiresAt, deadline);
    await tester.tap(find.text('View call'));
    await tester.pumpAndSettle();
    expect(find.byType(SocialCallScreen), findsOneWidget);
    expect(h.sounds.rings, hasLength(1));
    expect(h.sounds.rings.values.single.id, 'incoming-one');
    expect(h.sounds.rings.values.single.outgoing, false);
    expect(h.sounds.rings.values.single.expiresAt, deadline);
    expect(h.sounds.maximumSimultaneousRings, 1);
    expect(store.requests, isNot(contains('call_accept')));
    expect(store.requests, isNot(contains('call_config')));
    expect(deviceCalls, isEmpty);
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(h.sounds.rings, isEmpty);
    expect(h.sounds.quietOwners, isEmpty);
    expect(store.requests, contains('call_end'));
    await h.dispose(tester);
  });

  testWidgets('decline silences immediately and failed request stays silent', (
    tester,
  ) async {
    final store = _Store();
    final h = _Harness(store);
    await h.mount(tester);
    store.ring();
    await h.notifications.refreshCalls();
    await tester.pumpAndSettle();
    expect(h.sounds.rings, hasLength(1));
    store.declining = Completer<http.Response>();
    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(h.sounds.rings, isEmpty);
    store.declining!.complete(http.Response('{"error":"outage"}', 503));
    await tester.pumpAndSettle();
    await h.notifications.refreshCalls();
    await tester.pumpAndSettle();
    expect(h.sounds.rings, isEmpty);
    expect(
      find.text('Could not decline the call. Please retry.'),
      findsOneWidget,
    );
    await h.dispose(tester);
  });

  testWidgets('expired and signed-out invitations stop ringing', (
    tester,
  ) async {
    final store = _Store();
    final h = _Harness(store);
    await h.mount(tester);
    store.ring();
    await h.notifications.refreshCalls();
    await tester.pump();
    expect(h.sounds.rings, hasLength(1));
    await tester.pump(const Duration(seconds: 46));
    await tester.pumpAndSettle();
    expect(h.sounds.rings, isEmpty);
    await h.notifications.refreshCalls();
    expect(h.sounds.rings, isEmpty);
    store.ring();
    store.incoming!['id'] = 'incoming-two';
    await h.notifications.refreshCalls();
    expect(h.sounds.rings, hasLength(1));
    store.token = '';
    store.session.value++;
    await tester.pumpAndSettle();
    expect(h.sounds.rings, isEmpty);
    await h.dispose(tester);
  });

  test(
    'answer quiets before microphone permission; dispose releases quiet',
    () async {
      final store = calls.CallStore();
      final client = store.client('callee');
      final sounds = _Sounds();
      final media = calls.FakeMedia()..permission = Completer<void>();
      final call = SocialCallController(
        client: client,
        peer: _peer,
        video: false,
        incoming: {'id': store.id, 'state': 'ringing'},
        media: media,
        sounds: sounds,
      );
      await call.initialize();
      expect(sounds.rings, hasLength(1));
      expect(media.opened, 0);
      final accepting = call.accept();
      expect(sounds.rings, isEmpty);
      expect(sounds.quietOwners, contains(call));
      await Future<void>.delayed(Duration.zero);
      expect(media.opened, 1);
      call.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(sounds.rings, isEmpty);
      expect(sounds.quietOwners, isEmpty);
      media.permission!.complete();
      await accepting;
      expect(
        store.requests.where((r) => r['action'] == 'call_accept'),
        isEmpty,
      );
      client.dispose();
      store.revision.dispose();
      sounds.dispose();
    },
  );

  test(
    'outgoing ringback is central and stops on acceptance and hangup',
    () async {
      final store = calls.CallStore();
      final client = store.client('caller');
      final sounds = _Sounds();
      final call = SocialCallController(
        client: client,
        peer: _peer,
        video: false,
        media: calls.FakeMedia(),
        sounds: sounds,
      );
      await call.initialize();
      expect(sounds.rings.values.single.outgoing, true);
      expect(sounds.quietOwners, isEmpty);
      final deadline = sounds.rings.values.single.expiresAt;
      await call.poll();
      expect(sounds.rings.values.single.expiresAt, deadline);
      store.state = 'accepted';
      await call.poll();
      expect(sounds.rings, isEmpty);
      expect(sounds.quietOwners, contains(call));
      await call.end('done');
      await Future<void>.delayed(Duration.zero);
      expect(sounds.rings, isEmpty);
      expect(sounds.quietOwners, isEmpty);
      call.dispose();
      client.dispose();
      store.revision.dispose();
      sounds.dispose();
    },
  );
}
