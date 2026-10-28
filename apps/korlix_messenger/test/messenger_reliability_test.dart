import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korlix_social_core/social/social_alert_scope.dart';
import 'package:korlix_social_core/social/social_app_alerts.dart';
import 'package:korlix_social_core/social/social_call_controller.dart';
import 'package:korlix_social_core/social/social_call_screen.dart';
import 'package:korlix_social_core/social/social_call_session.dart';
import 'package:korlix_social_core/social/social_client.dart';
import 'package:korlix_social_core/social/social_forms.dart';
import 'package:korlix_social_core/social/social_notifications.dart';
import 'package:korlix_social_core/social/social_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const peer = <String, dynamic>{
  'id': 'peer',
  'name': 'Test Member',
  'handle': 'member',
  'color': 'cyan',
};

class Fixture {
  SocialMap? profile;
  bool failSave = false, failBootstrap = false, omitSavedProfile = false;
  String state = 'ringing';
  String token = 'Bearer fixture';
  final revision = ValueNotifier(0);
  final requests = <SocialMap>[];

  SocialClient client() => SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((request) async {
      final action = request.url.pathSegments.last;
      final data = request.method == 'POST'
          ? socialMap(jsonDecode(request.body))
          : request.url.queryParameters;
      requests.add({'action': action, ...data});
      SocialMap result = {'items': [], 'signals': []};
      if (action == 'bootstrap') {
        if (failBootstrap) return http.Response('{"error":"Try again"}', 503);
        result = {'profile': profile, 'categories': []};
      } else if (action == 'save_profile') {
        if (failSave) return http.Response('{"error":"Try again"}', 503);
        if (!omitSavedProfile) {
          profile = {'id': 'me', ...data};
          result = {'profile': profile};
        }
      } else if (action == 'member') {
        result = {'profile': data['peer'] == 'me' ? profile : peer};
      } else if (action == 'call_config') {
        result = {'enabled': true, 'relay': true, 'iceServers': []};
      } else if (action.startsWith('call_')) {
        if (action == 'call_end') state = 'ended';
        result = {
          'call': {'id': 'call', 'state': state},
          'signals': [],
        };
      }
      return http.Response(jsonEncode(result), 200);
    }),
  );
}

class FakeMedia extends SocialCallMedia {
  bool stopped = false;
  int opened = 0;
  @override
  Future<void> open(bool video, List<dynamic> servers) async {
    opened++;
    ready = true;
  }

