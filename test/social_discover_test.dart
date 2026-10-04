import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_discover.dart';
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as capture;

class Store {
  final calls = <SocialMap>[];
  final news = <SocialMap>[
    {
      'id': 'news1',
      'title': 'A new chapter for community creators',
      'summary':
          'A local creative programme has announced new workshops and shared spaces. Follow the original reporting for details.',
      'category': 'jamaica',
      'source': 'news.gov.jm',
      'url': 'https://news.gov.jm/story',
      'published_at': DateTime.now().toIso8601String(),
      'checked_at': DateTime.now().toIso8601String(),
      'saved': false,
    },
  ];
  final videos = <SocialMap>[
    for (var i = 0; i < 2; i++)
      {
        'id': 'video$i',
        'seq': 3 - i,
        'state': 'published',
        'caption': 'A moment from Kingston $i',
        'author': social.peer,
        'duration_ms': 12000,
        'created_at': DateTime.now().toIso8601String(),
        'saved': false,
        'liked': false,
        'like_count': 0,
      },
  ];
  Completer<http.Response>? delayed;
  late final client = SocialClient(
    baseUrl: 'https://fixture',
    headersBuilder: () => {'Authorization': 'Bearer alice'},
    client: MockClient((r) async {
      final action = r.url.pathSegments.last;
      final data = r.method == 'POST'
          ? socialMap(jsonDecode(r.body))
          : socialMap(r.url.queryParameters);
      calls.add({'action': action, ...data});
      if (action == 'discover_link') {
        if (delayed != null) return delayed!.future;
        return http.Response(
          jsonEncode({'url': 'https://media.example.org/clip.mp4'}),
          200,
        );
      }
      if (action == 'discover_news') {
        return http.Response(
          jsonEncode({
            'items': data['feed'] == 'saved'
                ? news.where((n) => n['saved'] == true).toList()
                : news,
            'available': true,
            'refreshed_at': DateTime.now().toIso8601String(),
          }),
          200,
        );
      }
      if (action == 'discover_videos') {
        return http.Response(
          jsonEncode({
            'items': data['feed'] == 'saved'
                ? videos.where((v) => v['saved'] == true).toList()
                : videos,
          }),
          200,
        );
      }
      if (action == 'discover_mark') {
        final item = (data['kind'] == 'news' ? news : videos).firstWhere(
          (v) => v['id'] == data['id'],
        );
        item[data['field']] = data['value'];
      }
      return http.Response('{"ok":true}', 200);
    }),
  );
}

