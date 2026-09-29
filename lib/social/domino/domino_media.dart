import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../social_client.dart';
import '../social_call_controller.dart' show SocialCallIo;
import '../social_audio_output.dart';
import '../social_audio_output_native.dart'
    if (dart.library.js_interop) '../social_audio_output_web.dart';

class DominoCallIo extends SocialCallIo {
  @override
  Future<rtc.MediaStream> capture(bool video) =>
      rtc.navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 480},
                'height': {'ideal': 360},
                'frameRate': {'ideal': 15, 'max': 20},
              }
            : false,
      });
}

class DominoPeer {
  DominoPeer(
    this.id,
    this.session,
    this.seat,
    this.peer,
    this.renderer,
    this.video,
    this.audio,
  );
  final String id, session;
  final int seat;
  final rtc.RTCPeerConnection peer;
  final rtc.RTCVideoRenderer renderer;
  final rtc.MediaStream video, audio;
  final candidates = <SocialMap>[];
  bool described = false, offered = false, closed = false;
  String state = 'connecting';
}

/// One local capture, up to three peers, and one independent audio sink per
/// remote seat. Video renderers never own audio or mute microphone tracks.
class DominoMedia extends ChangeNotifier {
  DominoMedia({SocialCallIo? io, List<SocialAudioOutput>? outputs})
    : io = io ?? DominoCallIo(),
      outputs = outputs ?? List.generate(4, (_) => createSocialAudioOutput()) {
    local = this.io.renderer();
    for (final a in this.outputs) {
      a.addListener(_changed);
    }
  }
  final SocialCallIo io;
  final List<SocialAudioOutput> outputs;
  late final rtc.RTCVideoRenderer local;
  final peers = <String, DominoPeer>{};
  rtc.MediaStream? _capture, _preview, _quiet;
  Future<void>? _init, _opening, _closing;
  Future<void> _tracks = Future.value();
  bool closed = false, ready = false, camera = true, microphone = true;
  String issue = '';
  String get session => _session;
  final _session = socialId();
  Future<void> Function(
    String peer,
    String targetSession,
    String kind,
    SocialMap payload,
  )?
  onSignal;
  void _changed() {
    if (!closed) notifyListeners();
  }

  void _problem(String message) {
    if (!closed) {
      issue = message;
      notifyListeners();
    }
  }

  void activate() {
    for (final a in outputs) {
      unawaited(a.activate().catchError((_) {}));
    }
  }

  Future<void> open() => _opening ??= _open();
  Future<void> _open() async {
    if (closed) return;
    _init = local.initialize();
    await _init;
    if (closed) return;
    await io.prepare();
    if (closed) return;
    await outputs.first.prepareCapture();
    if (closed) return;
    final stream = await io.capture(true);
    if (closed) {
      await _release(stream);
      return;
    }
    _capture = stream;
    if (stream.getAudioTracks().isEmpty || stream.getVideoTracks().isEmpty) {
      throw const SocialException(
        'Allow both camera and microphone to join table video. You can keep playing with video off.',
      );
    }
    _preview = await io.stream('domino-preview');
    _quiet = await io.stream('domino-quiet');
    if (closed) return;
    for (final track in stream.getTracks()) {
      track.enabled = true;
      track.onEnded = () => _problem(
        'Your ${track.kind == 'audio' ? 'microphone' : 'camera'} was interrupted. Reconnect video to restore it.',
      );
      if (track.kind == 'video') await _preview!.addTrack(track);
    }
    if (closed) return;
    local.srcObject = _preview;
    await io.configure();
    if (closed) return;
    if (outputs.first.canRouteSpeaker) await outputs.first.routeSpeaker(true);
    ready = true;
    _changed();
  }

  Future<void> sync(
    String me,
    List<SocialMap> players,
    List<dynamic> servers,
  ) async {
    if (closed || !ready) return;
    final active = {
      for (final p in players)
        if (p['id'] != me &&
            p['state'] == 'joined' &&
            p['mediaSession'] != null &&
            p['online'] == true)
          '${p['id']}': p,
    };
    for (final old in peers.values.toList()) {
      if (active[old.id]?['mediaSession'] != old.session) await _remove(old);
    }
    for (final entry in active.entries) {
      if (closed) return;
      if (peers.containsKey(entry.key)) continue;
      final p = entry.value, seat = (p['seat'] as num).toInt();
      final peer = await io.peer(servers);
      if (closed) {
        await peer.close();
        await peer.dispose();
        return;
      }
      final renderer = io.renderer();
      await renderer.initialize();
      final video = await io.stream('domino-video-${entry.key}'),
          audio = await io.stream('domino-audio-${entry.key}');
      final link = DominoPeer(
        entry.key,
        '${p['mediaSession']}',
        seat,
        peer,
        renderer,
        video,
        audio,
      );
      peers[entry.key] = link;
      if (closed) {
        await _remove(link);
        return;
      }
      peer.onIceCandidate = (candidate) {
        if (closed || link.closed || candidate.candidate?.isNotEmpty != true) {
          return;
        }
        unawaited(
          _send(link, 'candidate', {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }).catchError((_) {
            _problem('Video connection needs a retry. Tap Reconnect video.');
          }),
        );
      };
      peer.onConnectionState = (state) {
        if (closed || link.closed) return;
        link.state = state.name
            .replaceFirst('RTCPeerConnectionState', '')
            .toLowerCase();
        if (link.state == 'failed') {
          _problem('A video connection failed. Tap Reconnect video.');
        }
        _changed();
      };
      peer.onTrack = (event) {
        _tracks = _tracks
            .then((_) async {
              if (closed || link.closed) return;
              final target = event.track.kind == 'audio' ? audio : video;
              if (!target.getTracks().any((t) => t.id == event.track.id)) {
                await target.addTrack(event.track);
              }
              if (closed || link.closed) return;
              if (event.track.kind == 'audio') {
                await outputs[seat].attach(audio);
              } else {
                renderer.srcObject = video;
              }
              _changed();
            })
            .catchError((_) {
              _problem(
                'Tap Resume sound or reconnect video to restore this player.',
              );
            });
      };
      for (final track in _capture!.getTracks()) {
        if (closed || link.closed) return;
        await peer.addTrack(track, _capture!);
      }
      // Stable role per pair avoids offer glare. Rejoining changes session IDs
      // and creates fresh peers rather than renegotiating stale descriptions.
      if (me.compareTo(link.id) < 0) {
        link.offered = true;
        final offer = await peer.createOffer();
        if (closed || link.closed) return;
        await peer.setLocalDescription(offer);
        await _send(link, 'offer', {'sdp': offer.sdp});
      }
    }
    _changed();
  }

