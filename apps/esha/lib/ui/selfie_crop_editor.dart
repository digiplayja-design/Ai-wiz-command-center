import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../services/selfie.dart';
import 'brand.dart';

Future<void> showSelfieCropEditor(
  BuildContext context,
  SelfieStudioController controller,
) async {
  if (!controller.canCrop || controller.sourcePhoto == null) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SelfieCropEditor(controller: controller),
    ),
  );
}

class SelfieCropEditor extends StatefulWidget {
  const SelfieCropEditor({super.key, required this.controller});
  final SelfieStudioController controller;

  @override
  State<SelfieCropEditor> createState() => _SelfieCropEditorState();
}

class _SelfieCropEditorState extends State<SelfieCropEditor> {
  SelfiePhoto? _source;
  ui.Image? _image;
  double _zoom = 1, _maximumZoom = 1, _gestureZoom = 1;
  Offset _center = const Offset(.5, .5), _gestureAnchor = Offset.zero;
  Rect _frame = Rect.zero;
  bool _valid = false, _closing = false, _dismissScheduled = false;
  bool _gestureActive = false;

  bool get _sameSource =>
      _source != null && identical(widget.controller.sourcePhoto, _source);

  Rect get _crop {
    final extent = (1 / _zoom).clamp(0.0, 1.0);
    final left = (_center.dx - extent / 2).clamp(0.0, 1.0 - extent);
    final top = (_center.dy - extent / 2).clamp(0.0, 1.0 - extent);
    return Rect.fromLTRB(
      left,
      top,
      (left + extent).clamp(0.0, 1.0),
      (top + extent).clamp(0.0, 1.0),
    );
  }

  @override
  void initState() {
    super.initState();
    final source = widget.controller.sourcePhoto;
    if (source != null && widget.controller.canCrop) {
      _source = source;
      _image = source.image.clone();
      _maximumZoom = math
          .min(6.0, math.min(source.size.width / 160, source.size.height / 160))
          .clamp(1.0, 6.0);
      final previous = widget.controller.cropRect;
      final extent = math.max(previous.width, previous.height);
      _zoom = extent.isFinite && extent > 0
          ? (1 / extent).clamp(1.0, _maximumZoom)
          : 1;
      _center = _boundCenter(previous.center, _zoom);
      _valid = true;
    }
    widget.controller.addListener(_controllerChanged);
    if (!_valid) _scheduleDismiss();
  }

