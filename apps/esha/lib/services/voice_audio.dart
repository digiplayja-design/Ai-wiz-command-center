import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models.dart';

enum VoiceAudioEventType { started, closed, disconnected, error }

class VoiceAudioEvent {
  const VoiceAudioEvent(this.type, {this.sessionId});
  final VoiceAudioEventType type;
  final String? sessionId;
}

/// The transport contains no API credential and cannot create a paid session.
/// Only the authenticated Korlix backend supplies its remote SDP answer.
abstract interface class VoiceAudioTransport {
  Stream<VoiceAudioEvent> get events;
  bool get requestingMicrophone;
  Future<String> createOffer();
  Future<void> acceptAnswer(String sdp);
  Future<void> enableMicrophone();
  Future<void> close();
}

class WebRtcVoiceAudio implements VoiceAudioTransport {
  final _events = StreamController<VoiceAudioEvent>.broadcast();
  RTCPeerConnection? _peer;
  MediaStream? _microphone;
  RTCDataChannel? _channel;
  Future<void>? _closing;
  bool _closed = false;
  bool _requestingMicrophone = false;

  @override
  bool get requestingMicrophone => _requestingMicrophone;

  @override
  Stream<VoiceAudioEvent> get events => _events.stream;

  void _emit(VoiceAudioEvent event) {
    if (!_closed && !_events.isClosed) _events.add(event);
  }

  void _checkOpen() {
    if (_closed) {
      throw const EshaException('VOICE_CANCELLED', 'The voice session ended.');
    }
  }

  @override
  Future<String> createOffer() async {
    _checkOpen();
    try {
      _requestingMicrophone = true;
      late final MediaStream microphone;
      try {
        microphone = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      } finally {
        _requestingMicrophone = false;
      }
      // Capture permission does not authorize transmission. Disable every track
      // before attaching it; the controller enables audio only after both the
      // backend answer and the provider's session.started event are accepted.
      for (final track in microphone.getTracks()) {
        track.enabled = false;
      }
      if (_closed) {
        for (final track in microphone.getTracks()) {
          await track.stop();
        }
        await microphone.dispose();
        _checkOpen();
      }
      _microphone = microphone;
      if (microphone.getAudioTracks().isEmpty ||
          microphone.getVideoTracks().isNotEmpty) {
        throw const EshaException(
          'VOICE_MICROPHONE',
          'Esha could not open an audio-only microphone connection.',
        );
      }
      final peer = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        // The provider's SDP supplies the remote ICE candidates. No unrelated
        // public STUN service or credential is added to the device connection.
        'iceServers': <Map<String, dynamic>>[],
      });
      if (_closed) {
        await peer.close();
        await peer.dispose();
        _checkOpen();
      }
      _peer = peer;
      peer.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _emit(const VoiceAudioEvent(VoiceAudioEventType.disconnected));
        }
      };
      peer.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _emit(const VoiceAudioEvent(VoiceAudioEventType.disconnected));
        }
      };
      for (final track in microphone.getAudioTracks()) {
        track.onEnded = () =>
            _emit(const VoiceAudioEvent(VoiceAudioEventType.disconnected));
        await peer.addTrack(track, microphone);
        _checkOpen();
      }
      final channel = await peer.createDataChannel(
        'oai-events',
        RTCDataChannelInit()..ordered = true,
      );
      if (_closed) {
        await channel.close();
        _checkOpen();
      }
      _channel = channel;
      channel.onMessage = _onMessage;
      channel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelClosed) {
          _emit(const VoiceAudioEvent(VoiceAudioEventType.disconnected));
        }
      };
      final gathered = Completer<void>();
      peer.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !gathered.isCompleted) {
          gathered.complete();
        }
      };
      final offer = await peer.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      _checkOpen();
      await peer.setLocalDescription(offer);
      if (peer.iceGatheringState !=
          RTCIceGatheringState.RTCIceGatheringStateComplete) {
        await gathered.future.timeout(const Duration(seconds: 12));
      }
      _checkOpen();
      final local = await peer.getLocalDescription();
      final sdp = local?.sdp;
      if (sdp == null || !sdp.startsWith('v=0') || sdp.length > 65536) {
        throw const EshaException(
          'VOICE_CONNECTION',
          'Esha could not prepare the voice connection.',
        );
      }
      return sdp;
    } catch (error) {
      await close();
      if (error is EshaException) rethrow;
      throw const EshaException(
        'VOICE_MICROPHONE',
        'The microphone or voice connection could not start. Check microphone permission in your device settings and try again.',
      );
    }
  }

  void _onMessage(RTCDataChannelMessage message) {
    if (_closed || message.isBinary || message.text.length > 131072) return;
    try {
      final value = jsonDecode(message.text);
      if (value is! Map) return;
      final data = object(value);
      final session = object(data['session']);
      final id = session['id'] ?? data['session_id'];
      switch (data['type']) {
        case 'session.started':
          _emit(
            VoiceAudioEvent(
              VoiceAudioEventType.started,
              sessionId: id is String ? id : null,
            ),
          );
        case 'session.closed':
          _emit(const VoiceAudioEvent(VoiceAudioEventType.closed));
        case 'error':
        case 'session.error':
          _emit(const VoiceAudioEvent(VoiceAudioEventType.error));
      }
      // Transcripts, delegation content and SDP are never logged or persisted
      // here. Delegation and final billing evidence belong to the server.
    } catch (_) {
      // An unknown event cannot authorize microphone transmission or billing.
    }
  }

  @override
  Future<void> acceptAnswer(String sdp) async {
    _checkOpen();
    if (_peer == null || !sdp.startsWith('v=0') || sdp.length > 65536) {
      throw const EshaException(
        'VOICE_CONNECTION',
        'The voice answer was incomplete.',
      );
    }
    await _peer!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _checkOpen();
  }

  @override
  Future<void> enableMicrophone() async {
    _checkOpen();
    if (_microphone == null) {
      throw const EshaException(
        'VOICE_MICROPHONE',
        'The microphone is unavailable.',
      );
    }
    for (final track in _microphone!.getAudioTracks()) {
      track.enabled = true;
    }
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    // Disable audio synchronously before awaiting native disposal or the server.
    final microphone = _microphone;
    for (final track in microphone?.getTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = false;
    }
    final peer = _peer, channel = _channel;
    _peer = null;
    _channel = null;
    _microphone = null;
    _closing = () async {
      Future<void> attempt(Future<void> Function() action) async {
        try {
          await action();
        } catch (_) {
          // Continue releasing the remaining audio resources after one failure.
        }
      }

      if (channel != null) await attempt(channel.close);
      if (peer != null) {
        await attempt(peer.close);
        await attempt(peer.dispose);
      }
      if (microphone != null) {
        for (final track in microphone.getTracks()) {
          await attempt(track.stop);
        }
        await attempt(microphone.dispose);
      }
      await _events.close();
    }();
    return _closing!;
  }
}
