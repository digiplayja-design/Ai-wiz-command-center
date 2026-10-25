import 'dart:async';
import '../sounds/korlix_sound_service.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_media_widgets.dart' show SocialVoicePlayer;

abstract class SocialRecorder {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class DeviceSocialRecorder implements SocialRecorder {
  final _recorder = AudioRecorder();
  @override
  Future<Stream<Uint8List>> start() async {
    if (!await _recorder.hasPermission()) {
      throw const SocialException(
        'Microphone access is off. Allow it in your browser or device settings, then try again.',
      );
    }
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();
  @override
  Future<void> dispose() => _recorder.dispose();
}

Uint8List socialPcmToWav(Uint8List pcm) {
  final size = pcm.length - pcm.length % 2;
  final wav = Uint8List(size + 44), data = ByteData.view(wav.buffer);
  void text(int offset, String value) =>
      wav.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, size + 36, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, size, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}

String socialAudioTime(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

class SocialVoiceCapture extends ChangeNotifier {
  SocialVoiceCapture({SocialRecorder? recorder})
    : recorder = recorder ?? DeviceSocialRecorder();
  final SocialRecorder recorder;
  final Object _soundQuietOwner = Object();
  static const maxBytes = 24000 * 2 * 180;
  final _bytes = BytesBuilder(copy: false), _watch = Stopwatch();
  StreamSubscription<Uint8List>? _stream;
  Timer? _timer;
  Completer<void>? _ended;
  bool recording = false, busy = false, _closed = false;
  int _generation = 0;
  String? error;
  Uint8List? preview;
  Duration get elapsed => _watch.elapsed;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> start() async {
    if (busy || recording || _closed) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    preview = null;
    _bytes.clear();
    _notify();
    kKorlixSounds.setQuiet(_soundQuietOwner, true);
    try {
      final stream = await recorder.start();
      if (_closed || generation != _generation) {
        await recorder.cancel();
        return;
      }
      _ended = Completer<void>();
      _watch
        ..reset()
        ..start();
      recording = true;
      _stream = stream.listen(
        (part) {
          if (_closed) return;
          final remaining = maxBytes - _bytes.length;
          if (remaining > 0) {
            _bytes.add(
              part.length <= remaining ? part : part.sublist(0, remaining),
            );
          }
          if (_bytes.length >= maxBytes) unawaited(stop());
        },
        onDone: () {
          if (_ended?.isCompleted == false) _ended!.complete();
        },
        onError: (_) {
          error = 'Recording was interrupted. Try again.';
          unawaited(discard());
        },
      );
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_watch.elapsed >= const Duration(minutes: 3)) {
          unawaited(stop());
        } else {
          _notify();
        }
      });
    } catch (e) {
      error = e is SocialException
          ? e.message
          : 'The microphone could not start. Check microphone permissions and try again.';
      await recorder.cancel().catchError((_) {});
    } finally {
      if (!recording) kKorlixSounds.setQuiet(_soundQuietOwner, false);
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (busy || !recording || _closed) return;
    final generation = _generation;
    busy = true;
    _timer?.cancel();
    _watch.stop();
    _notify();
    try {
      await recorder.stop();
      // record's stream closes after the final PCM chunk, not before it.
      await _ended?.future.timeout(const Duration(seconds: 3));
      if (_closed || generation != _generation) return;
      final bytes = _bytes.takeBytes();
      if (bytes.length < 14400) {
        error =
            'That recording was too short. Record at least a moment of speech.';
      } else {
        preview = socialPcmToWav(bytes);
      }
    } catch (_) {
      await recorder.cancel().catchError((_) {});
      error = 'The recording could not be completed. Please try again.';
    } finally {
      kKorlixSounds.setQuiet(_soundQuietOwner, false);
      recording = false;
      busy = false;
      await _stream?.cancel();
      _notify();
    }
  }

  Future<void> discard() async {
    _generation++;
    _timer?.cancel();
    _watch.stop();
    await recorder.cancel().catchError((_) {});
    kKorlixSounds.setQuiet(_soundQuietOwner, false);
    await _stream?.cancel();
    _bytes.clear();
    preview = null;
    recording = false;
    busy = false;
    _notify();
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _watch.stop();
    _bytes.clear();
    preview = null;
    unawaited(_stream?.cancel());
    unawaited(
      recorder.cancel().catchError((_) {}).whenComplete(() {
        kKorlixSounds.setQuiet(_soundQuietOwner, false);
        return recorder.dispose();
      }),
    );
    super.dispose();
  }
}

class SocialVoiceNoteSheet extends StatefulWidget {
  const SocialVoiceNoteSheet({super.key, required this.client, this.capture});
  final SocialClient client;
  final SocialVoiceCapture? capture;
  @override
  State<SocialVoiceNoteSheet> createState() => _SocialVoiceNoteSheetState();
}

class _SocialVoiceNoteSheetState extends State<SocialVoiceNoteSheet>
    with WidgetsBindingObserver {
  late final capture = widget.capture ?? SocialVoiceCapture();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_access);
    capture.addListener(_visibility);
  }

  void _visibility() {
    if (mounted && ModalRoute.of(context)?.isCurrent == false) {
      if (capture.recording) {
        unawaited(capture.stop());
      } else if (capture.busy) {
        unawaited(capture.discard());
      }
    }
  }

  void _access() {
    if (!widget.client.available) unawaited(capture.discard());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && capture.recording) {
      unawaited(capture.stop());
    } else if (capture.busy &&
        [
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        ].contains(state)) {
      // Inactive alone can be the microphone permission dialog. A genuinely
      // backgrounded sheet must invalidate a late permission/start result.
      unawaited(capture.discard());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_access);
    capture.removeListener(_visibility);
    capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([capture, widget.client]),
    builder: (context, _) {
      final s = korlixSkinOf(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Voice note',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Say it in your own voice. Listen before sharing.\nUp to 3 minutes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: s.mutedText, height: 1.5),
              ),
              const SizedBox(height: 24),
              if (!widget.client.available)
                const Text(
                  'Your session changed. Close this window and sign in again.',
                )
              else if (capture.preview != null) ...[
                SocialVoicePlayer(
                  key: ObjectKey(capture.preview),
                  bytes: capture.preview,
                ),
                const SizedBox(height: 16),
                KorlixActionButton(
                  label: 'Use voice note',
                  icon: Icons.check_rounded,
                  expand: true,
                  onPressed: () => Navigator.pop(context, capture.preview),
                ),
                TextButton.icon(
                  onPressed: capture.discard,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Discard & record again'),
                ),
              ] else ...[
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [s.primary.withValues(alpha: .35), s.panelDeep],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: s.primary.withValues(alpha: .2),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Icon(
                    capture.recording
                        ? Icons.graphic_eq_rounded
                        : Icons.mic_rounded,
                    size: 40,
                    color: s.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: false,
                  child: Text(
                    socialAudioTime(capture.elapsed),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                KorlixActionButton(
                  label: capture.recording
                      ? 'Stop recording'
                      : 'Start recording',
                  icon: capture.recording
                      ? Icons.stop_rounded
                      : Icons.mic_rounded,
                  busy: capture.busy,
                  onPressed: capture.busy
                      ? null
                      : capture.recording
                      ? capture.stop
                      : capture.start,
                  expand: true,
                ),
              ],
              if (capture.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    capture.error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