  @override
  void didUpdateWidget(SelfieCropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      _invalidate();
    }
  }

  void _controllerChanged() {
    if (!mounted) return;
    // applyCrop notifies busy synchronously. That intended notification must
    // not pop twice, while an actual identity/access reset still blanks us.
    if (!_sameSource || (!_closing && !widget.controller.canCrop)) {
      _invalidate();
    }
  }

  void _invalidate() {
    if (!mounted) return;
    if (_valid) setState(() => _valid = false);
    _scheduleDismiss();
  }

  void _scheduleDismiss() {
    if (_dismissScheduled) return;
    _dismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    if (!mounted) return;
    _closing = true;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route?.isCurrent == true) {
      navigator.pop();
    } else if (route != null && route.isActive) {
      // Never dismiss a different route that may have covered this editor.
      navigator.removeRoute(route);
    }
  }

  Future<void> _apply() async {
    if (_closing) return;
    if (!_valid || !_sameSource || !widget.controller.canCrop) {
      _invalidate();
      return;
    }
    final crop = _crop;
    setState(() => _closing = true);
    // Capture the checked source in the controller before navigation can run
    // any callbacks. Its own generation guards protect the async result.
    final operation = widget.controller.applyCrop(crop);
    _dismiss();
    await operation;
  }

  static Offset _boundCenter(Offset center, double zoom) {
    final half = .5 / zoom;
    return Offset(
      (center.dx.isFinite ? center.dx : .5).clamp(half, 1 - half),
      (center.dy.isFinite ? center.dy : .5).clamp(half, 1 - half),
    );
  }

  void _setZoom(double value) {
    if (!_valid || _closing || !value.isFinite) return;
    setState(() {
      _zoom = value.clamp(1.0, _maximumZoom);
      _center = _boundCenter(_center, _zoom);
    });
  }

  void _moveCrop(Offset direction) {
    if (!_valid || _closing) return;
    setState(() {
      _center = _boundCenter(_center + direction * (.1 / _zoom), _zoom);
    });
  }

  void _reset() {
    if (!_valid || _closing) return;
    setState(() {
      _zoom = 1;
      _center = const Offset(.5, .5);
    });
  }

  Offset _withinFrame(Offset point) => Offset(
    (point.dx - _frame.left) / _frame.width,
    (point.dy - _frame.top) / _frame.height,
  );

  void _scaleStart(ScaleStartDetails details) {
    _gestureActive =
        _valid &&
        !_closing &&
        !_frame.isEmpty &&
        _frame.contains(details.localFocalPoint);
    if (!_gestureActive) return;
    _gestureZoom = _zoom;
    final at = _withinFrame(details.localFocalPoint);
    final crop = _crop;
    _gestureAnchor =
        crop.topLeft + Offset(at.dx * crop.width, at.dy * crop.height);
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    if (!_gestureActive || !_valid || _closing || !details.scale.isFinite) {
      return;
    }
    final zoom = (_gestureZoom * details.scale).clamp(1.0, _maximumZoom);
    final at = _withinFrame(details.localFocalPoint);
    final extent = 1 / zoom;
    setState(() {
      _zoom = zoom;
      _center = _boundCenter(
        _gestureAnchor - Offset((at.dx - .5) * extent, (at.dy - .5) * extent),
        zoom,
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final ready = _valid && _sameSource && image != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Crop / zoom',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          tooltip: 'Cancel crop',
          onPressed: _dismiss,
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            onPressed: ready && !_closing ? _reset : null,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: !ready
          ? const ColoredBox(color: ivory, child: SizedBox.expand())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final bounds = Offset.zero & constraints.biggest;
                        final available = bounds.deflate(16);
                        final fit = applyBoxFit(
                          BoxFit.contain,
                          Size(image.width.toDouble(), image.height.toDouble()),
                          available.size,
                        );
                        _frame = Alignment.center.inscribe(
                          fit.destination,
                          available,
                        );
                        return Semantics(
                          image: true,
                          label: 'Crop preview. Pinch to zoom and drag to position your face.',
                          value: '${_zoom.toStringAsFixed(2)} times zoom',
                          customSemanticsActions: {
                            const CustomSemanticsAction(
                              label: 'Move crop left',
                            ): () =>
                                _moveCrop(const Offset(-1, 0)),
                            const CustomSemanticsAction(
                              label: 'Move crop right',
                            ): () =>
                                _moveCrop(const Offset(1, 0)),
                            const CustomSemanticsAction(
                              label: 'Move crop up',
                            ): () =>
                                _moveCrop(const Offset(0, -1)),
                            const CustomSemanticsAction(
                              label: 'Move crop down',
                            ): () =>
                                _moveCrop(const Offset(0, 1)),
                          },
                          child: GestureDetector(
                            key: const Key('selfie-crop-gesture'),
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: _scaleStart,
                            onScaleUpdate: _scaleUpdate,
                            onScaleEnd: (_) => _gestureActive = false,
                            child: CustomPaint(
                              key: const Key('selfie-crop-canvas'),
                              size: Size.infinite,
                              painter: SelfieCropPainter(
                                image: image,
                                crop: _crop,
                                frame: _frame,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Flexible(
                    flex: 4,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Keep one face with both eyes and lips visible. Pinch or use Zoom, then drag to bring your face closer inside the frame.',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Zoom',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                '${_zoom.toStringAsFixed(2)}×',
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                          Semantics(
                            label: 'Zoom',
                            child: Slider(
                              key: const Key('selfie-crop-zoom'),
                              min: 1,
                              max: _maximumZoom,
                              value: _zoom,
                              semanticFormatterCallback: (value) =>
                                  '${value.toStringAsFixed(2)} times',
                              onChanged: !_closing && _maximumZoom > 1
                                  ? _setZoom
                                  : null,
                            ),
                          ),
                          if (_maximumZoom <= 1)
                            const Text(
                              'This photo is already at the minimum crop size. Choose a larger photo for more zoom.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          const Text(
                            'Reset shows the entire original photo. Changes stay on your device; the photo in your gallery is unchanged.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _dismiss,
                child: const Text('Cancel', textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('apply-selfie-crop'),
                onPressed: ready && !_closing && widget.controller.canCrop
                    ? _apply
                    : null,
                child: const Text('Apply crop', textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SelfieCropPainter extends CustomPainter {
  const SelfieCropPainter({
    required this.image,
    required this.crop,
    required this.frame,
  });
  final ui.Image image;
  final Rect crop, frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = plum);
    if (frame.isEmpty) return;
    final source = Rect.fromLTRB(
      crop.left * image.width,
      crop.top * image.height,
      crop.right * image.width,
      crop.bottom * image.height,
    );
    canvas.save();
    canvas.clipRect(frame);
    canvas.drawImageRect(
      image,
      source,
      frame,
      Paint()..filterQuality = FilterQuality.high,
    );
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .45)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), grid);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), grid);
    }
    canvas.restore();
    canvas.drawRect(
      frame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final corners = Paint()
      ..color = const Color(0xFFFFCEE0)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final length = math.min(20.0, math.min(frame.width, frame.height) * .12);
    for (final corner in [
      frame.topLeft,
      frame.topRight,
      frame.bottomLeft,
      frame.bottomRight,
    ]) {
      final dx = corner.dx == frame.left ? length : -length;
      final dy = corner.dy == frame.top ? length : -length;
      canvas.drawLine(corner, corner + Offset(dx, 0), corners);
      canvas.drawLine(corner, corner + Offset(0, dy), corners);
    }
  }

  @override
  bool shouldRepaint(SelfieCropPainter oldDelegate) =>
      !identical(image, oldDelegate.image) ||
      crop != oldDelegate.crop ||
      frame != oldDelegate.frame;
}
