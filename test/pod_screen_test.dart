import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_wiz_command_center/pod/pod_client.dart';
import 'package:ai_wiz_command_center/pod/pod_media.dart';
import 'package:ai_wiz_command_center/pod/pod_screen.dart';
import 'package:ai_wiz_command_center/pod/pod_wake_lock.dart';
import 'package:ai_wiz_command_center/pod/pod_transition_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _time = DateTime.utc(2026, 10, 1, 12);
Map<String, dynamic> _episode({
  String state = 'ready',
  int version = 0,
  int? remaining,
}) => {
  'id': 'private-episode',
  'category': 'technology',
  'topic': 'A useful question',
  'durationSeconds': 300,
  'hostCount': 2,
  'style': 'balanced',
  'state': state,
  'phase': 'ready',
  'version': version,
  'serverNow': _time.toIso8601String(),
  if (remaining != null)
    'deadlineAt': _time.add(Duration(seconds: remaining)).toIso8601String(),
  'turns': <Map<String, dynamic>>[],
  'sources': <Map<String, dynamic>>[],
};

Map<String, dynamic> _turnResponse({int remaining = 300}) {
  final turn = {
    'id': 'turn-1',
    'seq': 1,
    'speaker': 'host',
    'text': 'Welcome. Let us explore this question.',
    'sourceIds': <String>[],
  };
  return {
    'episode': {
      ..._episode(state: 'active', remaining: remaining),
      'turns': [turn],
    },
    'turn': turn,
    'audio': {
      'mime': 'audio/wav',
      'base64': base64Encode([82, 73, 70, 70]),
      'durationSeconds': 3,
    },
  };
}

class _FakePod extends PodClient {
  _FakePod(this.events)
    : super(backendBaseUrl: 'https://pod.test', headersBuilder: () => {});
  final List<String> events;
  bool allowed = true, cancelPreparing = true;
  Map<String, dynamic> current = _episode();
  final pending = <Completer<Map<String, dynamic>>>[];
  final actions = <String>[];
  final preparing = <Completer<Map<String, dynamic>>>[];
  final prepareIds = <String>[];
  final playedPrepared = <String>[];
  Map<String, dynamic>? preparedPlaybackResponse;
  Completer<Map<String, dynamic>>? consuming;
  Object? consumeFailure,
      contributionFailure,
      transcriptionFailure,
      resumeFailure;
  final contributionIds = <String>[];
  final transcriptionIds = <String>[];
  Completer<Map<String, dynamic>>? contributing;
  Completer<Map<String, dynamic>>? creating, interrupting;
  int creates = 0, transcriptions = 0, contributions = 0;
  @override
  Future<Map<String, dynamic>> load() async => {
    'catalog': [],
    'access': {
      'allowed': allowed,
      'durations': [300, 600, 900],
      'maxSeconds': 900,
    },
    'episodes': [],
  };
  @override
  Future<Map<String, dynamic>> create({
    required String requestId,
    required String category,
    required String topic,
    required int durationSeconds,
    required int hostCount,
    required String style,
  }) async {
    events.add('create');
    creates++;
    return creating == null ? current : creating!.future;
  }

