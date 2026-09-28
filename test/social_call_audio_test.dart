import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:ai_wiz_command_center/social/social_audio_output.dart';
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
  bool closed = false;
  @override
  Future<rtc.RTCRtpSender> addTrack(
    rtc.MediaStreamTrack t, [
    rtc.MediaStream? s,
  ]) async {
    sent.add(t);
    return Sender();
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
  bool deny = false;
  @override
  bool get canRouteSpeaker => true;
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
    playing = !deny;
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
  Future<rtc.MediaStream> capture(bool video) async => permission == null
      ? Stream('capture', [mic, if (video) camera])
      : permission!.future;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> configure() async {}
  @override
  Future<void> clear() async {}
}

Future<void> settleTrack() => Future<void>.delayed(Duration.zero);

void main() {
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
      await t.tap(find.byType(SwitchListTile));
      await t.pumpAndSettle();
      expect(audio.speaker, true);
      await t.tap(find.byTooltip('Close sound controls'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      client.dispose();
    });
  }
}
