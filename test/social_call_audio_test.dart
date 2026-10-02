import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:ai_wiz_command_center/social/social_audio_output.dart';
import 'package:ai_wiz_command_center/social/social_call_tones.dart';
import 'package:ai_wiz_command_center/social/social_call_controller.dart';
import 'package:ai_wiz_command_center/social/social_call_screen.dart';
import 'social_calls_test.dart' as calls;
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

class Track extends rtc.MediaStreamTrack {
  Track(this.id, this.kind);
  @override
  final String id, kind;
  @override
  bool enabled = true;
  @override
  bool muted = false;
  bool stopped = false;
  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Stream extends rtc.MediaStream {
  Stream(String id, [List<rtc.MediaStreamTrack>? tracks])
    : tracks = tracks ?? [],
      super(id, 'local');
  final List<rtc.MediaStreamTrack> tracks;
  bool disposed = false;
  @override
  List<rtc.MediaStreamTrack> getTracks() => tracks;
  @override
  List<rtc.MediaStreamTrack> getAudioTracks() =>
      tracks.where((t) => t.kind == 'audio').toList();
  @override
  List<rtc.MediaStreamTrack> getVideoTracks() =>
      tracks.where((t) => t.kind == 'video').toList();
  @override
  Future<void> addTrack(
    rtc.MediaStreamTrack t, {
    bool addToNative = true,
  }) async {
    tracks.add(t);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Renderer extends rtc.RTCVideoRenderer {
  rtc.MediaStream? stream;
  bool disposed = false;
  @override
  Future<void> initialize() async {}
  @override
  set srcObject(rtc.MediaStream? value) {
    expect(
      value?.getAudioTracks() ?? [],
      isEmpty,
      reason: 'Preview must never own microphone or incoming sound',
    );
    stream = value;
  }

  @override
  rtc.MediaStream? get srcObject => stream;
  @override
  set muted(bool value) =>
      throw StateError('Native muted setter changes the actual microphone');
  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

class Sender implements rtc.RTCRtpSender {
  Sender(this.current);
  rtc.MediaStreamTrack current;
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> replaceTrack(rtc.MediaStreamTrack? track) async {
    if (pending != null) await pending!.future;
    if (fail) throw StateError('Cannot replace');
    current = track!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Peer implements rtc.RTCPeerConnection {
  @override
  Function(rtc.RTCTrackEvent)? onTrack;
  @override
  Function(rtc.RTCIceCandidate)? onIceCandidate;
  @override
  Function(rtc.RTCPeerConnectionState)? onConnectionState;
  final sent = <rtc.MediaStreamTrack>[];
  final recordedSenders = <Sender>[];
  bool closed = false;
  List<rtc.StatsReport> reports = [];
  @override
  Future<List<rtc.StatsReport>> getStats([rtc.MediaStreamTrack? track]) async =>
      reports;
  @override
  Future<rtc.RTCRtpSender> addTrack(
    rtc.MediaStreamTrack t, [
    rtc.MediaStream? s,
  ]) async {
    sent.add(t);
    final sender = Sender(t);
    recordedSenders.add(sender);
    return sender;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Audio extends SocialAudioOutput {
  rtc.MediaStream? received;
  int resumes = 0;
  bool deny = false, native = false;
  int tests = 0, activations = 0;
  final ringChanges = <bool>[];
  @override
  bool get canRouteSpeaker => native;
  @override
  bool get canTestSound => true;
  @override
  Future<void> activate() async {
    activations++;
    activated = true;
    changed();
  }

  @override
  Future<void> setRinging(bool value) async {
    if (ringing == value) return;
    ringing = value;
    ringChanges.add(value);
  }

  @override
  Future<void> testSound() async {
    tests++;
    activated = true;
    changed();
  }

  @override
  String get guidance => 'Use your device’s volume buttons to listen louder.';
  @override
  Future<void> attach(rtc.MediaStream s) async {
    if (closed) return;
    received = s;
    await resume();
  }

  @override
  Future<void> resume() async {
    if (closed) return;
    resumes++;
    blocked = deny;
    playing = activated = !deny;
    changed();
  }

  @override
  Future<void> routeSpeaker(bool v) async {
    speaker = v;
    changed();
  }

  @override
  Future<void> setVolume(double v) async {
    volume = v;
    changed();
  }

  @override
  Future<void> close() async {
    closed = true;
    received = null;
  }
}

class Io extends SocialCallIo {
  final mic = Track('mic', 'audio'), camera = Track('camera', 'video');
  final connection = Peer(), projections = <Stream>[], renderers = <Renderer>[];
  Completer<rtc.MediaStream>? permission;
  final nextCaptures = <rtc.MediaStream>[];
  final captureModes = <bool>[];
  @override
  rtc.RTCVideoRenderer renderer() {
    final r = Renderer();
    renderers.add(r);
    return r;
  }

  @override
  Future<rtc.MediaStream> stream(String name) async {
    final s = Stream(name);
    projections.add(s);
    return s;
  }

  @override
  Future<rtc.RTCPeerConnection> peer(List<dynamic> servers) async => connection;
  @override
  Future<rtc.MediaStream> capture(bool video) async {
    captureModes.add(video);
    if (permission != null) return permission!.future;
    if (nextCaptures.isNotEmpty) return nextCaptures.removeAt(0);
    return Stream('capture', [mic, if (video) camera]);
  }

  @override
  Future<void> prepare() async {}
  @override
  Future<void> configure() async {}
  @override
  Future<void> clear() async {}
}

// Browser getTracks wraps an underlying JS track anew on each enumeration.
class RewrappedStream extends Stream {
  RewrappedStream() : super('rewrapped');
  @override
  List<rtc.MediaStreamTrack> getAudioTracks() => [Track('same-mic', 'audio')];
  @override
  List<rtc.MediaStreamTrack> getTracks() => [Track('same-mic', 'audio')];
}

class PendingAudioClose extends Audio {
  final gate = Completer<void>();
  @override
  Future<void> close() async {
    await gate.future;
    await super.close();
  }
}

Future<void> settleTrack() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'microphone recovery finds sender by track ID across browser wrappers',
    () async {
      final io = Io()..nextCaptures.add(RewrappedStream());
      final media = SocialCallMedia(io: io, audio: Audio());
      await media.open(false, []);
      final replacement = Track('replacement', 'audio');
      io.nextCaptures.add(Stream('new', [replacement]));
      await media.restartMicrophone();
      expect(io.connection.recordedSenders.single.current, same(replacement));
      expect(io.captureModes, [false, false]);
      await media.close();
    },
  );

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
  test(
    'real media wiring preserves outgoing audio and handles streamless incoming tracks once',
    () async {
      final io = Io(), audio = Audio();
      final media = SocialCallMedia(io: io, audio: audio);
      await media.open(true, []);
      expect(io.mic.enabled, true);
      expect(io.connection.sent, contains(io.mic));
      expect(media.local.srcObject!.getTracks(), [io.camera]);
      final voice = Track('remote-voice', 'audio'),
          video = Track('remote-video', 'video');
      io.connection.onTrack!(rtc.RTCTrackEvent(streams: [], track: voice));
      io.connection.onTrack!(rtc.RTCTrackEvent(streams: [], track: video));
      io.connection.onTrack!(rtc.RTCTrackEvent(streams: [], track: voice));
      await settleTrack();
      expect(audio.received!.getTracks(), [voice]);
      expect(media.remote.srcObject!.getTracks(), [video]);
      media.toggleMicrophone();
      expect(io.mic.enabled, false);
      expect(voice.enabled, true);
      media.toggleMicrophone();
      expect(io.mic.enabled, true);
      final closing = media.close();
      expect(
        io.mic.enabled,
        false,
        reason: 'Hangup must synchronously disable the microphone',
      );
      await closing;
      expect(io.mic.stopped, true);
      expect(audio.closed, true);
      expect(io.connection.closed, true);
      expect(io.projections.every((s) => s.disposed), true);
      io.connection.onTrack!(
        rtc.RTCTrackEvent(streams: [], track: Track('late', 'audio')),
      );
      await settleTrack();
      expect(audio.received, isNull);
    },
  );
  test(
    'interrupted microphone can be replaced without replacing camera or incoming audio',
    () async {
      final io = Io(), audio = Audio();
      io.mic.enabled = false;
      final m = SocialCallMedia(io: io, audio: audio);
      await m.open(true, []);
      expect(io.mic.enabled, true);
      io.mic.muted = true;
      io.mic.onMute!();
      expect(m.microphoneInterrupted, true);
      final replacement = Track('fresh-mic', 'audio');
      io.nextCaptures.add(Stream('recovery', [replacement]));
      final remote = Track('remote', 'audio');
      io.connection.onTrack!(rtc.RTCTrackEvent(streams: [], track: remote));
      await settleTrack();
      final received = audio.received;
      await m.restartMicrophone();
      expect(io.captureModes, [true, false]);
      expect(io.connection.recordedSenders.first.current, replacement);
      expect(io.connection.recordedSenders.last.current, io.camera);
      expect(io.camera.stopped, false);
      expect(io.mic.stopped, true);
      expect(m.microphoneInterrupted, false);
      expect(audio.received, received);
      final resumes = audio.resumes;
      remote.onUnMute!();
      await settleTrack();
      expect(audio.resumes, resumes + 1);
      io.mic.onEnded!();
      expect(
        m.microphoneInterrupted,
        false,
        reason:
            'Old microphone events must not mark the replacement interrupted',
      );
      final close = m.close();
      expect(replacement.enabled, false);
      await close;
      expect(replacement.stopped, true);
    },
  );
  test(
    'microphone replacement respects intentional mute and failed replacement keeps old source',
    () async {
      final io = Io();
      final call = SocialCallMedia(io: io, audio: Audio());
      await call.open(false, []);
      call.toggleMicrophone();
      final replacement = Track('fresh', 'audio');
      io.nextCaptures.add(Stream('fresh-stream', [replacement]));
      await call.restartMicrophone();
      expect(call.microphone, false);
      expect(replacement.enabled, false);
      call.toggleMicrophone();
      expect(replacement.enabled, true);
      final rejected = Track('failed-mic', 'audio');
      io.nextCaptures.add(Stream('failed-stream', [rejected]));
      io.connection.recordedSenders.single.fail = true;
      await call.restartMicrophone();
      expect(io.connection.recordedSenders.single.current, replacement);
      expect(replacement.stopped, false);
      expect(rejected.stopped, true);
      expect(call.microphoneIssue, contains('Could not reopen'));
      await call.close();
    },
  );
  test(
    'hangup during microphone replacement disables pending capture immediately',
    () async {
      final io = Io(), audio = Audio();
      final m = SocialCallMedia(io: io, audio: audio);
      await m.open(false, []);
      final replacement = Track('pending-mic', 'audio');
      io.nextCaptures.add(Stream('pending-stream', [replacement]));
      final pending = Completer<void>();
      io.connection.recordedSenders.single.pending = pending;
      final repair = m.restartMicrophone();
      await settleTrack();
      final close = m.close();
      expect(replacement.enabled, false);
      pending.complete();
      await Future.wait([repair, close]);
      expect(replacement.stopped, true);
      expect(m.ready, false);
    },
  );
  test(
    'hangup during recovery permission releases late microphone without swapping sender',
    () async {
      final io = Io(), audio = Audio();
      final m = SocialCallMedia(io: io, audio: audio);
      await m.open(false, []);
      io.permission = Completer<rtc.MediaStream>();
      final repair = m.restartMicrophone();
      await settleTrack();
      await m.close();
      final late = Track('late-recovery', 'audio');
      io.permission!.complete(Stream('late-recovery-stream', [late]));
      await repair;
      expect(late.stopped, true);
      expect(io.connection.recordedSenders.single.current, io.mic);
    },
  );
  test(
    'sound detection uses microphone source level, not sent packets or received sound',
    () async {
      final io = Io();
      final call = SocialCallMedia(io: io, audio: Audio());
      await call.open(false, []);
      io.connection.reports = [
        rtc.StatsReport('out', 'outbound-rtp', 0, {
          'kind': 'audio',
          'bytesSent': 1000,
        }),
        rtc.StatsReport('in', 'track', 0, {
          'kind': 'audio',
          'remoteSource': true,
          'audioLevel': .7,
        }),
        rtc.StatsReport('mic', 'media-source', 0, {
          'kind': 'audio',
          'audioLevel': 0.0,
          'totalAudioEnergy': 0.0,
        }),
      ];
      await call.checkAudio();
      expect(call.microphoneSoundDetected, false);
      io.connection.reports = [
        rtc.StatsReport('mic', 'media-source', 0, {
          'kind': 'audio',
          'audioLevel': .12,
          'totalAudioEnergy': .05,
        }),
      ];
      await call.checkAudio();
      expect(call.microphoneSoundDetected, true);
      io.mic.muted = true;
      io.mic.onMute!();
      expect(call.microphoneSoundDetected, false);
      expect(call.microphoneInterrupted, true);
      await call.close();
    },
  );
  testWidgets('interrupted microphone recovery stays usable on small screens', (
    t,
  ) async {
    final store = calls.CallStore();
    final client = store.client('caller');
    final io = Io(), audio = Audio();
    final m = SocialCallMedia(io: io, audio: audio);
    await social.mount(
      t,
      SocialCallScreen(
        client: client,
        peer: social.peer,
        video: false,
        media: m,
      ),
      width: 320,
      height: 1000,
      scale: 1.4,
    );
    await t.pumpAndSettle();
    io.mic.muted = true;
    io.mic.onMute!();
    await t.pumpAndSettle();
    expect(find.text('Your microphone was interrupted'), findsOneWidget);
    final repair = find.text('Reconnect microphone');
    await calls.reveal(t, repair);
    await fixtures.capture(t, 'social-microphone-interrupted-320');
    expect(t.takeException(), isNull);
    final fresh = Track('recovered', 'audio');
    io.nextCaptures.add(Stream('recovered-stream', [fresh]));
    await t.tap(repair);
    await t.pumpAndSettle();
    expect(m.microphoneInterrupted, false);
    expect(fresh.enabled, true);
    expect(store.signals, isEmpty);
    await calls.reveal(t, find.text('Sound settings & test'));
    await t.tap(find.text('Sound settings & test'));
    await t.pumpAndSettle();
    expect(find.text('Reconnect microphone'), findsOneWidget);
    expect(t.takeException(), isNull);
    await fixtures.capture(t, 'social-microphone-settings-320');
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(fresh.stopped, true);
    client.dispose();
  });
  test(
    'repeated hangup awaits the same cleanup before another call can open',
    () async {
      final io = Io(), audio = PendingAudioClose();
      final m = SocialCallMedia(io: io, audio: audio);
      await m.open(false, []);
      final first = m.close(), second = m.close();
      expect(identical(first, second), true);
      expect(io.mic.enabled, false);
      expect(io.connection.closed, false);
      audio.gate.complete();
      await second;
      expect(io.connection.closed, true);
      expect(io.mic.stopped, true);
      expect(io.projections.every((s) => s.disposed), true);
    },
  );
  test(
    'ending while microphone permission is pending releases a late stream',
    () async {
      final io = Io()..permission = Completer<rtc.MediaStream>();
      final media = SocialCallMedia(io: io, audio: Audio());
      final opening = media.open(false, []);
      await settleTrack();
      await media.close();
      io.permission!.complete(Stream('late', [io.mic]));
      await opening;
      expect(io.mic.stopped, true);
      expect(io.connection.sent, isEmpty);
      expect(media.ready, false);
    },
  );
  test(
    'ringback stops on answer and on hangup; incoming never rings back',
    () async {
      final store = calls.CallStore(),
          client = store.client('caller'),
          audio = Audio();
      final c = SocialCallController(
        client: client,
        peer: social.peer,
        video: false,
        media: calls.FakeMedia(audio: audio),
      );
      await c.initialize();
      expect(audio.ringChanges, [true]);
      await c.poll();
      expect(audio.ringChanges, [true]);
      store.state = 'accepted';
      await c.poll();
      expect(audio.ringChanges, [true, false]);
      await c.end('done');
      c.dispose();
      client.dispose();
      final second = calls.CallStore(),
          secondClient = second.client('caller'),
          secondAudio = Audio();
      final d = SocialCallController(
        client: secondClient,
        peer: social.peer,
        video: false,
        media: calls.FakeMedia(audio: secondAudio),
      );
      await d.initialize();
      await d.end('cancel');
      expect(secondAudio.ringChanges, [true, false]);
      d.dispose();
      secondClient.dispose();
      final third = calls.CallStore(),
          thirdClient = third.client('callee'),
          thirdAudio = Audio();
      final e = SocialCallController(
        client: thirdClient,
        peer: social.peer,
        video: false,
        incoming: {'id': 'incoming', 'state': 'ringing'},
        media: calls.FakeMedia(audio: thirdAudio),
      );
      await e.initialize();
      expect(thirdAudio.activations, 0);
      await e.accept();
      expect(thirdAudio.activations, 1);
      expect(thirdAudio.ringChanges, isEmpty);
      await e.end('done');
      e.dispose();
      thirdClient.dispose();
    },
  );
  test(
    'audio diagnostics use received audio bytes, not video or track presence',
    () async {
      final io = Io();
      final m = SocialCallMedia(io: io, audio: Audio());
      await m.open(false, []);
      io.connection.reports = [
        rtc.StatsReport('v', 'inbound-rtp', 0, {
          'kind': 'video',
          'bytesReceived': 9999,
        }),
        rtc.StatsReport('a', 'inbound-rtp', 0, {
          'kind': 'audio',
          'bytesReceived': 0,
        }),
        rtc.StatsReport('s', 'outbound-rtp', 0, {
          'kind': 'audio',
          'bytesSent': 123,
        }),
      ];
      await m.checkAudio();
      expect(m.audioStatsAvailable, true);
      expect(m.incomingAudioBytes, 0);
      expect(m.outgoingAudioBytes, 123);
      io.connection.reports.add(
        rtc.StatsReport('a2', 'inbound-rtp', 0, {
          'mediaType': 'audio',
          'bytesReceived': 456,
        }),
      );
      await m.checkAudio();
      expect(m.incomingAudioBytes, 456);
      await m.close();
    },
  );
  test(
    'local WAV tones have audible samples, quiet gaps, and a bounded level',
    () {
      final bytes = socialCallTone(ringing: true),
          data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(data.getUint32(24, Endian.little), 8000);
      expect(data.getUint32(40, Endian.little), bytes.length - 44);
      expect(
        [
          for (var i = 44; i < 44 + 16000; i += 2)
            data.getInt16(i, Endian.little),
        ].any((v) => v.abs() > 1000),
        true,
      );
      expect(
        [
          for (var i = 44 + 32000; i < bytes.length; i += 2)
            data.getInt16(i, Endian.little),
        ].every((v) => v == 0),
        true,
      );
      expect(
        [
          for (var i = 44; i < bytes.length; i += 2)
            data.getInt16(i, Endian.little),
        ].every((v) => v.abs() <= 6500),
        true,
      );
      expect(
        socialCallTone(silent: true).sublist(44).every((v) => v == 0),
        true,
      );
    },
  );
  testWidgets('native Speaker button selects and deselects the actual route', (
    t,
  ) async {
    final store = calls.CallStore(),
        client = store.client('caller'),
        audio = Audio()..native = true;
    await social.mount(
      t,
      SocialCallScreen(
        client: client,
        peer: social.peer,
        video: false,
        media: calls.FakeMedia(audio: audio),
      ),
    );
    await t.pumpAndSettle();
    final speaker = find.byTooltip('Speaker');
    await calls.reveal(t, speaker);
    await t.tap(speaker);
    await t.pumpAndSettle();
    expect(audio.speaker, true);
    expect(
      t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Speaker',
            ),
          )
          .isSelected,
      true,
    );
    await t.tap(speaker);
    await t.pumpAndSettle();
    expect(audio.speaker, false);
    await t.pumpWidget(const SizedBox());
    client.dispose();
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('Speaker and blocked sound recovery work at $width', (t) async {
      final store = calls.CallStore(), client = store.client('caller');
      final audio = Audio()..blocked = true;
      final media = calls.FakeMedia(audio: audio);
      await social.mount(
        t,
        SocialCallScreen(
          client: client,
          peer: social.peer,
          video: false,
          media: media,
        ),
        width: width,
        scale: width == 320 ? 1.4 : 1,
        theme: 'korlix_blue',
      );
      await t.pumpAndSettle();
      final retry = find.text('Tap to hear the call');
      expect(retry, findsOneWidget);
      await calls.reveal(t, retry);
      await t.tap(retry);
      await t.pumpAndSettle();
      expect(audio.resumes, 1);
      expect(retry, findsNothing);
      final speaker = find.byTooltip('Speaker');
      await calls.reveal(t, speaker);
      await fixtures.capture(t, 'social-audio-controls-${width.toInt()}');
      await t.tap(speaker);
      await t.pumpAndSettle();
      expect(find.text('Speaker & sound'), findsOneWidget);
      expect(find.text('Resume sound'), findsOneWidget);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-speaker-panel-${width.toInt()}');
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Speaker',
              ),
            )
            .isSelected,
        true,
      );
      expect(
        find.byType(SwitchListTile),
        findsNothing,
        reason: 'Browsers must not show a fake hardware route switch',
      );
      final testSound = find.text('Test sound');
      await calls.reveal(t, testSound);
      await t.tap(testSound);
      await t.pumpAndSettle();
      expect(audio.tests, 1);
      expect(audio.activated, true);
      await calls.reveal(t, find.byTooltip('Close sound controls'));
      await t.tap(find.byTooltip('Close sound controls'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      client.dispose();
    });
  }
}
