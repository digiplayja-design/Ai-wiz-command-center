import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pod_client.dart';
import 'pod_media.dart';

const _navy = Color(0xFF071B27);
const _panel = Color(0xFF102B3A);
const _cyan = Color(0xFF6CE5E8);
const _gold = Color(0xFFFFD18D);
const _violet = Color(0xFFC3A7FF);
const _muted = Color(0xFFA7BFCB);
const _usage =
    'Personal beta · uses your LIVE CONVO session and time allowance. AI usage limits also apply.';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().map(_map).toList() : [];
String _s(dynamic v) => v?.toString() ?? '';
bool _terminal(Map<String, dynamic>? e) =>
    e != null && ['ended', 'failed'].contains(e['state']);
String _speaker(String value) => switch (value) {
  'host' => 'K-Nova',
  'analyst' => 'Analyst',
  'challenger' => 'Challenger',
  'user' => 'You',
  _ => value,
};
Color _speakerColor(String value) => switch (value) {
  'analyst' => _gold,
  'challenger' => _violet,
  _ => _cyan,
};

class PodScreen extends StatefulWidget {
  const PodScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.media,
    this.disposeClient = true,
    this.openLink,
    this.now,
  });
  final PodClient client;
  final Future<bool> Function() ensureConsent;
  final PodMedia? media;
  final bool disposeClient;
  final Future<bool> Function(Uri)? openLink;
  final DateTime Function()? now;
  @override
  State<PodScreen> createState() => _PodScreenState();
}

class _PodScreenState extends State<PodScreen> with WidgetsBindingObserver {
  late final PodMedia _media;
  final _topic = TextEditingController();
  final _contribution = TextEditingController();
  final _scroll = ScrollController();
  final _studioAnchor = GlobalKey(debugLabel: 'pod-studio-anchor');
  final _errorAnchor = GlobalKey(debugLabel: 'pod-error-anchor');
  List<Map<String, dynamic>> _history = [], _catalog = [];
  Map<String, dynamic> _access = {}, _episode = {};
  bool _loading = true, _busy = false, _listening = false, _locked = false;
  bool _foreground = true;
  bool _creating = false;
  bool _recording = false,
      _transcribing = false,
      _composing = false,
      _heartbeatBusy = false;
  bool _startingRecording = false;
  String _category = 'technology', _style = 'balanced';
  int _duration = 300, _hosts = 2, _epoch = 0;
  String? _error, _notice, _speaking, _createRequestId;
  String? _contributionRequestId, _submittedText;
  DateTime? _deadlineLocal, _serverDeadline, _preparingSince;
  Uint8List? _pendingWav;
  String? _pendingSpeaker;
  Timer? _clockTimer, _deadlineTimer, _heartbeatTimer, _recordingTimer;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  bool get _hasEpisode => _episode['id'] is String;
  bool get _live => _hasEpisode && !_terminal(_episode);
  bool get _allowed => _access['allowed'] == true && !_locked;
  int? get _remaining => _deadlineLocal == null
      ? null
      : math.max(
          0,
          (_deadlineLocal!.difference(_now).inMilliseconds / 1000).ceil(),
        );
  List<int> get _durations {
    final raw = _access['durations'];
    final max = (_access['maxSeconds'] as num?)?.toInt() ?? 900;
    return [
      300,
      600,
      900,
    ].where((s) => s <= max && (raw is! List || raw.contains(s))).toList();
  }

