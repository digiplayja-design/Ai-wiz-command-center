import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'capture_cleanup.dart';
import 'magic_client.dart';
import 'magic_orbits.dart';
import 'magic_theme.dart';
import 'magic_result.dart';

class MagicCapture extends StatefulWidget {
  const MagicCapture({
    super.key,
    required this.client,
    required this.options,
    this.timer = 0,
    this.motion = 'Cosmic orbits',
    this.haptics = true,
  });
  final MagicClient client;
  final Map<String, dynamic> options;
  final int timer;
  final String motion;
  final bool haptics;
  @override
  State<MagicCapture> createState() => _MagicCaptureState();
}

class _MagicCaptureState extends State<MagicCapture>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  int _index = 0, _count = 0, _epoch = 0;
  String? _error, _requestKey;
  bool _busy = false,
      _captured = false,
      _recovering = false,
      _foreground = true;
  Future<void> _opening = Future.value();
  Future<void> _closing = Future.value();
  Future<void> _orienting = Future.value();
  Orientation _viewOrientation = Orientation.portrait;
  Map<String, dynamic>? _job;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_account);
    unawaited(_open());
  }

  void _account() {
    if (!widget.client.valid) {
      _epoch++;
      unawaited(_releaseCamera(_camera));
      if (mounted) {
        setState(() => _error = 'Your account changed. Reopen Magic Camera.');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewOrientation = MediaQuery.orientationOf(context);
    _cameraOrientationChanged();
  }

  DeviceOrientation _captureOrientation(CameraController camera) {
    final device = camera.value.deviceOrientation;
    final locked = camera.value.lockedCaptureOrientation;
    bool matchesView(DeviceOrientation? value) =>
        _viewOrientation == Orientation.portrait
        ? value == DeviceOrientation.portraitUp ||
              value == DeviceOrientation.portraitDown
        : value == DeviceOrientation.landscapeLeft ||
              value == DeviceOrientation.landscapeRight;
    // Sensor events can lag behind the visible interface on open/resume, or
    // report landscape while the OS keeps the interface in portrait.
    if (matchesView(device)) return device;
    if (matchesView(locked)) return locked!;
    return _viewOrientation == Orientation.portrait
        ? DeviceOrientation.portraitUp
        : DeviceOrientation.landscapeLeft;
  }

  Future<void> _syncOrientation() {
    final camera = _camera, epoch = _epoch;
    final pending = _orienting.then((_) async {
      if (kIsWeb ||
          camera == null ||
          !identical(camera, _camera) ||
          !_canOpen(epoch) ||
          !camera.value.isInitialized) {
        return;
      }
      final orientation = _captureOrientation(camera);
      if (camera.value.lockedCaptureOrientation != orientation) {
        // The camera plugin applies this to both the native preview and photo.
        await camera.lockCaptureOrientation(orientation);
      }
    });
    // A failed native operation must not poison future orientation requests.
    _orienting = pending.catchError((Object _) {});
    return pending;
  }

  void _cameraOrientationChanged() {
    if (_busy || _captured || !_foreground) return;
    unawaited(
      _syncOrientation().catchError((Object _) {
        if (mounted && !_captured && _foreground) {
          setState(
            () => _error = 'The camera could not adjust to your screen. Reopen Magic Camera and try again.',
          );
        }
      }),
    );
  }

  Future<void> _releaseCamera(CameraController? camera) {
    if (camera == null) return _closing;
    camera.removeListener(_cameraOrientationChanged);
    if (identical(_camera, camera)) _camera = null;
    final orienting = _orienting;
    _closing = _closing.then((_) async {
      try {
        await orienting;
        await camera.dispose();
      } catch (_) {
        // A device may already have released the camera while backgrounding.
      }
    });
    return _closing;
  }

  bool _canOpen(int epoch) =>
      mounted &&
      epoch == _epoch &&
      !_captured &&
      _foreground &&
      widget.client.valid;

  Future<void> _open() {
    final epoch = ++_epoch;
    // Resume and lens switches can overlap. Initialize one controller at a time.
    _opening = _opening.then((_) => _initializeCamera(epoch));
    return _opening;
  }

  Future<void> _initializeCamera(int epoch) async {
    CameraController? camera;
    try {
      await _releaseCamera(_camera);
      if (!_canOpen(epoch)) return;
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (!_canOpen(epoch)) return;
      if (_cameras.isEmpty) {
        throw const MagicApiException('No camera found on this device.');
      }
      camera = CameraController(
        _cameras[_index % _cameras.length],
        ResolutionPreset.max,
        enableAudio: false,
      );
      _camera = camera;
      await camera.initialize();
      if (!_canOpen(epoch)) return;
      camera.addListener(_cameraOrientationChanged);
      await _syncOrientation();
      if (!_canOpen(epoch)) return;
      setState(() {
        _error = null;
      });
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error =
              'Allow camera access in your device settings, then try again.',
        );
      }
    } finally {
      if (camera != null && (!_canOpen(epoch) || !camera.value.isInitialized)) {
        await _releaseCamera(camera);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      _epoch++;
      unawaited(_releaseCamera(_camera));
      if (mounted) setState(() => _count = 0);
    }
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (!_captured && widget.client.valid) unawaited(_open());
      if (_captured && !_busy && _job == null) unawaited(_recover());
    }
  }

  Future<void> _recover() async {
    final key = _requestKey;
    if (key == null || _recovering || !mounted || !widget.client.valid) return;
    setState(() => _recovering = true);
    try {
      final job = await widget.client.recover(key);
      if (mounted && widget.client.valid) {
        setState(() {
          _job = job;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && widget.client.valid) {
        setState(
          () => _error = 'We could not confirm this upload yet. Check its status again or return to your gallery. This check never starts another generation.',
        );
      }
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  Future<void> _shutter() async {
    if (_busy || _camera?.value.isInitialized != true) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    Uint8List? bytes;
    try {
      for (var n = widget.timer; n > 0; n--) {
        if (!mounted || epoch != _epoch) return;
        setState(() => _count = n);
        if (widget.haptics) unawaited(HapticFeedback.selectionClick());
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted || epoch != _epoch || !widget.client.valid) return;
      final camera = _camera!;
      // A countdown, screen rotation or delayed sensor event may have changed
      // the orientation. Finish the native update before taking the photo.
      await _syncOrientation();
      if (!_canOpen(epoch)) return;
      // Hide the live texture BEFORE the shutter; no captured image widget exists.
      setState(() {
        _captured = true;
        _count = 0;
      });
      await WidgetsBinding.instance.endOfFrame;
      try {
        if (!mounted || !widget.client.valid) return;
        if (epoch != _epoch) {
          throw const MagicApiException(
            'The camera was interrupted before capture. Return to Magic Camera and try again.',
          );
        }
        final file = await camera.takePicture();
        try {
          bytes = await file.readAsBytes();
        } finally {
          await eraseCapture(file.path);
        }
      } finally {
        // Release the native camera and remove its temporary file before upload.
        await _releaseCamera(camera);
      }
      if (!mounted || !widget.client.valid) return;
      _requestKey = magicRequestKey();
      final job = await widget.client.generate(
        bytes,
        widget.options,
        _requestKey!,
      );
      if (mounted && widget.client.valid) setState(() => _job = job);
    } catch (e) {
      if (mounted && widget.client.valid) {
        setState(
          () => _error =
              e is MagicApiException && e.status >= 400 && e.status < 500
              ? e.message
              : _requestKey != null
              ? 'The upload response was interrupted. Check this photo’s status before taking another. Only completed results use your allowance.'
              : 'The camera could not take this photo. Return to Magic Camera and try again.',
        );
        if (_requestKey != null &&
            (e is! MagicApiException || e.status == 0 || e.status >= 500)) {
          unawaited(_recover());
        }
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_account);
    unawaited(_releaseCamera(_camera));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.client.valid) {
      return const Scaffold(
        body: Center(child: Text('Sign in again to open your camera.')),
      );
    }
    if (_job != null) {
      return MagicResult(
        client: widget.client,
        initialJob: _job!,
        motion: widget.motion,
      );
    }
    return Scaffold(
      backgroundColor: magicNavy,
      appBar: AppBar(
        title: Text(_captured ? 'Your magic is starting' : 'Frame your moment'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: magicOrange,
                      size: 36,
                    ),
                    const SizedBox(height: 18),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (_requestKey != null) ...[
                      FilledButton.icon(
                        key: const Key('magic-recover-upload'),
                        onPressed: _recovering ? null : _recover,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _recovering
                              ? 'Checking this photo…'
                              : 'Check upload status',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to Magic Camera'),
                    ),
                  ],
                ),
              ),
            )
          : _captured
          ? MagicOrbits(
              style: widget.motion,
              label: 'A little spark. A new you.',
              detail: 'Uploading your private photo. Keep this screen open until the upload finishes.',
            )
          : Column(
              children: [
                Expanded(
                  child:
                      _camera?.value.isInitialized != true ||
                          (!kIsWeb &&
                              _camera?.value.lockedCaptureOrientation == null)
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(child: CameraPreview(_camera!)),
                            if (_count > 0)
                              Text(
                                '$_count',
                                style: const TextStyle(
                                  fontSize: 110,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(blurRadius: 20, color: Colors.black),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Frame it now. Only the magic photo is revealed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: magicMuted),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      bottom: 24,
                      left: 24,
                      right: 24,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          tooltip: 'Switch camera',
                          onPressed: _busy
                              ? null
                              : () async {
                                  final old = _camera;
                                  setState(() => _camera = null);
                                  _epoch++;
                                  await _releaseCamera(old);
                                  if (!mounted || !widget.client.valid) return;
                                  _index++;
                                  await _open();
                                },
                          icon: const Icon(
                            Icons.flip_camera_ios_outlined,
                            size: 30,
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: FilledButton.icon(
                            key: const Key('magic-shutter'),
                            onPressed:
                                _busy || _camera?.value.isInitialized != true
                                ? null
                                : _shutter,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Make magic'),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
