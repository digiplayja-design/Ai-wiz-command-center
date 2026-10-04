import 'dart:async';
import '../sounds/korlix_sound_service.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';

class KorlixVoiceLocale {
  const KorlixVoiceLocale(this.id, this.name);
  final String id, name;
}

abstract class KorlixDictationEngine {
  Future<List<KorlixVoiceLocale>> initialize({
    required ValueChanged<String> onStatus,
    required ValueChanged<String> onError,
  });
  Future<void> start({
    String? locale,
    required ValueChanged<String> onWords,
    required ValueChanged<double> onLevel,
  });
  Future<void> stop();
  Future<void> cancel();
  void dispose();
}

class KorlixDeviceDictation extends KorlixDictationEngine {
  final _speech = SpeechToText();
  final Object _soundQuietOwner = Object();
  bool _closed = false, _initialized = false, _captured = false;
  bool _requestedListening = false;
  ValueChanged<String>? _oldStatus, _statusListener;
  ValueChanged<SpeechRecognitionError>? _oldError, _errorListener;
  Completer<void>? _finish;
  @override
  Future<List<KorlixVoiceLocale>> initialize({
    required ValueChanged<String> onStatus,
    required ValueChanged<String> onError,
  }) async {
    if (!_captured) {
      _oldStatus = _speech.statusListener;
      _oldError = _speech.errorListener;
      _captured = true;
    }
    _statusListener = (status) {
      if (status == 'listening' && _requestedListening && !_closed) {
        kKorlixSounds.setQuiet(_soundQuietOwner, true);
      } else if (status == 'done' || status == 'notListening') {
        _requestedListening = false;
        kKorlixSounds.setQuiet(_soundQuietOwner, false);
      }
      if (status == 'done' && !(_finish?.isCompleted ?? true)) {
        _finish!.complete();
      }
      if (!_closed) onStatus(status);
    };
    _errorListener = (error) {
      _requestedListening = false;
      kKorlixSounds.setQuiet(_soundQuietOwner, false);
      if (!(_finish?.isCompleted ?? true)) _finish!.complete();
      if (!_closed) onError(error.errorMsg);
    };
    final available = await _speech.initialize(
      onStatus: _statusListener,
      onError: _errorListener,
    );
    _initialized = true;
    if (_closed) {
      await cancel();
      _restore();
      return [];
    }
    // speech_to_text is a singleton and initialize only registers once.
    _speech.statusListener = _statusListener;
    _speech.errorListener = _errorListener;
    if (!available) throw StateError('Speech recognition is unavailable.');
    return (await _speech.locales())
        .map((l) => KorlixVoiceLocale(l.localeId, l.name))
        .toList();
  }

  @override
  Future<void> start({
    String? locale,
    required ValueChanged<String> onWords,
    required ValueChanged<double> onLevel,
  }) async {
    if (_closed) return;
    _requestedListening = true;
    kKorlixSounds.setQuiet(_soundQuietOwner, true);
    try {
      await _speech.listen(
        onResult: (result) {
          if (!_closed) onWords(result.recognizedWords);
        },
        onSoundLevelChange: (level) {
          if (!_closed) onLevel(level);
        },
        listenOptions: SpeechListenOptions(
          localeId: locale,
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          autoPunctuation: true,
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 8),
        ),
      );
      // Some platforms decline without an error/status callback. A genuinely
      // delayed listening callback can reacquire this still-requested lease.
      if (_closed || !_speech.isListening) {
        kKorlixSounds.setQuiet(_soundQuietOwner, false);
      }
    } catch (_) {
      _requestedListening = false;
      kKorlixSounds.setQuiet(_soundQuietOwner, false);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _requestedListening = false;
    if (!_initialized || _closed) return;
    _finish = Completer<void>();
    try {
      await _speech.stop();
      await _finish!.future.timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () {},
      );
    } finally {
      _finish = null;
      kKorlixSounds.setQuiet(_soundQuietOwner, false);
    }
  }

  @override
  Future<void> cancel() async {
    _requestedListening = false;
    try {
      if (_initialized && _speech.statusListener == _statusListener) {
        await _speech.cancel();
      }
    } finally {
      kKorlixSounds.setQuiet(_soundQuietOwner, false);
    }
  }

  void _restore() {
    if (_speech.statusListener == _statusListener) {
      _speech.statusListener = _oldStatus;
    }
    if (_speech.errorListener == _errorListener) {
      _speech.errorListener = _oldError;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _requestedListening = false;
    if (!(_finish?.isCompleted ?? true)) _finish!.complete();
    unawaited(cancel());
    _restore();
  }
}

