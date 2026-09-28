import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'social_client.dart';

/// Device I/O is replaceable in tests; consent, signaling and teardown are not.
class SocialCallMedia extends ChangeNotifier {
  final local = rtc.RTCVideoRenderer(), remote = rtc.RTCVideoRenderer();
  rtc.RTCPeerConnection? _peer;
  rtc.MediaStream? _stream;
  Future<void>? _rendererInit;
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await rtc.Helper.ensureAudioSession();
    }
    if (_closed) return;
    final peer = await rtc.createPeerConnection({
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    });
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
    peer.onTrack = (event) {
      if (!_closed && event.streams.isNotEmpty) {
        remote.srcObject = event.streams.first;
        remote.muted = false;
        notifyListeners();
      }
    };
    final stream = await rtc.navigator.mediaDevices.getUserMedia({
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
    if (_closed) {
      await _releaseStream(stream);
      return;
    }
    _stream = stream;
    local.srcObject = stream;
    local.muted = true;
    for (final track in stream.getTracks()) {
      if (_closed) return;
      track.onEnded = () {
        if (!_closed) onState?.call('device-ended');
      };
      await peer.addTrack(track, stream);
    }
    if (_closed) return;
    if (!kIsWeb) await rtc.Helper.setSpeakerphoneOnButPreferBluetooth();
    if (_closed) return;
    ready = true;
    notifyListeners();
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
    microphone = !microphone;
    for (final track in _stream?.getAudioTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = microphone;
    }
    notifyListeners();
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ready = false;
    final stream = _stream, peer = _peer;
    _stream = null;
    _peer = null;
    // Disable synchronously, including during logout/navigation.
    for (final track in stream?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
      track.enabled = false;
    }
    try {
      if (stream != null) await _releaseStream(stream);
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await rtc.Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }
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
