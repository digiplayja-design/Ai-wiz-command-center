import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'social_client.dart';
import 'social_audio_output.dart';
import 'social_audio_output_native.dart'
    if (dart.library.js_interop) 'social_audio_output_web.dart';

/// Injectable device boundary also exercises the real media wiring in tests.
class SocialCallIo {
  rtc.RTCVideoRenderer renderer() => rtc.RTCVideoRenderer();
  Future<rtc.MediaStream> stream(String name) =>
      rtc.createLocalMediaStream(name);
  Future<rtc.RTCPeerConnection> peer(List<dynamic> servers) =>
      rtc.createPeerConnection({
        'iceServers': servers,
        'sdpSemantics': 'unified-plan',
      });
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
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 24, 'max': 30},
              }
            : false,
      });
  Future<void> prepare() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await rtc.Helper.ensureAudioSession();
    }
  }

  Future<void> configure() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      await rtc.Helper.setSpeakerphoneOn(false);
    }
  }

  Future<void> clear() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await rtc.Helper.clearAndroidCommunicationDevice();
    }
  }
}

/// Consent, signaling and teardown remain independent of device I/O.
class SocialCallMedia extends ChangeNotifier {
  SocialCallMedia({SocialCallIo? io, SocialAudioOutput? audio})
    : io = io ?? SocialCallIo(),
      audio = audio ?? createSocialAudioOutput() {
    local = this.io.renderer();
    remote = this.io.renderer();
    this.audio.addListener(_audioChanged);
  }
  final SocialCallIo io;
  final SocialAudioOutput audio;
  late final rtc.RTCVideoRenderer local, remote;
  rtc.MediaStream? _localVideo, _remoteVideo, _remoteAudio;
  Future<void> _tracks = Future.value();
  void _audioChanged() {
    if (!_closed) notifyListeners();
  }

  rtc.RTCPeerConnection? _peer;
  rtc.RTCRtpSender? _audioSender;
  rtc.MediaStreamTrack? _microphoneTrack;
  rtc.MediaStream? _replacementAudio, _pendingAudio;
  bool _microphoneEnded = false, repairingMicrophone = false;
  String microphoneIssue = '';
  double? microphoneLevel;
  DateTime? _lastVoice;
  double? _lastEnergy;
  bool get microphoneInterrupted =>
      microphone &&
      (_microphoneEnded ||
          _microphoneTrack?.muted == true ||
          _microphoneTrack?.enabled == false);
  bool get microphoneSoundDetected =>
      microphone &&
      !microphoneInterrupted &&
      _lastVoice != null &&
      DateTime.now().difference(_lastVoice!).inSeconds < 5;
  String get microphoneStatus => repairingMicrophone
      ? 'Reconnecting your microphone…'
      : !microphone
      ? 'Your microphone is off'
      : microphoneInterrupted
      ? 'Your microphone was interrupted'
      : microphoneSoundDetected
      ? 'Your microphone is picking up sound'
      : microphoneLevel != null
      ? 'Speak to check your microphone'
      : 'Microphone on · speak to the other person';
  bool _checkingAudio = false, audioStatsAvailable = false;
  int incomingAudioBytes = 0, outgoingAudioBytes = 0;
  Future<void> checkAudio() async {
    if (_closed || _peer == null || _checkingAudio) return;
    _checkingAudio = true;
    try {
      final reports = await _peer!.getStats();
      if (_closed) return;
      var incoming = 0, outgoing = 0;
      double? level, energy;
      for (final report in reports) {
        final v = report.values;
        if ((v['kind'] ?? v['mediaType']) != 'audio') continue;
        if (report.type == 'inbound-rtp') {
          incoming += (v['bytesReceived'] as num?)?.toInt() ?? 0;
        }
        if (report.type == 'outbound-rtp') {
          outgoing += (v['bytesSent'] as num?)?.toInt() ?? 0;
        }
        if (report.type == 'media-source' ||
            report.type == 'track' && v['remoteSource'] == false) {
          level = (v['audioLevel'] as num?)?.toDouble() ?? level;
          energy = (v['totalAudioEnergy'] as num?)?.toDouble() ?? energy;
        }
      }
      audioStatsAvailable = true;
      incomingAudioBytes = incoming;
      outgoingAudioBytes = outgoing;
      microphoneLevel = microphone && !microphoneInterrupted
          ? level?.clamp(0, 1)
          : 0;
      if (microphone &&
          !microphoneInterrupted &&
          ((level ?? 0) > .01 ||
              energy != null && _lastEnergy != null && energy > _lastEnergy!)) {
        _lastVoice = DateTime.now();
      }
      _lastEnergy = energy;
      notifyListeners();
    } catch (_) {
      /* Some browsers do not expose audio statistics. */
    } finally {
      _checkingAudio = false;
    }
  }

