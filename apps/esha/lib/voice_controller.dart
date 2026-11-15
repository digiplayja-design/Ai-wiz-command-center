import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services/korlix_api.dart';
import 'services/purchases.dart';
import 'services/voice.dart';
import 'services/voice_audio.dart';

enum EshaVoicePhase {
  idle,
  preparing,
  connecting,
  listening,
  stopping,
  paused,
  pending,
  ended,
}

class EshaVoiceController extends ChangeNotifier {
  static const connectionLimitMessage =
      'The voice connection limit has been reached for this billing period. Your other membership features remain available.';
  EshaVoiceController({
    required this.api,
    required this.purchases,
    VoiceGateway? gateway,
    VoiceAudioTransport Function()? transportFactory,
    DateTime Function()? now,
  }) : gateway = gateway ?? KorlixVoiceGateway(api),
       _transportFactory = transportFactory ?? WebRtcVoiceAudio.new,
       _now = now ?? DateTime.now {
    purchases.addListener(_membershipChanged);
  }

  final KorlixApi api;
  final EshaPurchases purchases;
  final VoiceGateway gateway;
  final VoiceAudioTransport Function() _transportFactory;
  final DateTime Function() _now;
  EshaVoicePhase phase = EshaVoicePhase.idle;
  VoiceAvailability? availability;
  VoiceUsage? usage;
  String? error;
  String? resultsError;
  bool loadingResults = false;
  final Map<String, VoiceDeepResult> _deepResults = {};
  List<String> _recentSessions = [];
  List<VoiceDeepResult> get deepResults =>
      List.unmodifiable(_deepResults.values.toList().reversed);
  bool get hasSavedAnswerSessions => _recentSessions.isNotEmpty;
  bool audioConsent = false, deepThinkingConsent = false;
  int elapsedSeconds = 0;
  String? _account, _pendingId, _providerSessionId;
  int _accountEpoch = -1;
  int _epoch = 0, _pendingPolls = 0;
  bool _disposed = false,
      _foreground = true,
      _starting = false,
      _restoring = false,
      _refreshing = false,
      _creationSent = false,
      _answerAccepted = false,
      _providerStarted = false,
      _enabling = false,
      _pauseRequested = false;
  VoiceAudioTransport? _audio;
  StreamSubscription<VoiceAudioEvent>? _audioEvents;
  Timer? _pollTimer, _startupTimer, _durationTimer, _elapsedTimer;
  Timer? _resultTimer;
  int _resultPolls = 0;
  Future<void>? _closing, _attaching;
  DateTime? _listeningAt;

  bool get active => phase == EshaVoicePhase.listening;
  bool get requestingMicrophone => _audio?.requestingMicrophone == true;
  bool get busy =>
      _starting ||
      _restoring ||
      _refreshing ||
      phase == EshaVoicePhase.preparing ||
      phase == EshaVoicePhase.connecting ||
      phase == EshaVoicePhase.stopping;
  bool get hasPendingSession => _pendingId != null;
  bool get canStart =>
      !_disposed &&
      _foreground &&
      !busy &&
      !hasPendingSession &&
      audioConsent &&
      purchases.hasAppAccess &&
      availability?.enabled == true &&
      (usage?.remainingSeconds ?? 0) > 0;
  bool get canStop => _starting || _audio != null || hasPendingSession;
  bool get canChooseConsent => !canStop && !busy;
  String _intentKey(String userId) => 'esha.voice.pending.$userId';
  String _historyKey(String userId) => 'esha.voice.recent.$userId';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _membershipChanged() {
    if (_disposed) return;
    if (_account != api.session?.userId || _accountEpoch != api.epoch) {
      unawaited(attachAccount());
    } else if (!purchases.hasAppAccess && (_audio != null || _starting)) {
      error = purchases.accessMessage;
      unawaited(stop(reason: 'transport_error'));
    }
    _notify();
  }