  Future<void> _send(DominoPeer p, String kind, SocialMap payload) async {
    if (closed || p.closed) return;
    await onSignal?.call(p.id, p.session, kind, payload);
  }

  Future<void> receive(SocialMap signal) async {
    if (closed || !ready || signal['targetSession'] != session) return;
    final p = peers[signal['sender']];
    if (p == null || p.closed || p.session != signal['session']) return;
    final kind = signal['kind'], payload = socialMap(signal['payload']);
    if (kind == 'candidate') {
      if (p.described) {
        await _candidate(p, payload);
      } else if (p.candidates.length < 100) {
        p.candidates.add(payload);
      }
    } else if (kind == 'offer' && !p.offered || kind == 'answer' && p.offered) {
      if (p.described) return;
      await p.peer.setRemoteDescription(
        rtc.RTCSessionDescription('${payload['sdp']}', kind),
      );
      if (closed || p.closed) return;
      p.described = true;
      for (final c in p.candidates) {
        if (closed || p.closed) return;
        await _candidate(p, c);
      }
      p.candidates.clear();
      if (kind == 'offer') {
        final answer = await p.peer.createAnswer();
        if (closed || p.closed) return;
        await p.peer.setLocalDescription(answer);
        await _send(p, 'answer', {'sdp': answer.sdp});
      }
    }
  }

  Future<void> _candidate(DominoPeer p, SocialMap value) => p.peer.addCandidate(
    rtc.RTCIceCandidate(
      value['candidate'],
      value['sdpMid'],
      (value['sdpMLineIndex'] as num?)?.toInt(),
    ),
  );
  void toggleMicrophone() {
    if (!ready || closed) return;
    microphone = !microphone;
    for (final t in _capture?.getAudioTracks() ?? <rtc.MediaStreamTrack>[]) {
      t.enabled = microphone;
    }
    _changed();
  }

  void toggleCamera() {
    if (!ready || closed) return;
    camera = !camera;
    for (final t in _capture?.getVideoTracks() ?? <rtc.MediaStreamTrack>[]) {
      t.enabled = camera;
    }
    _changed();
  }

  Future<void> switchCamera() async {
    if (!ready || closed) return;
    final t = _capture?.getVideoTracks().firstOrNull;
    if (t != null) await rtc.Helper.switchCamera(t);
  }

  Future<void> resumeSound() async {
    await Future.wait(outputs.map((a) => a.resume()));
    _changed();
  }

  Future<void> speaker() async {
    if (outputs.first.canRouteSpeaker) {
      await outputs.first.routeSpeaker(!outputs.first.speaker);
    } else {
      await resumeSound();
    }
    _changed();
  }

  Future<void> _remove(DominoPeer p) async {
    p.closed = true;
    peers.remove(p.id);
    p.peer.onTrack = null;
    p.peer.onIceCandidate = null;
    p.peer.onConnectionState = null;
    try {
      await p.peer.close();
      await p.peer.dispose();
    } catch (_) {}
    try {
      if (_quiet != null) await outputs[p.seat].attach(_quiet!);
    } catch (_) {}
    try {
      p.renderer.srcObject = null;
      await p.renderer.dispose();
    } catch (_) {}
    try {
      await p.video.dispose();
      await p.audio.dispose();
    } catch (_) {}
  }

  static Future<void> _release(rtc.MediaStream stream) async {
    for (final t in stream.getTracks()) {
      try {
        t.onEnded = null;
        t.enabled = false;
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    closed = true;
    ready = false;
    for (final t in _capture?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
      t.enabled = false;
    }
    // Capture permission and stream projection may resolve after navigation.
    // Let setup finish observing `closed`, then dispose every late resource.
    try {
      await _opening;
    } catch (_) {}
    for (final p in peers.values.toList()) {
      await _remove(p);
    }
    for (final a in outputs) {
      a.removeListener(_changed);
    }
    for (final a in outputs.skip(1)) {
      await a.close();
    }
    await outputs.first.close();
    final stream = _capture;
    _capture = null;
    if (stream != null) await _release(stream);
    await _tracks;
    try {
      await _init;
      local.srcObject = null;
      await local.dispose();
    } catch (_) {}
    try {
      await _preview?.dispose();
      await _quiet?.dispose();
      await io.clear();
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
