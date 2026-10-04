import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_call_controller.dart';
import 'package:ai_wiz_command_center/social/social_call_background.dart';
import 'package:ai_wiz_command_center/social/social_call_history.dart';
import 'package:ai_wiz_command_center/social/social_call_screen.dart';
import 'package:ai_wiz_command_center/social/social_app_alerts.dart';
import 'package:ai_wiz_command_center/social/social_alert_scope.dart';
import 'package:ai_wiz_command_center/social/social_call_session.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:ai_wiz_command_center/social/social_notification_settings.dart';
import 'package:ai_wiz_command_center/social/social_push_platform.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'social_calls_test.dart' as old;
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;
import 'social_call_audio_test.dart' as audio;

class VideoIo extends audio.Io {
  final replacement = audio.Track('new-camera', 'video');
  @override
  Future<audio.Stream> captureVideo() async =>
      audio.Stream('video-only', [replacement]);
}

class RecoveryMedia extends old.FakeMedia {
  int restarts = 0;
  @override
  Future<String> restartOffer() async {
    restarts++;
    return 'restart-$restarts';
  }
}

class UpgradeStore {
  bool recovery = true;
  int generation = 0;
  String state = 'ringing', token = 'Bearer account';
  final revision = ValueNotifier(0);
  final requests = <SocialMap>[], signals = <SocialMap>[];
  SocialClient client(String who) => SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.pathSegments.last;
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : r.url.queryParameters;
      requests.add({'who': who, 'action': action, ...data});
      if (action == 'call_accept') state = 'accepted';
      if (action == 'call_end') state = 'ended';
      if (action == 'call_restart') generation++;
      if (action == 'call_signal') {
        signals.add({...data, 'seq': signals.length + 1, 'who': who});
      }
      final result = action == 'call_config'
          ? {'enabled': true, 'relay': true, 'iceServers': []}
          : action == 'member'
          ? {'profile': social.peer}
          : {
              'call': {
                'id': 'call',
                'state': state,
                'generation': generation,
                'recovery_supported': recovery,
                'peer': social.peer,
              },
              'signals': action == 'call_poll'
                  ? signals
                        .where(
                          (s) =>
                              s['who'] != who &&
                              (s['seq'] as int) >
                                  int.parse('${data['after'] ?? 0}'),
                        )
                        .toList()
                  : [],
              'items': [],
            };
      return http.Response(jsonEncode(result), 200);
    }),
  );
}

class FakePush extends SocialPushPlatform {
  bool enabled = false;
  int permissions = 0, disabled = 0;
  @override
  bool get supported => true;
  @override
  String get permission => 'default';
  @override
  bool get launchRequested => false;
  @override
  void onOpen(void Function()? callback) {}
  @override
  Future<void> syncOwner(String owner) async {}
  @override
  Future<SocialMap?> current(String owner) async => enabled
      ? {'device': 'device', 'binding': 'binding', 'subscription': {}}
      : null;
  @override
  Future<SocialMap> subscribe(String owner, String publicKey) async {
    permissions++;
    enabled = true;
    return {'device': 'device', 'binding': 'binding', 'subscription': {}};
  }