  /// Only a saved client UUID is recovered. Audio, transcripts, SDP and provider
  /// credentials are not stored. Recovery can close a prior call, never start one.
  Future<void> attachAccount() {
    if (_attaching != null) return _attaching!;
    final user = api.session?.userId;
    if (user == _account && _accountEpoch == api.epoch) return Future.value();
    final epoch = ++_epoch;
    _account = user;
    _accountEpoch = api.epoch;
    audioConsent = false;
    deepThinkingConsent = false;
    availability = null;
    usage = null;
    error = null;
    resultsError = null;
    _deepResults.clear();
    _recentSessions = [];
    _resultTimer?.cancel();
    _pendingId = null;
    _creationSent = false;
    elapsedSeconds = 0;
    phase = EshaVoicePhase.idle;
    _cancelTimers();
    _restoring = true;
    final operation = () async {
      await _closeAudio();
      if (user == null) return;
      try {
        final saved = await api.secureStorage.read(_intentKey(user));
        final history = await api.secureStorage.read(_historyKey(user));
        if (_disposed || epoch != _epoch || api.session?.userId != user) return;
        if (history != null) {
          final parsed = jsonDecode(history);
          if (parsed is! List ||
              parsed.length > 20 ||
              parsed.any(
                (id) => id is! String || !voiceRequestIdPattern.hasMatch(id),
              )) {
            throw const FormatException('Invalid voice history');
          }
          _recentSessions = List<String>.from(parsed).toSet().toList();
        }
        if (saved != null) {
          if (!voiceRequestIdPattern.hasMatch(saved)) {
            error = 'The saved voice session could not be verified. Contact Korlix support before starting another call.';
            // A malformed saved intent is not silently discarded.
            _pendingId = saved;
          } else {
            _pendingId = saved;
            _creationSent = true;
            phase = EshaVoicePhase.pending;
            error = 'Checking the previous voice session before another call.';
          }
        }
      } catch (_) {
        error = 'Esha could not read its secure voice-session record. Reopen the app before starting voice.';
        _pendingId = 'unreadable';
      }
    }();
    _attaching = operation;
    return operation.whenComplete(() {
      if (identical(_attaching, operation)) _attaching = null;
      _restoring = false;
      _notify();
      if (!_disposed &&
          (api.session?.userId != _account || _accountEpoch != api.epoch)) {
        unawaited(attachAccount());
      }
    });
  }

  void setAudioConsent(bool allowed) {
    audioConsent = allowed && api.session != null;
    if (!audioConsent && canStop) {
      unawaited(stop());
    }
    _notify();
  }

  void setDeepThinkingConsent(bool allowed) {
    if (!canChooseConsent) return;
    deepThinkingConsent = allowed && (usage?.deepRemaining ?? 0) > 0;
    _notify();
  }