  bool _current(int epoch) => mounted && !_locked && epoch == _epoch;
  void _reveal(GlobalKey anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _locked) return;
      final target = anchor.currentContext;
      if (target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 240),
          alignment: .02,
        ),
      );
    });
  }

  bool _alive() {
    if (!mounted || _locked) return false;
    try {
      widget.client.checkAccess();
    } catch (_) {
      _lock();
      return false;
    }
    return mounted && !_locked;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _media = widget.media ?? createPodMedia();
    _media.addListener(_mediaChanged);
    widget.client.onAccessDenied = _lock;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _live && _deadlineLocal != null) {
        if (_remaining == 0) {
          unawaited(_end(deadline: true));
        } else {
          setState(() {});
        }
      } else if (mounted && _listening && _busy) {
        setState(() {});
      }
    });
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_heartbeat()),
    );
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A native microphone permission dialog temporarily makes the app inactive.
    // Real background transitions still arrive as hidden/paused/detached.
    if (state == AppLifecycleState.inactive && _startingRecording) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      if (_live) {
        unawaited(
          _pause(
            message:
                'Paused while the app is in the background. The episode clock keeps running.',
          ),
        );
      } else {
        // Consent and creation may still be pending before an episode exists.
        // Returning to the app never starts those abandoned gestures again.
        _epoch++;
        if (mounted) {
          setState(() {
            _busy = false;
            _listening = false;
          });
        }
        unawaited(_media.stop());
        unawaited(_media.cancelRecording());
      }
    }
  }

  void _mediaChanged() {
    if (!mounted || _locked) return;
    setState(() {});
    if (_recording && !_media.recording && _media.recordingAvailable) {
      scheduleMicrotask(() => unawaited(_finishRecording()));
    }
  }

  void _lock() {
    if (!mounted || _locked) return;
    _epoch++;
    _pendingWav = null;
    _deadlineTimer?.cancel();
    _recordingTimer?.cancel();
    unawaited(_media.stop());
    unawaited(_media.cancelRecording());
    setState(() {
      _locked = true;
      _listening = false;
      _busy = false;
      _recording = false;
      _transcribing = false;
      _startingRecording = false;
      _episode = {};
      _history = [];
      _error = null;
      _notice = null;
      _speaking = null;
      _topic.clear();
      _contribution.clear();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _epoch++;
    _clockTimer?.cancel();
    _heartbeatTimer?.cancel();
    _deadlineTimer?.cancel();
    _recordingTimer?.cancel();
    widget.client.onAccessDenied = null;
    _media.removeListener(_mediaChanged);
    _media.dispose();
    // Give the authenticated end request a chance to complete before closing its
    // transport. Server deadline/heartbeat leases also bound a lost connection.
    final id = _live ? _s(_episode['id']) : null;
    final client = widget.client;
    final disposeClient = widget.disposeClient;
    unawaited(() async {
      if (id != null) {
        try {
          await client.control(id, 'end');
        } catch (_) {}
      }
      if (disposeClient) client.dispose();
    }());
    _topic.dispose();
    _contribution.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_alive()) return;
    final epoch = _epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.client.load();
      if (!_current(epoch)) return;
      final raw = result['catalog'];
      final categories = raw is Map ? raw['categories'] : raw;
      setState(() {
        _access = _map(result['access']);
        _catalog = _maps(categories);
        _history = _maps(result['episodes']);
        if (_durations.isNotEmpty && !_durations.contains(_duration)) {
          _duration = _durations.first;
        }
      });
      if (!_hasEpisode) {
        final active = _history.where((e) => !_terminal(e)).firstOrNull;
        if (active != null) {
          _acceptEpisode(active);
          await _pause(
            message:
                'Your unfinished episode is paused. Resume when you are ready.',
          );
        }
      }
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted && !_locked) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _acceptEpisode(Map<String, dynamic> next) {
    if (!mounted || _locked) return;
    final same = next['id'] == _episode['id'];
    if (same &&
        (next['version'] as num? ?? 0) < (_episode['version'] as num? ?? 0)) {
      return;
    }
    if (same &&
        next['version'] == _episode['version'] &&
        _maps(next['turns']).length < _maps(_episode['turns']).length) {
      return;
    }
    final unexpectedPause =
        same &&
        next['state'] == 'paused' &&
        _episode['state'] != 'paused' &&
        (_listening || _recording || _transcribing || _startingRecording);
    final stopped = _terminal(next) || unexpectedPause;
    if (stopped) {
      _epoch++;
      _recordingTimer?.cancel();
      unawaited(_media.stop());
      unawaited(_media.cancelRecording());
    }
    if (!same) {
      _deadlineLocal = null;
      _serverDeadline = null;
      _pendingWav = null;
    }
    final deadline = DateTime.tryParse(_s(next['deadlineAt']));
    final serverNow = DateTime.tryParse(_s(next['serverNow']));
    if (deadline != null) {
      final elapsed = Duration(
        milliseconds: (next['_responseElapsedMs'] as num?)?.toInt() ?? 0,
      );
      if (_deadlineLocal == null) {
        // Establish a conservative local anchor once. serverNow is sampled at
        // response completion, so deducting a later generation's full request
        // time again would count its research time twice and end audio early.
        _deadlineLocal = _now.add(
          deadline.difference(serverNow ?? _now) - elapsed,
        );
        _serverDeadline = deadline;
      } else if (_serverDeadline != null &&
          deadline.isBefore(_serverDeadline!)) {
        // The server may shorten a deadline, but no response may extend it.
        _deadlineLocal = _deadlineLocal!.subtract(
          _serverDeadline!.difference(deadline),
        );
        _serverDeadline = deadline;
      }
    }
    setState(() {
      _episode = next;
      _history = [next, ..._history.where((e) => e['id'] != next['id'])];
      if (stopped) {
        _listening = false;
        _busy = false;
        _speaking = null;
        _recording = false;
        _transcribing = false;
        _startingRecording = false;
        if (_terminal(next)) _pendingWav = null;
        if (_terminal(next) && _s(next['error']).isNotEmpty) {
          _error = _s(next['error']);
        }
        if (unexpectedPause) {
          _notice =
              'The server paused this episode. Check your connection and choose Resume when you are ready.';
        }
      }
    });
    if (_terminal(next) && _s(next['error']).isNotEmpty) _reveal(_errorAnchor);
    _deadlineTimer?.cancel();
    if (_live && _deadlineLocal != null) {
      final remaining = _deadlineLocal!.difference(_now);
      _deadlineTimer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => unawaited(_end(deadline: true)),
      );
    }
  }

  Future<void> _heartbeat() async {
    if (!_alive() || !_live || _heartbeatBusy) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final epoch = _epoch;
    _heartbeatBusy = true;
    try {
      final result = await widget.client.control(
        _s(_episode['id']),
        'heartbeat',
      );
      if (_current(epoch)) _acceptEpisode(result);
    } catch (e) {
      if (_current(epoch)) {
        await _pause(
          message:
              'Connection interrupted. Check episode status before resuming.',
          error: e.toString(),
        );
      }
    } finally {
      _heartbeatBusy = false;
    }
  }

  Future<void> _listen() async {
    if (!_alive() ||
        !_foreground ||
        !_allowed ||
        _busy ||
        _creating ||
        _live ||
        _durations.isEmpty) {
      return;
    }
    // Preserve the browser's user gesture: activate is the first asynchronous call.
    final activation = _media.activate();
    FocusScope.of(context).unfocus();
    final epoch = ++_epoch;
    var beganCreation = false;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await activation;
      if (_media.error != null || _media.blocked) {
        throw PodException(
          _media.error ?? 'Sound is blocked. Tap Listen to enable it.',
        );
      }
      if (!_current(epoch) ||
          !await widget.ensureConsent() ||
          !_current(epoch)) {
        return;
      }
      final topic = _topic.text.trim();
      if (topic.isEmpty) {
        throw const PodException(
          'Choose a suggested question or enter a topic to listen.',
        );
      }
      _createRequestId ??= podRequestId();
      beganCreation = true;
      _creating = true;
      final result = await widget.client.create(
        requestId: _createRequestId!,
        category: _category,
        topic: topic,
        durationSeconds: _duration,
        hostCount: _hosts,
        style: _style,
      );
      _createRequestId = null;
      if (!_current(epoch) || !_foreground) {
        try {
          await widget.client.control(_s(result['id']), 'end');
        } catch (_) {}
        return;
      }
      _acceptEpisode(result);
      if (!_current(epoch) || !_live) return;
      setState(() {
        _listening = true;
        _busy = false;
        _composing = false;
      });
      unawaited(_next(epoch));
      _reveal(_studioAnchor);
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = e.toString();
          _listening = false;
        });
        _reveal(_errorAnchor);
      }
    } finally {
      if (beganCreation) {
        _creating = false;
        if (mounted) setState(() {});
      }
      if (_current(epoch) && !_listening) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _next(int epoch) async {
    if (!_current(epoch) ||
        !_foreground ||
        !_listening ||
        !_live ||
        _remaining == 0) {
      return;
    }
    setState(() {
      _busy = true;
      _speaking = null;
      _preparingSince = _now;
    });
    try {
      final result = await widget.client.next(
        _s(_episode['id']),
        requestId: podRequestId(),
        version: (_episode['version'] as num).toInt(),
      );
      if (!_current(epoch) || !_foreground || !_listening) return;
      _acceptEpisode(_map(result['episode']));
      if (!_current(epoch) || !_listening || !_live || _remaining == 0) return;
      final audio = _map(result['audio']);
      final turn = _map(result['turn']);
      if (result['audioUnavailable'] == true || audio['base64'] is! String) {
        await _pause(
          message:
              'This turn is available in the transcript. Audio is unavailable; choose Resume to continue with the next turn.',
        );
        return;
      }
      if (audio['mime'] != 'audio/wav') {
        throw const PodException(
          'This audio format is unavailable. Your transcript is saved.',
        );
      }
      _pendingWav = base64Decode(audio['base64'] as String);
      _pendingSpeaker = _s(turn['speaker']);
      await _playPending(epoch);
    } catch (e) {
      if (_current(epoch)) {
        await _pause(
          error: e.toString(),
          message: 'Playback paused. Nothing is retried automatically.',
        );
      }
    }
  }

  Future<void> _playPending(int epoch) async {
    final wav = _pendingWav;
    if (wav == null ||
        !_current(epoch) ||
        !_foreground ||
        !_listening ||
        !_live ||
        _remaining == 0) {
      return;
    }
    setState(() {
      _busy = false;
      _speaking = _pendingSpeaker;
    });
    await _media.play(wav);
    if (!_current(epoch) ||
        !_foreground ||
        !_listening ||
        !_live ||
        _remaining == 0) {
      return;
    }
    _pendingWav = null;
    _pendingSpeaker = null;
    // Exactly one next request, only after the preceding clip really ended.
    unawaited(_next(epoch));
  }

  Future<void> _pause({
    String? message,
    String? error,
    String action = 'pause',
  }) async {
    if (!_alive() || !_live) return;
    final id = _s(_episode['id']);
    final epoch = ++_epoch;
    if (action == 'interrupt') {
      _pendingWav = null;
      _pendingSpeaker = null;
    }
    _recordingTimer?.cancel();
    setState(() {
      _listening = false;
      _busy = true;
      _recording = false;
      _transcribing = false;
      _startingRecording = false;
      _speaking = null;
      if (message != null) _notice = message;
      if (error != null) _error = error;
    });
    if (error != null) _reveal(_errorAnchor);
    // Revoke both local operations immediately. A system permission prompt may
    // keep capture cleanup pending; it must not delay the server control call.
    unawaited(_media.stop());
    unawaited(_media.cancelRecording());
    if (!_current(epoch)) return;
    try {
      final result = await widget.client.control(id, action);
      if (_current(epoch)) _acceptEpisode(result);
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = error ?? e.toString();
        });
        _reveal(_errorAnchor);
      }
    } finally {
      if (_current(epoch) && !_listening) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _resume() async {
    if (!_alive() ||
        !_foreground ||
        !_live ||
        _busy ||
        _recording ||
        _transcribing ||
        _remaining == 0) {
      return;
    }
    final activation = _media.activate();
    FocusScope.of(context).unfocus();
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await activation;
      if (_media.error != null || _media.blocked) {
        throw PodException(
          _media.error ?? 'Sound is blocked. Tap Resume to enable it.',
        );
      }
      if (!_current(epoch) ||
          !await widget.ensureConsent() ||
          !_current(epoch)) {
        return;
      }
      final checked = await widget.client.episode(_s(_episode['id']));
      if (!_current(epoch)) return;
      _acceptEpisode(checked);
      if (!_live || _remaining == 0) return;
      final result = await widget.client.control(_s(_episode['id']), 'resume');
      if (!_current(epoch)) return;
      _acceptEpisode(result);
      if (!_live || _remaining == 0) return;
      setState(() {
        _listening = true;
        _busy = false;
        _composing = false;
      });
      _reveal(_studioAnchor);
      if (_pendingWav != null) {
        try {
          await _playPending(epoch);
        } catch (e) {
          if (_current(epoch)) {
            await _pause(
              error: e.toString(),
              message:
                  'Sound is paused. Resume replays this saved turn without generating it again.',
            );
          }
        }
      } else {
        unawaited(_next(epoch));
      }
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = e.toString();
        });
        _reveal(_errorAnchor);
      }
    } finally {
      if (_current(epoch) && !_listening) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _end({bool deadline = false}) async {
    if (!_alive() || !_live) return;
    final id = _s(_episode['id']);
    final epoch = ++_epoch;
    _pendingWav = null;
    _pendingSpeaker = null;
    _deadlineTimer?.cancel();
    _recordingTimer?.cancel();
    setState(() {
      _listening = false;
      _busy = false;
      _recording = false;
      _transcribing = false;
      _startingRecording = false;
      _speaking = null;
      _episode = {
        ..._episode,
        'state': 'ended',
        'endReason': deadline ? 'deadline' : 'listener',
      };
      _history = [_episode, ..._history.where((e) => e['id'] != id)];
      _notice = deadline
          ? 'Your episode time is complete. Audio and recording have stopped.'
          : 'Episode ended. Your private transcript is saved.';
    });
    unawaited(_media.stop());
    unawaited(_media.cancelRecording());
    try {
      final result = await widget.client.control(id, 'end');
      if (_current(epoch)) _acceptEpisode(result);
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error =
              'Playback has stopped. The server could not confirm the end; its deadline still applies. ${e.toString()}';
        });
      }
    }
  }

  Future<void> _chime({required bool voice}) async {
    if (!_alive() ||
        !_foreground ||
        !_live ||
        _recording ||
        _transcribing ||
        (_busy && !_listening) ||
        _remaining == 0) {
      return;
    }
    final interruptEpoch = _epoch + 1;
    await _pause(
      action: 'interrupt',
      message: voice
          ? 'Your turn. Record up to 30 seconds, then review before sending.'
          : 'Your turn. Write a thought or question, then send it to the hosts.',
    );
    if (!_current(interruptEpoch) ||
        !_foreground ||
        !_live ||
        _remaining == 0 ||
        _episode['state'] != 'paused') {
      return;
    }
    setState(() {
      _composing = true;
    });
    if (!voice) return;
    final epoch = _epoch;
    setState(() {
      _startingRecording = true;
      _busy = true;
    });
    try {
      // The only microphone-opening call in this screen follows Chime in.
      await _media.startRecording();
      if (!_current(epoch) || !_live || _remaining == 0) {
        await _media.cancelRecording();
        return;
      }
      setState(() {
        _recording = true;
        _startingRecording = false;
        _busy = false;
      });
      _recordingTimer = Timer(
        const Duration(seconds: 30),
        () => unawaited(_finishRecording()),
      );
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = '${e.toString()} You can type your contribution below.';
        });
      }
    } finally {
      if (_current(epoch)) {
        setState(() {
          _startingRecording = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _finishRecording() async {
    if (!_alive() || !_recording || !_live) return;
    final epoch = _epoch;
    _recordingTimer?.cancel();
    setState(() {
      _recording = false;
      _transcribing = true;
      _error = null;
    });
    try {
      final wav = await _media.stopRecording();
      if (!_current(epoch) || !_live || _remaining == 0) return;
      final text = await widget.client.transcribe(
        _s(_episode['id']),
        wav,
        requestId: podRequestId(),
      );
      if (!_current(epoch) || !_live || _remaining == 0) return;
      setState(() {
        _contribution.text = text;
        _notice =
            'Review or edit your words. Nothing is sent to the hosts until you choose Send.';
      });
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = '${e.toString()} You can type your contribution instead.';
        });
      }
    } finally {
      if (_current(epoch)) {
        setState(() {
          _transcribing = false;
        });
      }
    }
  }

  Future<void> _sendContribution() async {
    if (!_alive() ||
        !_live ||
        _busy ||
        _recording ||
        _transcribing ||
        _remaining == 0) {
      return;
    }
    final text = _contribution.text.trim();
    if (text.isEmpty) return;
    if (_submittedText != text) {
      _submittedText = text;
      _contributionRequestId = podRequestId();
    }
    _contributionRequestId ??= podRequestId();
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.contribute(
        _s(_episode['id']),
        text,
        requestId: _contributionRequestId!,
      );
      if (!_current(epoch)) return;
      _acceptEpisode(result);
      setState(() {
        _contribution.clear();
        _contributionRequestId = null;
        _submittedText = null;
        _notice =
            'Your contribution is in the conversation. Choose Resume to hear the hosts respond.';
        _composing = false;
      });
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (_current(epoch)) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _checkStatus() async {
    if (!_alive()) return;
    if (!_hasEpisode) {
      await _load();
      return;
    }
    final epoch = _epoch;
    try {
      final result = await widget.client.episode(_s(_episode['id']));
      if (_current(epoch)) {
        _acceptEpisode(result);
        setState(() {
          _error = null;
        });
      }
    } catch (e) {
      if (_current(epoch)) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _openHistory(Map<String, dynamic> episode) async {
    if (_live || _busy || !_alive()) return;
    ++_epoch;
    _acceptEpisode(episode);
    await _checkStatus();
  }

  Future<void> _delete(Map<String, dynamic> episode) async {
    if (!_terminal(episode) || !_alive()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this episode?'),
        content: const Text(
          'This removes its private transcript, recap and sources. It does not restore session or AI usage allowance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep episode'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_alive()) return;
    try {
      await widget.client.remove(_s(episode['id']));
      if (!_alive()) return;
      setState(() {
        _history.removeWhere((e) => e['id'] == episode['id']);
        if (_episode['id'] == episode['id']) {
          _episode = {};
          _deadlineLocal = null;
        }
      });
    } catch (e) {
      if (_alive()) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  List<String> get _suggestions {
    final entry = _catalog
        .where((c) => (c['id'] ?? c['category']) == _category)
        .firstOrNull;
    final topics = entry?['topics'] ?? entry?['questions'];
    if (topics is List) {
      return topics
          .map(
            (t) => t is Map
                ? _s(t['question'] ?? t['title'] ?? t['topic'])
                : _s(t),
          )
          .where((t) => t.isNotEmpty)
          .toList();
    }
    return switch (_category) {
      'trending' => ['Which current stories deserve a closer look?'],
      'politics' => ['How can we evaluate political claims fairly?'],
      'sports' => ['What makes a great team more than its star players?'],
      'religion' => ['How do different traditions approach a meaningful life?'],
      'culture' => ['How is technology changing the culture we share?'],
      'business' => ['What makes a small business resilient?'],
      _ => ['Where can AI be useful in everyday life?'],
    };
  }

  @override
  Widget build(BuildContext context) {
    final localTheme = Theme.of(context).copyWith(
      scaffoldBackgroundColor: _navy,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _cyan,
        secondary: _gold,
        surface: _panel,
        onPrimary: _navy,
      ),
      textTheme: Theme.of(
        context,
      ).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF1D4655)
              : const Color(0xFF09222F),
        ),
        labelStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: Colors.white),
        secondaryLabelStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: Colors.white),
        checkmarkColor: _cyan,
        iconTheme: const IconThemeData(color: _cyan),
        side: const BorderSide(color: Color(0xFF315462)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF09222F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF294957)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF294957)),
        ),
        hintStyle: const TextStyle(color: _muted),
      ),
    );
    return Theme(
      data: localTheme,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text(
            'THE POD AND YOU',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 2.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh episode status',
              onPressed: _locked ? null : _checkStatus,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _locked
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'Your sign-in changed. Reopen The Pod and You to continue securely.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _hero(),
                        const SizedBox(height: 24),
                        if (_loading)
                          const LinearProgressIndicator(minHeight: 2),
                        if (!_loading && !_allowed)
                          _noticeCard(
                            _s(_access['reason']).isEmpty
                                ? 'Personal beta is available with Ultra, Enterprise, or a verified developer entitlement.'
                                : _s(_access['reason']),
                            Icons.lock_outline_rounded,
                            _gold,
                          ),
                        if (!_loading && _allowed && _durations.isEmpty)
                          _noticeCard(
                            'Your current allowance does not have an available episode length. Check your LIVE CONVO session and time allowance.',
                            Icons.timer_outlined,
                            _gold,
                          ),
                        if (_error != null)
                          KeyedSubtree(
                            key: _errorAnchor,
                            child: _noticeCard(
                              _error!,
                              Icons.info_outline,
                              const Color(0xFFFFB3A5),
                              action: TextButton(
                                onPressed: _checkStatus,
                                child: const Text('Check status'),
                              ),
                            ),
                          ),
                        if (_notice != null)
                          _noticeCard(
                            _notice!,
                            Icons.chat_bubble_outline_rounded,
                            _cyan,
                          ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final setup = _setup();
                            final studio = KeyedSubtree(
                              key: _studioAnchor,
                              child: _studio(),
                            );
                            if (constraints.maxWidth < 880) {
                              return Column(
                                children: [
                                  _live || _hasEpisode ? studio : setup,
                                  const SizedBox(height: 20),
                                  _live || _hasEpisode ? setup : studio,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 5, child: setup),
                                const SizedBox(width: 22),
                                Expanded(flex: 7, child: studio),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        _historyView(),
                        const SizedBox(height: 20),
                        const Text(
                          'Private by default. Voice recordings are used for transcription and are not saved. AI hosts can make mistakes; check the sources and use your judgment.',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _hero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        colors: [Color(0xFF143847), Color(0xFF172A43), Color(0xFF202B43)],
      ),
      border: Border.all(color: const Color(0xFF375667)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.graphic_eq_rounded, color: _cyan, size: 23),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'YOUR PRIVATE AI PODCAST',
                style: TextStyle(
                  color: _cyan,
                  letterSpacing: 1.7,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'BETA',
                style: TextStyle(
                  color: _gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 21),
        const Text(
          'The Pod and You',
          style: TextStyle(
            fontSize: 34,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'A podcast that listens back.',
          style: TextStyle(
            color: _cyan,
            fontSize: 19,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Pick a question. Meet your hosts. Chime in whenever a thought strikes.',
          style: TextStyle(color: _muted, height: 1.6),
        ),
        const SizedBox(height: 19),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            _detail(
              Icons.headphones_rounded,
              'One listener. Your conversation.',
            ),
            _detail(Icons.timer_outlined, '5–15 minutes'),
            _detail(Icons.lock_outline_rounded, 'Private transcript'),
          ],
        ),
      ],
    ),
  );

  Widget _detail(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: _gold),
      const SizedBox(width: 6),
      Flexible(
        child: Text(text, style: const TextStyle(color: _muted, fontSize: 11)),
      ),
    ],
  );
  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFF254452)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _muted,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _setup() {
    final enabled = !_live && !_busy && !_creating && !_loading && _allowed;
    const categories = [
      ('trending', 'Trending', Icons.trending_up_rounded),
      ('politics', 'Politics', Icons.account_balance_outlined),
      ('sports', 'Sports', Icons.sports_basketball_outlined),
      ('religion', 'Religion', Icons.auto_awesome_outlined),
      ('culture', 'Culture', Icons.palette_outlined),
      ('business', 'Business', Icons.work_outline_rounded),
      ('technology', 'Technology', Icons.memory_rounded),
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Make it your episode',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          const Text(
            'Choose the question. We’ll bring the perspectives.',
            style: TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          _label('01  PICK YOUR TOPIC'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories
                .map(
                  (c) => ChoiceChip(
                    label: Text(c.$2),
                    avatar: Icon(c.$3, size: 16),
                    selected: _category == c.$1,
                    selectedColor: _cyan.withValues(alpha: .20),
                    onSelected: enabled
                        ? (_) => setState(() {
                            _category = c.$1;
                            _topic.clear();
                            _createRequestId = null;
                          })
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 15),
          const Text(
            'Suggested discussion questions',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          ..._suggestions
              .take(3)
              .map(
                (question) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: enabled
                        ? () => setState(() {
                            _topic.text = question;
                            _createRequestId = null;
                          })
                        : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _navy.withValues(alpha: .65),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.north_east_rounded,
                            color: _cyan,
                            size: 15,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              question,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 7),
          TextField(
            key: const Key('pod-topic'),
            controller: _topic,
            enabled: enabled,
            maxLength: 240,
            maxLines: 2,
            onChanged: (_) {
              _createRequestId = null;
            },
            decoration: const InputDecoration(
              labelText: 'Or ask your own question',
              hintText: 'What would you like to explore?',
            ),
          ),
          const SizedBox(height: 16),
          _label('02  SET THE PACE'),
          Wrap(
            spacing: 8,
            children: [300, 600, 900]
                .map(
                  (seconds) => ChoiceChip(
                    label: Text('${seconds ~/ 60} min'),
                    selected: _duration == seconds,
                    selectedColor: _cyan.withValues(alpha: .20),
                    onSelected: enabled && _durations.contains(seconds)
                        ? (_) => setState(() {
                            _duration = seconds;
                            _createRequestId = null;
                          })
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 17),
          Wrap(
            spacing: 8,
            children: [2, 3]
                .map(
                  (count) => ChoiceChip(
                    label: Text('$count AI hosts'),
                    selected: _hosts == count,
                    selectedColor: _gold.withValues(alpha: .20),
                    onSelected: enabled
                        ? (_) => setState(() {
                            _hosts = count;
                            _createRequestId = null;
                          })
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 17),
          Wrap(
            spacing: 8,
            children: ['balanced', 'relaxed', 'debate']
                .map(
                  (style) => ChoiceChip(
                    label: Text(
                      '${style[0].toUpperCase()}${style.substring(1)}',
                    ),
                    selected: _style == style,
                    selectedColor: _violet.withValues(alpha: .20),
                    onSelected: enabled
                        ? (_) => setState(() {
                            _style = style;
                            _createRequestId = null;
                          })
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              key: const Key('pod-listen'),
              onPressed: enabled && _durations.isNotEmpty ? _listen : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                _busy && !_live
                    ? 'Getting ready…'
                    : _live
                    ? 'Your episode is open'
                    : 'Listen',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _cyan,
                foregroundColor: _navy,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _s(_access['usageLabel']).isEmpty
                ? _usage
                : _s(_access['usageLabel']),
            style: const TextStyle(color: _muted, fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _studio() {
    final turns = _maps(_episode['turns']);
    final hostTurns = turns.where((turn) => turn['speaker'] != 'user').length;
    final preparing = _listening && _busy;
    final checkingSources =
        preparing && hostTurns == 1 && _episode['checkedAt'] == null;
    final preparationSeconds = _preparingSince == null
        ? 0
        : math.max(0, _now.difference(_preparingSince!).inSeconds);
    final count = _hasEpisode
        ? (_episode['hostCount'] as num?)?.toInt() ?? _hosts
        : _hosts;
    final status = !_hasEpisode
        ? 'THE TABLE IS YOURS'
        : _terminal(_episode)
        ? (_episode['state'] == 'failed'
              ? (hostTurns == 0 ? 'EPISODE COULD NOT START' : 'EPISODE STOPPED')
              : 'EPISODE ENDED')
        : _recording
        ? 'YOUR MIC IS ON'
        : _transcribing
        ? 'PREPARING YOUR WORDS'
        : _listening
        ? (_busy
              ? (hostTurns == 0
                    ? 'PREPARING YOUR EPISODE'
                    : checkingSources
                    ? 'CHECKING SOURCES'
                    : 'PREPARING THE NEXT TURN')
              : 'ON AIR · JUST FOR YOU')
        : 'PAUSED · YOUR PACE';
    final summary = _episode['summary'];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening || _recording ? _cyan : _gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  key: const Key('pod-playback-status'),
                  style: const TextStyle(
                    color: _cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (_remaining != null)
                Text(
                  '${_remaining! ~/ 60}:${(_remaining! % 60).toString().padLeft(2, '0')}',
                  key: const Key('pod-remaining'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _host('host', 'K-Nova', 'Your host'),
              _host('analyst', 'Analyst', 'The context'),
              if (count == 3)
                _host('challenger', 'Challenger', 'Another angle'),
            ],
          ),
          const SizedBox(height: 23),
          Container(
            height: 40,
            width: double.infinity,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(280, 36),
              painter: _WavePainter(
                active: _listening && !_busy,
                color: _speaking == null ? _cyan : _speakerColor(_speaking!),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _hasEpisode
                ? _s(_episode['topic'])
                : 'Good conversations leave room for you.',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hasEpisode
                ? (_speaking != null
                      ? '${_speaker(_speaking!)} is speaking'
                      : _busy && _listening
                      ? (hostTurns == 0
                            ? 'Preparing your host’s welcome. Audio will begin when the first turn is ready.'
                            : checkingSources
                            ? 'Checking sources for your topic before the hosts discuss the facts. Keep this screen open.'
                            : 'Creating the next host’s audio. Playback will continue when it is ready.')
                      : _terminal(_episode)
                      ? (hostTurns == 0
                            ? 'No host audio was generated for this episode. You can start a new episode when you are ready.'
                            : 'Revisit your transcript, sources and recap below.')
                      : 'Resume when you are ready. Pausing does not extend the episode deadline.')
                : 'Two or three AI perspectives, a question worth exploring, and a seat at the table for you.',
            style: const TextStyle(color: _muted, height: 1.6),
          ),
          if (preparing) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('pod-preparation-status'),
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_top_rounded,
                    color: _cyan,
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      checkingSources
                          ? 'Checking sources · ${preparationSeconds}s\nThe hosts are waiting for source context. No audio is playing during this step.'
                          : hostTurns == 0
                          ? 'Preparing welcome audio · ${preparationSeconds}s\nYour episode clock starts when the first turn is ready.'
                          : 'Preparing audio · ${preparationSeconds}s',
                      style: const TextStyle(
                        color: _cyan,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_live) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 58,
                    child: FilledButton.icon(
                      key: const Key('pod-chime'),
                      onPressed: _transcribing || (_busy && !_listening)
                          ? null
                          : _recording
                          ? _finishRecording
                          : () => _chime(voice: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: _navy,
                      ),
                      icon: Icon(
                        _recording ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        _recording ? 'Stop & review' : 'Chime in',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  key: const Key('pod-pause-resume'),
                  tooltip: _listening ? 'Pause episode' : 'Resume episode',
                  onPressed:
                      _recording || _transcribing || (_busy && !_listening)
                      ? null
                      : _listening
                      ? () => _pause()
                      : _resume,
                  icon: Icon(
                    _listening ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const Key('pod-type'),
                    onPressed:
                        _recording ||
                            _startingRecording ||
                            _transcribing ||
                            (_busy && !_listening)
                        ? null
                        : () => _chime(voice: false),
                    icon: const Icon(Icons.keyboard_alt_outlined, size: 17),
                    label: const Text('Type a contribution'),
                  ),
                ),
                TextButton(
                  key: const Key('pod-end'),
                  onPressed: () => _end(),
                  child: const Text('End', style: TextStyle(color: _muted)),
                ),
              ],
            ),
            if (_startingRecording)
              const Text(
                'Waiting for microphone permission…',
                style: TextStyle(color: _gold, fontSize: 12),
              ),
            if (_recording)
              Text(
                'Recording ${_media.elapsed.inSeconds}s / 30s · Stop to review before sending',
                style: const TextStyle(color: _gold, fontSize: 12),
              ),
            if (_transcribing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Transcribing your recording…',
                        style: TextStyle(color: _muted),
                      ),
                    ),
                  ],
                ),
              ),
            if (_composing && !_recording) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('pod-contribution'),
                controller: _contribution,
                enabled: !_transcribing && !_busy,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Your contribution',
                  hintText: 'Add a thought, ask a question, change the angle…',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('pod-send'),
                  onPressed: _transcribing || _busy ? null : _sendContribution,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  label: const Text('Send'),
                ),
              ),
            ],
          ],
          if (turns.isNotEmpty) ...[
            const SizedBox(height: 24),
            _label('THE CONVERSATION'),
            Container(
              constraints: const BoxConstraints(maxHeight: 380),
              child: SingleChildScrollView(
                reverse: _listening,
                child: Column(children: turns.map(_turn).toList()),
              ),
            ),
          ],
          if (_terminal(_episode) &&
              summary != null &&
              _s(summary).isNotEmpty) ...[
            const SizedBox(height: 19),
            _label('YOUR RECAP'),
            Text(
              summary is List ? summary.map(_s).join('\n') : _s(summary),
              style: const TextStyle(color: _muted, height: 1.7),
            ),
          ],
          if (_terminal(_episode) &&
              (_episode['error'] != null ||
                  _episode['endReason'] == 'failed')) ...[
            const SizedBox(height: 12),
            Text(
              _s(_episode['error']).isEmpty
                  ? 'This episode could not continue. Start a new episode when you are ready.'
                  : _s(_episode['error']),
              style: const TextStyle(color: _gold, height: 1.5),
            ),
          ],
          if (_maps(_episode['sources']).isNotEmpty) ...[
            const SizedBox(height: 20),
            _sources(),
          ],
          if (!_hasEpisode) ...[
            const SizedBox(height: 22),
            _noticeCard(
              'Listen starts a fresh, on-demand conversation. Chime in opens your microphone only when you tap it.',
              Icons.touch_app_outlined,
              _gold,
            ),
          ],
        ],
      ),
    );
  }

  Widget _host(String role, String name, String description) => Flexible(
    child: Column(
      children: [
        Semantics(
          label: '$name, $description${_speaking == role ? ', speaking' : ''}',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _speaking == role
                  ? _speakerColor(role).withValues(alpha: .16)
                  : Colors.transparent,
            ),
            child: CustomPaint(
              size: const Size(78, 78),
              painter: _HostPainter(color: _speakerColor(role), role: role),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 3),
        Text(description, style: const TextStyle(color: _muted, fontSize: 10)),
      ],
    ),
  );

  Widget _turn(Map<String, dynamic> turn) {
    final speaker = _s(turn['speaker']);
    final active =
        _speaking == speaker &&
        _maps(_episode['turns']).lastOrNull?['id'] == turn['id'];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active
            ? _speakerColor(speaker).withValues(alpha: .09)
            : _navy.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _speakerColor(speaker), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_speaker(speaker)}${turn['interrupted'] == true ? ' · interrupted' : ''}',
            style: TextStyle(
              color: _speakerColor(speaker),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _s(turn['text']),
            style: const TextStyle(fontSize: 13, height: 1.65),
          ),
        ],
      ),
    );
  }

  Widget _sources() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text(
      'Show sources',
      style: TextStyle(color: _cyan, fontSize: 13, fontWeight: FontWeight.w700),
    ),
    subtitle: _episode['checkedAt'] == null
        ? null
        : Text(
            'Research checked ${_s(_episode['checkedAt']).split('T').first}',
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
    children: _maps(_episode['sources']).map((source) {
      final uri = podPublicSourceUri(_s(source['url']));
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_s(source['title']), style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          uri?.host ?? 'Link unavailable',
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
        trailing: Icon(
          uri == null ? Icons.link_off : Icons.open_in_new_rounded,
          size: 16,
          color: _cyan,
        ),
        onTap: uri == null
            ? null
            : () async {
                try {
                  final opened =
                      await (widget.openLink?.call(uri) ??
                          launchUrl(uri, mode: LaunchMode.externalApplication));
                  if (!opened && mounted) {
                    setState(() {
                      _error = 'This source could not be opened.';
                    });
                  }
                } catch (_) {
                  if (mounted) {
                    setState(() {
                      _error = 'This source could not be opened.';
                    });
                  }
                }
              },
      );
    }).toList(),
  );

  Widget _noticeCard(
    String text,
    IconData icon,
    Color color, {
    Widget? action,
  }) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(color: color, fontSize: 12, height: 1.6),
              ),
              ?action,
            ],
          ),
        ),
      ],
    ),
  );

  Widget _historyView() {
    final items = _history.where(_terminal).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: _cyan, size: 20),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Your listening shelf',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text('${items.length}', style: const TextStyle(color: _muted)),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text(
              'Finished episodes, your words and the ideas worth keeping will live here.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
            ),
          ...items.map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.headphones_rounded, color: _gold),
              title: Text(
                _s(e['topic']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '${_s(e['category'])} · ${((e['durationSeconds'] as num?)?.toInt() ?? 300) ~/ 60} min · ${_s(e['state'])}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              onTap: _live ? null : () => _openHistory(e),
              trailing: IconButton(
                tooltip: 'Delete episode',
                onPressed: () => _delete(e),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: _muted,
                  size: 19,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostPainter extends CustomPainter {
  const _HostPainter({required this.color, required this.role});
  final Color color;
  final String role;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = math.pi / 8 + i * math.pi / 4;
      final point =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (size.width * .47);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: .10));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (role == 'host') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(0, -4),
            width: 15,
            height: 25,
          ),
          const Radius.circular(8),
        ),
        line,
      );
      canvas.drawArc(
        Rect.fromCenter(center: center.translate(0, -2), width: 28, height: 31),
        0,
        math.pi,
        false,
        line,
      );
      canvas.drawLine(center.translate(0, 13), center.translate(0, 20), line);
      canvas.drawLine(center.translate(-8, 20), center.translate(8, 20), line);
    } else if (role == 'analyst') {
      for (var i = 0; i < 3; i++) {
        canvas.drawLine(
          center.translate(-13 + i * 13, 16),
          center.translate(-13 + i * 13, 2 - i * 10),
          line..strokeWidth = 6,
        );
      }
    } else {
      final diamond = Path()
        ..moveTo(center.dx, center.dy - 19)
        ..lineTo(center.dx + 16, center.dy)
        ..lineTo(center.dx, center.dy + 19)
        ..lineTo(center.dx - 16, center.dy)
        ..close();
      canvas.drawPath(diamond, line);
      canvas.drawLine(center.translate(0, -8), center.translate(0, 5), line);
      canvas.drawCircle(center.translate(0, 11), 1, line);
    }
  }

  @override
  bool shouldRepaint(_HostPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.role != role;
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.active, required this.color});
  final bool active;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: active ? .8 : .25)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 40; i++) {
      final height = active
          ? 5 +
                (math.sin(i * 1.8).abs() *
                    math.sin(math.pi * i / 40).abs() *
                    28)
          : 3 + math.sin(i * 1.6).abs() * 5;
      final x = i * size.width / 40;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.active != active || oldDelegate.color != color;
}