  rtc.MediaStream? _stream;
  Future<void>? _rendererInit;
  Future<void>? _closing;
  bool _closed = false, ready = false;
  bool microphone = true,
      camera = true,
      remoteCamera = true,
      remoteMicrophone = true;
  void Function(SocialMap candidate)? onCandidate;
  void Function(String state)? onState;

  Future<void> open(bool video, List<dynamic> servers) async {
    camera = video;
    _rendererInit = Future.wait([
      local.initialize(),
      remote.initialize(),
    ]).then((_) {});
    await _rendererInit;
    if (_closed) return;
    await io.prepare();
    if (_closed) return;
    final peer = await io.peer(servers);
    if (_closed) {
      await peer.close();
      await peer.dispose();
      return;
    }
    _peer = peer;
    peer.onIceCandidate = (candidate) {
      if (!_closed && candidate.candidate?.isNotEmpty == true) {
        onCandidate?.call({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };
    peer.onConnectionState = (state) {
      if (!_closed) {
        onState?.call(
          state.name.replaceFirst('RTCPeerConnectionState', '').toLowerCase(),
        );
      }
    };
    // Render video-only projections. The native renderer's `muted` setter
    // mutes the actual local microphone, not merely a preview monitor.
    _localVideo = await io.stream('social-local-video');
    _remoteVideo = await io.stream('social-remote-video');
    _remoteAudio = await io.stream('social-remote-audio');
    if (_closed) {
      await _disposeProjections();
      return;
    }
    peer.onTrack = (event) {
      // RTCTrackEvent.streams can be empty. Track delivery is authoritative.
      _tracks = _tracks.then((_) => _receiveTrack(event.track)).catchError((
        Object _,
      ) {
        if (!_closed) {
          audio.issue =
              'Could not start incoming sound. Tap Resume sound or call again.';
          audio.changed();
        }
      });
    };
    await audio.prepareCapture();
    if (_closed) return;
    final stream = await io.capture(video);
    if (_closed) {
      await _releaseStream(stream);
      return;
    }
    _stream = stream;
    final microphones = stream.getAudioTracks();
    if (microphones.isEmpty) {
      throw const SocialException(
        'No microphone was opened. Allow microphone access and call again.',
      );
    }
    _watchMicrophone(microphones.first);
    microphones.first.enabled = microphone;
    for (final track in stream.getVideoTracks()) {
      await _localVideo!.addTrack(track);
      if (_closed) return;
    }
    if (video) local.srcObject = _localVideo;
    for (final track in stream.getTracks()) {
      if (_closed) return;
      if (track.kind != 'audio') {
        track.onEnded = () {
          if (!_closed) onState?.call('device-ended');
        };
      }
      final sender = await peer.addTrack(track, stream);
      if (track == _microphoneTrack) _audioSender = sender;
    }
    if (_closed) return;
    await io.configure();
    if (_closed) return;
    ready = true;
    notifyListeners();
  }

  Future<void> _receiveTrack(rtc.MediaStreamTrack track) async {
    if (_closed) return;
    final stream = track.kind == 'audio' ? _remoteAudio : _remoteVideo;
    if (stream == null) return;
    if (!stream.getTracks().any((t) => t.id == track.id)) {
      await stream.addTrack(track);
    }
    if (_closed) return;
    if (track.kind == 'audio') {
      track.onUnMute = () {
        if (!_closed) unawaited(audio.resume());
      };
      await audio.attach(stream);
    } else if (track.kind == 'video') {
      remote.srcObject = stream;
    }
    if (!_closed) notifyListeners();
  }

  Future<void> _disposeProjections() async {
    final streams = [_localVideo, _remoteVideo, _remoteAudio];
    _localVideo = _remoteVideo = _remoteAudio = null;
    for (final stream in streams) {
      try {
        await stream?.dispose();
      } catch (_) {}
    }
  }

  Future<String> offer() async {
    final description = await _peer!.createOffer();
    if (_closed) throw StateError('Call closed');
    await _peer!.setLocalDescription(description);
    return description.sdp!;
  }

  Future<String> answer() async {
    final description = await _peer!.createAnswer();
    if (_closed) throw StateError('Call closed');
    await _peer!.setLocalDescription(description);
    return description.sdp!;
  }

  Future<void> description(String kind, String sdp) =>
      _peer!.setRemoteDescription(rtc.RTCSessionDescription(sdp, kind));
  Future<void> candidate(SocialMap data) => _peer!.addCandidate(
    rtc.RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      (data['sdpMLineIndex'] as num?)?.toInt(),
    ),
  );
  void toggleMicrophone() {
    if (_closed || !ready || repairingMicrophone) return;
    microphone = !microphone;
    _microphoneTrack?.enabled = microphone;
    _lastVoice = null;
    microphoneLevel = null;
    notifyListeners();
  }

  void _watchMicrophone(rtc.MediaStreamTrack track) {
    _microphoneTrack = track;
    _microphoneEnded = false;
    void changed() {
      if (!_closed && identical(_microphoneTrack, track)) notifyListeners();
    }

    track.onMute = changed;
    track.onUnMute = changed;
    track.onEnded = () {
      if (!_closed && identical(_microphoneTrack, track)) {
        _microphoneEnded = true;
        _lastVoice = null;
        changed();
      }
    };
  }

  /// User-triggered recovery replaces only the existing audio sender. It keeps
  /// the call, camera and user's intentional mute state intact.
  Future<void> restartMicrophone() async {
    if (_closed || !ready || repairingMicrophone || _audioSender == null) {
      return;
    }
    repairingMicrophone = true;
    microphoneIssue = '';
    notifyListeners();
    rtc.MediaStream? fresh;
    try {
      await audio.prepareCapture();
      if (_closed) return;
      fresh = await io.capture(false);
      if (_closed) return;
      _pendingAudio = fresh;
      final tracks = fresh.getAudioTracks();
      if (tracks.isEmpty) throw StateError('No microphone track');
      final next = tracks.first;
      next.enabled = microphone;
      await _audioSender!.replaceTrack(next);
      if (_closed) return;
      final oldTrack = _microphoneTrack, oldStream = _replacementAudio;
      _replacementAudio = fresh;
      _pendingAudio = null;
      fresh = null;
      _watchMicrophone(next);
      _lastVoice = null;
      _lastEnergy = null;
      microphoneLevel = null;
      try {
        if (oldStream != null) {
          await _releaseStream(oldStream);
        } else {
          oldTrack?.enabled = false;
          await oldTrack?.stop();
        }
      } catch (_) {}
      if (!_closed) await audio.resume();
    } catch (_) {
      if (!_closed) {
        microphoneIssue =
            'Could not reopen the microphone. Allow microphone access for KORLIX in your browser settings, close other microphone apps or tabs, then try again.';
      }
    } finally {
      if (identical(_pendingAudio, fresh)) _pendingAudio = null;
      if (fresh != null) await _releaseStream(fresh);
      repairingMicrophone = false;
      if (!_closed) notifyListeners();
    }
  }

  void toggleCamera() {
    camera = !camera;
    for (final track in _stream?.getVideoTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = camera;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _stream?.getVideoTracks() ?? <rtc.MediaStreamTrack>[];
    if (tracks.isNotEmpty) await rtc.Helper.switchCamera(tracks.first);
  }

  void remoteStatus(SocialMap payload) {
    remoteCamera = payload['camera'] == true;
    remoteMicrophone = payload['microphone'] == true;
    notifyListeners();
  }

  static Future<void> _releaseStream(rtc.MediaStream stream) async {
    for (final track in stream.getTracks()) {
      track.enabled = false;
    }
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  // Navigation can call close after the controller starts teardown. Every
  // caller must await the same cleanup before a new call opens its devices.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    ready = false;
    audio.removeListener(_audioChanged);
    final audioClosing = audio.close();
    final stream = _stream,
        peer = _peer,
        replacement = _replacementAudio,
        pending = _pendingAudio;
    _stream = null;
    _peer = null;
    _replacementAudio = null;
    _pendingAudio = null;
    _audioSender = null;
    _microphoneTrack?.enabled = false;
    for (final track in pending?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = false;
    }
    // Disable synchronously, including during logout/navigation.
    for (final track in stream?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = false;
    }
    await audioClosing;
    try {
      if (stream != null) await _releaseStream(stream);
      if (replacement != null) await _releaseStream(replacement);
      if (pending != null) await _releaseStream(pending);
    } catch (_) {}
    try {
      await peer?.close();
      await peer?.dispose();
    } catch (_) {}
    try {
      if (_rendererInit != null) {
        await _rendererInit;
        local.srcObject = null;
        remote.srcObject = null;
        await local.dispose();
        await remote.dispose();
      }
    } catch (_) {}
    await _tracks;
    await _disposeProjections();
    try {
      await io.clear();
    } catch (_) {}
  }
}

class SocialCallController extends ChangeNotifier {
  SocialCallController({
    required this.client,
    required this.peer,
    required this.video,
    SocialMap? incoming,
    SocialCallMedia? media,
  }) : media = media ?? SocialCallMedia(),
       incoming = incoming != null,
       id = incoming?['id'] ?? socialId(),
       state = incoming?['state'] ?? 'preparing' {
    client.addListener(_session);
    this.media.onCandidate = (candidate) =>
        unawaited(_sendSignal('candidate', candidate));
    this.media.onState = _mediaState;
    this.media.addListener(_notify);
  }
  final SocialClient client;
  final SocialMap peer;
  final bool video, incoming;
  final String id;
  final SocialCallMedia media;
  String state, status = '', error = '';
  bool busy = false, ended = false, connected = false, relay = false;
  bool _disposed = false,
      _polling = false,
      _offered = false,
      _description = false;
  bool _started = false;
  bool _answerStarted = false;
  int _cursor = 0;
  Timer? _timer, _clock;
  DateTime? connectedAt, _acceptedAt, _disconnectedAt;
  DateTime _lastResponse = DateTime.now();
  Future<void> _outbox = Future.value();
  final List<SocialMap> _candidates = [];
  SocialMap get _data => {'id': id, 'device': client.callDevice};
  Duration get elapsed => connectedAt == null
      ? Duration.zero
      : DateTime.now().difference(connectedAt!);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _session() {
    if (!client.available) {
      unawaited(
        end(
          'Your session changed. Reopen Social after signing in.',
          notifyServer: false,
        ),
      );
    }
  }

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    status = incoming
        ? 'Incoming ${video ? 'video' : 'audio'} call'
        : 'Preparing your ${video ? 'camera and microphone' : 'microphone'}…';
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ended) return;
      if (!busy && DateTime.now().difference(_lastResponse).inSeconds > 25) {
        unawaited(end('Connection lost. Please try calling again.'));
      } else if (_acceptedAt != null &&
          !connected &&
          DateTime.now().difference(_acceptedAt!).inSeconds > 40) {
        unawaited(
          end(
            relay
                ? 'The call could not connect. Try again or switch networks.'
                : 'This network could not connect the call. Try another Wi-Fi or mobile network.',
          ),
        );
      } else if (_disconnectedAt != null &&
          DateTime.now().difference(_disconnectedAt!).inSeconds > 15) {
        unawaited(end('The connection was interrupted. Please call again.'));
      }
      if (connected && elapsed.inSeconds.isEven) unawaited(media.checkAudio());
      _notify();
    });
    if (incoming) {
      _startPolling();
    } else {
      busy = true;
      _notify();
      try {
        await _openMedia();
        if (ended) return;
        final result = await client.post('call_start', {
          ..._data,
          'peer': peer['id'],
          'mode': video ? 'video' : 'audio',
        });
        if (ended) {
          // A canceled request can finish after the first end attempt reached
          // the server. Close that late invitation instead of leaving it ringing.
          if (client.available) {
            try {
              await client.post('call_end', _data);
            } catch (_) {}
          }
          return;
        }
        _applyCall(socialMap(result['call']));
        _lastResponse = DateTime.now();
        _startPolling();
      } catch (e) {
        if (!ended) await end(_friendly(e));
      } finally {
        busy = false;
        _notify();
      }
    }
  }

  String _friendly(Object e) => e is SocialException
      ? '$e'
      : 'Camera or microphone unavailable. Allow access in your browser or device settings, then try again.';
  Future<void> _openMedia() async {
    final config = await client.get('call_config');
    if (ended) return;
    if (config['enabled'] != true) {
      throw const SocialException(
        'Calling is temporarily unavailable. You can still send a message.',
      );
    }
    relay = config['relay'] == true;
    await media.open(video, config['iceServers'] as List? ?? []);
  }

  void _startPolling() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(poll()),
    );
  }

  Future<void> accept() async {
    if (!incoming || busy || ended || _answerStarted || state != 'ringing') {
      return;
    }
    unawaited(media.audio.activate());
    _answerStarted = true;
    busy = true;
    status =
        'Preparing your ${video ? 'camera and microphone' : 'microphone'}…';
    _notify();
    try {
      await _openMedia();
      if (ended) return;
      final result = await client.post('call_accept', _data);
      if (ended) return;
      _lastResponse = DateTime.now();
      _applyCall(socialMap(result['call']));
    } catch (e) {
      if (!ended) await end(_friendly(e));
    } finally {
      busy = false;
      _notify();
    }
  }

  void _applyCall(SocialMap call) {
    if (ended || call.isEmpty) return;
    if (_acceptedAt != null && call['state'] == 'ringing') return;
    state = call['state'] ?? state;
    unawaited(media.audio.setRinging(state == 'ringing' && !incoming));
    if (!['ringing', 'accepted'].contains(state)) {
      unawaited(
        end(
          state == 'declined'
              ? 'Call declined'
              : state == 'missed'
              ? 'No answer'
              : 'Call ended',
          notifyServer: false,
        ),
      );
    } else if (state == 'accepted') {
      _acceptedAt ??= DateTime.now();
      if (!connected) status = 'Connecting…';
    } else {
      status = incoming
          ? 'Incoming ${video ? 'video' : 'audio'} call'
          : 'Calling ${peer['name']}…';
    }
  }

  Future<void> poll() async {
    if (ended || _polling) return;
    _polling = true;
    try {
      final result = await client.get('call_poll', {
        ..._data,
        'after': _cursor,
      });
      if (ended) return;
      _lastResponse = DateTime.now();
      _applyCall(socialMap(result['call']));
      if (ended) return;
      if (state == 'accepted' && !incoming && !_offered && media.ready) {
        _offered = true;
        final sdp = await media.offer();
        if (ended) return;
        await _sendSignal('offer', {'sdp': sdp});
      }
      for (final signal in socialItems(result['signals'])) {
        if (ended) return;
        final kind = signal['kind'], payload = socialMap(signal['payload']);
        if ((kind == 'offer' && incoming || kind == 'answer' && !incoming) &&
            !_description) {
          if (!media.ready) {
            return; // Answering permission dialog may still be open.
          }
          await media.description(kind, payload['sdp']);
          if (ended) return;
          _description = true;
          for (final candidate in _candidates) {
            if (!ended) await media.candidate(candidate);
          }
          _candidates.clear();
          if (kind == 'offer' && !ended) {
            await _sendSignal('answer', {'sdp': await media.answer()});
          }
        } else if (kind == 'candidate') {
          if (_description) {
            await media.candidate(payload);
          } else {
            _candidates.add(payload);
          }
        } else if (kind == 'media') {
          media.remoteStatus(payload);
        }
        _cursor = (signal['seq'] as num).toInt();
      }
      _notify();
    } catch (e) {
      if (!ended &&
          e is SocialException &&
          [401, 403, 404].contains(e.status)) {
        await end('$e', notifyServer: false);
      } else if (!ended && e is! SocialException) {
        await end('The call could not connect. Please try again.');
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _sendSignal(String kind, SocialMap payload) {
    final signalId = socialId();
    _outbox = _outbox
        .then((_) async {
          if (ended) return;
          final data = {
            ..._data,
            'kind': kind,
            'payload': payload,
            'signal_id': signalId,
          };
          try {
            await client.post('call_signal', data);
          } catch (_) {
            if (!ended && client.available) {
              await client.post('call_signal', data);
            }
          }
        })
        .catchError((Object _) async {
          if (!ended) {
            await end('The call connection was interrupted. Please try again.');
          }
        });
    return _outbox;
  }

  void _mediaState(String value) {
    if (ended) return;
    if (value == 'connected') {
      connected = true;
      connectedAt ??= DateTime.now();
      _disconnectedAt = null;
      status = 'Connected';
      _publishMedia();
    } else if (value == 'disconnected') {
      _disconnectedAt ??= DateTime.now();
      status = 'Reconnecting…';
    } else if (['failed', 'closed', 'device-ended'].contains(value)) {
      unawaited(
        end(
          value == 'device-ended'
              ? 'Your microphone or camera stopped.'
              : 'The call could not stay connected. Try another network.',
        ),
      );
    }
    _notify();
  }

  void toggleMicrophone() {
    if (ended || !media.ready) return;
    media.toggleMicrophone();
    _publishMedia();
  }

  Future<void> reconnectMicrophone() async {
    if (ended || !media.ready) return;
    unawaited(media.audio.resume());
    await media.restartMicrophone();
    if (!ended) _publishMedia();
  }

  void toggleCamera() {
    if (ended || !media.ready || !video) return;
    media.toggleCamera();
    _publishMedia();
  }

  void _publishMedia() {
    if (state == 'accepted') {
      unawaited(
        _sendSignal('media', {
          'camera': media.camera,
          'microphone': media.microphone,
        }),
      );
    }
  }

  Future<void> end(String message, {bool notifyServer = true}) async {
    if (ended) return;
    ended = true;
    unawaited(media.audio.setRinging(false));
    busy = false;
    connected = false;
    status = message;
    _timer?.cancel();
    _clock?.cancel();
    _candidates.clear();
    unawaited(media.close());
    _notify();
    if (notifyServer && client.available) {
      try {
        await client.post('call_end', _data);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    client.removeListener(_session);
    media.removeListener(_notify);
    unawaited(end('Call ended'));
    super.dispose();
  }
}