  Future<void> refresh() async {
    await attachAccount();
    if (_disposed || _refreshing || _account == null || !_foreground) return;
    final owner = api.owner();
    _refreshing = true;
    _pendingPolls = 0;
    _notify();
    try {
      if (_pendingId != null) await reconcile();
      if (!api.isOwner(owner) || _disposed) return;
      final value = await gateway.availability();
      if (!api.isOwner(owner) || _disposed) return;
      availability = value;
      usage = value.usage;
      if (!value.enabled && !canStop) {
        error = value.connectionLimitReached
            ? connectionLimitMessage
            : 'Live voice is not available yet. Your microphone is off.';
      } else if (!hasPendingSession) {
        error = null;
      }
      if ((usage?.deepRemaining ?? 0) == 0) deepThinkingConsent = false;
      if (_recentSessions.isNotEmpty) unawaited(refreshResults());
    } catch (failure) {
      if (api.isOwner(owner) && !_disposed) {
        availability = null;
        error = _message(failure);
      }
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  void _verifyOperation(int epoch, OwnerSnapshot owner) {
    api.verifyOwner(owner);
    if (_disposed ||
        epoch != _epoch ||
        !_foreground ||
        !audioConsent ||
        !purchases.hasAppAccess) {
      throw const EshaException(
        'VOICE_CANCELLED',
        'Voice was stopped before the connection completed.',
      );
    }
  }

  Future<void> start() async {
    await attachAccount();
    if (_disposed || busy || hasPendingSession || !_foreground) return;
    if (!audioConsent || !purchases.hasAppAccess) {
      error = !audioConsent
          ? 'Allow microphone audio sharing with OpenAI before starting voice.'
          : purchases.accessMessage;
      _notify();
      return;
    }
    final owner = api.owner(), epoch = ++_epoch;
    _starting = true;
    _pauseRequested = false;
    phase = EshaVoicePhase.preparing;
    error = null;
    elapsedSeconds = 0;
    _answerAccepted = false;
    _providerStarted = false;
    _providerSessionId = null;
    _creationSent = false;
    _notify();
    try {
      // Refresh entitlement and allowance before asking for microphone access.
      final ready = await gateway.availability();
      _verifyOperation(epoch, owner);
      availability = ready;
      usage = ready.usage;
      if (!ready.enabled || (usage?.remainingSeconds ?? 0) <= 0) {
        throw EshaException(
          'voice_not_configured',
          ready.connectionLimitReached ? connectionLimitMessage : 'Live voice is not available or the voice allowance has been used. Your microphone is off.',
        );
      }
      final allowanceAtStart = usage!.remainingSeconds;
      final deepConsent = deepThinkingConsent && usage!.deepRemaining > 0;
      final audio = _transportFactory();
      _audio = audio;
      _audioEvents = audio.events.listen(
        (event) => _onAudioEvent(event, epoch, owner),
      );
      final offer = await audio.createOffer();
      _verifyOperation(epoch, owner);
      final id = const Uuid().v4();
      // Secure persistence is a prerequisite for a paid creation. This UUID is
      // retained across timeouts and account changes until the server finalizes.
      await api.secureStorage.write(_intentKey(owner.userId), id);
      if (!api.isOwner(owner) || epoch != _epoch || _disposed) {
        // No create was sent. Do not attach an old account's intent to a new
        // account while a secure-storage write was in flight.
        await api.secureStorage.remove(_intentKey(owner.userId));
        _verifyOperation(epoch, owner);
      }
      _pendingId = id;
      _verifyOperation(epoch, owner);
      _creationSent = true;
      phase = EshaVoicePhase.connecting;
      // A local safety cutoff is additional microphone cleanup, never proof of
      // provider closure or a substitute for the backend's durable duration cap.
      _durationTimer = Timer(
        Duration(milliseconds: (allowanceAtStart * 1000).floor()),
        () {
          error = 'The available voice time has ended.';
          unawaited(stop());
        },
      );
      _notify();
      final result = await gateway.create(
        requestId: id,
        sdpOffer: offer,
        deepThinkingConsent: deepConsent,
      );
      _verifyOperation(epoch, owner);
      _providerSessionId = result.sessionId;
      usage = result.usage;
      await audio.acceptAnswer(result.sdpAnswer!);
      _verifyOperation(epoch, owner);
      _answerAccepted = true;
      _startupTimer = Timer(const Duration(seconds: 15), () {
        error = 'The voice connection did not become ready. Your microphone is off.';
        unawaited(stop(reason: 'transport_error'));
      });
      await _enableWhenReady(epoch, owner);
    } catch (failure) {
      _cancelTimers();
      await _closeAudio();
      if (api.isOwner(owner) && !_disposed) {
        error = _message(failure);
        if (!_creationSent ||
            failure is EshaException &&
                {
                  'voice_not_configured',
                  'voice_start_not_created',
                }.contains(failure.code)) {
          // Only these two server codes prove no reservation/provider work for
          // this UUID. A generic exhausted/begin/storage failure stays pending.
          audioConsent = false;
          deepThinkingConsent = false;
          if (_pendingId != null) {
            try {
              await api.secureStorage.remove(_intentKey(owner.userId));
              _pendingId = null;
            } catch (_) {
              error = 'Your microphone is off. The secure voice-session record could not be cleared; check the previous call before starting again.';
            }
          }
          phase = hasPendingSession
              ? EshaVoicePhase.pending
              : _pauseRequested
              ? EshaVoicePhase.paused
              : EshaVoicePhase.ended;
        } else {
          phase = EshaVoicePhase.pending;
        }
      }
    } finally {
      _starting = false;
      _notify();
      if (!_disposed &&
          api.isOwner(owner) &&
          hasPendingSession &&
          phase != EshaVoicePhase.listening &&
          phase != EshaVoicePhase.connecting) {
        await stop(reason: _pauseRequested ? 'paused' : 'transport_error');
      }
    }
  }

  void _onAudioEvent(VoiceAudioEvent event, int epoch, OwnerSnapshot owner) {
    if (_disposed || epoch != _epoch || !api.isOwner(owner)) return;
    switch (event.type) {
      case VoiceAudioEventType.started:
        if (event.sessionId != null && event.sessionId != _providerSessionId) {
          error = 'The voice connection did not match the authorized session.';
          unawaited(stop(reason: 'transport_error'));
          return;
        }
        _providerStarted = true;
        unawaited(_enableWhenReady(epoch, owner));
      case VoiceAudioEventType.closed:
        // A client event stops audio but cannot confirm the billable end.
        unawaited(stop());
      case VoiceAudioEventType.disconnected:
      case VoiceAudioEventType.error:
        error = 'The voice connection was interrupted. Your microphone is off.';
        unawaited(stop(reason: 'transport_error'));
    }
  }

  Future<void> _enableWhenReady(int epoch, OwnerSnapshot owner) async {
    if (!_answerAccepted || !_providerStarted || _enabling || active) return;
    _enabling = true;
    try {
      _verifyOperation(epoch, owner);
      await _audio!.enableMicrophone();
      _verifyOperation(epoch, owner);
      _startupTimer?.cancel();
      phase = EshaVoicePhase.listening;
      _listeningAt = _now();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedSeconds = _now()
            .difference(_listeningAt!)
            .inSeconds
            .clamp(0, 86400);
        _notify();
      });
      _schedulePoll();
      _notify();
    } catch (_) {
      await stop(reason: 'transport_error');
    } finally {
      _enabling = false;
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value && canStop) {
      unawaited(stop(reason: 'background'));
    } else if (value && hasPendingSession && !_disposed) {
      unawaited(reconcile());
    }
  }

