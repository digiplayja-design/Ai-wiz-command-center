// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../bookkeeping/receipt_picker.dart';
import '../theme/korlix_screensaver_controller.dart';
import 'receipt_wiz_client.dart';

Future<BookkeepingPickedReceipt?> captureReceiptWiz(
  BuildContext context,
  ReceiptWizClient client,
) => Navigator.of(context).push<BookkeepingPickedReceipt>(
  MaterialPageRoute(builder: (_) => _CameraCapture(client)),
);

class _CameraCapture extends StatefulWidget {
  const _CameraCapture(this.client);
  final ReceiptWizClient client;
  @override
  State<_CameraCapture> createState() => _CameraCaptureState();
}

class _CameraCaptureState extends State<_CameraCapture> {
  html.VideoElement? _video;
  html.MediaStream? _stream;
  StreamSubscription<html.Event>? _visibility, _ready;
  bool _front = false, _opening = false, _capturing = false, _hasFrame = false;
  String? _error;
  Timer? _activity;
  void _denied() {
    _stop();
    if (mounted) {
      setState(
        () => _error =
            'Your session changed. Close the scanner and sign in again.',
      );
    }
  }

  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_denied);
    _activity = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_hasFrame) kKorlixScreensaver.activity();
    });
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
    _stream?.getTracks().forEach((track) => track.stop());
    _stream = null;
    _video?.pause();
    _video?.srcObject = null;
    _hasFrame = false;
    _opening = false;
  }

  Future<void> _open() async {
    if (_opening || !mounted || widget.client.sessionChanged) return;
    _stop();
    final generation = _generation;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final media = html.window.navigator.mediaDevices;
      if (media == null) {
        throw const ReceiptWizException(
          'This browser cannot open the camera. Go back and choose photos.',
        );
      }
      final stream = await media.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': _front ? 'user' : 'environment',
          'width': {'ideal': 1920},
          'height': {'ideal': 2560},
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
      setState(() {
        _opening = false;
        _hasFrame = _video!.videoWidth > 0;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      _stop();
      setState(() {
        _error = e is ReceiptWizException
            ? e.message
            : 'Camera access is unavailable. Allow camera access in your browser, then try again—or go back and choose photos.';
      });
    }
  }

  void _capture() {
    final video = _video;
    if (!_hasFrame || video == null || video.videoWidth == 0 || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final scale = math.min(
        1.0,
        2400 / math.max(video.videoWidth, video.videoHeight),
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
      final photo = BookkeepingPickedReceipt('receipt-photo.jpg', bytes);
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
    _activity?.cancel();
    widget.client.removeAccessDeniedListener(_denied);
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
      title: const Text('THE RECEIPT WIZ'),
      backgroundColor: const Color(0xFF080F19),
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              'One receipt at a time. Keep all four corners and the total visible.',
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
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF8EE9DB).withValues(alpha: .65),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
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
                  onPressed: _opening || _capturing
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
                FilledButton.icon(
                  onPressed: _hasFrame && !_capturing ? _capture : null,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Capture receipt'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8EE9DB),
                    foregroundColor: const Color(0xFF082923),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16, left: 20, right: 20),
            child: Text(
              'Nothing is saved or analyzed until you review the photo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9CCD9), fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
