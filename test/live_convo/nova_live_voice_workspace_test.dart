import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_character_stage.dart';
import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_transcript_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets(
        'Voice ${dark ? 'dark' : 'white'} theme at $width with large text and pinned controls',
        (tester) async {
          final actions = <String>[];
          await mount(tester, dark: dark, width: width, scale: 1.25, actions: actions);
          expect(find.text('Rici'), findsOneWidget);
          expect(find.text('Start LIVE CONVO').hitTestable(), findsOneWidget);
          final agents = find.byKey(const Key('live-voice-agents'));
          expect(agents.hitTestable(), findsOneWidget);
          expect(tester.getTopLeft(agents).dy, lessThan(100));
          await tester.tap(agents);
          await tester.pumpAndSettle();
          expect(actions, ['agent'], reason: 'Agent Studio opens before starting voice');
          expect(
            tester.getBottomRight(find.text('Start LIVE CONVO')).dy,
            lessThan(844),
          );
          await tester.scrollUntilVisible(
            find.byKey(const Key('live-voice-tools')),
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(const Key('live-voice-tools')));
          await tester.pumpAndSettle();
          expect(find.text('Voice: Marin'), findsOneWidget);
          expect(find.text('Agent Studio'), findsOneWidget);
          expect(agents.hitTestable(), findsOneWidget,
              reason: 'The Agents shortcut stays visible while scrolling');
          expect(find.text('Start LIVE CONVO').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'Mute, pause, stop, text, voice and agent actions remain distinct',
    (tester) async {
      final actions = <String>[];
      await mount(tester, connected: true, width: 1280, actions: actions);
      for (final label in ['Mute', 'Pause', 'Stop', 'Type a message']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(actions, ['mute', 'pause', 'stop']);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'Help me plan tomorrow');
      await tester.tap(find.text('Send message'));
      await tester.pumpAndSettle();
      expect(actions.last, 'text:Help me plan tomorrow');
      await tester.scrollUntilVisible(
        find.byKey(const Key('live-voice-tools')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('live-voice-tools')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Voice: Marin'));
      await tester.tap(find.text('Voice: Marin'));
      await tester.ensureVisible(find.text('Agent Studio'));
      await tester.tap(find.text('Agent Studio'));
      expect(actions, containsAll(['voice', 'agent']));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Paused session offers Resume and clear microphone-off guidance',
    (tester) async {
      final actions = <String>[];
      await mount(tester, paused: true, actions: actions);
      expect(find.text('Resume').hitTestable(), findsOneWidget);
      expect(find.text('Start LIVE CONVO'), findsNothing);
      expect(find.textContaining('microphone is off'), findsOneWidget);
      final agents = find.byKey(const Key('live-voice-agents'));
      expect(agents.hitTestable(), findsOneWidget);
      expect(tester.widget<OutlinedButton>(agents).onPressed, isNull,
          reason: 'The shortcut preserves the paused-session lock');
      await tester.tap(find.text('Resume'));
      expect(actions, ['pause']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Inventory voice keeps its focused tools without an Agent Studio shortcut',
    (tester) async {
      await mount(tester, inventory: true);
      expect(find.byKey(const Key('live-voice-agents')), findsNothing);
      expect(find.text('Inventory results'), findsOneWidget);
      expect(find.text('Start LIVE CONVO').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Speaking status uses the agent identity and survives microphone mute',
    (tester) async {
      await mount(
        tester,
        connected: true,
        muted: true,
        status: 'Rici is speaking…',
        agent: 'Custom Coach',
      );
      expect(find.text('Custom Coach is speaking'), findsOneWidget);
      expect(find.text('Phil is speaking'), findsNothing);
      expect(find.text('Unmute'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'Reduced motion disables the continuous halo',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'System back respects stop cancellation and then closes after approval',
    (tester) async {
      var allow = false;
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('Home')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              fixture(connected: true, requestClose: () async => allow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await nav.currentState!.maybePop();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(KorlixLiveConvoCharacterStage), findsOneWidget);
      allow = true;
      await nav.currentState!.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Home'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Voice review captures desktop dark, white and phone screens', (
    tester,
  ) async {
    for (final spec in [
      (true, 1280.0, true),
      (false, 1280.0, false),
      (false, 390.0, true),
    ]) {
      await mount(
        tester,
        dark: spec.$1,
        width: spec.$2,
        connected: spec.$3,
        entries: spec.$3,
        status: spec.$3 ? 'Rici is speaking…' : 'Ready',
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('voice-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/voice-review/${spec.$1 ? 'dark' : 'white'}-${spec.$2.toInt()}.png',
        );
        file.parent.createSync(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}

Future<void> mount(
  WidgetTester tester, {
  bool dark = false,
  double width = 390,
  double scale = 1,
  bool connected = false,
  bool paused = false,
  bool muted = false,
  bool entries = false,
  String status = 'Ready',
  String agent = 'Rici',
  List<String>? actions,
  bool inventory = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: 'Roboto',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const Key('voice-capture'),
        child: fixture(
          connected: connected,
          paused: paused,
          muted: muted,
          entries: entries,
          status: status,
          agent: agent,
          actions: actions,
          inventory: inventory,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Widget fixture({
  bool connected = false,
  bool paused = false,
  bool muted = false,
  bool entries = false,
  String status = 'Ready',
  String agent = 'Rici',
  List<String>? actions,
  Future<bool> Function()? requestClose,
  bool inventory = false,
}) => KorlixLiveConvoCharacterStage(
  inventoryResults: inventory ? (_) => const Text('Inventory results') : null,
  characterId: 'phil',
  language: 'en',
  status: status,
  connected: connected,
  connecting: false,
  paused: paused,
  muted: muted,
  error: null,
  activeAgentName: agent,
  activeAgentDescription: 'Your personal voice companion.',
  userTranscript: '',
  assistantTranscript: '',
  transcriptEntries: entries
      ? [
          KorlixLiveConvoTranscriptEntry(
            id: 'a',
            role: KorlixLiveConvoTranscriptRole.user,
            text:
                'I have an idea for my business, but I’m not sure where to start.',
            source: 'voice',
            timestamp: DateTime(2026, 9, 28, 10, 24),
          ),
          KorlixLiveConvoTranscriptEntry(
            id: 'b',
            role: KorlixLiveConvoTranscriptRole.assistant,
            text:
                'Let’s make it feel manageable. Tell me who you want to help and what would make their day easier.',
            source: 'realtime',
            timestamp: DateTime(2026, 9, 28, 10, 24, 8),
          ),
        ]
      : const [],
  sessionStartedAt: null,
  eventLog: const [],
  rendererReady: false,
  remoteRenderer: rtc.RTCVideoRenderer(),
  onStart: () async => actions?.add('start'),
  onToggleMute: () async => actions?.add('mute'),
  onTogglePause: () async => actions?.add('pause'),
  onEnd: () async => actions?.add('stop'),
  onSendImage: null,
  onSendText: connected
      ? (text) async {
          actions?.add('text:$text');
        }
      : null,
  onOpenAgentHub: paused || inventory ? null : () async => actions?.add('agent'),
  onOpenVoiceSelector: () async => actions?.add('voice'),
  onRequestClose: requestClose,
);
