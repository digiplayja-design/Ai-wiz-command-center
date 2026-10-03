import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_media_widgets.dart';
import 'package:ai_wiz_command_center/social/social_note_playback.dart';
import 'social_test.dart' as social;

class Playback extends SocialNotePlayback {
  final events = <String>[];
  final sources = <String?>[];
  String? url;
  double rate = 1;
  int plays = 0;
  bool failPlay = false;
  @override
  void source({Uint8List? bytes, String? url}) {
    if (closed) return;
    this.url = url;
    sources.add(url);
    events.add(url == null ? 'clear' : 'source');
    playing = false;
    position = duration = Duration.zero;
  }

  @override
  Future<void> activate() {
    events.add('activate');
    return Future.value();
  }

  @override
  Future<void> play() async {
    events.add('play');
    plays++;
    if (failPlay) throw StateError('Expired URL');
    expect(url, isNotNull);
    playing = true;
    duration = const Duration(seconds: 30);
    changed();
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    playing = false;
    changed();
  }

  @override
  Future<void> seek(Duration value) async {
    events.add('seek');
    position = value;
  }

  @override
  Future<void> speed(double value) async {
    events.add('speed');
    rate = value;
  }

  @override
  void dispose() {
    closed = true;
    playing = false;
    super.dispose();
  }
}

Future<void> mount(
  WidgetTester t,
  Playback playback,
  Future<String> Function() refresh, {
  SocialClient? client,
  bool wall = true,
  String? url,
}) => social.mount(
  t,
  Scaffold(
    body: SocialVoicePlayer(
      durationMs: 30000,
      url: url,
      resolveBeforePlay: wall,
      accessClient: client,
      refreshUrl: refresh,
      playbackFactory: () => playback,
    ),
  ),
);

void main() {
  testWidgets(
    'wall waits for authorized URL on the first tap without autoplay',
    (t) async {
      final p = Playback();
      final gate = Completer<String>();
      await mount(t, p, () {
        p.events.add('resolve');
        return gate.future;
      });
      expect(p.events, isEmpty);
      await t.tap(find.byTooltip('Play voice note'));
      await t.pump();
      expect(p.events, ['activate', 'resolve']);
      expect(p.plays, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete('https://media.test/voice?token=fresh');
      await t.pumpAndSettle();
      expect(p.events, [
        'activate',
        'resolve',
        'source',
        'seek',
        'speed',
        'play',
      ]);
      expect(p.plays, 1);
      expect(find.byTooltip('Pause voice note'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('resume and replay reauthorize and preserve position and speed', (
    t,
  ) async {
    final p = Playback();
    var links = 0;
    await mount(t, p, () async => 'https://media.test/voice?token=${++links}');
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    p.position = const Duration(seconds: 12);
    p.changed();
    await t.tap(find.text('1×'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Pause voice note'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    expect(links, 2);
    expect(p.position, const Duration(seconds: 12));
    expect(p.rate, 1.5);
    expect(p.url, endsWith('token=2'));
    p.playing = false;
    p.position = Duration.zero;
    p.changed();
    await t.pump();
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    expect(links, 3);
    expect(p.position, Duration.zero);
  });

  for (final status in [403, 404]) {
    testWidgets('permission $status clears stale audio without playing', (
      t,
    ) async {
      final p = Playback();
      var denied = false;
      await mount(t, p, () async {
        if (denied) throw SocialException('Denied', status);
        return 'https://media.test/voice';
      });
      await t.tap(find.byTooltip('Play voice note'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Pause voice note'));
      await t.pumpAndSettle();
      denied = true;
      await t.tap(find.byTooltip('Play voice note'));
      await t.pumpAndSettle();
      expect(p.url, isNull);
      expect(p.playing, false);
      expect(p.plays, 1);
      expect(
        find.text('This voice note is no longer available to you.'),
        findsOneWidget,
      );
    });
  }

  testWidgets('failed signed source is cleared and retry fetches a new URL', (
    t,
  ) async {
    final p = Playback()..failPlay = true;
    var links = 0;
    await mount(t, p, () async => 'https://media.test/voice?token=${++links}');
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    expect(p.url, isNull);
    expect(find.textContaining('Could not play'), findsOneWidget);
    p.failPlay = false;
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    expect(p.url, endsWith('token=2'));
    expect(p.playing, true);
  });

  testWidgets('late URL after disposal cannot load or play', (t) async {
    final p = Playback(), gate = Completer<String>();
    await mount(t, p, () => gate.future);
    await t.tap(find.byTooltip('Play voice note'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    gate.complete('https://media.test/late');
    await t.pump();
    expect(p.closed, true);
    expect(p.sources, isEmpty);
    expect(p.plays, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('late URL after account change is discarded', (t) async {
    final p = Playback(), gate = Completer<String>();
    var token = 'Bearer account-one';
    final session = ValueNotifier(0);
    final client = SocialClient(
      baseUrl: 'https://api.test',
      headersBuilder: () => {'Authorization': token},
      sessionChanges: session,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await mount(t, p, () => gate.future, client: client);
    await t.tap(find.byTooltip('Play voice note'));
    await t.pump();
    token = 'Bearer account-two';
    session.value++;
    gate.complete('https://media.test/old-account');
    await t.pumpAndSettle();
    expect(p.url, isNull);
    expect(p.plays, 0);
    expect(find.textContaining('Your session changed'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    client.dispose();
    session.dispose();
  });

  testWidgets(
    '401 permission lookup clears audio and explains the session change',
    (t) async {
      final p = Playback();
      final client = SocialClient(
        baseUrl: 'https://api.test',
        headersBuilder: () => {'Authorization': 'Bearer account-one'},
        client: MockClient(
          (_) async => http.Response('{"error":"Please sign in"}', 401),
        ),
      );
      await mount(t, p, () async {
        final response = await client.get('attachment_link', {'id': 'voice'});
        return '${response['url']}';
      }, client: client);
      await t.tap(find.byTooltip('Play voice note'));
      await t.pumpAndSettle();
      expect(p.url, isNull);
      expect(p.plays, 0);
      expect(find.textContaining('Your session changed'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      client.dispose();
    },
  );

  testWidgets(
    'background cancels pending URL and does not autoplay on return',
    (t) async {
      final p = Playback(), gate = Completer<String>();
      await mount(t, p, () => gate.future);
      await t.tap(find.byTooltip('Play voice note'));
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gate.complete('https://media.test/late');
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(p.url, isNull);
      expect(p.plays, 0);
      expect(find.byTooltip('Play voice note'), findsOneWidget);
    },
  );

  testWidgets('background lifecycle sequence preserves resume position', (
    t,
  ) async {
    final p = Playback();
    var links = 0;
    await mount(t, p, () async => 'https://media.test/voice?token=${++links}');
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    p.position = const Duration(seconds: 17);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(p.url, isNull);
    expect(p.playing, false);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(p.plays, 1);
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    expect(links, 2);
    expect(p.position, const Duration(seconds: 17));
  });

  testWidgets('existing private audio keeps direct gesture playback', (
    t,
  ) async {
    final p = Playback();
    var refreshed = false;
    await mount(
      t,
      p,
      () async {
        refreshed = true;
        return 'https://media.test/unused';
      },
      wall: false,
      url: 'https://media.test/private',
    );
    await t.tap(find.byTooltip('Play voice note'));
    await t.pumpAndSettle();
    expect(p.events, ['source', 'play']);
    expect(refreshed, false);
  });
}