  @override
  Future<String> offer() async => 'test-offer';
  @override
  Future<void> close() async {
    stopped = true;
    ready = false;
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backgroundChannel = MethodChannel('korlix/social_call_background');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backgroundChannel, null);
  });

  for (final optOut in [false, true]) {
    testWidgets(
      'profile is required after login; new online default, opt-out=$optOut',
      (tester) async {
        final fixture = Fixture();
        var accountOpened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: SocialScreen(
              client: fixture.client(),
              messengerMode: true,
              onOpenAccount: () => accountOpened = true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Complete your profile'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(BackButton), findsNothing);
        await tester.tap(find.byTooltip('Account & help'));
        expect(accountOpened, true);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SocialProfileForm), findsOneWidget);
        final online = find.widgetWithText(
          SwitchListTile,
          'Show online status and last login',
        );
        expect(tester.widget<SwitchListTile>(online).value, true);
        await tester.enterText(find.byType(TextFormField).at(0), 'New Member');
        await tester.enterText(find.byType(TextFormField).at(1), 'new_member');
        if (optOut) await tapVisible(tester, online);
        expect(
          fixture.requests.where((r) => r['action'] == 'save_profile'),
          isEmpty,
        );
        await tapVisible(tester, find.byType(CheckboxListTile));
        await tapVisible(tester, find.text('Create my Social profile'));
        final saved = fixture.requests.singleWhere(
          (r) => r['action'] == 'save_profile',
        );
        expect(saved['show_online'], !optOut);
        expect(saved['accepted_rules'], true);
        expect(saved['discoverable'], true);
        expect(find.byType(SocialProfileForm), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        fixture.revision.dispose();
      },
    );
  }

  testWidgets('existing hidden online setting stays off when editing', (
    tester,
  ) async {
    final fixture = Fixture();
    final client = fixture.client();
    await tester.pumpWidget(
      MaterialApp(
        home: SocialProfileForm(
          client: client,
          profile: const {
            'id': 'me',
            'name': 'Existing Member',
            'handle': 'existing',
            'show_online': false,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(
              SwitchListTile,
              'Show online status and last login',
            ),
          )
          .value,
      false,
    );
    await tester.pumpWidget(const SizedBox());
    client.dispose();
    fixture.revision.dispose();
  });

  for (final missingResult in [false, true]) {
    testWidgets(
      'failed or unconfirmed profile save cannot bypass setup: $missingResult',
      (tester) async {
        final fixture = Fixture()
          ..failSave = !missingResult
          ..omitSavedProfile = missingResult;
        await tester.pumpWidget(
          MaterialApp(
            home: SocialScreen(client: fixture.client(), messengerMode: true),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'New Member');
        await tester.enterText(find.byType(TextFormField).at(1), 'new_member');
        await tapVisible(tester, find.byType(CheckboxListTile));
        await tapVisible(tester, find.text('Create my Social profile'));
        expect(find.byType(SocialProfileForm), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        fixture.revision.dispose();
      },
    );
  }

  testWidgets('bootstrap failure does not open a usable Messenger inbox', (
    tester,
  ) async {
    final fixture = Fixture()..failBootstrap = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SocialScreen(client: fixture.client(), messengerMode: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(SocialProfileForm), findsNothing);
    fixture.failBootstrap = false;
    await tester.tap(find.byTooltip('Refresh Social'));
    await tester.pumpAndSettle();
    expect(find.byType(SocialProfileForm), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    fixture.revision.dispose();
  });

  testWidgets('switching apps during service startup preserves the call', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ready = Completer<bool>();
    var starts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backgroundChannel, (method) async {
          if (method.method == 'start') {
            starts++;
            return ready.future;
          }
          return true;
        });
    final fixture = Fixture(), media = FakeMedia();
    final client = fixture.client();
    final call = SocialCallController(
      client: client,
      peer: peer,
      video: false,
      media: media,
    );
    final initialized = call.initialize();
    await tester.pump();
    expect(call.background.starting, true);
    call.backgrounded();
    call.backgrounded();
    await tester.pump(const Duration(seconds: 1));
    expect(call.ended, false);
    ready.complete(true);
    await tester.pump();
    await initialized;
    expect(starts, 1);
    expect(call.background.ready, true);
    expect(call.ended, false);
    expect(media.stopped, false);
    await call.end('End call');
    await tester.pump();
    expect(media.stopped, true);
    call.dispose();
    client.dispose();
    fixture.revision.dispose();
  });

  testWidgets(
    'returning before a failed background startup keeps the foreground call',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ready = Completer<bool>();
      var starts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backgroundChannel, (method) async {
            if (method.method != 'start') return true;
            starts++;
            return starts == 1 ? ready.future : true;
          });
      final fixture = Fixture(), media = FakeMedia();
      final client = fixture.client();
      final call = SocialCallController(
        client: client,
        peer: peer,
        video: false,
        media: media,
      );
      final initialized = call.initialize();
      await tester.pump();
      call.backgrounded();
      call.resume();
      ready.complete(false);
      await tester.pump();
      await initialized;
      expect(call.ended, false);
      expect(media.stopped, false);
      call.resume();
      await tester.pump();
      expect(starts, 2);
      expect(call.background.ready, true);
      await call.end('End call');
      await tester.pump();
      call.dispose();
      client.dispose();
      fixture.revision.dispose();
    },
  );

  testWidgets(
    'Back, Home and return keep the same active call; End still releases it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(backgroundChannel, (_) async => true);
      final fixture = Fixture(), media = FakeMedia();
      final navigator = GlobalKey<NavigatorState>();
      final notifications = SocialNotifications(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': fixture.token},
        sessionChanges: fixture.revision,
        shouldPoll: () => false,
        clientBuilder: fixture.client,
      );
      late SocialCallSession session;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => SocialAppAlerts(
            baseUrl: 'https://fixture.test',
            headersBuilder: () => {'Authorization': fixture.token},
            sessionChanges: fixture.revision,
            navigatorKey: navigator,
            routeObserver: RouteObserver<ModalRoute<dynamic>>(),
            notifications: notifications,
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              session = SocialAlertScope.maybeOf(context)!.calls!;
              return Scaffold(
                body: TextButton(
                  onPressed: () =>
                      unawaited(session.start(peer, false, media: media)),
                  child: const Text('Start test call'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start test call'));
      await tester.pumpAndSettle();
      final call = session.current!;
      expect(call.background.ready, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 3));
      expect(call.ended, false);
      expect(media.stopped, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(session.current, same(call));
      expect(session.minimized, true);
      expect(find.byType(SocialCallScreen), findsNothing);
      expect(find.byType(SocialActiveCallBar), findsOneWidget);
      unawaited(session.restore());
      await tester.pumpAndSettle();
      expect(find.byType(SocialCallScreen), findsOneWidget);
      expect(media.opened, 1);
      await session.end();
      await tester.pumpAndSettle();
      expect(media.stopped, true);
      await tester.pumpWidget(const SizedBox());
      notifications.dispose();
      fixture.revision.dispose();
    },
  );
}
