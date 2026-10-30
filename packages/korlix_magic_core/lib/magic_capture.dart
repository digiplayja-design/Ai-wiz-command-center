import 'dart:async';

import 'package:camera/camera.dart';
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
  String? _error;
  bool _busy = false, _captured = false;
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
      unawaited(_camera?.dispose());
      _camera = null;
      if (mounted) {
        setState(() => _error = 'Your account changed. Reopen Magic Camera.');
      }
    }
  }

  Future<void> _open() async {
    final epoch = ++_epoch;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw const MagicApiException('No camera found on this device.');
      }
      final camera = CameraController(
        _cameras[_index % _cameras.length],
        ResolutionPreset.max,
        enableAudio: false,
      );
      await camera.initialize();
      if (!mounted || epoch != _epoch || _captured) {
        await camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _error = null;
      });
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error =
              'Allow camera access in your device settings, then try again.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _epoch++;
      final old = _camera;
      _camera = null;
      unawaited(old?.dispose());
      if (mounted) setState(() => _count = 0);
    }
    if (state == AppLifecycleState.resumed &&
        !_captured &&
        widget.client.valid) {
      unawaited(_open());
    }
  }

  Future<void> _shutter() async {
    if (_busy || _camera?.value.isInitialized != true) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      for (var n = widget.timer; n > 0; n--) {
        if (!mounted || epoch != _epoch) return;
        setState(() => _count = n);
        if (widget.haptics) unawaited(HapticFeedback.selectionClick());
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted || epoch != _epoch || !widget.client.valid) return;
      final camera = _camera!;
      // Hide the live texture BEFORE the shutter; no captured image widget exists.
      setState(() {
        _captured = true;
        _count = 0;
      });
      await WidgetsBinding.instance.endOfFrame;
      final file = await camera.takePicture();
      try {
        final bytes = await file.readAsBytes();
        try {
          if (widget.client.valid) {
            _job = await widget.client.generate(
              bytes,
              widget.options,
              magicRequestKey(),
            );
          }
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      } finally {
        await eraseCapture(file.path);
        await camera.dispose();
        _camera = null;
      }
      if (mounted && widget.client.valid) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _captured
              ? 'The connection was interrupted. Check your gallery before taking another photo. Only completed results use your allowance.'
              : 'The camera could not take this photo. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_account);
    unawaited(_camera?.dispose());
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
                  child: _camera == null
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
                                  await old?.dispose();
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
                            onPressed: _busy || _camera == null
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