  Future<void> pause() => stop(reason: 'paused');
  Future<void> resume() => start();
  Future<void> restart() async {
    await stop();
    if (!hasPendingSession && !_disposed) {
      error = 'Confirm audio sharing for a new call, then tap Start again.';
      _notify();
    }
  }

  Future<void> stop({String reason = 'user_stop', bool resetPolling = true}) {
    if (_closing != null) return _closing!;
    ++_epoch;
    audioConsent = false;
    deepThinkingConsent = false;
    _pauseRequested = reason == 'paused' || reason == 'background';
    _cancelTimers();
    final owner = api.session == null ? null : api.owner();
    phase = EshaVoicePhase.stopping;
    final operation = () async {
      await _closeAudio();
      final id = _pendingId;
      if (owner == null ||
          !api.isOwner(owner) ||
          id == null ||
          !_creationSent) {
        if (!_disposed) {
          phase = _pauseRequested
              ? EshaVoicePhase.paused
              : EshaVoicePhase.ended;
        }
        return;
      }
      try {
        final result = await gateway.stop(id, reason);
        if (!api.isOwner(owner) || _disposed || _pendingId != id) return;
        await _applyStatus(result, owner);
      } catch (_) {
        if (api.isOwner(owner) && !_disposed && _pendingId == id) {
          phase = EshaVoicePhase.pending;
          error = 'Your microphone is off. Esha is still confirming the previous call ended before allowing another call.';
        }
      }
      if (resetPolling) _pendingPolls = 0;
      _schedulePoll();
    }();
    _closing = operation;
    _notify();
    return operation.whenComplete(() {
      if (identical(_closing, operation)) _closing = null;
      _notify();
    });
  }

  Future<void> reconcile() async {
    final id = _pendingId;
    if (_disposed ||
        id == null ||
        api.session == null ||
        _starting ||
        _closing != null) {
      return;
    }
    final owner = api.owner();
    try {
      final result = await gateway.status(id);
      if (!api.isOwner(owner) || _disposed || _pendingId != id) return;
      await _applyStatus(result, owner);
      if (!result.finalized && _audio == null) {
        // An idempotent stop also reattaches the server's watcher after a
        // backend restart, including durable closing/uncertain sessions.
        await stop(reason: 'transport_error', resetPolling: false);
      } else if (!{'starting', 'active'}.contains(result.state) &&
          _audio != null) {
        await stop(reason: 'transport_error');
      }
    } catch (_) {
      if (!api.isOwner(owner) || _disposed) return;
      if (_audio != null) {
        await stop(reason: 'transport_error');
      } else {
        phase = EshaVoicePhase.pending;
        error = 'Your microphone is off. Connect and check the previous call before starting again.';
      }
    }
    _notify();
  }