class KorlixVoiceDraft {
  const KorlixVoiceDraft(this.text, {this.openLiveConvo = false});
  final String text;
  final bool openLiveConvo;
}

class KorlixVoiceComposer extends StatefulWidget {
  const KorlixVoiceComposer({
    super.key,
    this.initialText = '',
    this.language = 'en',
    this.engine,
    this.sessionChanges,
    this.isSessionCurrent,
    this.showLiveConvo = true,
  });
  final String initialText, language;
  final KorlixDictationEngine? engine;
  final Listenable? sessionChanges;
  final bool Function()? isSessionCurrent;
  final bool showLiveConvo;
  @override
  State<KorlixVoiceComposer> createState() => _KorlixVoiceComposerState();
}

class _KorlixVoiceComposerState extends State<KorlixVoiceComposer>
    with WidgetsBindingObserver {
  late final _engine = widget.engine ?? KorlixDeviceDictation();
  late final _draft = TextEditingController(text: widget.initialText);
  List<KorlixVoiceLocale> _locales = [];
  String? _locale, _error, _undo;
  String _base = '';
  bool _ready = false,
      _starting = false,
      _listening = false,
      _finishing = false,
      _replace = false,
      _expired = false;
  int _epoch = 0, _seconds = 0;
  double _level = 0;
  Timer? _timer, _settle;
  bool get _valid => !_expired && (widget.isSessionCurrent?.call() ?? true);
  bool get _recording => _starting || _listening || _finishing;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sessionChanges?.addListener(_checkSession);
  }

  @override
  void dispose() {
    _epoch++;
    _timer?.cancel();
    _settle?.cancel();
    widget.sessionChanges?.removeListener(_checkSession);
    WidgetsBinding.instance.removeObserver(this);
    _engine.dispose();
    _draft.dispose();
    super.dispose();
  }

  void _checkSession() {
    if (!mounted || _valid) return;
    _expired = true;
    _epoch++;
    _draft.clear();
    unawaited(_engine.cancel());
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (state == AppLifecycleState.inactive && !_listening) return;
    if (!_recording) return;
    _epoch++;
    _timer?.cancel();
    _settle?.cancel();
    unawaited(_engine.cancel());
    if (mounted) {
      setState(() {
        _starting = false;
        _listening = false;
        _finishing = false;
        _level = 0;
      });
    }
  }

  void _status(String status) {
    if (!mounted || !_valid || !_recording) return;
    if (status == 'listening') {
      setState(() => _listening = true);
      return;
    }
    if (status == 'notListening' || status == 'done') {
      _timer?.cancel();
      _settle?.cancel();
      setState(() {
        _listening = false;
        _finishing = status != 'done';
        _level = 0;
      });
      if (status != 'done') {
        _settle = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _finishing = false);
        });
      }
    }
  }

  void _speechError(String message) {
    if (!mounted || !_valid) return;
    _timer?.cancel();
    _settle?.cancel();
    setState(() {
      _starting = false;
      _listening = false;
      _finishing = false;
      _level = 0;
      _error = message.contains('permission') || message.contains('not_allowed')
          ? 'Microphone access is blocked. Allow it in your browser or device settings, then try again. You can also type below.'
          : message.contains('unavailable')
          ? 'Dictation is unavailable in this browser or device. You can type below or open Live Convo.'
          : message.contains('no_match') || message.contains('speech_timeout')
          ? 'No speech was detected. Tap Start dictation and try again, or type below.'
          : 'Dictation stopped. Your draft is still here. Try again or edit the text below.';
    });
  }

  Future<void> _start() async {
    if (_recording || !_valid) return;
    final epoch = ++_epoch;
    _undo = _draft.text;
    _base = _replace ? '' : _draft.text.trimRight();
    setState(() {
      _starting = true;
      _error = null;
      _seconds = 0;
    });
    try {
      if (!_ready) {
        final locales = await _engine.initialize(
          onStatus: _status,
          onError: _speechError,
        );
        if (!mounted || !_valid || epoch != _epoch) {
          await _engine.cancel();
          return;
        }
        _locales = {
          for (final locale in locales) locale.id: locale,
        }.values.toList();
        for (final locale in locales) {
          if (locale.id.toLowerCase().startsWith(
            widget.language.toLowerCase(),
          )) {
            _locale = locale.id;
            break;
          }
        }
        _ready = true;
      }
      if (!mounted || !_valid || epoch != _epoch) return;
      setState(() {
        _starting = false;
        _listening = true;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _listening) setState(() => _seconds++);
      });
      await _engine.start(
        locale: _locale,
        onWords: (words) {
          if (!mounted ||
              !_valid ||
              epoch != _epoch ||
              (!_listening && !_finishing) ||
              words.trim().isEmpty) {
            return;
          }
          final value = '${_base.isEmpty ? '' : '$_base\n'}${words.trim()}';
          setState(
            () => _draft.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            ),
          );
        },
        onLevel: (level) {
          if (mounted && _valid && epoch == _epoch && _listening) {
            setState(() => _level = (level.abs() / 30).clamp(0.0, 1.0));
          }
        },
      );
      if (!mounted || !_valid || epoch != _epoch) await _engine.cancel();
    } catch (error) {
      if (mounted && epoch == _epoch) _speechError(error.toString());
    }
  }

  Future<void> _stop() async {
    if (!_listening || _finishing) return;
    _timer?.cancel();
    setState(() {
      _listening = false;
      _finishing = true;
      _level = 0;
    });
    try {
      await _engine.stop();
    } catch (_) {
      if (mounted) _speechError('stopped');
    }
    if (mounted) setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final time =
        '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Rici voice input')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: KorlixActionButton(
            label: 'Use this text',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: _recording || !_valid || _draft.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, KorlixVoiceDraft(_draft.text)),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [skin.panelSoft, skin.panelDeep],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: skin.primary.withValues(alpha: .35),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [skin.primary, skin.secondary],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: skin.primary.withValues(alpha: .18),
                            blurRadius: 26,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        _listening
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_rounded,
                        color: skin.textOnAccent,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _starting
                          ? 'Opening your microphone…'
                          : _finishing
                          ? 'Finishing your words…'
                          : _listening
                          ? 'Listening · $time'
                          : 'Speak. Review. Send.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Turn your voice into an editable message for Rici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: skin.mutedText, height: 1.5),
                    ),
                    if (_listening)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Semantics(
                          label: 'Microphone input level',
                          child: LinearProgressIndicator(
                            value: _level,
                            minHeight: 4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              KorlixActionButton(
                label: _starting
                    ? 'Opening microphone…'
                    : _finishing
                    ? 'Finishing…'
                    : _listening
                    ? 'Stop dictation'
                    : 'Start dictation',
                icon: _listening
                    ? Icons.stop_circle_outlined
                    : Icons.mic_rounded,
                selected: _listening,
                expand: true,
                onPressed: _starting || _finishing
                    ? null
                    : _listening
                    ? _stop
                    : _start,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _locale ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Dictation language',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Device default'),
                  ),
                  for (final locale in _locales)
                    DropdownMenuItem(
                      value: locale.id,
                      child: Text(locale.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _recording
                    ? null
                    : (value) =>
                          setState(() => _locale = value == '' ? null : value),
              ),
              if (!_ready)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Available languages appear after microphone access is enabled.',
                    style: TextStyle(color: skin.mutedText, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Add to draft'),
                    selected: !_replace,
                    onSelected: _recording
                        ? null
                        : (_) => setState(() => _replace = false),
                  ),
                  ChoiceChip(
                    label: const Text('Replace draft'),
                    selected: _replace,
                    onSelected: _recording
                        ? null
                        : (_) => setState(() => _replace = true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: skin.danger, height: 1.4),
                    ),
                  ),
                ),
              TextField(
                controller: _draft,
                readOnly: _recording,
                minLines: 6,
                maxLines: 14,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Your draft',
                  hintText: 'Your words appear here. You can also type.',
                  alignLabelWithHint: true,
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    '${_draft.text.trim().isEmpty ? 0 : _draft.text.trim().split(RegExp(r'\s+')).length} words',
                    style: TextStyle(color: skin.mutedText, fontSize: 12),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Undo dictation'),
                    onPressed: _recording || _undo == null
                        ? null
                        : () => setState(() {
                            _epoch++;
                            _draft.text = _undo!;
                            _undo = null;
                          }),
                  ),
                ],
              ),
              Text(
                'Review your text, then tap Use this text. Nothing is sent until you tap Send in the conversation. Dictation uses your device or browser speech service.',
                style: TextStyle(
                  color: skin.mutedText,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (widget.showLiveConvo) ...[
                const SizedBox(height: 18),
                KorlixActionButton(
                  label: 'Talk with Rici instead',
                  subtitle: 'Open Live Convo',
                  icon: Icons.spatial_audio_off_rounded,
                  expand: true,
                  onPressed: _recording
                      ? null
                      : () => Navigator.pop(
                          context,
                          KorlixVoiceDraft(_draft.text, openLiveConvo: true),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
