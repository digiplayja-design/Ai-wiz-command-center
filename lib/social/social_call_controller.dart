import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../sounds/korlix_sound_service.dart';
import 'social_client.dart';
import 'social_audio_output.dart';
import 'social_call_background.dart';
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
      await rtc.Helper.setAppleAudioConfiguration(
        rtc.AppleAudioConfiguration(
          appleAudioCategory: rtc.AppleAudioCategory.playAndRecord,
          appleAudioMode: rtc.AppleAudioMode.voiceChat,
          appleAudioCategoryOptions: {
            rtc.AppleAudioCategoryOption.allowBluetooth,
          },
        ),
      );
      await rtc.Helper.ensureAudioSession();
    }
  }

  Future<rtc.MediaStream> captureVideo() =>
      rtc.navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      });

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
  rtc.RTCRtpSender? _videoSender;
  rtc.MediaStream? _replacementVideo;
  bool _cameraSuspended = false, _repairingCamera = false;
  bool get cameraSuspended => _cameraSuspended;
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
          if (!_closed && !_cameraSuspended) onState?.call('device-ended');
        };
      }
      final sender = await peer.addTrack(track, stream);
      // Web getTracks() wraps the same JS track in a NEW Dart object each time.
      // Object equality leaves the audio sender unset and makes recovery a no-op.
      if (track.kind == 'audio' && track.id == _microphoneTrack?.id) {
        _audioSender = sender;
      }
      if (track.kind == 'video') _videoSender = sender;
    }
    if (_closed) return;
    await io.configure();
    if (video && audio.canRouteSpeaker && !_closed) {
      await audio.routeSpeaker(true);
    }
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
      // A blocked audio play promise must not hold the video track queue.
      unawaited(
        audio.attach(stream).catchError((Object _) {
          if (!_closed) {
            audio.issue = 'Tap Resume sound to start incoming audio.';
            audio.changed();
          }
        }),
      );
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

  Future<String> restartOffer() async {
    await _peer!.restartIce();
    if (_closed) throw StateError('Call closed');
    return offer();
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

  Future<void> toggleCamera() async {
    if (_closed || !ready || _repairingCamera) return;
    if (_cameraSuspended) {
      await _restoreCamera();
      return;
    }
    camera = !camera;
    for (final track in _stream?.getVideoTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = camera;
    }
    notifyListeners();
  }

  /// Stop capture, not just transmission, when a native app leaves view.
  /// Reopening the camera always requires another explicit camera-button tap.
  Future<void> suspendCamera() async {
    if (_closed || _cameraSuspended) return;
    _cameraSuspended = true;
    camera = false;
    local.srcObject = null;
    for (final track in [
      ...?_stream?.getVideoTracks(),
      ...?_replacementVideo?.getVideoTracks(),
    ]) {
      track.onEnded = null;
      track.enabled = false;
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await _videoSender?.replaceTrack(null);
    } catch (_) {}
    if (!_closed) notifyListeners();
  }

  Future<void> _restoreCamera() async {
    if (_videoSender == null) return;
    _repairingCamera = true;
    rtc.MediaStream? fresh;
    try {
      fresh = await io.captureVideo();
      if (_closed) return;
      final track = fresh.getVideoTracks().first;
      await _videoSender!.replaceTrack(track);
      if (_closed) return;
      if (_replacementVideo != null) await _releaseStream(_replacementVideo!);
      _replacementVideo = fresh;
      fresh = null;
      local.srcObject = _replacementVideo;
      _cameraSuspended = false;
      camera = true;
      track.onEnded = () {
        if (!_closed && !_cameraSuspended) onState?.call('device-ended');
      };
      notifyListeners();
    } catch (_) {
      // Keep video off and preserve the audio call. Another tap can retry.
    } finally {
      if (fresh != null) await _releaseStream(fresh);
      _repairingCamera = false;
    }
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
        replacementVideo = _replacementVideo,
        pending = _pendingAudio;
    _stream = null;
    _peer = null;
    _replacementAudio = null;
    _replacementVideo = null;
    _pendingAudio = null;
    _audioSender = null;
    _videoSender = null;
    _microphoneTrack?.enabled = false;
    for (final track in pending?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = false;
    }
    // Disable synchronously, including during logout/navigation.
    for (final track in stream?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = false;
    }
    for (final track
        in replacementVideo?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = false;
    }
    await audioClosing;
    try {
      if (stream != null) await _releaseStream(stream);
      if (replacement != null) await _releaseStream(replacement);
      if (replacementVideo != null) await _releaseStream(replacementVideo);
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
    KorlixSoundService? sounds,
    DateTime? ringExpiresAt,
    SocialCallBackground? background,
  }) : media = media ?? SocialCallMedia(),
       background = background ?? SocialCallBackground(),
       sounds = sounds ?? kKorlixSounds,
       // Only incoming invitations inherit the app-wide alert's deadline.
       _ringExpiresAt = incoming != null ? ringExpiresAt : null,
       incoming = incoming != null,
       id = incoming?['id'] ?? socialId(),
       state = incoming?['state'] ?? 'preparing' {
    client.addListener(_session);
    this.media.onCandidate = (candidate) => unawaited(
      _sendSignal('candidate', {...candidate, 'generation': _generation}),
    );
    this.media.onState = _mediaState;
    this.media.addListener(_notify);
    this.background.onStopped = () =>
        unawaited(end('Call ended by your device.'));
  }
  final SocialClient client;
  final SocialMap peer;
  final bool video, incoming;
  final String id;
  final SocialCallMedia media;
  final KorlixSoundService sounds;
  final SocialCallBackground background;
  DateTime? _ringExpiresAt;
  bool _closingMedia = false;
  String state, status = '', error = '';
  bool busy = false, ended = false, connected = false, relay = false;
  bool recoverySupported = false;
  String relayStatus = '';
  bool _disposed = false,
      _polling = false,
      _offered = false,
      _description = false;
  bool _started = false;
  bool _answerStarted = false;
  int _cursor = 0;
  int _generation = 0, _remoteGeneration = -1, _recoveries = 0;
  bool _recovering = false;
  DateTime? _lastRecovery;
  String get connectionDetails => _recoveries > 0
      ? 'Network recovery $_recoveries of 3 · ${relay ? 'Call relay available' : 'Direct connection'}'
      : relay
      ? 'Call relay available'
      : 'Direct connection';
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
    _syncSounds();
    if (!_disposed) notifyListeners();
  }

  void _syncSounds() {
    final ringing =
        !ended && !_disposed && state == 'ringing' && !_answerStarted;
    if (ringing) {
      _ringExpiresAt ??= DateTime.now().add(const Duration(seconds: 45));
    }
    // Ringback is allowed while waiting for an answer. Effects stay silent
    // during capture setup, answering, connection, and track teardown.
    sounds.setQuiet(
      this,
      _closingMedia ||
          (!ended &&
              !_disposed &&
              (_answerStarted ||
                  connected ||
                  state == 'accepted' ||
                  state == 'preparing' && busy)),
    );
    sounds.setRinging(
      this,
      ringing,
      callId: id,
      expiresAt: _ringExpiresAt,
      outgoing: !incoming,
    );
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
      if (!busy && DateTime.now().difference(_lastResponse).inSeconds > 45) {
        unawaited(end('Connection lost. Please try calling again.'));
      } else if (_acceptedAt != null &&
          !connected &&
          DateTime.now().difference(_acceptedAt!).inSeconds > 40) {
        unawaited(
          end(
            relay
                ? 'The call could not connect. Try again or switch networks.'
                : 'The call could not connect. KORLIX needs its call relay enabled for this network.',
          ),
        );
      } else if (_disconnectedAt != null &&
          DateTime.now().difference(_disconnectedAt!).inSeconds > 40) {
        unawaited(end('The connection was interrupted. Please call again.'));
      } else if (_disconnectedAt != null &&
          (_lastRecovery == null ||
              DateTime.now().difference(_lastRecovery!).inSeconds >= 10)) {
        unawaited(reconnect());
      }
      if (media.ready && DateTime.now().second.isEven) {
        unawaited(media.checkAudio());
      }
      _notify();
    });
    if (incoming) {
      _notify();
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
          'protocol': 2,
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

  String _friendly(Object e) {
    if (e is SocialException) return '$e';
    final detail = '$e';
    if (detail.contains('NotAllowedError') ||
        detail.contains('PermissionDenied')) {
      return 'Microphone${video ? ' or camera' : ''} access was denied. Allow it for KORLIX in browser or device settings, then call again.';
    }
    if (detail.contains('NotReadableError') ||
        detail.contains('TrackStartError')) {
      return 'Another app or tab may be using your microphone or camera. Close it and call again.';
    }
    if (detail.contains('NotFoundError')) {
      return 'No microphone${video ? ' or camera' : ''} was found on this device.';
    }
    return 'Camera or microphone unavailable. Allow access in your browser or device settings, then try again.';
  }

  Future<void> _openMedia() async {
    final config = await client.get('call_config');
    if (ended) return;
    if (config['enabled'] != true) {
      throw const SocialException(
        'Calling is temporarily unavailable. You can still send a message.',
      );
    }
    relay = config['relay'] == true;
    relayStatus =
        '${config['relayStatus'] ?? (relay ? 'ready' : 'not-configured')}';
    await media.open(video, config['iceServers'] as List? ?? []);
    if (!ended) await background.start(id);
    if (ended) await background.stop();
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
      final result = await client.post('call_accept', {
        ..._data,
        'protocol': 2,
      });
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
    recoverySupported = call['recovery_supported'] == true;
    _syncSounds();
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
        await _sendSignal('offer', {'sdp': sdp, 'generation': _generation});
      }
      for (final signal in socialItems(result['signals'])) {
        if (ended) return;
        final kind = signal['kind'], payload = socialMap(signal['payload']);
        final generation = (payload['generation'] as num?)?.toInt() ?? 0;
        if ((kind == 'offer' && incoming || kind == 'answer' && !incoming) &&
            generation >= _generation &&
            generation != _remoteGeneration &&
            (incoming || generation == _generation)) {
          if (!media.ready) {
            return; // Answering permission dialog may still be open.
          }
          _generation = generation;
          await media.description(kind, payload['sdp']);
          if (ended) return;
          _description = true;
          _remoteGeneration = generation;
          for (final candidate in _candidates) {
            if (!ended && (candidate['generation'] ?? 0) == generation) {
              await _applyCandidate(candidate);
            }
          }
          _candidates.clear();
          if (kind == 'offer' && !ended) {
            await _sendSignal('answer', {
              'sdp': await media.answer(),
              'generation': generation,
            });
          }
        } else if (kind == 'candidate') {
          if (_description && generation == _generation) {
            await _applyCandidate(payload);
          } else if (generation >= _generation && _candidates.length < 128) {
            _candidates.add(payload);
          }
        } else if (kind == 'restart_request' &&
            !incoming &&
            generation == _generation) {
          unawaited(reconnect());
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
          if (ended ||
              kind != 'media' && (payload['generation'] ?? 0) < _generation) {
            return;
          }
          final data = {
            ..._data,
            'kind': kind,
            'payload': payload,
            'signal_id': signalId,
          };
          try {
            await client.post('call_signal', data);
          } catch (e) {
            if (e is SocialException && e.status == 409) {
              // A peer can restart ICE while an earlier candidate is in
              // flight. The next poll supplies the current offer.
              unawaited(poll());
              return;
            }
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

  Future<void> _applyCandidate(SocialMap candidate) async {
    try {
      await media.candidate(candidate);
    } catch (_) {
      // One unusable route must not discard a working relay or other ICE
      // candidates. Connection-state recovery and its deadline remain active.
    }
  }

  void _mediaState(String value) {
    if (ended) return;
    if (value == 'connected') {
      connected = true;
      connectedAt ??= DateTime.now();
      _disconnectedAt = null;
      status = 'Connected';
      _publishMedia();
    } else if (value == 'disconnected' || value == 'failed') {
      connected = false;
      _disconnectedAt ??= DateTime.now();
      status = 'Reconnecting…';
      unawaited(reconnect());
    } else if (['closed', 'device-ended'].contains(value)) {
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

  /// One caller produces offers, so simultaneous network changes cannot create
  /// SDP glare. A bounded, server-versioned restart keeps the same call ID.
  Future<void> reconnect() async {
    if (ended ||
        !recoverySupported ||
        state != 'accepted' ||
        !media.ready ||
        _recovering ||
        _recoveries >= 3 ||
        _lastRecovery != null &&
            DateTime.now().difference(_lastRecovery!).inSeconds < 8) {
      return;
    }
    _recovering = true;
    _lastRecovery = DateTime.now();
    _recoveries++;
    _disconnectedAt ??= DateTime.now();
    status = 'Reconnecting · attempt $_recoveries of 3…';
    _notify();
    try {
      if (incoming) {
        await _sendSignal('restart_request', {'generation': _generation});
      } else {
        final result = await client.post('call_restart', {
          ..._data,
          'generation': _generation,
        });
        if (ended) return;
        final call = socialMap(result['call']);
        final generation = (call['generation'] as num?)?.toInt();
        if (call['state'] != 'accepted' ||
            generation == null ||
            generation <= _generation) {
          throw const SocialException(
            'The other device could not restart this call.',
          );
        }
        _generation = generation;
        _description = false;
        _candidates.clear();
        final sdp = await media.restartOffer();
        if (!ended) {
          await _sendSignal('offer', {'sdp': sdp, 'generation': generation});
        }
      }
    } catch (e) {
      if (!ended &&
          e is SocialException &&
          [401, 403, 404].contains(e.status)) {
        await end('$e', notifyServer: false);
      } else if (!ended) {
        status = 'Waiting for the network · recovery $_recoveries of 3';
      }
    } finally {
      _recovering = false;
      _notify();
    }
  }

  void resume() {
    if (ended) return;
    _lastResponse = DateTime.now();
    unawaited(poll());
    if (_disconnectedAt != null) unawaited(reconnect());
  }

  void backgrounded() {
    if (ended || kIsWeb) return;
    if (!background.ready || !media.ready) {
      unawaited(
        end(
          'This device cannot keep the call active in the background. Keep KORLIX open to call.',
        ),
      );
      return;
    }
    if (video) {
      unawaited(
        media.suspendCamera().then((_) {
          if (!ended) _publishMedia();
        }),
      );
    }
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
    unawaited(
      media.toggleCamera().then((_) {
        if (!ended) _publishMedia();
      }),
    );
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
    _closingMedia = true;
    busy = false;
    connected = false;
    status = message;
    _timer?.cancel();
    _clock?.cancel();
    _candidates.clear();
    unawaited(background.stop());
    unawaited(
      media.close().whenComplete(() {
        _closingMedia = false;
        _syncSounds();
      }),
    );
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
