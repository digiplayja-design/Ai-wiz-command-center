import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'agent_studio_test.dart' as shots;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:ai_wiz_command_center/social/social_online_settings.dart';
import 'package:ai_wiz_command_center/social/social_app_alerts.dart';
import 'package:ai_wiz_command_center/sounds/korlix_sound_service.dart';
import 'social_test.dart' as fixtures;

const peer = <String, dynamic>{
  'id': 'friend',
  'name': 'Jordan',
  'handle': 'jordan',
  'online': true,
  'connection': 'accepted',
  'color': 'cyan',
};

class Store {
  final session = ValueNotifier(0);
  String token = 'Bearer online-user';
  List<SocialMap> events = [], watches = [];
  bool failSave = false;
  Completer<http.Response>? delayed;
  final requests = <SocialMap>[];
  Map<String, String> headers() => {'Authorization': token};
  SocialClient client() => SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: headers,
    sessionChanges: session,
    client: MockClient((r) async {
      final action = r.url.pathSegments.last;
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : socialMap(r.url.queryParameters);
      requests.add({'action': action, ...data});
      if (action == 'online_events' && delayed != null) return delayed!.future;
      if (action == 'online_watch_set' && failSave) {
        return http.Response('{"error":"Please retry"}', 503);
      }
      return http.Response(
        jsonEncode(switch (action) {
          'online_events' => {'items': events},
          'online_watches' => {'items': watches},
          'connections' => {
            'items': [peer],
          },
          'groups' => {'items': []},
          'call_inbox' => {'call': null},
          _ => {'ok': true},
        }),
        200,
      );
    }),
  );
  SocialNotifications notifications() => SocialNotifications(
    baseUrl: 'https://fixture.test',
    headersBuilder: headers,
    sessionChanges: session,
    shouldPoll: () => true,
    clientBuilder: client,
    enableOnlineAlerts: true,
    interval: const Duration(days: 1),
  );
  SocialMap event(String id, {String sound = 'bell'}) => {
    'id': id,
    'peer': peer,
    'sound': sound,
  };
}

class Sounds extends KorlixSoundService {
  final played = <KorlixSound>[];
  @override
  Future<void> play(KorlixSound sound, {String? eventId}) async {
    played.add(sound);
  }

  @override
  void setRinging(
    Object owner,
    bool ringing, {
    String? callId,
    DateTime? expiresAt,
    bool outgoing = false,
  }) {}
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets(
    'online settings remain usable on a narrow screen with large text',
    (t) async {
      final s = Store(), client = s.client();
      s.watches = [
        {'peer': peer, 'sound': 'ring'},
      ];
      await fixtures.mount(
        t,
        SocialOnlineSettings(client: client, peer: peer),
        width: 320,
        scale: 1.5,
      );
      await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      client.dispose();
      s.session.dispose();
    },
  );

  testWidgets(
    'online events queue once, expire on refresh and do not repeat after dismissal',
    (t) async {
      final s = Store(),
          n = Store(); // Separate accounts never share a baseline.
      final alerts = s.notifications(), other = n.notifications();
      s.events = [s.event('one'), s.event('two')];
      await alerts.refreshOnline();
      expect(alerts.onlineAlert!.id, 'one');
      final revision = alerts.onlineRevision;
      await alerts.refreshOnline();
      expect(alerts.onlineRevision, revision);
      alerts.dismissOnline();
      expect(alerts.onlineAlert!.id, 'two');
      alerts.dismissOnline();
      await alerts.refreshOnline();
      expect(alerts.onlineAlert, isNull);
      await other.refreshOnline();
      expect(other.onlineAlert, isNull);
      s.events = [s.event('new')];
      await alerts.refreshOnline();
      expect(alerts.onlineAlert, isNotNull);
      s.events = [];
      await alerts.refreshOnline();
      expect(alerts.onlineAlert, isNull);
      alerts.dispose();
      other.dispose();
      s.session.dispose();
      n.session.dispose();
    },
  );
  testWidgets(
    'account change clears alert identity and discards a late prior-account response',
    (t) async {
      final s = Store();
      final n = s.notifications();
      s.events = [s.event('first')];
      await n.refreshOnline();
      s.delayed = Completer<http.Response>();
      final request = n.refreshOnline();
      s.token = 'Bearer replacement';
      s.events = [];
      s.session.value++;
      expect(n.onlineAlert, isNull);
      final pending = s.delayed!;
      s.delayed = null;
      pending.complete(
        http.Response(
          jsonEncode({
            'items': [s.event('private-old')],
          }),
          200,
        ),
      );
      await request;
      await n.refreshOnline();
      expect(n.onlineAlert, isNull);
      n.dispose();
      s.session.dispose();
    },
  );
  for (final choice in ['bell', 'ring', 'silent']) {
    testWidgets(
      '$choice alert displays the selected connection and plays at most once',
      (t) async {
        final s = Store(), sound = Sounds(), n = s.notifications();
        final navigator = GlobalKey<NavigatorState>(),
            observer = RouteObserver<ModalRoute<dynamic>>();
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            builder: (_, child) => SocialAppAlerts(
              baseUrl: 'https://fixture.test',
              headersBuilder: s.headers,
              sessionChanges: s.session,
              navigatorKey: navigator,
              routeObserver: observer,
              notifications: n,
              sounds: sound,
              child: child!,
            ),
            home: const Scaffold(body: Text('Another KORLIX tool')),
          ),
        );
        await t.pumpAndSettle();
        s.events = [s.event('arrival', sound: choice)];
        await n.refreshOnline();
        await t.pumpAndSettle();
        expect(find.text('Connection online'), findsOneWidget);
        expect(find.text('Jordan'), findsOneWidget);
        expect(
          sound.played,
          choice == 'silent'
              ? isEmpty
              : equals([
                  choice == 'ring' ? KorlixSound.ringtone : KorlixSound.bell,
                ]),
        );
        await n.refreshOnline();
        await t.pumpAndSettle();
        expect(sound.played.length, choice == 'silent' ? 0 : 1);
        await t.tap(find.text('Dismiss'));
        await t.pumpAndSettle();
        expect(find.text('Connection online'), findsNothing);
        await t.pumpWidget(const SizedBox());
        n.dispose();
        sound.dispose();
        s.session.dispose();
      },
    );
  }
  testWidgets(
    'selection is opt-in, failed saves stay off and account changes clear settings',
    (t) async {
      final s = Store(), client = s.client();
      await fixtures.mount(
        t,
        SocialOnlineSettings(client: client, peer: peer),
        width: 390,
      );
      await t.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('online-watch-friend'));
      await t.ensureVisible(toggle);
      s.failSave = true;
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(find.text('Please retry'), findsOneWidget);
      expect(find.text('Alert sound'), findsNothing);
      s.failSave = false;
      await t.ensureVisible(toggle);
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(find.text('Alert sound'), findsOneWidget);
      await shots.capture(t, 'online-alert-settings');
      expect(
        s.requests.lastWhere((r) => r['action'] == 'online_watch_set'),
        containsPair('enabled', true),
      );
      await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Short ring').last);
      await t.pumpAndSettle();
      expect(
        s.requests.lastWhere((r) => r['action'] == 'online_watch_set'),
        containsPair('sound', 'ring'),
      );
      expect(t.takeException(), isNull);
      s.token = 'Bearer replacement';
      s.session.value++;
      await t.pumpAndSettle();
      expect(find.text('Jordan'), findsNothing);
      await t.pumpWidget(const SizedBox());
      client.dispose();
      s.session.dispose();
    },
  );
}
