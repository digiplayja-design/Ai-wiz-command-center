// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'camera_ask_client.dart';
import 'camera_flashlight.dart';

Future<CameraPhoto?> captureCameraAskPhoto(BuildContext context) =>
    Navigator.of(context).push<CameraPhoto>(
      MaterialPageRoute(builder: (_) => const _CameraCapture()),
    );

class _CameraCapture extends StatefulWidget {
  const _CameraCapture();
  @override
  State<_CameraCapture> createState() => _CameraCaptureState();
}

class _CameraCaptureState extends State<_CameraCapture> {
  html.VideoElement? _video;
  html.MediaStream? _stream;
  CameraFlashlight? _flashlight;
  StreamSubscription<html.Event>? _visibility, _ready;
  bool _front = false, _opening = false, _capturing = false, _hasFrame = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _visibility = html.document.onVisibilityChange.listen((_) {
      if (html.document.visibilityState != 'visible') {
        _stop();
        if (mounted) {
          setState(
            () => _error =
                'Camera paused while you were away. Reopen it when you are ready.',
          );
        }
      }
    });
  }

  void _stop() {
    _generation++;
    _flashlight?.close();
    _flashlight = null;
    // Stopping the source releases its camera and torch, including when a
    // flashlight command is still pending. Never wait to release the camera.
    _stream?.getTracks().forEach((track) => track.stop());
    _stream = null;
    _video?.pause();
    _video?.srcObject = null;
    _hasFrame = false;
    _opening = false;
  }

  Future<void> _open() async {
    if (_opening || !mounted) return;
    _stop();
    final generation = _generation;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final media = html.window.navigator.mediaDevices;
      if (media == null) {
        throw const CameraAskException(
          'This browser cannot open the camera. Go back and choose photos.',
        );
      }
      final stream = await media.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': _front ? 'user' : 'environment',
          'torch': false,
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
        },
      });
      if (!mounted ||
          generation != _generation ||
          html.document.visibilityState != 'visible') {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      _stream = stream;
      _video!.srcObject = stream;
      await _video!.play();
      if (!mounted || generation != _generation) return;
      final tracks = stream.getVideoTracks();
      if (tracks.isNotEmpty) {
        final track = tracks.first;
        Object? capability;
        try {
          capability = track.getCapabilities()['torch'];
        } catch (_) {
          // Older browsers can capture photos without exposing capabilities.
        }
        _flashlight = CameraFlashlight(
          capability: capability,
          apply: (enabled) async {
            await track.applyConstraints({
              // Change only the light. Reapplying camera selection/resolution
              // can unnecessarily reconfigure a mobile camera's live preview.
              'torch': enabled,
              'advanced': [
                {'torch': enabled},
              ],
            });
          },
          readEnabled: () {
            final setting = track.getSettings()['torch'];
            return setting is bool ? setting : null;
          },
        );
      }
      setState(() {
        _opening = false;
        _hasFrame = _video!.videoWidth > 0;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      _stop();
      setState(() {
        _error = e is CameraAskException
            ? e.message
            : 'Camera access is unavailable. Allow camera access in your browser, then try again—or go back and choose photos.';
      });
    }
  }

  Future<void> _toggleFlashlight() async {
    final flashlight = _flashlight;
    if (!_hasFrame ||
        _opening ||
        _capturing ||
        flashlight == null ||
        !flashlight.supported ||
        flashlight.changing) {
      return;
    }
    final change = flashlight.toggle();
    setState(() {});
    var failed = false;
    try {
      await change;
    } catch (_) {
      failed = true;
    }
    if (!mounted || !identical(_flashlight, flashlight)) return;
    // A light change can briefly pause the video on a mobile camera. Keep the
    // same element and stream, and resume playback instead of closing capture.
    final video = _video;
    if (video != null && video.paused && _stream != null) {
      try {
        await video.play();
      } catch (_) {
        // A torch/playback warning must not release a still usable camera.
      }
    }
    if (!mounted || !identical(_flashlight, flashlight)) return;
    setState(() {});
    if (failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The light could not be changed. You can still take a photo or try the light again.',
          ),
        ),
      );
    }
  }

  void _capture() {
    final video = _video;
    if (!_hasFrame ||
        video == null ||
        video.videoWidth == 0 ||
        _capturing ||
        (_flashlight?.changing ?? false)) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final scale = math.min(
        1.0,
        2048 / math.max(video.videoWidth, video.videoHeight),
      );
      final canvas = html.CanvasElement(
        width: (video.videoWidth * scale).round(),
        height: (video.videoHeight * scale).round(),
      );
      canvas.context2D.drawImageScaled(
        video,
        0,
        0,
        canvas.width!,
        canvas.height!,
      );
      final bytes = base64Decode(
        canvas.toDataUrl('image/jpeg', 0.9).split(',').last,
      );
      final photo = CameraPhoto(bytes: bytes, name: 'camera-photo.jpg');
      _stop();
      Navigator.of(context).pop(photo);
    } catch (_) {
      _stop();
      setState(() {
        _capturing = false;
        _error =
            'That frame could not be captured. Reopen the camera or choose a photo.';
      });
    }
  }

  @override
  void dispose() {
    _stop();
    unawaited(_visibility?.cancel());
    unawaited(_ready?.cancel());
    _video?.removeAttribute('src');
    _video = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080F19),
    appBar: AppBar(
      title: const Text('Take a photo'),
      backgroundColor: const Color(0xFF080F19),
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              'Fill the frame. Keep small text sharp and well lit.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9CCD9)),
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                HtmlElementView.fromTagName(
                  tagName: 'video',
                  onElementCreated: (element) {
                    final video = element as html.VideoElement;
                    _video = video;
                    video
                      ..autoplay = true
                      ..muted = true
                      ..setAttribute('playsinline', 'true')
                      ..style.width = '100%'
                      ..style.height = '100%'
                      ..style.objectFit = 'contain'
                      ..style.pointerEvents = 'none';
                    _ready = video.onLoadedData.listen((_) {
                      if (mounted && _stream != null) {
                        setState(() => _hasFrame = video.videoWidth > 0);
                      }
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) unawaited(_open());
                    });
                  },
                ),
                if (_opening)
                  const Center(
                    child: CircularProgressIndicator(color: Color(0xFF8EE9DB)),
                  ),
                if (_error != null)
                  ColoredBox(
                    color: const Color(0xFF080F19),
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.no_photography_outlined,
                              size: 44,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () => unawaited(_open()),
                              child: const Text('Reopen camera'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Back to photo options'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _opening || _capturing || (_flashlight?.changing ?? false)
                      ? null
                      : () {
                          _front = !_front;
                          unawaited(_open());
                        },
                  icon: const Icon(Icons.flip_camera_ios_outlined),
                  label: const Text('Flip camera'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                ),
                if (_flashlight?.supported ?? false)
                  OutlinedButton.icon(
                    onPressed:
                        _hasFrame &&
                            !_opening &&
                            !_capturing &&
                            !_flashlight!.changing
                        ? () => unawaited(_toggleFlashlight())
                        : null,
                    icon: Icon(
                      _flashlight!.enabled
                          ? Icons.flashlight_on
                          : Icons.flashlight_off,
                    ),
                    label: Text(
                      _flashlight!.changing
                          ? 'Changing light…'
                          : _flashlight!.enabled
                          ? 'Turn light off'
                          : 'Turn light on',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _flashlight!.enabled
                          ? const Color(0xFF8EE9DB)
                          : Colors.white,
                      backgroundColor: _flashlight!.enabled
                          ? const Color(0xFF123D37)
                          : null,
                    ),
                  ),
                FilledButton.icon(
                  onPressed:
                      _hasFrame &&
                          !_opening &&
                          !_capturing &&
                          !(_flashlight?.changing ?? false)
                      ? _capture
                      : null,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Capture photo'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8EE9DB),
                    foregroundColor: const Color(0xFF082923),
                  ),
                ),
              ],
            ),
          ),
          if (_hasFrame && !_opening && !(_flashlight?.supported ?? false))
            const Padding(
              padding: EdgeInsets.only(bottom: 12, left: 20, right: 20),
              child: Text(
                'Flashlight is unavailable for this camera or browser. You can also take a photo using your phone’s flash, then choose it from your photos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB9CCD9), fontSize: 12),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16, left: 20, right: 20),
            child: Text(
              'Camera preview only. Nothing is sent until you ask.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9CCD9), fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