  @override
  Future<Map<String, dynamic>> next(
    String id, {
    required String requestId,
    required int version,
  }) {
    events.add('next');
    final result = Completer<Map<String, dynamic>>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<Map<String, dynamic>> prepare(
    String id, {
    required String requestId,
    required int version,
  }) {
    events.add('prepare');
    final result = Completer<Map<String, dynamic>>();
    preparing.add(result);
    prepareIds.add(requestId);
    return result.future;
  }

  void completePreparation(int index) {
    current = {...current, 'preparedId': prepareIds[index]};
    preparing[index].complete({
      'episode': current,
      'prepared': true,
      'preparedId': prepareIds[index],
    });
  }

  @override
  Future<Map<String, dynamic>> playPrepared(
    String id, {
    required String requestId,
    required int version,
  }) async {
    events.add('play-prepared');
    playedPrepared.add(requestId);
    if (consumeFailure != null) {
      final failure = consumeFailure!;
      consumeFailure = null;
      throw failure;
    }
    if (consuming != null) return consuming!.future;
    final turn = {
      'id': 'turn-${playedPrepared.length + 1}',
      'seq': playedPrepared.length + 1,
      'speaker': 'analyst',
      'text': 'The next perspective stays private until playback.',
      'sourceIds': <String>[],
    };
    final response =
        preparedPlaybackResponse ??
        {
          ..._turnResponse(),
          'turn': turn,
          'episode': {
            ...current,
            'preparedId': null,
            'turns': [...current['turns'] as List, turn],
          },
        };
    current = Map<String, dynamic>.from(response['episode']);
    return response;
  }

  void complete(int index, Map<String, dynamic> response) {
    current = Map<String, dynamic>.from(response['episode']);
    pending[index].complete(response);
  }

  @override
  Future<Map<String, dynamic>> episode(String id) async => current;
  @override
  Future<Map<String, dynamic>> control(String id, String action) async {
    actions.add(action);
    if (['pause', 'interrupt', 'end'].contains(action)) {
      if (cancelPreparing) {
        for (final pending in preparing) {
          if (!pending.isCompleted) {
            pending.completeError(const PodException('Preparation cancelled.'));
          }
        }
      }
      if (action != 'pause') current = {...current, 'preparedId': null};
    }
    if (action == 'interrupt' && interrupting != null) {
      return interrupting!.future;
    }
    if (action == 'resume' && resumeFailure != null) {
      final failure = resumeFailure!;
      resumeFailure = null;
      throw failure;
    }
    if (action != 'heartbeat') {
      current = {
        ...current,
        'version': (current['version'] as int) + 1,
        'state': action == 'end'
            ? 'ended'
            : action == 'resume'
            ? 'active'
            : 'paused',
      };
    }
    return current;
  }

  @override
  Future<String> transcribe(
    String id,
    Uint8List wav, {
    required String requestId,
  }) async {
    transcriptions++;
    transcriptionIds.add(requestId);
    events.add('transcribe');
    if (transcriptionFailure != null) {
      final failure = transcriptionFailure!;
      transcriptionFailure = null;
      throw failure;
    }
    return 'My reviewed thought';
  }

  @override
  Future<Map<String, dynamic>> contribute(
    String id,
    String text, {
    required String requestId,
  }) async {
    contributions++;
    contributionIds.add(requestId);
    events.add('contribute');
    if (contributionFailure != null) {
      final failure = contributionFailure!;
      contributionFailure = null;
      throw failure;
    }
    if (contributing != null) return contributing!.future;
    return current;
  }
}

class _FakeMedia extends PodMedia {
  _FakeMedia(this.events);
  final List<String> events;
  int activations = 0, plays = 0, stops = 0, recordings = 0, cancellations = 0;
  bool failPlay = false, autoStart = true;
  VoidCallback? playbackStarted;
  Completer<void>? playback;
  Completer<void>? microphonePermission;
  @override
  bool blocked = false;
  @override
  bool playing = false;
  @override
  bool recording = false;
  @override
  bool recordingAvailable = false;
  @override
  Duration elapsed = Duration.zero;
  @override
  String? error;
  @override
  Future<void> activate() async {
    events.add('activate');
    activations++;
    blocked = false;
    error = null;
  }

  @override
  Future<void> play(Uint8List wav, {VoidCallback? onStarted}) async {
    plays++;
    if (failPlay) {
      failPlay = false;
      throw const PodMediaException(
        'Sound blocked. Tap Resume sound.',
        blocked: true,
      );
    }
    playbackStarted = onStarted;
    if (autoStart) begin();
    playback = Completer<void>();
    await playback!.future;
    playing = false;
  }

  void begin() {
    playing = true;
    playbackStarted?.call();
    playbackStarted = null;
  }

  void finish() {
    if (playback?.isCompleted == false) playback!.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
    finish();
  }

  @override
  Future<void> startRecording() async {
    recordings++;
    if (microphonePermission != null) await microphonePermission!.future;
    recording = true;
  }

  @override
  Future<Uint8List> stopRecording() async {
    recording = false;
    return Uint8List(44);
  }

  @override
  Future<void> cancelRecording() async {
    cancellations++;
    recording = false;
  }
}

class _WakeLease implements PodWakeLockLease {
  @override
  bool released = false;
  VoidCallback? callback;
  @override
  void onRelease(VoidCallback? value) => callback = value;
  @override
  Future<void> release() async {
    released = true;
    callback?.call();
  }
}

class _WakeBackend implements PodWakeLockBackend {
  @override
  bool get supported => true;
  final leases = <_WakeLease>[];
  @override
  Future<PodWakeLockLease> acquire() async {
    final lease = _WakeLease();
    leases.add(lease);
    return lease;
  }
}

class _TransitionBackend implements PodTransitionBackend {
  final events = <String>[];
  @override
  bool get supported => true;
  @override
  Future<bool> activate() async {
    events.add('activate');
    return true;
  }