  Future<void> _applyStatus(
    VoiceSessionStatus result,
    OwnerSnapshot owner,
  ) async {
    if (result.requestId != _pendingId || !api.isOwner(owner)) return;
    usage = result.usage;
    _mergeResults(result.deepResults);
    if (result.finalized) {
      await _closeAudio();
      // Save only the completed call's UUID before clearing the unfinished
      // intent, so a crash cannot strand an answer that finishes after audio.
      await _rememberSession(result.requestId, owner);
      await api.secureStorage.remove(_intentKey(owner.userId));
      if (!api.isOwner(owner) || _disposed) return;
      _pendingId = null;
      _creationSent = false;
      audioConsent = false;
      deepThinkingConsent = false;
      _cancelTimers();
      phase = _pauseRequested ? EshaVoicePhase.paused : EshaVoicePhase.ended;
      error = null;
      if (_recentSessions.contains(result.requestId) &&
          (result.usage?.deepReserved ?? 0) > 0) {
        _resultPolls = 0;
        _scheduleResults(result.requestId);
      }
    } else if (_audio == null) {
      phase = EshaVoicePhase.pending;
      error = 'Your microphone is off. Waiting for the service to confirm the call ended.';
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (_disposed || !_foreground || !hasPendingSession) return;
    if (_audio == null && _pendingPolls++ >= 12) return;
    _pollTimer = Timer(Duration(seconds: _audio == null ? 5 : 10), () async {
      await reconcile();
      _schedulePoll();
    });
  }

  Future<void> _rememberSession(String id, OwnerSnapshot owner) async {
    api.verifyOwner(owner);
    final recent = [
      id,
      ..._recentSessions.where((entry) => entry != id),
    ].take(20).toList();
    await api.secureStorage.write(
      _historyKey(owner.userId),
      jsonEncode(recent),
    );
    api.verifyOwner(owner);
    _recentSessions = recent;
  }

  void _mergeResults(List<VoiceDeepResult> results) {
    for (final result in results) {
      _deepResults.putIfAbsent(result.requestId, () => result);
    }
    // Current-period counts are small; bound memory even in a long app session.
    while (_deepResults.length > 100) {
      _deepResults.remove(_deepResults.keys.first);
    }
  }

  /// The server persists successful Sol answers. Read them using account-bound
  /// recent voice UUIDs; never regenerate an answer or persist its text locally.
  Future<void> refreshResults({String? sessionId}) async {
    if (_disposed || loadingResults || api.session == null || !_foreground) {
      return;
    }
    final owner = api.owner();
    final ids = sessionId == null ? [..._recentSessions] : [sessionId];
    if (ids.isEmpty || ids.any((id) => !_recentSessions.contains(id))) return;
    loadingResults = true;
    resultsError = null;
    _notify();
    try {
      // At most twenty reads, in small batches. Stop on the first failed batch
      // instead of issuing a long series of requests while the service is down.
      for (var index = 0; index < ids.length; index += 3) {
        final batch = await Future.wait(
          ids.skip(index).take(3).map(gateway.status),
        );
        api.verifyOwner(owner);
        if (_disposed) return;
        for (final result in batch) {
          _mergeResults(result.deepResults);
          // Historical session usage belongs to its original billing period.
          // Only fresh availability may replace the current-period allowance.
          if (sessionId == result.requestId &&
              (result.usage?.deepReserved ?? 0) > 0) {
            _scheduleResults(result.requestId);
          }
        }
      }
    } catch (_) {
      if (api.isOwner(owner) && !_disposed) {
        resultsError = 'Some saved deep-thinking answers could not be loaded. Refresh answers to check again; this will not use another consultation.';
      }
    } finally {
      loadingResults = false;
      _notify();
    }
  }

  void _scheduleResults(String id) {
    _resultTimer?.cancel();
    if (_disposed || !_foreground || _resultPolls++ >= 36) return;
    _resultTimer = Timer(
      const Duration(seconds: 5),
      () => unawaited(refreshResults(sessionId: id)),
    );
  }

  String _message(Object failure) => failure is EshaException
      ? failure.message
      : 'The voice connection could not be confirmed. Your microphone is off.';

  Future<void> _closeAudio() async {
    final audio = _audio, subscription = _audioEvents;
    _audio = null;
    _audioEvents = null;
    _answerAccepted = false;
    _providerStarted = false;
    _startupTimer?.cancel();
    _elapsedTimer?.cancel();
    // close() disables local tracks before its first await.
    final closing = audio?.close();
    await subscription?.cancel();
    await closing;
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _startupTimer?.cancel();
    _durationTimer?.cancel();
    _elapsedTimer?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    purchases.removeListener(_membershipChanged);
    _cancelTimers();
    _resultTimer?.cancel();
    unawaited(_closeAudio());
    // A remaining secure intent survives disposal and is reconciled next time.
    // Only the backend can confirm the final provider usage and release it.
    super.dispose();
  }
}
