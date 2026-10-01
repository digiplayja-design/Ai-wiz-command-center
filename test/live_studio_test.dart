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
  FixtureClient({this.saved = false})
    : super(
        backendBaseUrl: 'https://fixture.invalid',
        headersBuilder: () => {},
      );
  bool saved;
  int starts = 0, saves = 0;
  String? requestId;
  Map<String, dynamic>? input;
  @override
  Future<Map<String, dynamic>> load() async => {
    'shows': saved ? [show()] : [],
    'access': {
      'rehearsalReady': true,
      'youtubeReady': false,
      'message': 'Connect YouTube and activate the broadcast worker.',
    },
  };
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
  }) async {
    starts++;
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
