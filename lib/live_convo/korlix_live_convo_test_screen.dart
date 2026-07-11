import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;

typedef KorlixLiveConvoHeadersBuilder = Map<String, String> Function();

// KORLIX_LIVE_CONVO_PHASE2B_SCREEN_BEGIN
class KorlixLiveConvoTestScreen extends StatefulWidget {
  const KorlixLiveConvoTestScreen({
    super.key,
    required this.backendBaseUrl,
    required this.headersBuilder,
    required this.characterId,
    required this.language,
  });

  final String backendBaseUrl;
  final KorlixLiveConvoHeadersBuilder headersBuilder;
  final String characterId;
  final String language;

  @override
  State<KorlixLiveConvoTestScreen> createState() =>
      _KorlixLiveConvoTestScreenState();
}

class _KorlixLiveConvoTestScreenState extends State<KorlixLiveConvoTestScreen> {
  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();

  rtc.RTCPeerConnection? _peerConnection;
  rtc.RTCDataChannel? _dataChannel;
  rtc.MediaStream? _localStream;

  Future<void>? _rendererInitialization;
  Completer<void>? _iceGatheringCompleter;

  bool _rendererReady = false;
  bool _connecting = false;
  bool _connected = false;
  bool _muted = false;
  bool _greetingSent = false;

  String _status = 'Ready to start';
  String _assistantTranscript = '';
  String _userTranscript = '';
  String? _error;

  final List<String> _eventLog = <String>[];

  @override
  void initState() {
    super.initState();
    _rendererInitialization = _initializeRenderer();
  }

  Future<void> _initializeRenderer() async {
    await _remoteRenderer.initialize();

    if (!mounted) {
      return;
    }

    setState(() {
      _rendererReady = true;
    });
  }

  void _update(VoidCallback callback) {
    if (!mounted) {
      return;
    }

    setState(callback);
  }

