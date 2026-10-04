import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:ai_wiz_command_center/main.dart' as app;

class IntroVideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final plays = <int, int>{};
  final volumes = <int, double>{};
  final positions = <int, Duration>{};
  final playing = <int, bool>{};
  int next = 1;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = next++;
    streams[id] = StreamController<VideoEvent>.broadcast();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    scheduleMicrotask(
      () => streams[id]!.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(180, 320),
        ),
      ),
    );
    return streams[id]!.stream;
  }

  @override
  Future<void> dispose(int id) async {
    playing[id] = false;
    await streams[id]?.close();
  }

  @override
  Future<void> play(int id) async {
    plays[id] = (plays[id] ?? 0) + 1;
    playing[id] = true;
  }

  @override
  Future<void> pause(int id) async {
    playing[id] = false;
  }

  @override
  Future<void> setLooping(int id, bool looping) async {
    expect(looping, false);
  }

  @override
  Future<void> setVolume(int id, double volume) async {
    volumes[id] = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<void> seekTo(int id, Duration position) async {
    positions[id] = position;
  }

  @override
  Future<Duration> getPosition(int id) async => positions[id] ?? Duration.zero;
  @override
  Widget buildView(int id) => const ColoredBox(color: Colors.teal);
  @override
  Future<void> setMixWithOthers(bool value) async {}
  void complete(int id) =>
      streams[id]!.add(VideoEvent(eventType: VideoEventType.completed));
}

Widget preview({String id = 'jj', bool loop = true}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 180,
        height: 320,
        child: app.KorlixCharacterIntroPreview(
          key: ValueKey(id),
          assetPath: 'assets/characters/$id/intro.mp4',
          showSoundButton: true,
          loop: loop,
        ),
      ),
    ),
  ),
);

void main() {
  late IntroVideoPlatform fake;
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    fake = IntroVideoPlatform();
    VideoPlayerPlatform.instance = fake;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);
  testWidgets(
    'autoplay completes twice and remains muted after duplicate completion or rebuild',
    (tester) async {
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(fake.plays[1], 1);
      fake.complete(1);
      await tester.pumpAndSettle();
      expect(fake.plays[1], 2);
      expect(fake.playing[1], true);
      expect(fake.positions[1], Duration.zero);
      fake.complete(1);
      await tester.pumpAndSettle();
      expect(fake.plays[1], 2);
      expect(fake.playing[1], false);
      expect(fake.volumes[1], 0);
      fake.complete(1);
      await tester.pumpAndSettle();
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(fake.plays[1], 2);
      expect(find.byTooltip('Replay intro (2 plays)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'unmute starts a fresh full intro plus one repeat; then audio is muted',
    (tester) async {
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      fake.positions[1] = const Duration(seconds: 5);
      await tester.tap(find.byTooltip('Unmute'));
      await tester.pumpAndSettle();
      expect(fake.volumes[1], 1);
      expect(fake.positions[1], Duration.zero);
      final audibleStart = fake.plays[1]!;
      fake.complete(1);
      await tester.pumpAndSettle();
      expect(fake.plays[1], audibleStart + 1);
      expect(fake.volumes[1], 1);
      fake.complete(1);
      await tester.pumpAndSettle();
      expect(fake.plays[1], audibleStart + 1);
      expect(fake.volumes[1], 0);
      expect(fake.playing[1], false);
      await tester.tap(find.byTooltip('Replay intro (2 plays)'));
      await tester.pumpAndSettle();
      expect(fake.volumes[1], 1);
      expect(fake.positions[1], Duration.zero);
      fake.complete(1);
      await tester.pumpAndSettle();
      fake.complete(1);
      await tester.pumpAndSettle();
      expect(fake.volumes[1], 0);
      expect(fake.playing[1], false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'changing character resets the two-play cycle and disposes the old player',
    (tester) async {
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      fake.complete(1);
      await tester.pumpAndSettle();
      fake.complete(1);
      await tester.pumpAndSettle();
      await tester.pumpWidget(preview(id: 'yuna'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(fake.plays[2], 1);
      expect(fake.streams[1]!.isClosed, true);
      fake.complete(2);
      await tester.pumpAndSettle();
      expect(fake.plays[2], 2);
      fake.complete(2);
      await tester.pumpAndSettle();
      expect(fake.playing[2], false);
      expect(fake.volumes[2], 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'a global stop prevents a pending repeat and never restarts on rebuild',
    (tester) async {
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      fake.complete(1);
      app.stopKorlixCharacterSpeechGlobally();
      await tester.pumpAndSettle();
      expect(fake.plays[1], 1);
      expect(fake.volumes[1], 0);
      expect(fake.playing[1], false);
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(fake.plays[1], 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'the full final words play and non-looping intros stop after one play',
    (tester) async {
      await tester.pumpWidget(preview(loop: false));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      fake.positions[1] = const Duration(milliseconds: 9900);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(controller.value.isPlaying, true);
      expect(fake.plays[1], 1);
      fake.complete(1);
      await tester.pumpAndSettle();
      expect(fake.plays[1], 1);
      expect(fake.playing[1], false);
      expect(fake.volumes[1], 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
