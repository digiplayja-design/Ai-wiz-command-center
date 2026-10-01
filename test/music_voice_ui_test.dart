import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/music_studio/music_studio_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'music_studio_test.dart' as fixture;

class VoicePlayer extends fixture.FakePlayer {
  int pauses = 0;
  bool failPause = false;
  Completer<void>? pauseWait;
  @override
  Future<void> pauseForVoice() async {
    pauses++;
    if (failPause) throw StateError('Native pause failed');
    if (pauseWait != null) await pauseWait!.future;
    playing = false;
    notifyListeners();
  }
}

final capture = GlobalKey();
Future<void> showVoice(
  WidgetTester t,
  fixture.FakeMusic client, {
  required Future<Map<String, dynamic>?> Function(Map<String, dynamic>) open,
  VoicePlayer? player,
  double width = 1100,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 1100);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('korlix_blue'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: capture,
        child: MusicStudioScreen(
          client: client,
          player: player ?? VoicePlayer(),
          openVoice: open,
          ensureConsent: (_) async => true,
          pollInterval: const Duration(hours: 1),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 150));
}

Future<void> talk(WidgetTester t) =>
    fixture.tap(t, find.byKey(const ValueKey('music-open-voice')));
Map<String, dynamic> draftResult() => {
  'action': 'draft',
  'draft': fixture.recipe(),
};

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
  testWidgets(
    'Talk awaits actual audio pause and prepares without saving or generating',
    (t) async {
      final c = fixture.FakeMusic();
      final p = VoicePlayer()
        ..playing = true
        ..pauseWait = Completer<void>();
      final voice = Completer<Map<String, dynamic>?>();
      Map<String, dynamic>? sent;
      await showVoice(
        t,
        c,
        player: p,
        open: (draft) {
          sent = draft;
          return voice.future;
        },
      );
      await fixture.enter(t, 'music-idea', 'My unsaved jingle');
      await talk(t);
      expect(p.pauses, 1);
      expect(sent, isNull);
      p.pauseWait!.complete();
      await t.pump();
      expect(sent!['idea'], 'My unsaved jingle');
      expect(p.playing, isFalse);
      voice.complete(draftResult());
      await t.pump();
      expect(c.saves, isEmpty);
      expect(c.starts, isEmpty);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('music-idea')))
            .controller!
            .text,
        fixture.recipe()['idea'],
      );
      expect(
        find.textContaining('Nothing has been generated.'),
        findsOneWidget,
      );
      await fixture.close(t);
    },
  );

  testWidgets('Failed native pause never opens the microphone route', (
    t,
  ) async {
    final c = fixture.FakeMusic();
    final p = VoicePlayer()..failPause = true;
    int calls = 0;
    await showVoice(
      t,
      c,
      player: p,
      open: (_) async {
        calls++;
        return null;
      },
    );
    await talk(t);
    expect(calls, 0);
    expect(find.textContaining('Could not switch audio modes'), findsOneWidget);
    expect(c.starts, isEmpty);
    await fixture.close(t);
  });

  testWidgets(
    'Voice creation requires exact recipe confirmation and cancel writes nothing',
    (t) async {
      final c = fixture.FakeMusic();
      await showVoice(t, c, open: (_) async => draftResult());
      await talk(t);
      await fixture.tap(t, find.byKey(const ValueKey('music-generate')));
      expect(find.text('Create this music?'), findsOneWidget);
      expect(find.textContaining('Uses 1 creation'), findsWidgets);
      expect(
        find.textContaining('Fresh start · Song from idea'),
        findsOneWidget,
      );
      expect(c.saves, isEmpty);
      expect(c.starts, isEmpty);
      await fixture.tap(t, find.text('Keep editing'));
      expect(c.saves, isEmpty);
      expect(c.starts, isEmpty);
      await fixture.tap(t, find.byKey(const ValueKey('music-generate')));
      await fixture.tap(
        t,
        find.byKey(const ValueKey('music-voice-confirm-generation')),
      );
      expect(c.saves, hasLength(1));
      expect(c.starts, hasLength(1));
      expect(c.starts.single['idea'], fixture.recipe()['idea']);
      await fixture.close(t);
    },
  );

  testWidgets(
    'Uncertain voice generation retries same key without a second approval',
    (t) async {
      final c = fixture.FakeMusic()..failStart = true;
      await showVoice(t, c, open: (_) async => draftResult());
      await talk(t);
      await fixture.tap(t, find.byKey(const ValueKey('music-generate')));
      await fixture.tap(
        t,
        find.byKey(const ValueKey('music-voice-confirm-generation')),
      );
      expect(c.starts, hasLength(1));
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const ValueKey('music-open-voice')),
            )
            .onPressed,
        isNull,
      );
      await fixture.tap(t, find.byKey(const ValueKey('music-generate')));
      expect(find.text('Create this music?'), findsNothing);
      expect(c.starts, hasLength(2));
      expect(c.starts.last['request_key'], c.starts.first['request_key']);
      await fixture.close(t);
    },
  );

  testWidgets(
    'Listen rechecks an owned ready version before playing after voice returns',
    (t) async {
      final c = fixture.FakeMusic()..rows = [fixture.job()];
      final p = VoicePlayer();
      final voice = Completer<Map<String, dynamic>?>();
      await showVoice(t, c, player: p, open: (_) => voice.future);
      await talk(t);
      expect(p.toggles, 0);
      expect(c.statuses, 0);
      voice.complete({
        'action': 'listen',
        'job_id': fixture.id,
        'track_index': 0,
      });
      await t.pump();
      await t.pump();
      expect(c.statuses, 1);
      expect(p.toggles, 1);
      expect(p.activeId, '${fixture.id}:0');
      expect(find.textContaining('Listen mode · K-Nova'), findsOneWidget);
      expect(c.starts, isEmpty);
      await fixture.close(t);
    },
  );

  testWidgets('Listen rejects an invalid version without starting playback', (
    t,
  ) async {
    final c = fixture.FakeMusic()..rows = [fixture.job()];
    final p = VoicePlayer();
    await showVoice(
      t,
      c,
      player: p,
      open: (_) async => {
        'action': 'listen',
        'job_id': fixture.id,
        'track_index': 99,
      },
    );
    await talk(t);
    expect(c.statuses, 1);
    expect(p.toggles, 0);
    expect(find.textContaining('That version is not ready'), findsOneWidget);
    await fixture.close(t);
  });

  testWidgets('Malformed returned recipes preserve the current unsaved idea', (
    t,
  ) async {
    final c = fixture.FakeMusic();
    await showVoice(
      t,
      c,
      open: (_) async => {
        'action': 'draft',
        'draft': {
          ...fixture.recipe(),
          'request_key': 'not-an-allowed-draft-field',
        },
      },
    );
    await fixture.enter(t, 'music-idea', 'Keep this idea');
    await talk(t);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('music-idea')))
          .controller!
          .text,
      'Keep this idea',
    );
    expect(c.starts, isEmpty);
    expect(c.saves, isEmpty);
    await fixture.close(t);
  });

  testWidgets('A late voice recipe never overwrites a studio change', (
    t,
  ) async {
    final c = fixture.FakeMusic();
    final voice = Completer<Map<String, dynamic>?>();
    await showVoice(t, c, open: (_) => voice.future);
    await talk(t);
    final field = t.widget<TextField>(find.byKey(const ValueKey('music-idea')));
    field.controller!.text = 'A newer idea';
    voice.complete(draftResult());
    await t.pump();
    expect(field.controller!.text, 'A newer idea');
    expect(find.textContaining('Your current edits were kept'), findsOneWidget);
    expect(c.starts, isEmpty);
    await fixture.close(t);
  });

  testWidgets('Sign-out discards a late voice result and stops playback', (
    t,
  ) async {
    final c = fixture.FakeMusic();
    final p = VoicePlayer();
    final voice = Completer<Map<String, dynamic>?>();
    await showVoice(t, c, player: p, open: (_) => voice.future);
    await talk(t);
    c.logout();
    await t.pump();
    voice.complete(draftResult());
    await t.pump();
    expect(find.textContaining('Your session changed.'), findsOneWidget);
    expect(c.starts, isEmpty);
    expect(c.saves, isEmpty);
    expect(p.stops, greaterThan(0));
    await fixture.close(t);
  });

  for (final width in [390.0, 1024.0]) {
    testWidgets(
      'Producer card fits ${width.toInt()} px and appears in both tabs',
      (t) async {
        final c = fixture.FakeMusic()..rows = [fixture.job()];
        await showVoice(
          t,
          c,
          width: width,
          scale: 1.25,
          open: (_) async => null,
        );
        expect(find.text('Create with K-Nova'), findsOneWidget);
        expect(t.takeException(), isNull);
        await fixture.library(t);
        expect(find.text('Create with K-Nova'), findsOneWidget);
        expect(t.takeException(), isNull);
        final dir = const String.fromEnvironment('MUSIC_VOICE_SCREENSHOT_DIR');
        if (dir.isNotEmpty) {
          await t.pump();
          await t.runAsync(() async {
            await Directory(dir).create(recursive: true);
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$dir/music-voice-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await fixture.close(t);
      },
    );
  }
}
