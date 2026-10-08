import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'korlix_review_activity.dart';

/// Tracks input across the navigator without retaining typed text or locations.
/// The app supplies its safe home/idle boundary; native and web presentation are
/// kept outside this host so a native review request has no custom pre-prompt.
class KorlixReviewHost extends StatefulWidget {
  const KorlixReviewHost({
    super.key,
    required this.child,
    required this.sessionChanges,
    required this.accountScope,
    required this.isAvailable,
    required this.canPrompt,
    required this.navigatorKey,
    required this.onPrompt,
    this.onPromptCancelled,
    this.repository,
    this.monotonicNow,
  });

  final Widget child;
  final Listenable sessionChanges;
  final String? Function() accountScope;
  final bool Function() isAvailable;
  final bool Function() canPrompt;
  final GlobalKey<NavigatorState> navigatorKey;
  final Future<void> Function(BuildContext) onPrompt;
  final Future<void> Function()? onPromptCancelled;
  final SharedPreferencesReviewActivityRepository? repository;
  final Duration Function()? monotonicNow;

  @override
  State<KorlixReviewHost> createState() => _KorlixReviewHostState();
}

class _KorlixReviewHostState extends State<KorlixReviewHost>
    with WidgetsBindingObserver {
  static const _tickInterval = Duration(seconds: 5);
  static const _checkpointInterval = Duration(seconds: 30);
  static const _quietInterval = Duration(seconds: 3);

  final _stopwatch = Stopwatch();
  late final SharedPreferencesReviewActivityRepository _defaultRepository;
  Timer? _timer;
  KorlixReviewActivityTracker? _tracker;
  TextEditingController? _focusedController;
  String? _account;
  int _generation = 0;
  bool _foreground = true;
  bool _storageFailed = false;
  bool _attemptingPrompt = false;
  bool _presenting = false;
  bool _cancelRequested = false;
  Duration? _lastInput;
  Duration _lastCheckpoint = Duration.zero;

  Duration get _now => widget.monotonicNow?.call() ?? _stopwatch.elapsed;
  SharedPreferencesReviewActivityRepository get _repository =>
      widget.repository ?? _defaultRepository;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _defaultRepository = SharedPreferencesReviewActivityRepository();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_watchFocusedEditor);
    widget.sessionChanges.addListener(_onSessionChanged);
    _onSessionChanged();
    _timer = Timer.periodic(_tickInterval, (_) => _onTick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _watchFocusedEditor();
    });
  }

  @override
  void didUpdateWidget(covariant KorlixReviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessionChanges, widget.sessionChanges)) {
      oldWidget.sessionChanges.removeListener(_onSessionChanged);
      widget.sessionChanges.addListener(_onSessionChanged);
    }
    _onSessionChanged();
  }

  String? _readAccount() {
    final account = widget.accountScope()?.trim();
    return account == null || account.isEmpty ? null : account;
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final account = _readAccount();
    if (account != _account) {
      final previous = _tracker;
      previous?.setAvailable(false);
      if (previous != null) unawaited(_persist(previous));
      _cancelPrompt();
      _generation += 1;
      _account = account;
      _tracker = null;
      _lastInput = null;
      _storageFailed = false;
      _lastCheckpoint = _now;
      if (account != null) unawaited(_loadAccount(account, _generation));
    }
    _refreshAvailability();
    if (!_safeBoundary) _cancelPrompt();
  }

  Future<void> _loadAccount(String account, int generation) async {
    try {
      final progress = await _repository.load(account);
      if (!mounted || generation != _generation || account != _readAccount()) {
        return;
      }
      _tracker = KorlixReviewActivityTracker(
        userId: account,
        initialProgress: progress,
        monotonicNow: () => _now,
      );
      _refreshAvailability();
    } catch (_) {
      // A storage error must not turn into a recurring automatic prompt.
      if (mounted && generation == _generation) _storageFailed = true;
    }
  }

  void _refreshAvailability() {
    final tracker = _tracker;
    if (tracker == null) return;
    final available = _foreground && widget.isAvailable();
    if (tracker.available && !available) {
      tracker.setAvailable(false);
      _lastInput = null;
      unawaited(_persist(tracker));
    } else {
      tracker.setAvailable(available);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _onSessionChanged();
  }

  void _recordInput() {
    _onSessionChanged();
    final tracker = _tracker;
    if (tracker == null || !tracker.available || _storageFailed) return;
    tracker.recordInteraction();
    _lastInput = _now;
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _recordInput();
    return false;
  }

  void _watchFocusedEditor() {
    final focus = FocusManager.instance.primaryFocus;
    final focusContext = focus?.context;
    final editor = focusContext?.findAncestorStateOfType<EditableTextState>();
    final controller = editor?.widget.controller;
    if (identical(controller, _focusedController)) return;
    _focusedController?.removeListener(_recordInput);
    _focusedController = controller;
    // Mobile software keyboards do not reliably emit HardwareKeyboard events.
    // Observe changes only; no text, selection or composition data is read.
    _focusedController?.addListener(_recordInput);
  }

  bool get _safeBoundary =>
      _foreground && widget.isAvailable() && widget.canPrompt();

  bool get _readyToPrompt {
    final tracker = _tracker;
    final lastInput = _lastInput;
    final keyboardVisible =
        (MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0) > 0;
    return !_storageFailed &&
        tracker != null &&
        tracker.userId == _readAccount() &&
        tracker.eligible &&
        _safeBoundary &&
        !keyboardVisible &&
        _focusedController == null &&
        lastInput != null &&
        _now - lastInput >= _quietInterval;
  }

  void _onTick() {
    _onSessionChanged();
    final tracker = _tracker;
    tracker?.tick();
    if (tracker != null && _now - _lastCheckpoint >= _checkpointInterval) {
      _lastCheckpoint = _now;
      unawaited(_persist(tracker));
    }
    if (!_attemptingPrompt && _readyToPrompt) unawaited(_maybePrompt());
  }

  Future<void> _persist(KorlixReviewActivityTracker tracker) async {
    try {
      final saved = await _repository.save(tracker.userId, tracker.progress);
      tracker.mergeProgress(saved);
    } catch (_) {
      if (identical(_tracker, tracker)) _storageFailed = true;
    }
  }

  Future<void> _maybePrompt() async {
    if (_attemptingPrompt || !_readyToPrompt) return;
    final tracker = _tracker!;
    final navigator = widget.navigatorKey.currentState;
    final promptContext = navigator?.overlay?.context;
    if (promptContext == null || !promptContext.mounted) return;
    final generation = _generation;
    _attemptingPrompt = true;
    try {
      final claimed = await _repository.claimAutomaticPrompt(
        tracker.userId,
        tracker.progress,
      );
      // Persist before presentation. A route/account change during persistence
      // consumes this attempt safely instead of showing it to another member.
      if (!claimed) {
        tracker.mergeProgress(await _repository.load(tracker.userId));
        return;
      }
      final stillReady =
          mounted &&
          generation == _generation &&
          identical(tracker, _tracker) &&
          promptContext.mounted &&
          _readyToPrompt;
      tracker.mergeProgress(
        tracker.progress.copyWith(automaticPromptHandled: true),
      );
      if (!stillReady || !promptContext.mounted) return;
      _presenting = true;
      _cancelRequested = false;
      await widget.onPrompt(promptContext);
    } catch (_) {
      // Native review availability is best effort. Do not retry, redirect to
      // feedback or present a different review UI after a handled request.
      if (identical(tracker, _tracker)) _storageFailed = true;
    } finally {
      _presenting = false;
      _attemptingPrompt = false;
    }
  }

  void _cancelPrompt() {
    if (!_presenting || _cancelRequested) return;
    _cancelRequested = true;
    final cancel = widget.onPromptCancelled;
    if (cancel != null) unawaited(_runCancellation(cancel));
  }

  Future<void> _runCancellation(Future<void> Function() cancel) async {
    try {
      await cancel();
    } catch (_) {
      // Dismissal is best effort; the once-only claim remains persisted.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelPrompt();
    _generation += 1;
    final tracker = _tracker;
    tracker?.setAvailable(false);
    if (tracker != null) unawaited(_persist(tracker));
    widget.sessionChanges.removeListener(_onSessionChanged);
    _focusedController?.removeListener(_recordInput);
    FocusManager.instance.removeListener(_watchFocusedEditor);
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _recordInput(),
    onPointerMove: (_) => _recordInput(),
    onPointerHover: (_) => _recordInput(),
    onPointerSignal: (_) => _recordInput(),
    child: widget.child,
  );
}
