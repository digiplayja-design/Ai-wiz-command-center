import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing plugin interfaces are used only to keep native services out of widget tests.
// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:ai_wiz_command_center/main.dart' as app;
import 'package:ai_wiz_command_center/contacts_crm/contacts_screen.dart';
import 'package:ai_wiz_command_center/navigation/home_tool_finder.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_grid.dart';
import 'package:ai_wiz_command_center/navigation/home_tool_catalog.dart';
import 'package:ai_wiz_command_center/social/social_alert_scope.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'character_intro_playback_test.dart' show IntroVideoPlatform;

class _Audio extends AudioplayersPlatformInterface {
  @override
  Stream<AudioEvent> getEventStream(String playerId) => const Stream.empty();
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _GlobalAudio extends GlobalAudioplayersPlatformInterface {
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Purchases extends InAppPurchasePlatform {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
}

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final video = VideoPlayerPlatform.instance;
  final audio = AudioplayersPlatformInterface.instance;
  final globalAudio = GlobalAudioplayersPlatformInterface.instance;
  setUpAll(() async {
    final sdk =
        Platform.environment['KORLIX_FLUTTER_ROOT'] ??
        Platform.resolvedExecutable.split('/bin/cache/').first;
    for (final font in [
      (
        'MaterialIcons',
        '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('Roboto', 'assets/fieldproof/Roboto-Regular.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(
            File(font.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchasePlatform.instance = _Purchases();
    debugDefaultTargetPlatformOverride = null;
  });
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchasePlatform.instance = _Purchases();
    AudioplayersPlatformInterface.instance = _Audio();
    GlobalAudioplayersPlatformInterface.instance = _GlobalAudio();
    VideoPlayerPlatform.instance = IntroVideoPlatform();
    SharedPreferences.setMockInitialValues({});
    app.kKorlixAccessToken =
        'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'test', 'sub': 'user', 'session_id': 'session'})))}.signature';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugin.csdcorp.com/speech_to_text'),
          (_) async => true,
        );
  });
  tearDown(() {
    app.kKorlixAccessToken = null;
    debugDefaultTargetPlatformOverride = null;
    VideoPlayerPlatform.instance = video;
    AudioplayersPlatformInterface.instance = audio;
    GlobalAudioplayersPlatformInterface.instance = globalAudio;
  });

  for (final scenario in ['loading', 'failed', 'enterprise', 'denied']) {
    testWidgets('real home opens CRM while tier is $scenario', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<http.Response>();
      final boundary = GlobalKey();
      final requests = <String>[];
      final notifications = SocialNotifications(
        baseUrl: 'https://test.invalid',
        headersBuilder: () => {},
        sessionChanges: app.kKorlixAuthRevision,
        shouldPoll: () => false,
      );
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: app.korlixBuildTheme('korlix_blue'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations:
                      scenario == 'loading' || scenario == 'denied',
                ),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
              home: SocialAlertScope(
                notifications: notifications,
                routeObserver: RouteObserver<ModalRoute<dynamic>>(),
                child: const app.CommandCenterScreen(),
              ),
            ),
          );
          debugDefaultTargetPlatformOverride = null;
          await frames(tester);
          expect(find.byKey(const Key('button-climbers-canvas')), findsNothing);
          final crm = find.byKey(const ValueKey('home-crm'));
          final business = find.byWidgetPredicate(
            (w) => w is KorlixActionSection && w.title == 'For business',
          );
          expect(find.descendant(of: business, matching: crm), findsOneWidget);
          expect(homeBusinessTools.first, 'Contacts CRM');
          await tester.ensureVisible(crm);
          await frames(tester);
          expect(crm.hitTestable(), findsOneWidget);
          expect(find.text('CRM'), findsOneWidget);
          expect(find.text('Contacts CRM'), findsNothing);
          if (scenario == 'failed') {
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            for (final layout in [(390.0, 1.0), (320.0, 2.0), (1024.0, 1.0)]) {
              tester.view.physicalSize = Size(layout.$1, 1000);
              tester.platformDispatcher.textScaleFactorTestValue = layout.$2;
              await frames(tester);
              await Scrollable.ensureVisible(tester.element(business));
              await frames(tester);
              expect(crm.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull, reason: 'home $layout');
              final directory =
                  Platform.environment['KORLIX_NAVIGATION_REVIEW'];
              if (directory != null) {
                await tester.runAsync(() async {
                  final render =
                      boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary;
                  final shot = await render.toImage();
                  final bytes = await shot.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await Directory(directory).create(recursive: true);
                  await File(
                    '$directory/business-${layout.$1.toInt()}-${layout.$2}.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  shot.dispose();
                });
              }
            }
            tester.view.physicalSize = const Size(390, 844);
            tester.platformDispatcher.textScaleFactorTestValue = 1;
            await frames(tester);
            await tester.ensureVisible(crm);
          }
          await tester.tap(crm);
          // A second tap before the transition cannot stack CRM routes.
          await tester.tap(crm, warnIfMissed: false);
          await frames(tester);
          expect(find.byType(ContactsScreen), findsOneWidget);
          expect(requests.where((p) => p.endsWith('/counts')).length, 1);
          if (scenario == 'denied') {
            expect(
              find.text('Contacts CRM requires Enterprise.'),
              findsOneWidget,
            );
          } else {
            expect(find.text('Add your first contact'), findsOneWidget);
          }
          if (scenario == 'denied') {
            await tester.tap(find.text('Back to Korlix'));
          } else {
            await tester.tap(find.byTooltip('Back to Korlix'));
          }
          await frames(tester);
          expect(crm.hitTestable(), findsOneWidget);
          if (scenario == 'enterprise') {
            final search = find.byKey(const ValueKey('home-find-tool'));
            await tester.ensureVisible(search);
            await tester.tap(search);
            await frames(tester);
            await tester.enterText(
              find.byKey(const ValueKey('tool-search')),
              'crm',
            );
            await frames(tester);
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await frames(tester);
            await frames(tester);
            expect(find.byType(ContactsScreen), findsOneWidget);
            expect(requests.where((p) => p.endsWith('/counts')).length, 2);
          }
          if (!pending.isCompleted) pending.complete(response({}, 503));
          await tester.pumpWidget(const SizedBox());
          await frames(tester);
          notifications.dispose();
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path == '/api/me') {
            if (scenario == 'loading') return pending.future;
            if (scenario == 'failed') return response({}, 503);
            return response({
              'profile': {'tier': 'enterprise', 'selected_character': 'jj'},
              'characters': [],
            });
          }
          if (request.url.path.startsWith('/api/contacts')) {
            if (scenario == 'denied')
              return response({'error': 'Enterprise required'}, 403);
            if (request.url.path.endsWith('/counts'))
              return response({'total': 0, 'categories': {}});
            if (request.url.path.endsWith('/capabilities')) return response({});
            return response({'contacts': [], 'count': 0});
          }
          return response({});
        }),
      );
    });
  }

  testWidgets('finder searches tasks, resets empty results and returns CRM', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = null;
    HomeToolEntry? selected;
    final tools = searchableHomeTools(
      quickActionLabels: ['Study / learn', 'Create an App'],
      enterprise: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.push<HomeToolEntry>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HomeToolFinder(tools: tools),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tool-search')),
      'team reminders',
    );
    await tester.pump();
    expect(find.text('Workforce'), findsOneWidget);
    expect(find.text('Contacts CRM'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('tool-search')),
      'zzunknown',
    );
    await tester.pump();
    expect(find.text('No tools found'), findsOneWidget);
    await tester.tap(find.text('Show all tools'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('tool-search')),
      'customers',
    );
    await tester.pump();
    expect(find.text('Contacts CRM'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(selected?.label, 'Contacts CRM');
  });

  testWidgets(
    'tool finder fits small phones, large text, tablets and light themes',
    (tester) async {
      debugDefaultTargetPlatformOverride = null;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final theme in ['korlix_blue', 'pure_white']) {
        for (final layout in [(390.0, 1.0), (320.0, 2.0), (1024.0, 1.0)]) {
          tester.view.physicalSize = Size(layout.$1, 844);
          await tester.pumpWidget(
            MaterialApp(
              theme: app.korlixBuildTheme(theme),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(layout.$2)),
                child: child!,
              ),
              home: HomeToolFinder(
                tools: searchableHomeTools(
                  quickActionLabels: [],
                  enterprise: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('tool-search')),
            'crm',
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Contacts CRM'),
            240,
            scrollable: find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(tester.takeException(), isNull, reason: '$theme $layout');
        }
      }
    },
  );
}