class FakeVideo extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final events = <String>[];
  int next = 1;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = next++;
    streams[id] = StreamController<VideoEvent>.broadcast();
    events.add('create:$id');
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    Future.microtask(
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
    events.add('dispose:$id');
    await streams[id]?.close();
  }

  @override
  Future<void> play(int id) async {
    events.add('play:$id');
  }

  @override
  Future<void> pause(int id) async {
    events.add('pause:$id');
  }

  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setVolume(int id, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<void> seekTo(int id, Duration position) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Widget buildView(int id) => const ColoredBox(color: Colors.teal);
  @override
  Future<void> setMixWithOthers(bool value) async {}
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

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
  for (final size in [(360.0, 1.0), (320.0, 1.6), (1100.0, 1.0)]) {
    testWidgets('Discover mixed feed fits ${size.$1} at scale ${size.$2}', (
      t,
    ) async {
      final s = Store();
      await social.mount(
        t,
        SocialDiscoverScreen(client: s.client, profile: social.me),
        width: size.$1,
        scale: size.$2,
      );
      expect(find.text('Discover'), findsWidgets);
      expect(find.text('Share a video'), findsOneWidget);
      expect(find.byKey(const ValueKey('discover-card-news1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discover-card-video0')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      if (size.$2 == 1) {
        await capture.capture(
          t,
          size.$1 > 700 ? 'discover-desktop' : 'discover-mobile',
        );
      }
    });
  }
  testWidgets('news and video tabs, saved stories and topic filters work', (
    t,
  ) async {
    final s = Store();
    await social.mount(
      t,
      SocialDiscoverScreen(client: s.client, profile: social.me),
    );
    await tap(t, find.byKey(const ValueKey('discover-tab-news')));
    expect(find.byKey(const ValueKey('discover-card-video0')), findsNothing);
    await tap(t, find.byTooltip('Save').first);
    expect(s.calls.last['action'], 'discover_mark');
    expect(s.calls.last['kind'], 'news');
    await tap(t, find.byKey(const ValueKey('discover-tab-saved')));
    expect(find.byKey(const ValueKey('discover-card-news1')), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('discover-tab-videos')));
    expect(find.text('Following'), findsOneWidget);
    await tap(t, find.text('Following'));
    expect(
      s.calls.where((c) => c['action'] == 'discover_videos').last['feed'],
      'following',
    );
  });
  testWidgets('sign-out clears cards and rejects pending news or media', (
    t,
  ) async {
    final s = Store();
    await social.mount(
      t,
      SocialDiscoverScreen(client: s.client, profile: social.me),
    );
    s.client.invalidateSession();
    await t.pump();
    expect(find.byKey(const ValueKey('discover-card-news1')), findsNothing);
    expect(find.textContaining('Your session changed'), findsOneWidget);
  });
  testWidgets('a ready draft requires permission before publishing', (t) async {
    final s = Store();
    await social.mount(
      t,
      DiscoverUploadScreen(client: s.client, draft: {'id': 'draft'}),
    );
    final button = find.byKey(const ValueKey('discover-publish'));
    await t.ensureVisible(button);
    expect(t.widget<FilledButton>(button).onPressed, isNull);
    await tap(t, find.byType(CheckboxListTile));
    expect(t.widget<FilledButton>(button).onPressed, isNotNull);
    expect(s.calls.where((c) => c['action'] == 'discover_publish'), isEmpty);
    await tap(t, button);
    expect(s.calls.last['action'], 'discover_publish');
    expect(s.calls.last['accepted_rules'], true);
  });
  testWidgets(
    'video starts on Play, stops on swipe and clears on account change',
    (t) async {
      final original = VideoPlayerPlatform.instance, fake = FakeVideo();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final s = Store();
      await social.mount(
        t,
        DiscoverVideoViewer(
          client: s.client,
          items: s.videos,
          initialId: 'video0',
        ),
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(fake.events, isEmpty);
      expect(find.text('Videos · 1/2'), findsOneWidget);
      await t.tap(find.text('Play').hitTestable());
      await t.pumpAndSettle();
      expect(fake.events, contains('play:1'));

      await t.dragFrom(
        t.getTopLeft(find.byType(PageView)) + const Offset(100, 200),
        const Offset(0, -650),
      );
      await t.pumpAndSettle();

      expect(find.text('Videos · 2/2'), findsOneWidget);
      await t.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await t.pump();
      expect(fake.events, contains('dispose:1'));
      await t.tap(find.text('Play').hitTestable());
      await t.pumpAndSettle();
      expect(fake.events, contains('play:2'));
      s.client.invalidateSession();
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      expect(fake.events, contains('dispose:2'));
      expect(find.text('Your session changed.'), findsOneWidget);
    },
  );
  testWidgets('late playback response cannot open media after sign-out', (
    t,
  ) async {
    final original = VideoPlayerPlatform.instance, fake = FakeVideo();
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = original);
    final s = Store()..delayed = Completer<http.Response>();
    await social.mount(
      t,
      DiscoverVideoViewer(
        client: s.client,
        items: s.videos,
        initialId: 'video0',
      ),
    );
    await t.tap(find.text('Play').first);
    await t.pump();
    s.client.invalidateSession();
    s.delayed!.complete(
      http.Response('{"url":"https://media.example.org/clip.mp4"}', 200),
    );
    await t.pumpAndSettle();
    expect(fake.events, isEmpty);
  });
}
