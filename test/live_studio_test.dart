import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher/link.dart';
import 'package:ai_wiz_command_center/live_studio/live_studio_client.dart';
import 'package:ai_wiz_command_center/live_studio/live_studio_screen.dart';

const showId = 'd98ec9a9-5b8d-4765-b294-063f5ca11292';
Map<String, dynamic> show({String state = 'draft', int version = 1}) => {
  'id': showId,
  'state': state,
  'version': version,
  'config': {
    'title': 'KORLIX Live',
    'topic': 'How can AI help a small business?',
    'category': 'business',
    'durationSeconds': 900,
    'hostCount': 2,
  },
  'progress': {},
};

class FixtureClient extends LiveStudioClient {
  FixtureClient({this.saved = false, this.connected = false})
    : super(
        backendBaseUrl: 'https://fixture.invalid',
        headersBuilder: () => {},
      );
  bool saved;
  bool connected, enabled = true;
  int connectionRevision = 1;
  String channelTitle = 'Customer Channel';
  String state = 'draft';
  int rehearsals = 6, broadcastSeconds = 3600, generations = 450;
  List<Map<String, dynamic>> pendingConnections = [];
  String? confirmedChannel;
  int disconnections = 0, ends = 0;
  int connectionStarts = 0;
  String? disconnectMessage;
  int starts = 0, saves = 0;
  String? requestId;
  String? startedConnectionId;
  int? startedConnectionRevision;
  Map<String, dynamic>? input;
  @override
  Future<Map<String, dynamic>> load() async => {
    'shows': saved ? [show(state: state)] : [],
    'access': {
      'rehearsalReady': true,
      'youtubeReady': connected,
      'canStart': enabled,
      'message': 'Manage shows and your channel from this workspace.',
    },
    'connectionConfigured': true,
    'connection': connected
        ? {
            'id': '6aa0fc74-df5b-4b3d-953c-9b49a40c1fc3',
            'channelId': 'UC-customer-channel',
            'channelTitle': channelTitle,
            'state': 'connected',
            'revision': connectionRevision,
          }
        : null,
    'pendingConnections': pendingConnections,
    'entitlement': {
      'enabled': enabled,
      'label': 'Customer allowance',
      'maxDailyStarts': 7,
    },
    'usage': {
      'dailyStarts': 2,
      'rehearsalsRemaining': rehearsals,
      'broadcastSecondsRemaining': broadcastSeconds,
      'generationsRemaining': generations,
    },
  };
  @override
  Future<Uri> startYouTubeConnection() async {
    connectionStarts++;
    throw const LiveStudioException('Authorization request stopped in test.');
  }

  @override
  Future<void> confirmYouTubeConnection(String id) async {
    confirmedChannel = id;
    connected = true;
    pendingConnections = [];
  }

  @override
  Future<Map<String, dynamic>> disconnectYouTube() async {
    disconnections++;
    connected = false;
    pendingConnections = [];
    return {
      'providerRevoked': disconnectMessage == null,
      if (disconnectMessage != null) 'message': disconnectMessage,
    };
  }

  @override
  Future<Map<String, dynamic>> control(
    String id,
    String action, {
    String? text,
  }) async {
    if (action == 'end') ends++;
    state = 'completed';
    return show(state: state, version: 3);
  }

  @override
  Future<Map<String, dynamic>> save(
    Map<String, dynamic> data,
    String id,
  ) async {
    saved = true;
    saves++;
    input = data;
    requestId = id;
    return show();
  }

  @override
  Future<Map<String, dynamic>> start(
    String id,
    String mode,
    String requestId, {
    DateTime? scheduledAt,
    String? connectionId,
    int? connectionRevision,
  }) async {
    starts++;
    startedConnectionId = connectionId;
    startedConnectionRevision = connectionRevision;
    state = 'queued';
    return {...show(state: 'queued', version: 2), 'mode': mode};
  }
}

String token(String user) =>
    'x.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'sub': user, 'session_id': 'session'}))).replaceAll('=', '')}.x';

