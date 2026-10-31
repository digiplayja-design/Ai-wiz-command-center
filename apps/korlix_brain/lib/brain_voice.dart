import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'brain_api.dart';
import 'voice_usage_guard.dart';

class BrainVoice {
  BrainVoice(this.api, this.emit);
  final BrainApi api;
  final void Function(Map<String, dynamic>) emit;
  RTCPeerConnection? _peer;
  MediaStream? _microphone;
  RTCDataChannel? _channel;
  RTCVideoRenderer? _renderer;
  KorlixLiveConvoUsageGuard? _usage;
  Timer? _deadline, _disconnect;
  int _generation = 0;
  bool _active = false, _ready = false;
  bool get active => _active;

  void _state(String phase, String message) =>
      emit({'type': 'voice', 'phase': phase, 'message': message});

  Future<void> start() async {
    await stop();
    final generation = ++_generation;
    final account = api.auth.revision;
    bool current() =>
        generation == _generation && account == api.auth.revision && _active;
    void check() {
      if (!current()) throw const BrainApiException('Voice start canceled.');
    }

    _active = true;
    _state('connecting', 'Connecting to Rici…');
    _deadline = Timer(const Duration(seconds: 65), () {
      if (current()) {
        unawaited(
          stop(message: 'Voice took too long to connect. Please try again.'),
        );
      }
    });
    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      if (!current()) {
        await renderer.dispose();
        check();
      }
      _renderer = renderer;
      final peer = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      if (!current()) {
        await peer.close();
        await peer.dispose();
        check();
      }
      _peer = peer;
      final ice = Completer<void>();
      peer.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !ice.isCompleted) {
          ice.complete();
        }
      };
      peer.onConnectionState = (state) {
        if (!current()) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(
            stop(
              message: 'The voice connection ended. Your microphone is off.',
            ),
          );
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _state('connecting', 'Reconnecting…');
          _disconnect?.cancel();
          _disconnect = Timer(const Duration(seconds: 8), () {
            if (current()) {
              unawaited(
                stop(
                  message: 'Connection lost. Tap reconnect when you are ready.',
                ),
              );
            }
          });
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _disconnect?.cancel();
          if (_ready) _state('listening', 'Rici is listening');
        }
      };
      peer.onTrack = (event) {
        if (current() && event.streams.isNotEmpty) {
          renderer.srcObject = event.streams.first;
        }
      };
      final microphone = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      if (!current()) {
        for (final track in microphone.getTracks()) {
          await track.stop();
        }
        await microphone.dispose();
        check();
      }
      _microphone = microphone;
      if (microphone.getAudioTracks().isEmpty) {
        throw const BrainApiException('Microphone access is needed to talk.');
      }
      for (final track in microphone.getTracks()) {
        track.enabled =
            false; // Open only after the session configuration is acknowledged.
        await peer.addTrack(track, microphone);
        check();
      }
      final channel = await peer.createDataChannel(
        'oai-events',
        RTCDataChannelInit()..ordered = true,
      );
      if (!current()) {
        await channel.close();
        check();
      }
      _channel = channel;
      channel.onMessage = (message) {
        if (!current() || message.isBinary) return;
        try {
          final event = Map<String, dynamic>.from(
            jsonDecode(message.text) as Map,
          );
          unawaited(_usage?.observeServerEvent(event));
          final type = event['type'];
          if (type == 'session.created') {
            final instructions = (event['session'] as Map?)?['instructions'];
            if (instructions is! String || instructions.isEmpty) {
              unawaited(
                stop(
                  message:
                      'Rici could not load her instructions. Please reconnect.',
                ),
              );
              return;
            }
            // Preserve all server instructions and account memory. The standalone
            // app does not expose external-action tools or automatic memory writes.
            unawaited(
              channel.send(
                RTCDataChannelMessage(
                  jsonEncode({
                    'type': 'session.update',
                    'session': {
                      'type': 'realtime',
                      'tools': <Object>[],
                      'tool_choice': 'none',
                      'instructions':
                          '$instructions\n\nIn this standalone KORLIX Brain app your spoken name is Rici, pronounced Ree-See. Memory and behavior changes require the user to review and approve them using the app controls. Never claim a change was saved through conversation.',
                    },
                  }),
                ),
              ),
            );
          } else if (type == 'session.updated') {
            _ready = true;
            _deadline?.cancel();
            for (final track in microphone.getAudioTracks()) {
              track.enabled = true;
            }
            _state('listening', 'Rici is listening');
          } else if (type == 'input_audio_buffer.speech_started') {
            _state('listening', 'Listening…');
          } else if (type == 'input_audio_buffer.speech_stopped' ||
              type == 'response.created') {
            _state('thinking', 'Rici is thinking');
          } else if (type == 'output_audio_buffer.started') {
            _state('speaking', 'Rici is speaking');
          } else if (type == 'output_audio_buffer.stopped' ||
              type == 'output_audio_buffer.cleared') {
            _state('listening', 'Rici is listening');
          } else if (type ==
              'conversation.item.input_audio_transcription.completed') {
            emit({
              'type': 'transcript',
              'role': 'you',
              'text': event['transcript']?.toString() ?? '',
            });
          } else if (type == 'response.output_audio_transcript.done' ||
              type == 'response.audio_transcript.done') {
            emit({
              'type': 'transcript',
              'role': 'rici',
              'text': event['transcript']?.toString() ?? '',
            });
          } else if (type == 'error') {
            unawaited(
              stop(
                message: 'Rici could not continue this conversation. Please reconnect.',
              ),
            );
          }
        } catch (_) {
          /* Non-message events never become executable bridge code. */
        }
      };
      channel.onDataChannelState = (state) {
        if (current() && state == RTCDataChannelState.RTCDataChannelClosed) {
          unawaited(
            stop(
              message: 'The voice connection closed. Your microphone is off.',
            ),
          );
        }
      };
      final offer = await peer.createOffer();
      check();
      await peer.setLocalDescription(offer);
      check();
      await ice.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      check();
      final local = await peer.getLocalDescription();
      check();
      final sdp = local?.sdp ?? offer.sdp ?? '';
      if (!sdp.trimLeft().startsWith('v=')) {
        throw const BrainApiException('Could not prepare microphone audio.');
      }
      final response = await api.send(
        'POST',
        '/api/live-convo/session',
        body: sdp,
        headers: {
          'Content-Type': 'application/sdp',
          'Accept': 'application/sdp, application/json',
          'x-korlix-character': 'jj',
          'x-korlix-language': 'English',
          'x-korlix-live-convo-agent': 'general',
          'x-korlix-live-convo-voice': 'marin',
          'x-korlix-live-convo-accent': 'neutral',
        },
        timeout: const Duration(seconds: 45),
      );
      // Always meter and close an allocated session, even if canceled in flight.
      final usage = KorlixLiveConvoUsageGuard();
      await usage.beginFromSessionResponse(
        response,
        onLimitReached: (message) async {
          if (current()) await stop(message: message);
        },
      );
      if (!current()) {
        await usage.end(reason: 'start_canceled');
        check();
      }
      _usage = usage;
      if (!response.body.trimLeft().startsWith('v=')) {
        throw const BrainApiException(
          'Rici returned an invalid voice connection.',
        );
      }
      await peer.setRemoteDescription(
        RTCSessionDescription(response.body, 'answer'),
      );
      check();
      await Helper.setSpeakerphoneOn(true);
      check();
    } catch (error) {
      if (current()) {
        await stop(
          message: error is BrainApiException ? error.message : 'Could not start voice. Check microphone permission and your connection.',
        );
        rethrow;
      }
    }
  }

  Future<void> stop({String message = 'Microphone off'}) async {
    ++_generation;
    _active = false;
    _ready = false;
    _deadline?.cancel();
    _disconnect?.cancel();
    final microphone = _microphone,
        peer = _peer,
        channel = _channel,
        renderer = _renderer,
        usage = _usage;
    _microphone = null;
    _peer = null;
    _channel = null;
    _renderer = null;
    _usage = null;
    // Release microphone before any network bookkeeping, even during failures.
    if (microphone != null) {
      for (final track in microphone.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await microphone.dispose();
      } catch (_) {}
    }
    try {
      await channel?.close();
    } catch (_) {}
    try {
      await peer?.close();
      await peer?.dispose();
    } catch (_) {}
    try {
      if (renderer != null) {
        renderer.srcObject = null;
        await renderer.dispose();
      }
    } catch (_) {}
    _state('complete', message);
    await usage?.end();
  }
}