  @override
  Future<void> unsubscribe(String owner) async {
    disabled++;
    enabled = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native background camera capture stops and only an explicit tap restores video',
    () async {
      final io = VideoIo(),
          media = SocialCallMedia(io: VideoIo(), audio: audio.Audio());
      await media.close();
      final active = SocialCallMedia(io: io, audio: audio.Audio());
      await active.open(true, []);
      await active.suspendCamera();
      expect(io.camera.stopped, true);
      expect(io.mic.stopped, false);
      expect(active.camera, false);
      expect(active.local.srcObject, isNull);
      await active.toggleCamera();
      expect(active.camera, true);
      expect(active.local.srcObject!.getAudioTracks(), isEmpty);
      expect(io.connection.recordedSenders.last.current, same(io.replacement));
      await active.close();
      expect(io.replacement.stopped, true);
      expect(io.mic.stopped, true);
    },
  );
  test(
    'native background lease is capability-gated and stops on call end',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('korlix/social_call_background');
      final commands = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            commands.add(call);
            return call.method == 'start';
          });
      final store = UpgradeStore(),
          client = store.client('left'),
          media = RecoveryMedia();
      final background = SocialCallBackground();
      final call = SocialCallController(
        client: client,
        peer: social.peer,
        video: false,
        media: media,
        background: background,
      );
      try {
        await call.initialize();
        expect(background.ready, true);
        call.backgrounded();
        expect(call.ended, false);
        await call.end('Ended');
        await Future<void>.delayed(Duration.zero);
        expect(background.ready, false);
        expect(
          commands.map((c) => c.method),
          containsAllInOrder(['start', 'stop']),
        );
      } finally {
        call.dispose();
        client.dispose();
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
  test(
    'failed native background capability ends safely when the app is hidden',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('korlix/social_call_background');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => false);
      final store = UpgradeStore(),
          client = store.client('left'),
          media = RecoveryMedia();
      final call = SocialCallController(
        client: client,
        peer: social.peer,
        video: false,
        media: media,
      );
      try {
        await call.initialize();
        expect(call.background.ready, false);
        call.backgrounded();
        expect(call.ended, true);
        expect(media.stopped, true);
      } finally {
        call.dispose();
        client.dispose();
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
  test(
    'negotiated recovery keeps the same call and renegotiates exactly once',
    () async {
      final store = UpgradeStore(),
          leftClient = store.client('left'),
          rightClient = store.client('right');
      final leftMedia = RecoveryMedia(), rightMedia = RecoveryMedia();
      final left = SocialCallController(
        client: leftClient,
        peer: social.peer,
        video: false,
        media: leftMedia,
      );
      final right = SocialCallController(
        client: rightClient,
        peer: social.peer,
        video: false,
        media: rightMedia,
        incoming: {'id': 'call', 'state': 'ringing'},
      );
      try {
        await left.initialize();
        await right.initialize();
        await right.accept();
        await left.poll();
        await right.poll();
        await left.poll();
        leftMedia.onState!('connected');
        rightMedia.onState!('connected');
        final id = left.id;
        await left.reconnect();
        await right.poll();
        await left.poll();
        expect(left.id, id);
        expect(leftMedia.restarts, 1);
        expect(rightMedia.descriptions, contains('offer:restart-1'));
        expect(
          leftMedia.descriptions.where((s) => s.startsWith('answer:')).length,
          2,
        );
        await right.poll();
        await left.poll();
        await left.reconnect();
        expect(leftMedia.restarts, 1);
        expect(
          store.requests.where((r) => r['action'] == 'call_restart').length,
          1,
        );
        expect(
          store.requests
              .where((r) => ['call_start', 'call_accept'].contains(r['action']))
              .every((r) => r['protocol'] == 2),
          true,
        );
        leftMedia.onState!('connected');
        expect(left.status, 'Connected');
        expect(left.ended, false);
        expect(right.ended, false);
      } finally {
        left.dispose();
        right.dispose();
        leftClient.dispose();
        rightClient.dispose();
      }
    },
  );
  test(
    'legacy peers do not receive a restart protocol they cannot answer',
    () async {
      final store = UpgradeStore()..recovery = false;
      final client = store.client('left'), media = RecoveryMedia();
      final call = SocialCallController(
        client: client,
        peer: social.peer,
        video: false,
        media: media,
      );
      await call.initialize();
      store.state = 'accepted';
      await call.poll();
      media.onState!('failed');
      await call.reconnect();
      expect(media.restarts, 0);
      expect(
        store.requests.where((r) => r['action'] == 'call_restart'),
        isEmpty,
      );
      call.dispose();
      client.dispose();
    },
  );
  test('push ownership excludes session credentials and requires an account', () {
    final jwt =
        'x.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://issuer', 'sub': 'owner', 'session_id': 'secret-session'}))).replaceAll('=', '')}.x';
    expect(
      socialPushOwner({'Authorization': 'Bearer $jwt'}),
      '["https://issuer","owner"]',
    );
    expect(socialPushOwner({'Authorization': 'Bearer sensitive-token'}), '');
  });
  test(
    'history distinguishes missed incoming calls and unanswered outgoing calls',
    () {
      expect(
        socialCallHistoryLabel({'state': 'missed', 'incoming': true}),
        'Missed call',
      );
      expect(
        socialCallHistoryLabel({'state': 'missed', 'incoming': false}),
        'No answer',
      );
    },
  );
  testWidgets(
    'minimize survives navigation and logout releases the microphone',
    (t) async {
      final store = UpgradeStore(), media = RecoveryMedia();
      final navigator = GlobalKey<NavigatorState>();
      final notifications = SocialNotifications(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': store.token},
        sessionChanges: store.revision,
        shouldPoll: () => false,
        clientBuilder: () => store.client('left'),
      );
      late SocialCallSession session;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: korlixBuildTheme('pure_black'),
          builder: (context, child) => SocialAppAlerts(
            baseUrl: 'https://fixture.test',
            headersBuilder: () => {'Authorization': store.token},
            sessionChanges: store.revision,
            navigatorKey: navigator,
            routeObserver: RouteObserver<ModalRoute<dynamic>>(),
            notifications: notifications,
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              session = SocialAlertScope.maybeOf(context)!.calls!;
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => unawaited(
                      session.start(social.peer, false, media: media),
                    ),
                    child: const Text('Start fixture call'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Start fixture call'));
      await t.pumpAndSettle();
      expect(media.opened, 1);
      expect(session.current, isNotNull);
      await t.tap(find.byTooltip('Minimize call and keep using KORLIX'));
      await t.pumpAndSettle();
      expect(find.byType(SocialCallScreen), findsNothing);
      expect(find.byType(SocialActiveCallBar), findsOneWidget);
      expect(media.stopped, false);
      expect(notifications.callOpen, true);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Another KORLIX tool')),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Another KORLIX tool'), findsOneWidget);
      expect(media.stopped, false);
      store.token = 'Bearer another-account';
      store.revision.value++;
      expect(media.stopped, true);
      await t.pumpAndSettle();
      expect(session.current, isNull);
      await t.pumpWidget(const SizedBox());
      notifications.dispose();
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets(
      'notification and history screens fit $width with account-safe actions',
      (t) async {
        final push = FakePush(), revision = ValueNotifier(0);
        var token = 'Bearer fixture';
        final writes = <SocialMap>[];
        final client = SocialClient(
          baseUrl: 'https://fixture.test',
          headersBuilder: () => {'Authorization': token},
          sessionChanges: revision,
          client: MockClient((r) async {
            if (r.method == 'POST') writes.add(socialMap(jsonDecode(r.body)));
            final history = r.url.pathSegments.last == 'call_history';
            return http.Response(
              jsonEncode(
                history
                    ? {
                        'items': [
                          {
                            'id': 'one',
                            'state': 'missed',
                            'incoming': true,
                            'mode': 'video',
                            'created_at': '2026-10-04T01:00:00Z',
                            'peer': social.peer,
                            'can_call': true,
                          },
                          {
                            'id': 'two',
                            'state': 'ended',
                            'peer': {'id': null, 'name': 'Unavailable member'},
                            'can_call': false,
                          },
                        ],
                        'has_more': false,
                      }
                    : {
                        'enabled': true,
                        'publicKey': 'fixture',
                        'subscriptions': [],
                      },
              ),
              200,
            );
          }),
        );
        await social.mount(
          t,
          SocialNotificationSettings(client: client, platform: push),
          width: width,
          scale: width == 320 ? 2 : 1,
          theme: width == 390 ? 'korlix_blue' : 'pure_black',
        );
        expect(push.permissions, 0);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(
          find.text('Enable browser notifications'),
          300,
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Enable browser notifications'));
        await t.pumpAndSettle();
        expect(push.permissions, 1);
        expect(writes.single['calls'], true);
        await fixtures.capture(t, 'social-notifications-${width.toInt()}');
        await old.reveal(t, find.text('Turn off on this browser'));
        await t.tap(find.text('Turn off on this browser'));
        await t.pumpAndSettle();
        expect(push.disabled, 1);
        await social.mount(
          t,
          SocialCallHistory(client: client, onCall: (peer, video) async {}),
          width: width,
          scale: width == 320 ? 2 : 1,
          theme: width == 390 ? 'korlix_blue' : 'pure_black',
        );
        expect(find.text('Missed call · Video'), findsOneWidget);
        expect(find.text('Audio call'), findsOneWidget);
        expect(t.takeException(), isNull);
        await fixtures.capture(t, 'social-history-${width.toInt()}');
        token = 'Bearer changed';
        revision.value++;
        await t.pumpAndSettle();
        expect(find.text('Jordan Rivera'), findsNothing);
        await t.pumpWidget(const SizedBox());
        client.dispose();
      },
    );
  }
}