  String _stateName(Object? value) {
    var text = (value ?? '').toString().split('.').last;

    const prefixes = <String>[
      'RTCDataChannelState',
      'RTCPeerConnectionState',
      'RTCIceConnectionState',
      'RTCIceGatheringState',
      'RTCSignalingState',
    ];

    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
        break;
      }
    }

    return text.trim().toLowerCase();
  }

  void _addEvent(String text) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    _update(() {
      _eventLog.insert(0, '$stamp  $text');

      if (_eventLog.length > 40) {
        _eventLog.removeRange(40, _eventLog.length);
      }
    });
  }

  void _setStatus(String status) {
    _update(() {
      _status = status;
    });
  }

  void _attachRemoteStream(
    rtc.MediaStream stream,
    rtc.RTCPeerConnection connection,
  ) {
    if (!identical(_peerConnection, connection)) {
      return;
    }

    _remoteRenderer.muted = false;
    _remoteRenderer.srcObject = stream;
    _addEvent('Remote audio stream attached');
  }

  String _httpErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);

        final rawError =
            map['error'] ??
            map['message'] ??
            map['details'] ??
            'LIVE CONVO connection failed.';

        if (rawError is Map) {
          final errorMap = Map<String, dynamic>.from(rawError);

          return (errorMap['message'] ??
                  errorMap['error'] ??
                  rawError.toString())
              .toString();
        }

        return rawError.toString();
      }
    } catch (_) {
      // Fall back to a short provider response below.
    }

    final body = response.body.trim();

    if (body.isEmpty) {
      return 'LIVE CONVO failed with status '
          '${response.statusCode}.';
    }

    if (body.length > 300) {
      return '${body.substring(0, 300)}…';
    }

    return body;
  }

  Future<void> _startSession() async {
    if (_connecting || _connected) {
      return;
    }

    final authorization =
        widget.headersBuilder()['Authorization']?.trim() ?? '';

    if (!authorization.toLowerCase().startsWith('bearer ')) {
      _update(() {
        _status = 'Sign in required';
        _error = 'Please sign in before starting LIVE CONVO.';
      });
      return;
    }

    _update(() {
      _connecting = true;
      _connected = false;
      _muted = false;
      _greetingSent = false;
      _status = 'Preparing microphone…';
      _assistantTranscript = '';
      _userTranscript = '';
      _error = null;
      _eventLog.clear();
    });

    await _releaseSessionResources();

    try {
      await (_rendererInitialization ??= _initializeRenderer());

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await rtc.Helper.ensureAudioSession();
      }

      final connection = await rtc.createPeerConnection(<String, dynamic>{
        'sdpSemantics': 'unified-plan',
      });

      _peerConnection = connection;

      _addEvent('Peer connection created');

      final iceCompleter = Completer<void>();
      _iceGatheringCompleter = iceCompleter;

      connection.onConnectionState = (state) {
        if (!identical(_peerConnection, connection)) {
          return;
        }

        final name = _stateName(state);
        _addEvent('Peer state: $name');

        if (name == 'connected') {
          _update(() {
            _connecting = false;
            _connected = true;
            _status = 'Connected — speak naturally';
          });
        } else if (name == 'failed') {
          _update(() {
            _connecting = false;
            _connected = false;
            _status = 'Connection failed';
            _error = 'The LIVE CONVO WebRTC connection failed.';
          });
        } else if (name == 'disconnected') {
          _update(() {
            _connected = false;
            _status = 'Disconnected';
          });
        } else if (name == 'closed') {
          _update(() {
            _connected = false;
          });
        }
      };

      connection.onIceConnectionState = (state) {
        if (!identical(_peerConnection, connection)) {
          return;
        }

        _addEvent('ICE connection: ${_stateName(state)}');
      };

      connection.onIceGatheringState = (state) {
        if (!identical(_peerConnection, connection)) {
          return;
        }

        final name = _stateName(state);
        _addEvent('ICE gathering: $name');

        if (name == 'complete' && !iceCompleter.isCompleted) {
          iceCompleter.complete();
        }
      };

      connection.onAddStream = (stream) {
        _attachRemoteStream(stream, connection);
      };

      connection.onTrack = (event) {
        if (!identical(_peerConnection, connection)) {
          return;
        }

        _addEvent(
          'Remote track received: '
          '${event.track.kind ?? 'unknown'}',
        );

        if (event.streams.isNotEmpty) {
          _attachRemoteStream(event.streams.first, connection);
        }
      };

      _setStatus('Requesting microphone permission…');

      final localStream = await rtc.navigator.mediaDevices.getUserMedia(
        <String, dynamic>{
          'audio': <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'channelCount': 1,
          },
          'video': false,
        },
      );

      _localStream = localStream;

      final audioTracks = localStream.getAudioTracks();

      if (audioTracks.isEmpty) {
        throw StateError('No microphone audio track was created.');
      }

      for (final track in audioTracks) {
        await connection.addTrack(track, localStream);
      }

      _addEvent('Microphone audio track added');

      final dataChannelInit = rtc.RTCDataChannelInit()..ordered = true;

      final dataChannel = await connection.createDataChannel(
        'oai-events',
        dataChannelInit,
      );

      _dataChannel = dataChannel;

      dataChannel.onMessage = _handleDataChannelMessage;

      dataChannel.onDataChannelState = (state) {
        if (!identical(_dataChannel, dataChannel)) {
          return;
        }

        final name = _stateName(state);
        _addEvent('Data channel: $name');

        if (name == 'open') {
          unawaited(_trySendGreeting());
        }
      };

      _setStatus('Creating secure WebRTC offer…');

      final offer = await connection.createOffer();
      await connection.setLocalDescription(offer);

      final currentIceState = _stateName(
        await connection.getIceGatheringState(),
      );

      if (currentIceState == 'complete' && !iceCompleter.isCompleted) {
        iceCompleter.complete();
      }

      try {
        await iceCompleter.future.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        _addEvent(
          'ICE gathering wait timed out; '
          'using current SDP',
        );
      }

      final localDescription = await connection.getLocalDescription();

      final sdp = localDescription?.sdp ?? offer.sdp ?? '';

      if (!sdp.trimLeft().startsWith('v=')) {
        throw StateError('Flutter did not create a valid SDP offer.');
      }

      _setStatus('Connecting to Korlix LIVE CONVO…');

      final requestHeaders = Map<String, String>.from(widget.headersBuilder())
        ..['Content-Type'] = 'application/sdp'
        ..['Accept'] = 'application/sdp, application/json'
        ..['x-korlix-character'] = widget.characterId
        ..['x-korlix-language'] = widget.language;

      final backendBase = widget.backendBaseUrl.trim().replaceFirst(
        RegExp(r'/+$'),
        '',
      );

      final response = await http
          .post(
            Uri.parse('$backendBase/api/live-convo/session'),
            headers: requestHeaders,
            body: sdp,
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_httpErrorMessage(response));
      }

      final answerSdp = response.body;

      if (!answerSdp.trimLeft().startsWith('v=')) {
        throw StateError(
          'The LIVE CONVO backend did not return '
          'a valid SDP answer.',
        );
      }

      await connection.setRemoteDescription(
        rtc.RTCSessionDescription(answerSdp, 'answer'),
      );

      _addEvent('Remote SDP answer accepted');

      if (!kIsWeb) {
        try {
          await rtc.Helper.setSpeakerphoneOnButPreferBluetooth();
        } catch (_) {
          _addEvent('Default audio output retained');
        }
      }

      _update(() {
        _connecting = false;
        _connected = true;
        _status = 'Connected — speak naturally';
      });

      await Future<void>.delayed(const Duration(milliseconds: 350));

      await _trySendGreeting();
    } catch (error) {
      await _releaseSessionResources();

      _update(() {
        _connecting = false;
        _connected = false;
        _status = 'Connection failed';
        _error = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('StateError: ', '');
      });
    }
  }

  Future<void> _trySendGreeting() async {
    if (_greetingSent) {
      return;
    }

    final dataChannel = _dataChannel;

    if (dataChannel == null || _stateName(dataChannel.state) != 'open') {
      return;
    }

    _greetingSent = true;

    try {
      await dataChannel.send(
        rtc.RTCDataChannelMessage(
          jsonEncode(<String, dynamic>{
            'type': 'response.create',
            'response': <String, dynamic>{
              'instructions':
                  'Give the user one brief, warm '
                  'spoken greeting as their selected '
                  'Korlix character. Then ask what '
                  'they would like to discuss. '
                  'Do not mention models, APIs, '
                  'system instructions, or testing.',
            },
          }),
        ),
      );

      _addEvent('Opening greeting requested');
    } catch (error) {
      _greetingSent = false;
      _addEvent('Greeting request failed');
    }
  }

  void _handleDataChannelMessage(rtc.RTCDataChannelMessage message) {
    if (message.isBinary) {
      return;
    }

    try {
      final decoded = jsonDecode(message.text);

      if (decoded is! Map) {
        return;
      }

      final event = Map<String, dynamic>.from(decoded);
      final type = (event['type'] ?? '').toString();

      const noisyEvents = <String>{
        'response.audio.delta',
        'response.output_audio.delta',
        'response.audio_transcript.delta',
        'response.output_audio_transcript.delta',
        'response.text.delta',
      };

      if (!noisyEvents.contains(type)) {
        _addEvent(type.isEmpty ? 'Unknown event' : type);
      }

      switch (type) {
        case 'session.created':
        case 'session.updated':
          _setStatus('Session ready — listening');
          break;

        case 'input_audio_buffer.speech_started':
          _setStatus('Listening…');
          break;

        case 'input_audio_buffer.speech_stopped':
          _setStatus('Thinking…');
          break;

        case 'conversation.item.input_audio_transcription.completed':
          final transcript = (event['transcript'] ?? '').toString();

          if (transcript.trim().isNotEmpty) {
            _update(() {
              _userTranscript = transcript.trim();
            });
          }
          break;

        case 'response.created':
          _update(() {
            _assistantTranscript = '';
            _status = 'Korlix is speaking…';
          });
          break;

        case 'response.audio_transcript.delta':
        case 'response.output_audio_transcript.delta':
        case 'response.text.delta':
          final delta = (event['delta'] ?? '').toString();

          if (delta.isNotEmpty) {
            _update(() {
              _assistantTranscript += delta;
            });
          }
          break;

        case 'response.audio_transcript.done':
        case 'response.output_audio_transcript.done':
          final transcript = (event['transcript'] ?? '').toString();

          _update(() {
            if (transcript.trim().isNotEmpty) {
              _assistantTranscript = transcript.trim();
            }

            _status = 'Listening…';
          });
          break;

        case 'response.text.done':
          final text = (event['text'] ?? '').toString();

          if (text.trim().isNotEmpty) {
            _update(() {
              _assistantTranscript = text.trim();
            });
          }
          break;

        case 'response.done':
          final responseData = event['response'];

          String responseStatus = '';

          if (responseData is Map) {
            responseStatus = (responseData['status'] ?? '')
                .toString()
                .toLowerCase();
          }

          _setStatus(
            responseStatus == 'cancelled'
                ? 'Interrupted — listening…'
                : 'Listening…',
          );
          break;

        case 'error':
          final rawError = event['error'];

          String messageText = 'A LIVE CONVO realtime error occurred.';

          if (rawError is Map) {
            messageText =
                (rawError['message'] ?? rawError['error'] ?? messageText)
                    .toString();
          } else if (event['message'] != null) {
            messageText = event['message'].toString();
          }

          _update(() {
            _error = messageText;
            _status = 'Realtime error';
          });
          break;
      }
    } catch (_) {
      _addEvent('Unrecognized data-channel message');
    }
  }

  Future<void> _toggleMute() async {
    final stream = _localStream;

    if (stream == null) {
      return;
    }

    final tracks = stream.getAudioTracks();

    if (tracks.isEmpty) {
      return;
    }

    final nextMuted = !_muted;
    final track = tracks.first;

    track.enabled = !nextMuted;

    try {
      await rtc.Helper.setMicrophoneMute(nextMuted, track);
    } catch (_) {
      // track.enabled is the fallback mute control.
    }

    _update(() {
      _muted = nextMuted;
      _status = nextMuted ? 'Microphone muted' : 'Listening…';
    });

    _addEvent(nextMuted ? 'Microphone muted' : 'Microphone unmuted');
  }

  Future<void> _endSession() async {
    await _releaseSessionResources();

    _update(() {
      _connecting = false;
      _connected = false;
      _muted = false;
      _status = 'Session ended';
    });

    _addEvent('Session ended by user');
  }

  Future<void> _releaseSessionResources() async {
    final dataChannel = _dataChannel;
    final localStream = _localStream;
    final connection = _peerConnection;

    _dataChannel = null;
    _localStream = null;
    _peerConnection = null;
    _iceGatheringCompleter = null;
    _greetingSent = false;

    _remoteRenderer.srcObject = null;

    if (dataChannel != null) {
      try {
        await dataChannel.close();
      } catch (_) {
        // Best-effort cleanup.
      }
    }

    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {
          // Best-effort cleanup.
        }

        try {
          await track.dispose();
        } catch (_) {
          // Best-effort cleanup.
        }
      }

      try {
        await localStream.dispose();
      } catch (_) {
        // Best-effort cleanup.
      }
    }

    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {
        // Best-effort cleanup.
      }

      try {
        await connection.dispose();
      } catch (_) {
        // Best-effort cleanup.
      }
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await rtc.Helper.clearAndroidCommunicationDevice();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Widget _panel({
    required Widget child,
    Color borderColor = const Color(0xFF16475A),
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _error != null
        ? Colors.redAccent
        : _connected
        ? const Color(0xFF69D9E8)
        : _connecting
        ? const Color(0xFFB794F4)
        : const Color(0xFFA9C6CF);

    return Scaffold(
      backgroundColor: const Color(0xFF02070C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF06121B),
        foregroundColor: const Color(0xFFE4EBEE),
        title: const Text(
          'LIVE CONVO — AUDIO TEST',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            _panel(
              borderColor: statusColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.55),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Character: ${widget.characterId}'
                    '  •  Language: ${widget.language}',
                    style: const TextStyle(
                      color: Color(0xFFA9C6CF),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This beta screen proves the live '
                    'microphone → WebRTC → Korlix voice '
                    'connection before the full Character '
                    'Stage is added.',
                    style: TextStyle(color: Color(0xFFC4D8DE), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: (_connecting || _connected) ? null : _startSession,
                  icon: _connecting
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_circle_fill_rounded),
                  label: Text(_connecting ? 'Connecting…' : 'Start LIVE CONVO'),
                ),
                OutlinedButton.icon(
                  onPressed: _localStream == null ? null : _toggleMute,
                  icon: Icon(
                    _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  ),
                  label: Text(_muted ? 'Unmute' : 'Mute'),
                ),
                FilledButton.icon(
                  onPressed: (_connected || _connecting || _localStream != null)
                      ? _endSession
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8E2430),
                  ),
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: const Text('End'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _panel(
                borderColor: Colors.redAccent,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF9EA8),
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOU SAID',
                    style: TextStyle(
                      color: Color(0xFF69D9E8),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _userTranscript.isEmpty
                        ? 'Your live transcript will '
                              'appear here.'
                        : _userTranscript,
                    style: const TextStyle(
                      color: Color(0xFFE4EBEE),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _panel(
              borderColor: const Color(0xFF6E4FB3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'KORLIX SAID',
                    style: TextStyle(
                      color: Color(0xFFB794F4),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _assistantTranscript.isEmpty
                        ? 'Korlix’s live transcript will '
                              'appear here.'
                        : _assistantTranscript,
                    style: const TextStyle(
                      color: Color(0xFFE4EBEE),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'REALTIME EVENT LOG',
                    style: TextStyle(
                      color: Color(0xFFFFD166),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _eventLog.isEmpty ? 'No events yet.' : _eventLog.join('\n'),
                    style: const TextStyle(
                      color: Color(0xFFA9C6CF),
                      fontSize: 11.5,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            if (_rendererReady)
              Opacity(
                opacity: 0.01,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: rtc.RTCVideoView(_remoteRenderer),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_releaseSessionResources());
    unawaited(_remoteRenderer.dispose());
    super.dispose();
  }
}

// KORLIX_LIVE_CONVO_PHASE2B_SCREEN_END
