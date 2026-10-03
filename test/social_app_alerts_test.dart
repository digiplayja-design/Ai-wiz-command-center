import 'dart:async';
import 'dart:convert';

import 'package:ai_wiz_command_center/social/social_app_alerts.dart';
import 'package:ai_wiz_command_center/social/social_call_screen.dart';
import 'package:ai_wiz_command_center/social/social_call_controller.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _peer = <String, dynamic>{
  'id': 'peer-one',
  'name': 'Jordan Rivera',
  'handle': 'jordan',
  'color': 'violet',
  'connection': 'accepted',
};
const _group = <String, dynamic>{
  'id': 'group-one',
  'name': 'Weekend plans',
  'state': 'accepted',
  'color': 'mint',
};
const _profile = <String, dynamic>{
  'id': 'me',
  'name': 'Alex Morgan',
  'handle': 'alex',
  'color': 'cyan',
};

class _AlertStore {
  String token = 'Bearer alert-account';
  final revision = ValueNotifier(0);
  final requests = <SocialMap>[];
  final clients = <SocialClient>[];
  int unread = 0, groupUnread = 0, declineFailures = 0;
  SocialMap? incoming;
  Completer<http.Response>? pendingDecline;

  Map<String, String> headers() => {'Authorization': token};

  SocialClient client() {
    final result = SocialClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: headers,
      sessionChanges: revision,
      client: MockClient((request) async {
        final action = request.url.pathSegments.last;
        final data = request.method == 'POST'
            ? socialMap(jsonDecode(request.body))
            : request.url.queryParameters;
        requests.add({'action': action, 'method': request.method, ...data});
        SocialMap response = {};
        switch (action) {
          case 'connections':
            response = {
              'items': [
                {..._peer, 'unread': unread},
              ],
            };
          case 'groups':
            response = {
              'items': [
                {..._group, 'unread': groupUnread},
              ],
            };
          case 'bootstrap':
            response = {
              'profile': _profile,
              'categories': [],
              'moderator': false,
            };
          case 'messages':
            response = {'peer': _peer, 'items': []};
          case 'group_messages':
            response = {'peer': _group, 'items': []};
          case 'call_inbox':
            response = {'call': incoming};
          case 'call_poll':
            response = {'call': incoming, 'signals': []};
          case 'call_config':
            response = {'enabled': false};
          case 'call_end':
            if (pendingDecline != null) return pendingDecline!.future;
            if (declineFailures > 0) {
              declineFailures--;
              return http.Response('{"error":"Temporary outage"}', 503);
            }
            incoming = null;
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    clients.add(result);
    return result;
  }

  void ring({bool video = false}) {
    incoming = {
      'id': 'call-one',
      'peer': _peer,
      'mode': video ? 'video' : 'audio',
      'state': 'ringing',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  void signOut() {
    token = '';
    revision.value++;
  }
}

class _Harness {
  _Harness(this.store) {
    notifications = SocialNotifications(
      baseUrl: 'https://fixture.test',
      headersBuilder: store.headers,
      sessionChanges: store.revision,
      shouldPoll: () => true,
      clientBuilder: store.client,
      enableCalls: true,
      interval: const Duration(days: 1),
    );
  }
  final _AlertStore store;
  late final SocialNotifications notifications;
  final navigator = GlobalKey<NavigatorState>();
  final observer = RouteObserver<ModalRoute<dynamic>>();
  final draft = TextEditingController();
  int beforeOpenCall = 0;
  bool _disposed = false;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        theme: korlixBuildTheme('pure_black'),
        builder: (context, child) => SocialAppAlerts(
          baseUrl: 'https://fixture.test',
          headersBuilder: store.headers,
          sessionChanges: store.revision,
          navigatorKey: navigator,
          routeObserver: observer,
          notifications: notifications,
          clientBuilder: store.client,
          beforeOpenCall: () => beforeOpenCall++,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
        home: const Scaffold(body: Center(child: Text('KORLIX tools'))),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => dispose(tester));
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    notifications.dispose();
    draft.dispose();
    store.revision.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  Future<void> pushTool(WidgetTester tester) async {
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('VoiceScribe draft')),
            body: Padding(
              padding: const EdgeInsets.only(top: 320),
              child: TextField(
                key: const ValueKey('tool-draft'),
                controller: draft,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tool-draft')),
      'Keep this unfinished work',
    );
  }

  Future<void> message(WidgetTester tester, {bool group = false}) async {
    if (group) {
      store.groupUnread++;
    } else {
      store.unread++;
    }
    await notifications.refresh();
    await tester.pumpAndSettle();
  }

  Future<void> call(WidgetTester tester, {bool video = false}) async {
    store.ring(video: video);
    await notifications.refreshCalls();
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'production host maintains presence above a tool without changing its draft',
    (tester) async {
      final store = _AlertStore();
      final navigator = GlobalKey<NavigatorState>();
      final observer = RouteObserver<ModalRoute<dynamic>>();
      final draft = TextEditingController();
      int presenceCount() => store.requests
          .where((request) => request['action'] == 'presence')
          .length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          builder: (context, child) => SocialAppAlerts(
            baseUrl: 'https://fixture.test',
            headersBuilder: store.headers,
            sessionChanges: store.revision,
            navigatorKey: navigator,
            routeObserver: observer,
            clientBuilder: store.client,
            child: child!,
          ),
          home: const Scaffold(body: Text('KORLIX tools')),
        ),
      );
      await tester.pumpAndSettle();
      expect(presenceCount(), 1);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Copy Box draft')),
              body: TextField(
                key: const ValueKey('presence-tool-draft'),
                controller: draft,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('presence-tool-draft')),
        'Preserve my Copy Box work',
      );
      await tester.pump(const Duration(seconds: 30));
      expect(presenceCount(), 2);
      expect(find.text('Copy Box draft'), findsOneWidget);
      expect(draft.text, 'Preserve my Copy Box work');

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(seconds: 90));
      expect(presenceCount(), 2);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(presenceCount(), 3);
      expect(draft.text, 'Preserve my Copy Box work');
      expect(
        store.requests
            .where((request) => request['action'] == 'presence')
            .map((request) => request['active']),
        everyElement(true),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
      expect(presenceCount(), 3);
      draft.dispose();
      store.revision.dispose();
    },
  );

  testWidgets(
    'message appears above a pushed tool and dialog, preserving drafts',
    (tester) async {
      final harness = _Harness(_AlertStore());
      await harness.mount(tester);
      await harness.pushTool(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byKey(const ValueKey('tool-draft'))),
          builder: (_) => const AlertDialog(
            title: Text('Keep editing'),
            content: Text('The tool dialog stays open.'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await harness.message(tester);
      expect(find.text('Incoming message'), findsOneWidget);
      expect(find.text('The tool dialog stays open.'), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Incoming message'), findsNothing);
      expect(find.text('The tool dialog stays open.'), findsOneWidget);
      harness.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(harness.draft.text, 'Keep this unfinished work');
      expect(find.text('VoiceScribe draft'), findsOneWidget);
      expect(
        harness.store.requests.where((r) => r['action'] == 'read'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    },
  );

  for (final group in [false, true]) {
    testWidgets(
      'Open message enters the correct ${group ? 'group' : 'private'} chat',
      (tester) async {
        final harness = _Harness(_AlertStore());
        await harness.mount(tester);
        await harness.pushTool(tester);
        await harness.message(tester, group: group);
        await tester.tap(find.text('Open message'));
        await tester.pumpAndSettle();
        final screen = tester.widget<SocialScreen>(
          find.byType(SocialScreen, skipOffstage: false),
        );
        final chat = tester.widget<SocialChatScreen>(
          find.byType(SocialChatScreen),
        );
        expect(
          screen.initialConversation?['id'],
          group ? 'group-one' : 'peer-one',
        );
        expect(screen.initialGroupChat, group);
        expect(chat.peer['id'], group ? 'group-one' : 'peer-one');
        expect(chat.groupChat, group);
        expect(
          harness.notifications.activeConversationKey,
          group ? 'group:group-one' : 'peer:peer-one',
        );
        expect(find.text('Incoming message'), findsNothing);
        expect(harness.notifications.client, isNot(same(screen.client)));
        harness.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        harness.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(harness.draft.text, 'Keep this unfinished work');
        expect(harness.notifications.available, isTrue);
        expect(harness.notifications.activeConversationKey, isNull);
        expect(tester.takeException(), isNull);
        await harness.dispose(tester);
      },
    );
  }

  testWidgets(
    'View call uses the receiving device without accepting or capturing media',
    (tester) async {
      final platformCalls = <String>[];
      const channel = MethodChannel('FlutterWebRTC.Method');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        platformCalls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final harness = _Harness(_AlertStore());
      await harness.mount(tester);
      await harness.pushTool(tester);
      await harness.call(tester, video: true);
      final receiver = harness.notifications.client!;
      await tester.tap(find.text('View call'));
      await tester.pumpAndSettle();
      final screen = tester.widget<SocialCallScreen>(
        find.byType(SocialCallScreen),
      );
      expect(screen.client, same(receiver));
      expect(screen.client.callDevice, receiver.callDevice);
      expect(screen.peer['id'], 'peer-one');
      expect(screen.incoming?['id'], 'call-one');
      expect(screen.video, isTrue);
      expect(harness.beforeOpenCall, 1);
      expect(harness.notifications.callOpen, isTrue);
      expect(find.text('View call'), findsNothing);
      expect(find.text('Answer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        harness.store.requests.where(
          (r) => [
            'call_config',
            'call_accept',
            'call_start',
          ].contains(r['action']),
        ),
        isEmpty,
      );
      expect(
        platformCalls.where(
          (method) => method.toLowerCase().contains('getusermedia'),
        ),
        isEmpty,
      );
      final polls = harness.store.requests.where(
        (r) => r['action'] == 'call_poll',
      );
      expect(polls, isNotEmpty);
      expect(polls.every((r) => r['device'] == receiver.callDevice), isTrue);
      // Answer is the first operation permitted to request call configuration.
      // Disabled fixture calling then stops before touching a real device.
      await tester.tap(find.byTooltip('Answer'));
      await tester.pumpAndSettle();
      expect(
        harness.store.requests.where((r) => r['action'] == 'call_config'),
        hasLength(1),
      );
      expect(
        harness.store.requests.where((r) => r['action'] == 'call_accept'),
        isEmpty,
      );
      harness.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(harness.notifications.callOpen, isFalse);
      expect(harness.draft.text, 'Keep this unfinished work');
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    },
  );

  testWidgets('Decline posts the receiver call/device and clears the banner', (
    tester,
  ) async {
    final harness = _Harness(_AlertStore());
    await harness.mount(tester);
    await harness.call(tester);
    final device = harness.notifications.client!.callDevice;
    expect(find.text('Incoming phone call'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    final ended = harness.store.requests.singleWhere(
      (r) => r['action'] == 'call_end',
    );
    expect(ended['method'], 'POST');
    expect(ended['id'], 'call-one');
    expect(ended['device'], device);
    expect(find.text('Incoming phone call'), findsNothing);
    expect(find.byType(SocialCallScreen), findsNothing);
    expect(harness.notifications.incomingCall, isNull);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('session replacement immediately ends the incoming call route', (
    tester,
  ) async {
    final harness = _Harness(_AlertStore());
    await harness.mount(tester);
    await harness.call(tester);
    await tester.tap(find.text('View call'));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(SocialCallScreen));
    final controller = state.call as SocialCallController;
    expect(controller.ended, isFalse);
    expect(controller.media.ready, isFalse);
    final receivingClient = controller.client;
    harness.store.token = 'Bearer different-account';
    harness.store.revision.value++;
    // Session revocation must be synchronous, before the next 2-second poll.
    expect(controller.ended, isTrue);
    expect(receivingClient.available, isFalse);
    expect(controller.media.ready, isFalse);
    expect(harness.notifications.client, isNot(same(receivingClient)));
    await tester.pumpAndSettle();
    expect(
      harness.store.requests.where(
        (r) => ['call_config', 'call_accept'].contains(r['action']),
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
    'messages wait behind the call until its closing transition finishes',
    (tester) async {
      final harness = _Harness(_AlertStore());
      await harness.mount(tester);
      await harness.call(tester);
      await tester.tap(find.text('View call'));
      await tester.pumpAndSettle();
      await harness.message(tester);
      expect(harness.notifications.messageAlert, isNotNull);
      expect(find.text('Incoming message'), findsNothing);
      expect(find.text('Open message'), findsNothing);
      expect(find.byType(SocialCallScreen), findsOneWidget);
      expect(find.byType(SocialScreen), findsNothing);
      harness.navigator.currentState!.pop();
      await tester.pump();
      expect(harness.notifications.callOpen, isTrue);
      expect(find.text('Open message'), findsNothing);
      await tester.pumpAndSettle();
      expect(harness.notifications.callOpen, isFalse);
      expect(find.byType(SocialCallScreen), findsNothing);
      expect(find.text('Incoming message'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    },
  );

  testWidgets('failed decline stays visible and can be retried', (
    tester,
  ) async {
    final store = _AlertStore()..declineFailures = 1;
    final harness = _Harness(store);
    await harness.mount(tester);
    await harness.call(tester);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not decline the call. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('Incoming phone call'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(
      store.requests.where((r) => r['action'] == 'call_end'),
      hasLength(2),
    );
    expect(find.text('Incoming phone call'), findsNothing);
    expect(
      find.text('Could not decline the call. Please retry.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('sign-out hides a pending decline and ignores its late failure', (
    tester,
  ) async {
    final store = _AlertStore()..pendingDecline = Completer<http.Response>();
    final harness = _Harness(store);
    await harness.mount(tester);
    await harness.call(tester);
    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(
      store.requests.where((r) => r['action'] == 'call_end'),
      hasLength(1),
    );
    store.signOut();
    await tester.pumpAndSettle();
    expect(harness.notifications.client, isNull);
    expect(find.text('Incoming phone call'), findsNothing);
    store.pendingDecline!.complete(
      http.Response('{"error":"Late failure"}', 503),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not decline the call. Please retry.'),
      findsNothing,
    );
    expect(find.text('KORLIX tools'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });
}