  @override
  bool start(Duration maximumDuration) {
    events.add('start');
    return true;
  }

  @override
  Future<void> stop({required bool immediate}) async {
    events.add(immediate ? 'stop' : 'fade');
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _mount(
  WidgetTester tester,
  _FakePod client,
  _FakeMedia media,
  List<String> events, {
  DateTime Function()? now,
  PodWakeLock? wakeLock,
  PodTransitionAudio? transitionAudio,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: PodScreen(
        client: client,
        media: media,
        wakeLock: wakeLock,
        transitionAudio: transitionAudio,
        now: now,
        ensureConsent: () async {
          events.add('consent');
          return true;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _listen(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('pod-topic')),
    'A useful question',
  );
  await tester.ensureVisible(find.byKey(const Key('pod-listen')));
  await tester.tap(find.byKey(const Key('pod-listen')));
  await tester.pumpAndSettle();
}

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _foreground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  testWidgets('screen lock pauses once and Resume reuses interrupted audio', (
    tester,
  ) async {
    final events = <String>[];
    final client = _FakePod(events);
    final media = _FakeMedia(events);
    final backend = _WakeBackend();
    final wakeLock = PodWakeLock(backend: backend);
    await _mount(
      tester,
      client,
      media,
      events,
      now: () => _time,
      wakeLock: wakeLock,
    );
    await _listen(tester);
    expect(wakeLock.active, isTrue);
    expect(
      find.text('Screen-awake protection is on while you listen.'),
      findsOneWidget,
    );
    client.complete(0, _turnResponse());
    await tester.pumpAndSettle();
    expect(media.plays, 1);
    _background(tester);
    await tester.pumpAndSettle();
    expect(client.actions.where((action) => action == 'pause').length, 1);
    expect(backend.leases.single.released, isTrue);
    expect(media.playing, isFalse);
    _foreground(tester);
    await tester.pumpAndSettle();
    expect(media.plays, 1);
    expect(wakeLock.active, isFalse);
    await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
    await tester.tap(find.byKey(const Key('pod-pause-resume')));
    await tester.pumpAndSettle();
    expect(media.plays, 2);
    expect(client.pending.length, 1);
    expect(wakeLock.active, isTrue);
    await tester.ensureVisible(find.byKey(const Key('pod-end')));
    await tester.tap(find.byKey(const Key('pod-end')));
    await tester.pumpAndSettle();
    expect(wakeLock.active, isFalse);
    expect(backend.leases.last.released, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'late committed audio after screen lock is reused before any next request',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      _background(tester);
      await tester.pumpAndSettle();
      _foreground(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(client.pending.length, 1);
      expect(
        find.textContaining('Recovering the interrupted turn'),
        findsOneWidget,
      );
      final response = _turnResponse();
      client.current = {
        ...Map<String, dynamic>.from(response['episode']),
        'state': 'paused',
        'version': 1,
      };
      client.pending.single.complete(response);
      await tester.pumpAndSettle();
      expect(media.plays, 1);
      expect(client.pending.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('screen lock recovery has a bounded wait without paid retries', (
    tester,
  ) async {
    final events = <String>[];
    final client = _FakePod(events);
    final media = _FakeMedia(events);
    await _mount(tester, client, media, events, now: () => _time);
    await _listen(tester);
    _background(tester);
    await tester.pumpAndSettle();
    _foreground(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
    await tester.tap(find.byKey(const Key('pod-pause-resume')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(client.pending.length, 1);
    expect(media.plays, 0);
    expect(
      find.textContaining('The interrupted request is still settling'),
      findsOneWidget,
    );
    final resume = tester.widget<IconButton>(
      find.byKey(const Key('pod-pause-resume')),
    );
    expect(resume.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('unlock after the deadline never plays retained or late audio', (
    tester,
  ) async {
    final events = <String>[];
    final client = _FakePod(events);
    final media = _FakeMedia(events);
    var now = _time;
    await _mount(tester, client, media, events, now: () => now);
    await _listen(tester);
    client.complete(0, _turnResponse(remaining: 2));
    await tester.pumpAndSettle();
    _background(tester);
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 3));
    _foreground(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(media.plays, 1);
    expect(media.playing, isFalse);
    expect(client.pending.length, 1);
    expect(client.actions, contains('end'));
    expect(find.byKey(const Key('pod-pause-resume')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'Listen reveals preparation on a phone and errors remain visible',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await _listen(tester);
      final status = find.byKey(const Key('pod-playback-status'));
      expect(find.text('PREPARING YOUR EPISODE'), findsOneWidget);
      expect(tester.getRect(status).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(status).bottom, lessThan(844));
      expect(media.plays, 0);
      client.pending.single.completeError(
        const PodException('The research request timed out.'),
      );
      await tester.pumpAndSettle();
      final error = find.text('The research request timed out.');
      expect(error, findsOneWidget);
      expect(tester.getRect(error).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(error).bottom, lessThan(844));
      expect(client.pending.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'research wait keeps heartbeats alive and does not subtract its time twice',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      var now = _time;
      await _mount(tester, client, media, events, now: () => now);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      media.finish();
      await tester.pumpAndSettle();
      expect(find.text('CHECKING SOURCES'), findsOneWidget);
      expect(client.pending.length, 1);
      expect(client.preparing.length, 1);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(client.actions, contains('heartbeat'));
      now = _time.add(const Duration(seconds: 150));
      final response = _turnResponse();
      response['episode'] = {
        ...(response['episode'] as Map),
        'serverNow': now.toIso8601String(),
        '_responseElapsedMs': 150000,
        'checkedAt': now.toIso8601String(),
      };
      client.preparedPlaybackResponse = response;
      client.completePreparation(0);
      await tester.pumpAndSettle();
      expect(media.plays, 2);
      expect(find.text('2:30'), findsOneWidget);
      expect(client.actions, isNot(contains('end')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'next transport allows bounded research beyond the old 180-second timeout',
    (tester) async {
      final pending = Completer<http.Response>();
      final transport = MockClient((_) => pending.future);
      final client = PodClient(
        backendBaseUrl: 'https://pod.test',
        headersBuilder: () => {},
        client: transport,
      );
      Object? failure;
      Map<String, dynamic>? response;
      final request = client
          .next('private-episode', requestId: 'request-one', version: 0)
          .then<void>(
            (value) {
              response = value;
            },
            onError: (Object error) {
              failure = error;
            },
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 210));
      expect(failure, isNull);
      expect(response, isNull);
      pending.complete(http.Response(jsonEncode(_turnResponse()), 200));
      await tester.pumpAndSettle();
      await request;
      expect(failure, isNull);
      expect(response, isNotNull);
      client.dispose();
      transport.close();
    },
  );

  testWidgets(
    'browsing is silent; Listen activates audio before consent and creation',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events);
      expect(client.creates, 0);
      expect(client.pending, isEmpty);
      expect(media.activations, 0);
      expect(media.recordings, 0);
      await _listen(tester);
      expect(events, ['activate', 'consent', 'create', 'next']);
      expect(media.recordings, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('plan lock disables Listen and all provider requests', (
    tester,
  ) async {
    final events = <String>[];
    final client = _FakePod(events)..allowed = false;
    final media = _FakeMedia(events);
    await _mount(tester, client, media, events);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('pod-listen')))
          .onPressed,
      isNull,
    );
    expect(client.creates, 0);
    expect(client.pending, isEmpty);
    expect(media.activations, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'one next voice prepares during speech and stays unheard until handoff',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      expect(client.preparing, isEmpty);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      expect(media.plays, 1);
      expect(client.pending.length, 1);
      expect(client.preparing.length, 1);
      client.completePreparation(0);
      await tester.pumpAndSettle();
      expect(client.playedPrepared, isEmpty);
      expect(find.text('Rici is speaking'), findsOneWidget);
      expect(
        find.text('The next perspective stays private until playback.'),
        findsNothing,
      );
      media.finish();
      await tester.pumpAndSettle();
      expect(client.pending.length, 1);
      expect(client.playedPrepared, [client.prepareIds.first]);
      expect(media.plays, 2);
      expect(find.text('Analyst is speaking'), findsOneWidget);
      expect(
        find.text('The next perspective stays private until playback.'),
        findsOneWidget,
      );
      expect(client.preparing.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('preparation waits for actual device playback start', (
    tester,
  ) async {
    final events = <String>[];
    final client = _FakePod(events);
    final media = _FakeMedia(events)..autoStart = false;
    await _mount(tester, client, media, events, now: () => _time);
    await _listen(tester);
    client.complete(0, _turnResponse());
    await tester.pumpAndSettle();
    expect(client.preparing, isEmpty);
    media.begin();
    await tester.pumpAndSettle();
    expect(client.preparing.length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'prepare failure lets current voice finish and never retries itself',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      client.preparing.single.completeError(
        const PodException('Sources are unavailable.'),
      );
      await tester.pumpAndSettle();
      expect(media.playing, isTrue);
      expect(client.actions, isNot(contains('pause')));
      expect(find.text('Sources are unavailable.'), findsNothing);
      media.finish();
      await tester.pumpAndSettle();
      expect(client.actions, contains('pause'));
      expect(find.text('Sources are unavailable.'), findsOneWidget);
      expect(client.preparing.length, 1);
      expect(client.pending.length, 1);
      expect(client.playedPrepared, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'screen lock preserves ready next voice while replaying interrupted audio',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      client.completePreparation(0);
      await tester.pumpAndSettle();
      _background(tester);
      await tester.pumpAndSettle();
      _foreground(tester);
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(media.plays, 2);
      expect(client.preparing.length, 1);
      expect(client.playedPrepared, isEmpty);
      media.finish();
      await tester.pumpAndSettle();
      expect(media.plays, 3);
      expect(client.playedPrepared, [client.prepareIds.first]);
      expect(client.preparing.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'Chime discards a ready voice and resumes with the new contribution',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      client.completePreparation(0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-type')));
      await tester.tap(find.byKey(const Key('pod-type')));
      await tester.pumpAndSettle();
      expect(client.actions, contains('interrupt'));
      expect(media.playing, isFalse);
      expect(client.playedPrepared, isEmpty);
      await tester.enterText(
        find.byKey(const Key('pod-contribution')),
        'How does this affect small businesses?',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-send')));
      await tester.tap(find.byKey(const Key('pod-send')));
      await tester.pumpAndSettle();
      expect(client.contributions, 1);
      expect(client.actions, contains('resume'));
      expect(client.pending.length, 2);
      expect(
        events.lastIndexOf('activate'),
        lessThan(events.lastIndexOf('contribute')),
      );
      expect(client.playedPrepared, isEmpty);
      expect(
        find.text('The next perspective stays private until playback.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'voice contribution is reviewed before Send and then returns to the pod',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(client.transcriptions, 1);
      expect(client.contributions, 0);
      expect(client.actions, isNot(contains('resume')));
      expect(find.text('My reviewed thought'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('pod-send')));
      await tester.tap(find.byKey(const Key('pod-send')));
      await tester.pumpAndSettle();
      expect(client.contributions, 1);
      expect(client.actions, contains('resume'));
      expect(client.pending.length, 2);
      expect(media.activations, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'uncertain Send outcome keeps draft and request ID for explicit retry',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-type')));
      await tester.tap(find.byKey(const Key('pod-type')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pod-contribution')),
        'Keep this thought.',
      );
      await tester.pumpAndSettle();
      client.contributionFailure = const PodException(
        'Server did not confirm the save.',
        503,
      );
      await tester.ensureVisible(find.byKey(const Key('pod-send')));
      await tester.tap(find.byKey(const Key('pod-send')));
      await tester.pumpAndSettle();
      expect(client.contributions, 1);
      expect(client.actions, isNot(contains('resume')));
      expect(client.pending.length, 1);
      expect(find.text('Keep this thought.'), findsOneWidget);
      expect(find.text('Server did not confirm the save.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('pod-send')));
      await tester.tap(find.byKey(const Key('pod-send')));
      await tester.pumpAndSettle();
      expect(client.contributions, 2);
      expect(client.contributionIds.first, client.contributionIds.last);
      expect(client.actions.where((action) => action == 'resume').length, 1);
      expect(client.pending.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'stopping preparation waits before transcription and retains WAV for explicit retry',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events)..cancelPreparing = false;
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(client.transcriptions, 0);
      expect(
        find.textContaining('Finishing the interrupted response'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(client.transcriptions, 0);
      expect(find.byKey(const Key('pod-retry-transcription')), findsOneWidget);
      client.preparing.single.completeError(
        const PodException('Preparation cancelled.'),
      );
      await tester.pumpAndSettle();
      expect(client.transcriptions, 0);
      await tester.ensureVisible(
        find.byKey(const Key('pod-retry-transcription')),
      );
      await tester.tap(find.byKey(const Key('pod-retry-transcription')));
      await tester.pumpAndSettle();
      expect(client.transcriptions, 1);
      expect(media.recordings, 1);
      expect(client.contributions, 0);
      expect(find.text('My reviewed thought'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'transcription retry keeps its ID and definitive unavailability never becomes blank success',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      client.transcriptionFailure = const PodException(
        'Response not confirmed.',
        503,
      );
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(client.transcriptions, 1);
      expect(find.byKey(const Key('pod-retry-transcription')), findsOneWidget);
      client.transcriptionFailure = const PodException(
        'This transcription cannot be recovered.',
        409,
        'pod_transcription_unavailable',
      );
      await tester.ensureVisible(
        find.byKey(const Key('pod-retry-transcription')),
      );
      await tester.tap(find.byKey(const Key('pod-retry-transcription')));
      await tester.pumpAndSettle();
      expect(client.transcriptions, 2);
      expect(client.transcriptionIds.first, client.transcriptionIds.last);
      expect(find.byKey(const Key('pod-retry-transcription')), findsNothing);
      expect(
        find.textContaining('This transcription cannot be recovered.'),
        findsOneWidget,
      );
      expect(find.text('My reviewed thought'), findsNothing);
      expect(client.contributions, 0);
      expect(client.actions, isNot(contains('resume')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'backgrounding while old preparation settles never sends late transcription',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events)..cancelPreparing = false;
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      _background(tester);
      await tester.pumpAndSettle();
      client.preparing.single.completeError(
        const PodException('Preparation cancelled.'),
      );
      await tester.pumpAndSettle();
      _foreground(tester);
      await tester.pumpAndSettle();
      expect(client.transcriptions, 0);
      expect(client.contributions, 0);
      expect(client.actions, isNot(contains('resume')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'saved contribution with resume failure shows a recoverable Resume action',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pod-type')));
      await tester.tap(find.byKey(const Key('pod-type')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pod-contribution')),
        'A confirmed contribution.',
      );
      await tester.pumpAndSettle();
      client.resumeFailure = const PodException('Connection interrupted.');
      await tester.ensureVisible(find.byKey(const Key('pod-send')));
      await tester.tap(find.byKey(const Key('pod-send')));
      await tester.pumpAndSettle();
      expect(client.contributions, 1);
      expect(client.pending.length, 1);
      expect(
        find.textContaining('Your contribution is saved. Tap Resume'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('pod-pause-resume')))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(client.contributions, 1);
      expect(client.pending.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'lost consume response keeps its ID for explicit Resume recovery',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      client.completePreparation(0);
      client.consumeFailure = const PodException('Connection interrupted.');
      media.finish();
      await tester.pumpAndSettle();
      expect(client.actions, contains('pause'));
      expect(client.playedPrepared.length, 1);
      expect(client.pending.length, 1);
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(client.playedPrepared, [
        client.prepareIds.first,
        client.prepareIds.first,
      ]);
      expect(media.plays, 2);
      expect(client.preparing.length, 2);
      expect(client.pending.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'expired buffered audio requires explicit Resume before new generation',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      client.completePreparation(0);
      client.current = {...client.current, 'preparedId': null};
      client.consumeFailure = const PodException(
        'The prepared audio expired.',
        409,
        'pod_prepared_audio_unavailable',
      );
      media.finish();
      await tester.pumpAndSettle();
      expect(client.pending.length, 1);
      expect(client.playedPrepared.length, 1);
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(client.pending.length, 2);
      expect(client.playedPrepared.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'committed replay with unavailable audio clears recovery ID and pauses once',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      client.completePreparation(0);
      client.consumeFailure = const PodException('Response lost.');
      media.finish();
      await tester.pumpAndSettle();
      // The original claim committed on the server, but its HTTP response was
      // lost and the transient WAV expired before the listener chose Resume.
      final committed = {
        'id': 'committed-analyst',
        'seq': 2,
        'speaker': 'analyst',
        'text': 'This already committed turn has no cached audio.',
        'sourceIds': <String>[],
      };
      client.current = {
        ...client.current,
        'preparedId': null,
        'turns': [...client.current['turns'] as List, committed],
      };
      client.preparedPlaybackResponse = {
        'episode': {...client.current, 'state': 'active', 'version': 2},
        'turn': committed,
        'audio': null,
        'audioUnavailable': true,
        'replayed': true,
      };
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Audio is unavailable'), findsOneWidget);
      expect(client.playedPrepared.length, 2);
      expect(client.pending.length, 1);
      expect(media.plays, 1);
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(client.playedPrepared.length, 2);
      expect(client.pending.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'transition music fills only waiting gaps and toggle or Chime silences it',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      final backend = _TransitionBackend();
      final transition = PodTransitionAudio(backend: backend);
      await _mount(
        tester,
        client,
        media,
        events,
        now: () => _time,
        transitionAudio: transition,
      );
      expect(backend.events, isEmpty);
      await _listen(tester);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(transition.active, isTrue);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      expect(transition.active, isFalse);
      expect(backend.events.last, 'fade');
      media.finish();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(transition.active, isTrue);
      await tester.ensureVisible(find.byKey(const Key('pod-transition-music')));
      await tester.tap(find.byKey(const Key('pod-transition-music')));
      await tester.pumpAndSettle();
      expect(transition.active, isFalse);
      expect(backend.events.last, 'stop');
      await tester.tap(find.byKey(const Key('pod-transition-music')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(transition.active, isTrue);
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(transition.active, isFalse);
      expect(backend.events.last, 'stop');
      expect(media.recording, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'Chime in cancels stale generation and opens mic only on explicit tap',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events);
      await _listen(tester);
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(client.actions, contains('interrupt'));
      expect(media.recordings, 1);
      client.complete(0, _turnResponse());
      await tester.pump();
      expect(media.plays, 0);
      expect(client.pending.length, 1);
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(client.transcriptions, 1);
      expect(client.contributions, 0);
      expect(find.text('My reviewed thought'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('deadline stops playback and cannot generate another turn', (
    tester,
  ) async {
    final events = <String>[];
    final client = _FakePod(events);
    final media = _FakeMedia(events);
    var now = _time;
    await _mount(tester, client, media, events, now: () => now);
    await _listen(tester);
    client.complete(0, _turnResponse(remaining: 2));
    await tester.pumpAndSettle();
    expect(media.plays, 1);
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(client.actions, contains('end'));
    expect(media.stops, greaterThan(0));
    expect(media.cancellations, greaterThan(0));
    expect(client.pending.length, 1);
    expect(
      find.textContaining('Your episode time is complete'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'blocked audio Resume replays saved bytes without a paid next request',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events)..failPlay = true;
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      expect(client.actions, contains('pause'));
      expect(media.plays, 1);
      expect(client.pending.length, 1);
      await tester.ensureVisible(find.byKey(const Key('pod-pause-resume')));
      await tester.tap(find.byKey(const Key('pod-pause-resume')));
      await tester.pumpAndSettle();
      expect(media.plays, 2);
      expect(client.pending.length, 1);
      expect(media.activations, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'an unsolicited server pause stops media and prevents the next turn',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      client.complete(0, _turnResponse());
      await tester.pumpAndSettle();
      client.current = {...client.current, 'state': 'paused', 'version': 1};
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(media.playing, isFalse);
      expect(client.pending.length, 1);
      expect(
        find.textContaining('The server paused this episode'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'a terminal heartbeat cancels a microphone recording immediately',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(media.recording, isTrue);
      final cancellations = media.cancellations;
      client.current = {...client.current, 'state': 'ended', 'version': 2};
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(media.recording, isFalse);
      expect(media.cancellations, greaterThan(cancellations));
      expect(client.transcriptions, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'backgrounding during creation ends the late episode without generation',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events)..creating = Completer();
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events);
      await _listen(tester);
      _background(tester);
      await tester.pump();
      client.creating!.complete(client.current);
      await tester.pumpAndSettle();
      expect(client.pending, isEmpty);
      expect(client.actions, contains('end'));
      expect(media.plays, 0);
      _foreground(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'background pause supersedes a pending Chime interrupt before mic opens',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events)..interrupting = Completer();
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events);
      await _listen(tester);
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      _background(tester);
      await tester.pumpAndSettle();
      client.interrupting!.complete(client.current);
      await tester.pumpAndSettle();
      expect(media.recordings, 0);
      _foreground(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'microphone permission disables Resume and End still reaches the server',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events)..microphonePermission = Completer();
      await _mount(tester, client, media, events);
      await _listen(tester);
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('pod-pause-resume')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('pod-end')));
      await tester.pumpAndSettle();
      expect(client.actions, contains('end'));
      media.microphonePermission!.complete();
      await tester.pumpAndSettle();
      expect(media.recording, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'request elapsed metadata is subtracted from the server deadline',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events);
      await _mount(tester, client, media, events, now: () => _time);
      await _listen(tester);
      final response = _turnResponse(remaining: 2);
      (response['episode'] as Map)['_responseElapsedMs'] = 3000;
      client.complete(0, response);
      await tester.pumpAndSettle();
      expect(media.plays, 0);
      expect(client.actions, contains('end'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'the microphone permission dialog may go inactive without cancelling Chime',
    (tester) async {
      final events = <String>[];
      final client = _FakePod(events);
      final media = _FakeMedia(events)..microphonePermission = Completer();
      await _mount(tester, client, media, events);
      await _listen(tester);
      await tester.ensureVisible(find.byKey(const Key('pod-chime')));
      await tester.tap(find.byKey(const Key('pod-chime')));
      await tester.pumpAndSettle();
      final cancellations = media.cancellations;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      media.microphonePermission!.complete();
      await tester.pumpAndSettle();
      expect(media.recording, isTrue);
      expect(media.cancellations, cancellations);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'auth revision clears the private screen and rejects a late response',
    (tester) async {
      var subject = 'first';
      final revision = ValueNotifier<int>(0);
      final response = Completer<http.Response>();
      String token() =>
          'a.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'issuer', 'sub': subject, 'session_id': 'session'})))}.z';
      final client = PodClient(
        backendBaseUrl: 'https://pod.test',
        headersBuilder: () => {'Authorization': 'Bearer ${token()}'},
        sessionChanges: revision,
        client: MockClient((_) => response.future),
      );
      final media = _FakeMedia([]);
      await tester.pumpWidget(
        MaterialApp(
          home: PodScreen(
            client: client,
            media: media,
            ensureConsent: () async => true,
          ),
        ),
      );
      subject = 'second';
      revision.value++;
      await tester.pump();
      response.complete(
        http.Response(
          jsonEncode({
            'access': {'allowed': true},
            'episodes': [_episode()],
            'catalog': [],
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Your sign-in changed'), findsOneWidget);
      expect(find.text('A useful question'), findsNothing);
      expect(media.stops, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      revision.dispose();
    },
  );

  test(
    'prepare and playback transport preserve the same ID without hidden retries',
    () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/prepare')) {
          return http.Response(
            jsonEncode({
              'episode': _episode(state: 'active', version: 4),
              'prepared': true,
              'preparedId': 'buffered-request',
            }),
            200,
          );
        }
        return http.Response(jsonEncode(_turnResponse()), 200);
      });
      final client = PodClient(
        backendBaseUrl: 'https://pod.test',
        headersBuilder: () => {},
        client: transport,
      );
      final prepared = await client.prepare(
        'private-episode',
        requestId: 'buffered-request',
        version: 4,
      );
      expect(prepared['turn'], isNull);
      expect(prepared['preparedId'], 'buffered-request');
      await client.playPrepared(
        'private-episode',
        requestId: 'buffered-request',
        version: 6,
      );
      expect(requests.length, 2);
      expect(requests.map((request) => request.url.path), [
        '/api/pod/episodes/private-episode/prepare',
        '/api/pod/episodes/private-episode/play-prepared',
      ]);
      expect(jsonDecode(requests.last.body), {
        'requestId': 'buffered-request',
        'version': 6,
      });
      client.dispose();
      transport.close();
    },
  );

  test('source links reject non-public or unsafe URLs', () {
    for (final value in [
      'http://news.example.com/a',
      'https://127.0.0.1/a',
      'https://169.254.169.254/',
      'https://[::1]/',
      'https://user:pass@news.example.com/',
      'https://news.local/a',
      'https://localhost/a',
      'https://news.example.com:8443/a',
      'javascript:alert(1)',
    ]) {
      expect(podPublicSourceUri(value), isNull, reason: value);
    }
    expect(
      podPublicSourceUri('https://www.bbc.com/news/article')?.host,
      'www.bbc.com',
    );
  });
}