void main() {
  test(
    'transport uses authenticated studio paths, never retries writes and reports uncertainty',
    () async {
      var calls = 0;
      final client = LiveStudioClient(
        backendBaseUrl: 'https://fixture.invalid',
        headersBuilder: () => {'Authorization': 'Bearer ${token('one')}'},
        client: MockClient((r) async {
          calls++;
          expect(r.url.path, '/api/live-studio/shows');
          expect(r.headers['authorization'], isNotEmpty);
          throw http.ClientException('offline');
        }),
      );
      await expectLater(
        client.save(show()['config'], liveStudioRequestId()),
        throwsA(isA<LiveStudioException>()),
      );
      expect(calls, 1);
      client.dispose();
    },
  );
  test(
    'changed account invalidates a late response and prevents further access',
    () async {
      var user = 'one';
      final session = ValueNotifier(0), pending = Completer<http.Response>();
      var denied = 0, calls = 0;
      final client = LiveStudioClient(
        backendBaseUrl: 'https://fixture.invalid',
        headersBuilder: () => {'Authorization': 'Bearer ${token(user)}'},
        sessionChanges: session,
        client: MockClient((r) {
          calls++;
          return pending.future;
        }),
      );
      client.onAccessDenied = () => denied++;
      final request = client.load();
      final expectation = expectLater(
        request,
        throwsA(isA<LiveStudioException>()),
      );
      user = 'two';
      session.value++;
      pending.complete(http.Response('{"shows":[]}', 200));
      await expectation;
      await expectLater(client.load(), throwsA(isA<LiveStudioException>()));
      expect(calls, 1);
      expect(denied, 1);
      client.dispose();
      session.dispose();
    },
  );
  test('connection launch accepts only the trusted backend ticket endpoint', () async {
    for (final url in [
      'https://attacker.invalid/api/live-studio/connect/youtube/launch?ticket=safe',
      'https://fixture.invalid.evil.example/api/live-studio/connect/youtube/launch?ticket=safe',
      'http://fixture.invalid/api/live-studio/connect/youtube/launch?ticket=safe',
      'https://user@fixture.invalid/api/live-studio/connect/youtube/launch?ticket=safe',
      'https://fixture.invalid/api/live-studio/connect/youtube/callback?ticket=safe',
      'https://fixture.invalid/api/live-studio/connect/youtube/launch?ticket=safe&ticket=other',
      'https://fixture.invalid/api/live-studio/connect/youtube/launch?ticket=safe&redirect=https://evil.example',
      'https://fixture.invalid/api/live-studio/connect/youtube/launch?ticket=',
      'https://fixture.invalid/api/live-studio/connect/youtube/launch?ticket=safe#other',
      'https://fixture.invalid/api/live-studio/connect/youtube/launch?ticket=safe',
    ]) {
      final client = LiveStudioClient(
        backendBaseUrl: 'https://fixture.invalid',
        headersBuilder: () => {'Authorization': 'Bearer ${token('one')}'},
        client: MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, '/api/live-studio/connections/youtube/start');
          expect(jsonDecode(r.body), {'confirmed': true});
          return http.Response(jsonEncode({'id': 'pending', 'url': url}), 200);
        }),
      );
      if (url ==
          'https://fixture.invalid/api/live-studio/connect/youtube/launch?ticket=safe') {
        expect((await client.startYouTubeConnection()).toString(), url);
      } else {
        await expectLater(
          client.startYouTubeConnection(),
          throwsA(isA<LiveStudioException>()),
        );
      }
      client.dispose();
    }
  });
  test(
    'connection confirmation and disconnect send authenticated explicit consent',
    () async {
      final calls = <http.Request>[];
      final client = LiveStudioClient(
        backendBaseUrl: 'https://fixture.invalid',
        headersBuilder: () => {'Authorization': 'Bearer ${token('one')}'},
        client: MockClient((r) async {
          calls.add(r);
          expect(r.headers['authorization'], isNotEmpty);
          return http.Response('{}', 200);
        }),
      );
      await client.confirmYouTubeConnection('pending-customer-channel');
      await client.disconnectYouTube();
      expect(calls[0].url.path, '/api/live-studio/connections/youtube/confirm');
      expect(jsonDecode(calls[0].body), {
        'id': 'pending-customer-channel',
        'confirmed': true,
      });
      expect(calls[1].method, 'DELETE');
      expect(calls[1].url.path, '/api/live-studio/connections/youtube');
      expect(jsonDecode(calls[1].body), {'confirmed': true});
      client.dispose();
    },
  );
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('studio has no overflow at $width pixels', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1000),
              textScaler: const TextScaler.linear(1.2),
            ),
            child: LiveStudioScreen(
              client: FixtureClient(),
              ensureConsent: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('K-Nova'), findsWidgets);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -950),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final width in [320.0, 768.0]) {
    testWidgets(
      'YouTube consent requires agreement and exposes accessible policy links at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = FixtureClient();
        await tester.pumpWidget(
          MaterialApp(
            home: LiveStudioScreen(
              client: client,
              ensureConsent: () async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expectedLinks = {
          'https://www.korlixdeveloper.com/privacy-policy.html',
          'https://www.korlixdeveloper.com/terms.html',
          'https://www.youtube.com/t/terms',
          'https://policies.google.com/privacy',
        };
        expect(
          tester
              .widgetList<Link>(find.byType(Link))
              .map((link) => link.uri.toString())
              .toSet(),
          expectedLinks,
        );
        final connect = find.byKey(
          const ValueKey('live-studio-connect-youtube'),
        );
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        final links = find.descendant(of: dialog, matching: find.byType(Link));
        expect(
          tester
              .widgetList<Link>(links)
              .map((link) => link.uri.toString())
              .toSet(),
          expectedLinks,
        );
        for (final link in tester.widgetList<Link>(links)) {
          expect(link.target, LinkTarget.blank);
        }
        final proceed = find.byKey(
          const ValueKey('live-studio-youtube-consent-continue'),
        );
        final agreement = find.byKey(
          const ValueKey('live-studio-youtube-agreement'),
        );
        expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
        expect(tester.widget<CheckboxListTile>(agreement).value, isFalse);
        expect(client.connectionStarts, 0);
        await tester.ensureVisible(agreement);
        await tester.tap(agreement);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(proceed).onPressed, isNotNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(client.connectionStarts, 0);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(proceed).onPressed, isNull);
        await tester.ensureVisible(agreement);
        await tester.tap(agreement);
        await tester.pumpAndSettle();
        await tester.tap(proceed);
        await tester.pumpAndSettle();
        expect(client.connectionStarts, 1);
        expect(
          find.text('Authorization request stopped in test.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'save is persistent, YouTube stays disabled, and declining rehearsal never dispatches',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LiveStudioScreen(
            client: client,
            ensureConsent: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('live-studio-save')),
      );
      await tester.tap(find.byKey(const ValueKey('live-studio-save')));
      await tester.pumpAndSettle();
      expect(client.saves, 1);
      expect(client.input?['durationSeconds'], 900);
      expect(client.requestId, isNotEmpty);
      final goLive = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Go live · unlisted'),
      );
      expect(goLive.onPressed, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('live-studio-rehearse')),
      );
      await tester.tap(find.byKey(const ValueKey('live-studio-rehearse')));
      await tester.pumpAndSettle();
      expect(find.text('Create private rehearsal?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.starts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'accepted private rehearsal starts once and survives leaving the screen',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient(saved: true);
      await tester.pumpWidget(
        MaterialApp(
          home: LiveStudioScreen(
            client: client,
            ensureConsent: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ListTile).first);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('live-studio-rehearse')),
      );
      await tester.tap(find.byKey(const ValueKey('live-studio-rehearse')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create rehearsal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.starts, 1);
      expect(
        find.text('You can leave this screen. The server continues the job.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(client.starts, 1);
    },
  );
  testWidgets(
    'allowance changes disable generation but keep saved shows manageable',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient(saved: true, connected: true);
      await tester.pumpWidget(
        MaterialApp(
          home: LiveStudioScreen(
            client: client,
            ensureConsent: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('6 rehearsals remaining'), findsOneWidget);
      expect(find.text('60 broadcast minutes remaining'), findsOneWidget);
      expect(find.text('2 / 7 starts in 24 hours'), findsOneWidget);
      await tester.ensureVisible(find.byType(ListTile).first);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('live-studio-rehearse')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Go live · unlisted'),
            )
            .onPressed,
        isNotNull,
      );
      client.generations = 9;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('live-studio-rehearse')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Go live · unlisted'),
            )
            .onPressed,
        isNull,
      );
      client.generations = 450;
      client.broadcastSeconds = 899;
      client.rehearsals = 0;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('live-studio-rehearse')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Go live · unlisted'),
            )
            .onPressed,
        isNull,
      );
      client.enabled = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Allowance not active'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('live-studio-save')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Remove'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('live-studio-disconnect-youtube')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'channel review confirms the exact pending channel and disconnect explains stopping shows',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient()
        ..pendingConnections = [
          {
            'id': 'pending-2',
            'channelTitle': 'Customer Two',
            'channelId': 'UC-customer-two',
            'expiresAt': '2027-01-01T00:00:00Z',
          },
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: LiveStudioScreen(
            client: client,
            ensureConsent: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final review = find.byKey(
        const ValueKey('live-studio-confirm-pending-2'),
      );
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Customer Two\nChannel ID: UC-customer-two'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.confirmedChannel, isNull);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm channel'));
      await tester.pumpAndSettle();
      expect(client.confirmedChannel, 'pending-2');
      expect(find.text('Review channel before connecting'), findsNothing);
      final disconnect = find.byKey(
        const ValueKey('live-studio-disconnect-youtube'),
      );
      await tester.ensureVisible(disconnect);
      await tester.tap(disconnect);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Queued YouTube shows will be cancelled'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Customer Channel (UC-customer-channel)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Disconnect channel'));
      await tester.pumpAndSettle();
      expect(client.disconnections, 1);
      expect(find.text('No YouTube channel connected.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'disconnect displays provider revocation instructions from the server',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const message =
          'YouTube disconnected from KORLIX. Google revocation could not be confirmed. Remove KORLIX access in your Google account permissions.';
      final client = FixtureClient(connected: true)
        ..disconnectMessage = message;
      await tester.pumpWidget(
        MaterialApp(
          home: LiveStudioScreen(
            client: client,
            ensureConsent: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final disconnect = find.byKey(
        const ValueKey('live-studio-disconnect-youtube'),
      );
      await tester.ensureVisible(disconnect);
      await tester.tap(disconnect);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect channel'));
      await tester.pumpAndSettle();
      expect(client.disconnections, 1);
      expect(find.text(message), findsOneWidget);
      expect(find.text('No YouTube channel connected.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('an expired allowance still allows ending a running show', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FixtureClient(saved: true, connected: true)
      ..enabled = false
      ..state = 'live';
    await tester.pumpWidget(
      MaterialApp(
        home: LiveStudioScreen(client: client, ensureConsent: () async => true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ListTile).first);
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    final end = find.widgetWithText(OutlinedButton, 'End show');
    await tester.ensureVisible(end);
    expect(tester.widget<OutlinedButton>(end).onPressed, isNotNull);
    await tester.tap(end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'End show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(client.ends, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'broadcast remains bound to the channel reviewed before a polling update',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = FixtureClient(saved: true, connected: true);
      await tester.pumpWidget(
        MaterialApp(
          home: LiveStudioScreen(
            client: client,
            ensureConsent: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ListTile).first);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      final live = find.widgetWithText(OutlinedButton, 'Go live · unlisted');
      await tester.ensureVisible(live);
      await tester.tap(live);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('on Customer Channel (UC-customer-channel)'),
        findsOneWidget,
      );
      client.connectionRevision = 2;
      client.channelTitle = 'Different Channel';
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm broadcast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.starts, 1);
      expect(
        client.startedConnectionId,
        '6aa0fc74-df5b-4b3d-953c-9b49a40c1fc3',
      );
      expect(client.startedConnectionRevision, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('capture desktop studio for visual review', (tester) async {
    await tester.runAsync(() async {
      Future<ByteData> font(String path) async =>
          ByteData.sublistView(await File(path).readAsBytes());
      await (FontLoader('Roboto')
            ..addFont(font('assets/fieldproof/Roboto-Regular.ttf'))
            ..addFont(font('assets/fieldproof/Roboto-Bold.ttf')))
          .load();
      final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
      if (sdk != null)
        await (FontLoader('MaterialIcons')..addFont(
              font(
                '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ),
            ))
            .load();
    });
    tester.view.physicalSize = const Size(1200, 1320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RepaintBoundary(
          key: key,
          child: LiveStudioScreen(
            client: FixtureClient(),
            ensureConsent: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (Platform.environment['LIVE_STUDIO_CAPTURE'] case final String output) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
